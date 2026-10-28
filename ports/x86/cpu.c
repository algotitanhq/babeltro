// cpu.c: a small i386 + SSE interpreter, just enough to run fx.bin.
//
// The browser has no x86, so this file is one: 8 general registers, the
// flags the program tests, 8 xmm registers (their low 64 bits: scalar SSE
// never looks higher), and 32 MiB of memory that live inside the wasm
// module's own linear memory. bb_init therefore returns the address of the
// emulated framebuffer itself: the lab reads the pixels the x86 code wrote,
// with no copy in between.
//
// It decodes exactly the instructions ports/x86/*.asm uses, and stops with
// a clear message on anything else. Floats are computed with C float and
// double on wasm, whose f32 and f64 operations are IEEE, rounded once, like
// SSE's (and unlike the x87's).
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "fx_bin.h" // fx_bin[], fx_bin_len: the assembled image, from build.sh

#define EXPORT(name) __attribute__((export_name(name)))

enum { MEM_SIZE = 32 << 20, RETURN_MAGIC = 0xFFFFFFF0u };
enum { EAX, ECX, EDX, EBX, ESP, EBP, ESI, EDI };

static uint8_t mem[MEM_SIZE] __attribute__((aligned(16)));
static uint32_t r[8], eip;
static uint64_t xmm[8];
static int cf, zf, sf, of, pf;
static uint64_t retired, last_frame;
static int dead;

static void trap(const char *what, uint32_t at)
{
    fprintf(stderr, "x86: %s at eip=%08x (bytes %02x %02x %02x %02x)\n", what, at,
            mem[at], mem[at + 1], mem[at + 2], mem[at + 3]);
    dead = 1;
}

// memory: little-endian, like wasm, so a plain memcpy is a load or a store
static inline uint32_t chk(uint32_t a, uint32_t n)
{
    if (a > MEM_SIZE - n) {
        trap("memory access out of range", eip);
        return 0;
    }
    return a;
}
static inline uint8_t rd8(uint32_t a) { return mem[chk(a, 1)]; }
static inline uint32_t rd32(uint32_t a) { uint32_t v; memcpy(&v, mem + chk(a, 4), 4); return v; }
static inline uint64_t rd64(uint32_t a) { uint64_t v; memcpy(&v, mem + chk(a, 8), 8); return v; }
static inline void wr8(uint32_t a, uint8_t v) { mem[chk(a, 1)] = v; }
static inline void wr32(uint32_t a, uint32_t v) { memcpy(mem + chk(a, 4), &v, 4); }
static inline void wr64(uint32_t a, uint64_t v) { memcpy(mem + chk(a, 8), &v, 8); }

// instruction stream
static inline uint8_t f8(void) { return mem[eip++]; }
static inline uint32_t f32(void) { uint32_t v; memcpy(&v, mem + eip, 4); eip += 4; return v; }

// ModRM: either a register (is_reg) or an effective address
static int is_reg, rm_reg, reg_field;
static uint32_t ea;

static void modrm(void)
{
    uint8_t m = f8();
    int mod = m >> 6, rm = m & 7;
    reg_field = m >> 3 & 7;
    is_reg = mod == 3;
    if (is_reg) {
        rm_reg = rm;
        return;
    }
    uint32_t a = 0;
    if (rm == 4) { // SIB: base + index << scale
        uint8_t s = f8();
        int base = s & 7, idx = s >> 3 & 7;
        if (idx != 4)
            a = r[idx] << (s >> 6);
        if (base == 5 && mod == 0)
            a += f32();
        else
            a += r[base];
    } else if (rm == 5 && mod == 0) {
        a = f32();
    } else {
        a = r[rm];
    }
    if (mod == 1)
        a += (uint32_t)(int32_t)(int8_t)f8();
    else if (mod == 2)
        a += f32();
    ea = a;
}

static inline uint32_t get_rm32(void) { return is_reg ? r[rm_reg] : rd32(ea); }
static inline void set_rm32(uint32_t v) { if (is_reg) r[rm_reg] = v; else wr32(ea, v); }
static inline uint8_t get_r8(int i) { return i < 4 ? (uint8_t)r[i] : (uint8_t)(r[i - 4] >> 8); }
static inline uint8_t get_rm8(void) { return is_reg ? get_r8(rm_reg) : rd8(ea); }
static inline uint64_t get_xrm64(void) { return is_reg ? xmm[rm_reg] : rd64(ea); }
static inline uint32_t get_xrm32(void) { return is_reg ? (uint32_t)xmm[rm_reg] : rd32(ea); }

static inline void szp(uint32_t v) { zf = v == 0; sf = v >> 31; }

// the integer ALU: add or and sub xor cmp (adc, sbb: not used)
static uint32_t alu(int op, uint32_t a, uint32_t b)
{
    uint32_t v;
    switch (op) {
    case 0: v = a + b; cf = v < a; of = (~(a ^ b) & (a ^ v)) >> 31; break;
    case 1: v = a | b; cf = of = 0; break;
    case 4: v = a & b; cf = of = 0; break;
    case 5: case 7: v = a - b; cf = a < b; of = ((a ^ b) & (a ^ v)) >> 31; break;
    case 6: v = a ^ b; cf = of = 0; break;
    default: trap("adc/sbb not implemented", eip); return a;
    }
    szp(v);
    return op == 7 ? a : v;
}

static int cond(int cc)
{
    int v;
    switch (cc >> 1) {
    case 0: v = of; break;
    case 1: v = cf; break;
    case 2: v = zf; break;
    case 3: v = cf | zf; break;
    case 4: v = sf; break;
    case 5: v = pf; break;
    case 6: v = sf != of; break;
    default: v = zf | (sf != of); break;
    }
    return v ^ (cc & 1);
}

static inline float f_of(uint32_t b) { float f; memcpy(&f, &b, 4); return f; }
static inline uint32_t b_of_f(float f) { uint32_t b; memcpy(&b, &f, 4); return b; }
static inline double d_of(uint64_t b) { double d; memcpy(&d, &b, 8); return d; }
static inline uint64_t b_of_d(double d) { uint64_t b; memcpy(&b, &d, 8); return b; }
static inline void set_xs(int i, float f) { xmm[i] = (xmm[i] & ~0xFFFFFFFFull) | b_of_f(f); }

// SSE float -> int32: out of range and NaN give 0x80000000, the "integer
// indefinite", as the hardware does (a C cast would be undefined there)
static uint32_t to_i32(double v)
{
    if (!(v >= -2147483648.0 && v < 2147483648.0))
        return 0x80000000u;
    return (uint32_t)(int32_t)v;
}

static void comi(double a, double b)
{
    of = sf = 0;
    if (a != a || b != b)
        zf = pf = cf = 1;
    else {
        zf = a == b;
        cf = a < b;
        pf = 0;
    }
}

// the SSE scalar ops, 0F xx with an F3 (ss), F2 (sd) or 66 (pd) prefix
static void sse(uint8_t op, int pre, uint32_t at)
{
    modrm();
    int d = reg_field;
    if (pre == 0xF3) { // single precision
        float a = f_of((uint32_t)xmm[d]), b;
        switch (op) {
        case 0x10: xmm[d] = is_reg ? (xmm[d] & ~0xFFFFFFFFull) | (uint32_t)xmm[rm_reg] : rd32(ea); return;
        case 0x11: if (is_reg) set_xs(rm_reg, a); else wr32(ea, (uint32_t)xmm[d]); return;
        case 0x2A: set_xs(d, (float)(int32_t)get_rm32()); return;
        case 0x2C: r[d] = to_i32(__builtin_truncf(f_of(get_xrm32()))); return;
        case 0x5A: xmm[d] = b_of_d((double)f_of(get_xrm32())); return;
        }
        b = f_of(get_xrm32());
        switch (op) {
        case 0x51: set_xs(d, __builtin_sqrtf(b)); return;
        case 0x58: set_xs(d, a + b); return;
        case 0x59: set_xs(d, a * b); return;
        case 0x5C: set_xs(d, a - b); return;
        case 0x5D: set_xs(d, a < b ? a : b); return;
        case 0x5E: set_xs(d, a / b); return;
        case 0x5F: set_xs(d, a > b ? a : b); return;
        }
    } else if (pre == 0xF2) { // double precision
        double a = d_of(xmm[d]), b;
        switch (op) {
        case 0x10: xmm[d] = get_xrm64(); return;
        case 0x11: if (is_reg) xmm[rm_reg] = xmm[d]; else wr64(ea, xmm[d]); return;
        case 0x2A: xmm[d] = b_of_d((double)(int32_t)get_rm32()); return;
        case 0x2C: r[d] = to_i32(__builtin_trunc(d_of(get_xrm64()))); return;
        case 0x2D: r[d] = to_i32(__builtin_rint(d_of(get_xrm64()))); return; // MXCSR: nearest, ties to even
        case 0x5A: set_xs(d, (float)d_of(get_xrm64())); return;
        }
        b = d_of(get_xrm64());
        switch (op) {
        case 0x51: xmm[d] = b_of_d(__builtin_sqrt(b)); return;
        case 0x58: xmm[d] = b_of_d(a + b); return;
        case 0x59: xmm[d] = b_of_d(a * b); return;
        case 0x5C: xmm[d] = b_of_d(a - b); return;
        case 0x5D: xmm[d] = b_of_d(a < b ? a : b); return;
        case 0x5E: xmm[d] = b_of_d(a / b); return;
        case 0x5F: xmm[d] = b_of_d(a > b ? a : b); return;
        }
    } else if (pre == 0x66) {
        switch (op) {
        case 0x2E: case 0x2F: comi(d_of(xmm[d]), d_of(get_xrm64())); return;
        case 0x57: xmm[d] ^= get_xrm64(); return; // xorpd: low lane is all we keep
        }
    } else {
        switch (op) {
        case 0x2E: case 0x2F: comi(f_of((uint32_t)xmm[d]), f_of(get_xrm32())); return;
        case 0x57: xmm[d] ^= get_xrm64(); return; // xorps
        }
    }
    trap("unknown SSE instruction", at);
}

static inline void push(uint32_t v) { r[ESP] -= 4; wr32(r[ESP], v); }
static inline uint32_t pop(void) { uint32_t v = rd32(r[ESP]); r[ESP] += 4; return v; }

// run calls the routine at `entry` with eax and edx set, until it returns
// to the magic address the host pushed. Every instruction counts as one,
// rep stosb included, however many bytes it stores.
static void run(uint32_t entry, uint32_t a, uint32_t d)
{
    if (dead)
        return;
    r[EAX] = a;
    r[EDX] = d;
    r[ESP] = MEM_SIZE;
    push(RETURN_MAGIC);
    eip = entry;
    while (eip != RETURN_MAGIC && !dead) {
        uint32_t at = eip;
        retired++;
        if (eip > fx_bin_len) {
            trap("jump outside the program", at);
            return;
        }
        uint8_t op = f8();
        int pre = 0;
        if (op == 0x66 || op == 0xF2 || op == 0xF3) {
            pre = op;
            op = f8();
        }
        if (op == 0x0F) {
            op = f8();
            if (op >= 0x80 && op <= 0x8F) { // jcc rel32
                int32_t rel = (int32_t)f32();
                if (cond(op & 15))
                    eip += rel;
            } else if (op >= 0x40 && op <= 0x4F) { // cmovcc
                modrm();
                uint32_t v = get_rm32(); // read even when false, like the CPU
                if (cond(op & 15))
                    r[reg_field] = v;
            } else if (op == 0xAF) { // imul r32, r/m32
                modrm();
                r[reg_field] = (uint32_t)((int32_t)r[reg_field] * (int64_t)(int32_t)get_rm32());
            } else if (op == 0xB6) { // movzx r32, r/m8
                modrm();
                r[reg_field] = get_rm8();
            } else {
                sse(op, pre, at);
            }
            continue;
        }
        if (pre == 0xF3 && (op == 0xAA || op == 0xAB)) { // rep stosb / stosd
            int n = op == 0xAA ? 1 : 4;
            while (r[ECX] && !dead) {
                if (n == 1)
                    wr8(r[EDI], (uint8_t)r[EAX]);
                else
                    wr32(r[EDI], r[EAX]);
                r[EDI] += n;
                r[ECX]--;
            }
            continue;
        }
        if (pre) {
            trap("unknown prefixed instruction", at);
            return;
        }
        if (op < 0x40 && (op & 7) < 6) { // the ALU block: add or and sub xor cmp
            int alu_op = op >> 3;
            switch (op & 7) {
            case 1: modrm(); { uint32_t v = alu(alu_op, get_rm32(), r[reg_field]); if (alu_op != 7) set_rm32(v); } break;
            case 3: modrm(); r[reg_field] = alu(alu_op, r[reg_field], get_rm32()); break;
            case 5: r[EAX] = alu(alu_op, r[EAX], f32()); break;
            default: trap("unknown 8-bit ALU instruction", at); return;
            }
            continue;
        }
        if (op >= 0x40 && op <= 0x4F) { // inc / dec r32: CF untouched
            uint32_t *p = &r[op & 7], a0 = *p;
            *p += op < 0x48 ? 1 : -1;
            of = op < 0x48 ? *p == 0x80000000u : a0 == 0x80000000u;
            szp(*p);
            continue;
        }
        if (op >= 0x50 && op <= 0x57) { push(r[op & 7]); continue; }
        if (op >= 0x58 && op <= 0x5F) { r[op & 7] = pop(); continue; }
        if (op >= 0x70 && op <= 0x7F) { // jcc rel8
            int8_t rel = (int8_t)f8();
            if (cond(op & 15))
                eip += rel;
            continue;
        }
        if (op >= 0xB8 && op <= 0xBF) { r[op & 7] = f32(); continue; }
        switch (op) {
        case 0x81: case 0x83: { // ALU r/m32, imm32 / imm8
            modrm();
            uint32_t imm = op == 0x81 ? f32() : (uint32_t)(int32_t)(int8_t)f8();
            uint32_t v = alu(reg_field, get_rm32(), imm);
            if (reg_field != 7)
                set_rm32(v);
            break;
        }
        case 0x85: modrm(); alu(4, get_rm32(), r[reg_field]); break; // test
        case 0xA9: alu(4, r[EAX], f32()); break;                     // test eax, imm32
        case 0x88: { // mov r/m8, r8
            modrm();
            uint8_t v = get_r8(reg_field);
            if (is_reg)
                trap("mov to an 8-bit register not implemented", at);
            else
                wr8(ea, v);
            break;
        }
        case 0x89: modrm(); set_rm32(r[reg_field]); break;
        case 0x8B: modrm(); r[reg_field] = get_rm32(); break;
        case 0x8D: modrm(); r[reg_field] = ea; break; // lea
        case 0xA1: r[EAX] = rd32(f32()); break;
        case 0xA3: wr32(f32(), r[EAX]); break;
        case 0xC6: modrm(); if (is_reg) trap("mov r8, imm8", at); else wr8(ea, f8()); break;
        case 0xC7: modrm(); set_rm32(f32()); break;
        case 0xC1: { // shl / shr / sar r/m32, imm8 (only ZF and SF are kept)
            modrm();
            uint32_t v = get_rm32();
            int s = f8() & 31;
            switch (reg_field) {
            case 4: v <<= s; break;
            case 5: v >>= s; break;
            case 7: v = (uint32_t)((int32_t)v >> s); break;
            default: trap("unknown shift", at); return;
            }
            set_rm32(v);
            szp(v);
            break;
        }
        case 0xF7: // test imm / div r/m32
            modrm();
            if (reg_field == 0) {
                alu(4, get_rm32(), f32());
            } else if (reg_field == 6) {
                uint32_t dv = get_rm32();
                uint64_t n = (uint64_t)r[EDX] << 32 | r[EAX];
                if (dv == 0 || n / dv > 0xFFFFFFFFu) {
                    trap("divide error", at);
                    return;
                }
                r[EAX] = (uint32_t)(n / dv);
                r[EDX] = (uint32_t)(n % dv);
            } else {
                trap("unknown F7 instruction", at);
                return;
            }
            break;
        case 0xFF: // inc / dec r/m32, call r/m32
            modrm();
            if (reg_field == 2) {
                uint32_t to = get_rm32();
                push(eip);
                eip = to;
            } else if (reg_field <= 1) {
                uint32_t a0 = get_rm32(), v = reg_field ? a0 - 1 : a0 + 1;
                set_rm32(v);
                of = reg_field ? a0 == 0x80000000u : v == 0x80000000u;
                szp(v);
            } else {
                trap("unknown FF instruction", at);
                return;
            }
            break;
        case 0xE8: { int32_t rel = (int32_t)f32(); push(eip); eip += rel; break; }
        case 0xE9: { int32_t rel = (int32_t)f32(); eip += rel; break; }
        case 0xEB: { int8_t rel = (int8_t)f8(); eip += rel; break; }
        case 0xC3: eip = pop(); break;
        default: trap("unknown instruction", at); return;
        }
    }
}

// the header at address 0: four entry points, dd init, start, step, render
static uint32_t entry(int i) { return rd32(4 * i); }

EXPORT("bb_init") int32_t bb_init(int32_t w, int32_t h)
{
    static int loaded;
    if (!loaded) {
        memcpy(mem, fx_bin, fx_bin_len);
        loaded = 1;
    }
    run(entry(0), (uint32_t)w, (uint32_t)h);
    return (int32_t)(uintptr_t)(mem + r[EAX]);
}

EXPORT("bb_start") void bb_start(int32_t scene) { run(entry(1), (uint32_t)scene, 0); }
EXPORT("bb_step") void bb_step(int32_t n) { run(entry(2), (uint32_t)n, 0); }

EXPORT("bb_render") void bb_render(int32_t n)
{
    uint64_t before = retired;
    run(entry(3), (uint32_t)n, 0);
    last_frame = retired - before;
}

// bb_retired: x86 instructions executed by the last bb_render, for the lab
EXPORT("bb_retired") double bb_retired(void) { return (double)last_frame; }
