# GBA Pong

Pong at Game Boy Advance limits: 240x160, integer-scaled pixels, a small 15-bit palette,
a 3x5 pixel font and square-wave blips. Made with Godot 4.7.2.

**Controls:** Up / Down arrows (or a gamepad d-pad). First to 7 wins.

**Power-ups** spawn in the middle of the court. A ball collects one when it flies through it,
for whoever touched that ball last (a freshly served ball collects nothing):

| Icon color | Power-up | Effect |
|---|---|---|
| yellow | FAST BALL | that ball speeds up 35% |
| white | MULTI BALL | two extra balls split off it |
| green | BIG PADDLE | collector paddle 1.5x taller |
| cyan | QUICK PADDLE | collector paddle 1.5x faster |
| red | SHRINK FOE | opponent paddle 0.6x as tall |
| purple | SLOW FOE | opponent paddle 0.6x as fast |

Paddle effects last 8 seconds (tunable) and show as icons with timers in the top corners.
With several balls in play, each ball that gets past a paddle scores, and the next serve
waits until the last ball is gone.

**Debug menu:** F1 or ` (backtick). Up/Down pick, Left/Right change (Shift for 5 steps),
Enter to spawn a power-up or reset. Changes are saved (in the browser for the web build).

## Play

Natively:

```
godot --path .
```

In the browser (after exporting):

```
godot --headless --path . --export-release "Web" build/web/index.html
npx http-server build/web -p 8139      # in PowerShell: npx.cmd http-server build/web -p 8139
```

Then open http://localhost:8139.

## Develop

```
godot --headless --path . -s res://test/test_rules.gd   # rule tests
```

Game code: `scenes/main.gd` (game, power-ups, debug menu), `scripts/tuning.gd` (all
tunable values and their ranges), `scripts/pixel_font.gd`, `scripts/ball.gd`.
