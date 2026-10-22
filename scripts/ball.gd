extends RefCounted
## One ball in play. last_touch is the side that hit it last (0 player, 1 CPU, -1 nobody yet).

var pos := Vector2.ZERO
var vel := Vector2.ZERO
var trail: Array[Vector2] = []
var squash: float = 0.0
var last_touch: int = -1
