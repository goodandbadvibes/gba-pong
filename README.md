# GBA Pong

Pong at Game Boy Advance limits: 240x160, integer-scaled pixels, a small 15-bit palette,
a 3x5 pixel font and square-wave blips. Made with Godot 4.7.2.

**Play online:** https://tuomassoukka-prog.github.io/gba-pong/

**How a run works:** points win a *game* (first to 3), games win a *round* (best of 5), and
each round is one node on the map. Win a round to pick one of three upgrades and move to the next
node; lose one and the run is over. Opponents get faster and aim better every level, and every 5th
level is a boss. When a run ends you earn gems (2 per round cleared, 5 per boss, plus gem shards you
collected), and your best run is saved.

**Controls:** Up / Down arrows (or a gamepad d-pad); Left / Right and Enter on the upgrade screen.
On a phone or tablet, swipe anywhere to move your paddle and tap to continue; on the upgrade screen
tap a card, then tap it again to take it. ON SCREEN BUTTONS in the debug menu adds hold-to-move
buttons.

**Upgrades** (last for the whole run, stack a few levels):

| Upgrade | Effect |
|---|---|
| FLAME BALL | balls you hit catch fire; a burning hit makes the CPU paddle shrink until the burn ends |
| SLIME BALL | balls you hit turn slimy; a slimy hit slows the CPU paddle until it wears off |
| MAGNET BALL | balls you hit pull in nearby power-ups and gem shards |
| LONG PADDLE | +15% paddle size per level |
| SWIFT PADDLE | +15% paddle speed per level |
| POWER HIT | balls you hit fly 12% faster per level |
| LUCKY FIND | more power-ups and gem shards, shards worth more |
| BIG GRAB | your balls collect things from further away |

**Power-ups** spawn mid-court and go to whoever touched the ball that collects them last (a freshly
served ball collects nothing). Gem shards only count for balls you hit.

| Icon color | Power-up | Effect |
|---|---|---|
| yellow | FAST BALL | that ball speeds up 35% |
| white | MULTI BALL | two extra balls split off it |
| green | BIG PADDLE | collector paddle 1.5x taller |
| cyan | QUICK PADDLE | collector paddle 1.5x faster |
| red | SHRINK FOE | opponent paddle 0.6x as tall |
| purple | SLOW FOE | opponent paddle 0.6x as fast |

**Debug menu:** F1 or ` (backtick), or tap the top center of the screen (touch screens get a
tappable UP / DOWN / - / + / OK / CLOSE bar). It has every tunable value (match length, opponent
difficulty per level, boss strength, power-up hitbox, upgrade timings and more), plus buttons to win
or lose the current round, add any upgrade, spawn power-ups or gems, and reset settings or saved
progress. Settings and progress are saved (in the browser for the web build).

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

Publish to GitHub Pages (after exporting):

```
node tools/deploy-pages.mjs
```

## Develop

```
godot --headless --path . -s res://test/test_rules.gd   # rule tests
```

Game code: `scenes/main.gd` (court, rounds, power-ups, upgrades in play, debug menu),
`scripts/screens.gd` (title, map, upgrade and run-over screens), `scripts/run.gd` (run progress
and saved best/gems), `scripts/upgrades.gd`, `scripts/tuning.gd` (every tunable value),
`scripts/pixel_font.gd`, `scripts/palette.gd`, `scripts/ball.gd`.
