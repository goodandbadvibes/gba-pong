extends RefCounted
## Screen size and the 15-bit-friendly palette (every channel a multiple of 8), shared by all drawing code.

const W := 240
const H := 160

const BG := Color8(8, 8, 24)
const BG_FLASH := Color8(40, 56, 112)
const DIM := Color8(40, 56, 112)
const MID := Color8(88, 120, 200)
const WHITE := Color8(248, 248, 248)
const PLAYER := Color8(248, 176, 48)
const CPU := Color8(248, 72, 112)
const SPARK := Color8(248, 248, 160)
const GEM := Color8(96, 232, 232)
const BOSS := Color8(248, 56, 56)
