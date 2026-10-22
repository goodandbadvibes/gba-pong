# GBA Pong

Pong at Game Boy Advance limits: 240x160, integer-scaled pixels, a small 15-bit palette,
a 3x5 pixel font and square-wave blips. Made with Godot 4.7.2.

**Play online:** https://tuomassoukka-prog.github.io/gba-pong/

**How a run works:** points win a *game* (first to 3), games win a *round* (best of 5), and
each round is one node on the map. A run starts with a free pick of one of three upgrades. Win a
round to pick another and move to the next
node; lose one and the run is over. Every 2 levels the map stops at a **relic shop**. Opponents get faster and aim better every level, gain one random upgrade per level after the
first (their burn, slime and poison hit you too), and every 5th level is a boss. You earn gems as you go (2 per round cleared, 5 per boss, plus gem shards you collect) and
spend them on relics. Your best run and gems are saved, and a run can be suspended and continued.

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
| WINGMAN | every game starts with an extra paddle per level that patrols up and down in front of yours |
| VENOM BALL | balls you hit are poisonous; enough poison freezes the foe paddle for a second and costs its wingmen and turrets 1 HP |
| OVERCHARGE | every game starts with a booster, 2 seconds per level |
| TURRET | a turret per level guards your side and swats balls that come close; it rebuilds after a cooldown |

**Wingmen and turrets** have HP (2 hits by default); every ball they hit costs one. Wingmen
patrol on their own; turrets stay put and hit balls within reach, with the same effect as a
paddle hit. The WINGMAN and TURRET power-ups give either side a one-off wingman or turret.

**Relics** (shop, once per run each):

| Relic | Effect |
|---|---|
| HIVE MIND | your turrets use your upgrades (flame, slime, power hit) |
| WING SYNC | your wingmen use your upgrades |
| VIRULENT | burn and slime last 50% longer and hit 50% harder |
| SPLITTER | each paddle hit has a chance to split off an extra ball |
| MOMENTUM | +6% paddle size and speed per game won in a row; losing a game resets it |
| THICK PLATING | your wingmen and turrets take one more hit |
| QUICK REPAIR | destroyed turrets rebuild twice as fast |
| SECOND WIND | once per run, a lost round does not end the run |
| GEM TITHE | +2 gems for every round cleared |

**Pause:** Esc, P or the II button in the top-left corner. Resume, sound on/off, view your relics,
suspend the run (continue it from the title), end the run and go to the main menu, or quit
(desktop only). Relics are also shown on the map.

**Music** is generated in code with GBA-style channels (two pulse waves, a 4-bit wave bass and
LFSR noise, 8-bit at 16 kHz). It starts as a low pulse and gets more layers every level; the tempo
rises each level and again with every game inside a level. The map and upgrade screens have
their own calm track and the shop a bouncy one. The debug menu sets volume, base tempo, tempo per level, a fixed intensity and each layer
(OFF / AUTO / ON).

**Power-ups** spawn mid-court and go to whoever touched the ball that collects them last (a freshly
served ball collects nothing). Gem shards only count for balls you hit. After 30 seconds in a round, power-ups start
coming twice as often (both tunable).

| Icon color | Power-up | Effect |
|---|---|---|
| purple | POISON | 4 poison on the collector's foe |
| pale yellow | BOOSTER | for 6 seconds all the collector's modifiers work 1.5x as hard |
| periwinkle | WINGMAN | a one-off extra paddle for the collector |
| gold | TURRET | a one-off turret for the collector |
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
`scripts/screens.gd` (title, map, upgrade, shop, run-over and pause screens), `scripts/run.gd` (run
progress, save, suspend), `scripts/upgrades.gd`, `scripts/relics.gd`, `scripts/music.gd`, `scripts/tuning.gd` (every tunable value),
`scripts/pixel_font.gd`, `scripts/palette.gd`, `scripts/ball.gd`.
