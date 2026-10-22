extends RefCounted
## Reads the hand-editable game content in res://content/*.cfg (power-ups, upgrades, relics,
## opponents, music). Each [section] becomes an entry, in file order. Color strings like
## "#f88020" (in a "color" key or a "colors" list) become Colors.

const DIR := "res://content/"


static func table(file: String) -> Dictionary:
	var cfg := ConfigFile.new()
	var err: int = cfg.load(DIR + file + ".cfg")
	if err != OK:
		push_error("Could not read content/%s.cfg (error %d)" % [file, err])
		return {}
	var out: Dictionary = {}
	for section in cfg.get_sections():
		var entry: Dictionary = {}
		for key in cfg.get_section_keys(section):
			var value: Variant = cfg.get_value(section, key)
			if key == "color" and value is String:
				value = Color.html(value)
			elif key == "colors" and value is Array:
				value = value.map(func(c: Variant) -> Color: return Color.html(c) if c is String else c)
			entry[key] = value
		out[section] = entry
	return out


## A number from an entry, or fallback when the file leaves it out.
static func num(entries: Dictionary, id: String, key: String, fallback: float) -> float:
	return float(entries.get(id, {}).get(key, fallback))
