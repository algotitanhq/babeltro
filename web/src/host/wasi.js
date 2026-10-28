// A minimal wasi_snapshot_preview1 for the ports. The Go runtime needs a
// clock, random bytes for its own start-up and somewhere to print a panic;
// C's libc links fd_write and proc_exit. Nothing here may reach the pixels:
// the time and random numbers the effects use come from the frame number
// and from their own xorshift32.

const ERRNO_SUCCESS = 0;
const ERRNO_BADF = 8;
const ERRNO_NOSYS = 52;

export function wasiImports(getMemory, log = console.log) {
  const view = () => new DataView(getMemory().buffer);
  const bytes = () => new Uint8Array(getMemory().buffer);
  const decoder = new TextDecoder();
  let pending = '';

  const sizesZero = (countPtr, sizePtr) => {
    const v = view();
    v.setUint32(countPtr, 0, true);
    v.setUint32(sizePtr, 0, true);
    return ERRNO_SUCCESS;
  };

  return {
    args_sizes_get: sizesZero,
    args_get: () => ERRNO_SUCCESS,
    environ_sizes_get: sizesZero,
    environ_get: () => ERRNO_SUCCESS,

    clock_res_get: (_id, resPtr) => {
      view().setBigUint64(resPtr, 1000n, true);
      return ERRNO_SUCCESS;
    },
    clock_time_get: (_id, _precision, timePtr) => {
      const ns = BigInt(Math.round(performance.now() * 1e6));
      view().setBigUint64(timePtr, ns, true);
      return ERRNO_SUCCESS;
    },

    random_get: (ptr, len) => {
      const out = bytes().subarray(ptr, ptr + len);
      for (let i = 0; i < len; i += 65536) {
        crypto.getRandomValues(out.subarray(i, Math.min(len, i + 65536)));
      }
      return ERRNO_SUCCESS;
    },

    fd_write: (fd, iovs, iovsLen, nwrittenPtr) => {
      if (fd !== 1 && fd !== 2) return ERRNO_BADF;
      const v = view();
      const mem = bytes();
      let written = 0;
      for (let i = 0; i < iovsLen; i++) {
        const ptr = v.getUint32(iovs + i * 8, true);
        const len = v.getUint32(iovs + i * 8 + 4, true);
        pending += decoder.decode(mem.subarray(ptr, ptr + len));
        written += len;
      }
      const lines = pending.split('\n');
      pending = lines.pop();
      for (const line of lines) log(line);
      v.setUint32(nwrittenPtr, written, true);
      return ERRNO_SUCCESS;
    },
    fd_close: () => ERRNO_SUCCESS,
    fd_seek: () => ERRNO_NOSYS,
    fd_fdstat_get: () => ERRNO_NOSYS,
    fd_prestat_get: () => ERRNO_BADF,
    fd_prestat_dir_name: () => ERRNO_BADF,

    poll_oneoff: () => ERRNO_NOSYS,
    sched_yield: () => ERRNO_SUCCESS,
    proc_exit: (code) => {
      throw new Error(`port exited with code ${code}`);
    },
  };
}
