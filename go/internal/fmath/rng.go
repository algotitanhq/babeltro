package fmath

// Rng is a xorshift32 generator. The demo uses it instead of math/rand
// everywhere a random number shapes the image, because every port has to
// reproduce the same sequence bit for bit: three shifts and three xors are
// the same in any language, math/rand's algorithm is not.
type Rng uint32

// Next advances the generator and returns the new state. The state must
// never be zero.
func (r *Rng) Next() uint32 {
	x := uint32(*r)
	x ^= x << 13
	x ^= x >> 17
	x ^= x << 5
	*r = Rng(x)
	return x
}

// Float32 returns a number in [0, 1) built from the top 24 bits of Next, so
// the conversion to float32 is exact in every language.
func (r *Rng) Float32() float32 {
	return float32(r.Next()>>8) * (1.0 / 16777216)
}
