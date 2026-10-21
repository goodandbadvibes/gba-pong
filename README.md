# GBA Pong

Pong at Game Boy Advance limits: 240x160, integer-scaled pixels, a small 15-bit palette,
a 3x5 pixel font and square-wave blips. Made with Godot 4.7.2.

**Controls:** Up / Down arrows (or a gamepad d-pad). First to 7 wins.

## Play

Natively:

```
godot --path .
```

In the browser (after exporting):

```
godot --headless --path . --export-release "Web" build/web/index.html
npx http-server build/web -p 8139
```

Then open http://localhost:8139.

## Develop

```
godot --headless --path . -s res://test/test_rules.gd   # rule tests
```

All game code is in `scenes/main.gd`.
