extends RefCounted
## 3x5 pixel font drawn with rects, so text stays on the GBA pixel grid.

const GLYPHS := {
	"0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"],
	"2": ["111", "001", "111", "100", "111"], "3": ["111", "001", "111", "001", "111"],
	"4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "111", "001", "111"],
	"6": ["111", "100", "111", "101", "111"], "7": ["111", "001", "010", "010", "010"],
	"8": ["111", "101", "111", "101", "111"], "9": ["111", "101", "111", "001", "111"],
	"A": ["010", "101", "111", "101", "101"], "B": ["110", "101", "110", "101", "110"],
	"C": ["011", "100", "100", "100", "011"], "D": ["110", "101", "101", "101", "110"],
	"E": ["111", "100", "110", "100", "111"], "F": ["111", "100", "110", "100", "100"],
	"G": ["011", "100", "101", "101", "011"], "H": ["101", "101", "111", "101", "101"],
	"I": ["111", "010", "010", "010", "111"], "J": ["001", "001", "001", "101", "010"],
	"K": ["101", "101", "110", "101", "101"], "L": ["100", "100", "100", "100", "111"],
	"M": ["101", "111", "111", "101", "101"], "N": ["110", "101", "101", "101", "101"],
	"O": ["010", "101", "101", "101", "010"], "P": ["110", "101", "110", "100", "100"],
	"Q": ["010", "101", "101", "110", "011"], "R": ["110", "101", "110", "101", "101"],
	"S": ["011", "100", "010", "001", "110"], "T": ["111", "010", "010", "010", "010"],
	"U": ["101", "101", "101", "101", "111"], "V": ["101", "101", "101", "101", "010"],
	"W": ["101", "101", "111", "111", "101"], "X": ["101", "101", "010", "101", "101"],
	"Y": ["101", "101", "010", "010", "010"], "Z": ["111", "001", "010", "100", "111"],
	".": ["000", "000", "000", "000", "010"], ":": ["000", "010", "000", "010", "000"],
	"-": ["000", "000", "111", "000", "000"], "+": ["000", "010", "111", "010", "000"],
	"!": ["010", "010", "010", "000", "010"], "/": ["001", "001", "010", "100", "100"],
	">": ["100", "110", "111", "110", "100"], "<": ["001", "011", "111", "011", "001"],
	"%": ["101", "001", "010", "100", "101"], "?": ["111", "001", "010", "000", "010"],
	"'": ["010", "010", "000", "000", "000"], ",": ["000", "000", "000", "010", "100"],
	" ": ["000", "000", "000", "000", "000"],
}

enum Align { LEFT, CENTER, RIGHT }


## Splits text into lines of at most max_chars, breaking at spaces.
static func wrap(text: String, max_chars: int) -> Array[String]:
	var lines: Array[String] = []
	var line: String = ""
	for word in text.split(" ", false):
		if line.is_empty():
			line = word
		elif line.length() + 1 + word.length() <= max_chars:
			line += " " + word
		else:
			lines.append(line)
			line = word
	if not line.is_empty():
		lines.append(line)
	return lines


static func width(text: String, scale: int = 1) -> int:
	return maxi(0, text.length() * 4 * scale - scale)


## Draws text on canvas; x is the left edge, center or right edge depending on align.
static func draw(canvas: CanvasItem, text: String, x: int, y: int, scale: int, color: Color, align: Align = Align.LEFT) -> void:
	var left: int = x
	if align == Align.CENTER:
		left = x - width(text, scale) / 2
	elif align == Align.RIGHT:
		left = x - width(text, scale)
	for ch in text.to_upper():
		var glyph: Array = GLYPHS.get(ch, GLYPHS[" "])
		for row in 5:
			for col in 3:
				if glyph[row][col] == "1":
					canvas.draw_rect(Rect2(left + col * scale, y + row * scale, scale, scale), color)
		left += 4 * scale
