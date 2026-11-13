# Abyss

Abyss is a small 2D top-down action roguelite made with Godot 4 and GDScript. You play a Mage who fights through a seeded grid of dungeon rooms, collects Ancient Seals to unseal the boss, and then continues into deeper dungeon levels. It is a solo course project, built as a small playable MVP and still in development.

## About the Game

- **Genre:** action roguelite with real-time combat.
- **Perspective:** 2D, top-down, with pixel-art characters and tiles.
- **Atmosphere:** dungeon, cave and crypt rooms with themed visuals, dungeon music and sound effects.
- **Main objective:** clear rooms to earn Ancient Seals, unseal and defeat the boss of the current dungeon level, then descend to the next level. Levels continue endlessly and get harder.

## Gameplay

A run starts from the main menu, where you choose a difficulty tier and an optional Pact. The run begins in a Home room that holds an Anvil and a controls guide on the floor. From there you explore a seeded 5x5 grid of rooms, shown on a minimap.

- **Movement and combat:** move with WASD, aim with the mouse and hold the left mouse button to cast Fire Ball. Space dashes.
- **Exploration:** rooms are connected by doors. Combat rooms must be cleared to be rewarded. Survival trials and treasure rooms offer optional challenges.
- **Seals and the boss:** each dungeon level plans a fixed number of seal rooms (treasure rooms and miniboss rooms). Clearing them reveals Ancient Seals, which are needed to unseal the boss gate. The boss room is also gated by the Mage's level.
- **Progression:** defeated enemies give XP and gold. XP raises the Mage's level, and gold buys upgrades and supplies at an Anvil. See [Progression](#progression).
- **Death and victory:** when the Mage dies the run ends and can be restarted. Defeating the boss shows a relic choice and a run summary.

## Features

Implemented:

- Mage with a hold-to-cast Fire Ball (data-driven spell system) and a dash.
- Seeded 5x5 dungeon layout with doors, a minimap and per-level encounter planning.
- Room types: combat rooms (arena, cave and crypt scenes), a Home room, survival trials, treasure rooms (a timed challenge altar and a rune sequence puzzle), miniboss rooms and a boss room.
- Anvil upgrade stations, supply purchases and consumable items in an ability bar (Health Potion, Speed Potion, Home Teleport).
- Relics, optional Pacts chosen before a run, and relic synergies.
- Difficulty tiers (Normal, Hard, Abyssal), unlocked in order.
- Endless dungeon levels with biomes.
- Health bars, hit feedback, knockback and enemy death animations.
- Central audio system with music and sound effects.
- Main menu with a Settings screen that lists the controls, and an in-world controls guide in the Home room.
- Victory and game-over screens with a run summary.

Planned or unfinished items are listed under [Development Status](#development-status).

## Controls

Keyboard and mouse. These are the bindings in `project.godot`; the same list is shown in the game under Settings (gear button in the main menu) and in the Home room, generated from `scripts/ui/controls_info.gd`.

| Input | Action |
| --- | --- |
| W A S D | Move |
| Mouse | Aim |
| Left click (hold) | Cast Fire Ball |
| Space | Dash |
| E | Interact (Anvil, chests, altars, runes) |
| 1, 2, 3 | Use item slots (drag to reorder) |
| 1-4 | Buy upgrade (only while an Anvil menu is open) |
| 5-7 | Buy supply (only while an Anvil menu is open) |

An open Anvil menu uses keys 1-7, so the item slots are not triggered while it is open.

## Enemies and Combat

Combat is real-time. Most special attacks are telegraphed: the danger area is drawn on the floor before the hit lands, so it can be dodged. Enemies have health bars, and hits give visual feedback and knockback.

Regular enemies (`scenes/enemies/`):

- **Demon:** a basic melee enemy that chases the Mage and deals contact damage.
- **Giant Goblin:** a melee pursuer. It uses sword swings with a telegraphed sector, then a stronger special strike, then recovers.
- **Blood Monster:** a slow, heavy elite. It uses a telegraphed straight-line dash and leaves a delayed blast when it dies.
- **Demon Caster:** a ranged enemy that keeps its distance and fires projectiles. A Water Caster variant replaces it in a later biome.

Minibosses (found in seal rooms; their attacks are telegraphed and some give a punish window):

- **Brood Mother:** summons Demons, takes extra damage while channelling, and uses a telegraphed charge.
- **Hexcaller:** creates lingering hex zones on the floor, fires a fan of bolts, and blinks across the room.
- **Water Caster (miniboss):** fires large bouncing water bolts and staggered water zones.

Boss:

- **Abyss Warden:** a slow boss with three health phases. It fires bolt volleys, slams the area around it with a growing circle, and adds rings of bolts in its last phase.

## Progression

- **Mage level:** XP from defeated enemies raises the Mage's level. Higher levels make the Mage stronger and unlock level-gated rooms and Anvil upgrades.
- **Anvil upgrades and supplies:** gold buys upgrades (some are level-locked) and consumable supplies.
- **Items and relics:** items are found in rooms and as miniboss rewards; a relic is chosen after the boss. Some relics combine with a Pact into a synergy.
- **Pacts:** an optional Pact chosen before the run gives a benefit and a drawback for the whole run.
- **Difficulty tiers:** Hard and Abyssal are unlocked by completing the previous tier. Higher tiers make enemies tougher, add pressure to encounters and increase gold rewards.
- **Dungeon levels:** each level makes enemies stronger. Regular enemies, minibosses and the boss scale along separate paths, and the biome changes every few levels. The exact values are still being tuned and are not documented here.

## Screenshots

No screenshots have been added yet. To add some, place the images in a new folder (for example `docs/screenshots/`) and reference them here with standard Markdown image syntax. Useful shots: the main menu, the Home room controls guide, a combat room, an Anvil menu and the boss fight.

## Technology

- **Engine:** Godot 4.7 (`config/features` in `project.godot` lists `4.7` and Forward Plus).
- **Language:** GDScript (typed, tab-indented).
- **Structure:** scenes and resources for rooms, enemies and UI; autoloads for progression (`Progression`) and audio (`Audio`); SpriteFrames generated by helper scripts; headless test suites written as `SceneTree` scripts.

## Project Structure

- `scenes/`: Godot scenes (`.tscn`) for the dungeon, rooms, enemies, items, spells, UI and the Mage, plus generated `sprite_frames/`.
- `scripts/`: GDScript sources grouped by area (`dungeon`, `enemies`, `mage`, `progression`, `rooms`, `spells`, `ui`, `audio` and others).
- `assets/`: third-party art and audio (see [License](#license)).
- `tools/`: headless helper scripts: sprite-frame builders (`build_*.gd`) and the test suites (`test_*.gd`).
- `CLAUDE.md`: project conventions and workflow notes.

## Getting Started

1. Install Godot 4.7 (the version in `project.godot`).
2. Clone the repository and open the folder in the Godot project manager (select `project.godot`).
3. Press Play (F5). The main scene is the main menu (`res://scenes/ui/main_menu.tscn`).

### Running the tests

Each suite in `tools/test_*.gd` extends `SceneTree`, prints PASS/FAIL lines and a final RESULT, and exits with a non-zero code on failure. With the Godot executable available as `godot`:

```
godot --headless --path . --import
godot --headless --path . --script res://tools/test_<name>.gd
```

Run the import step once (and after adding assets), then run any suite by name, for example `test_dungeon.gd`. Headless runs render nothing, so visual changes still need a manual check in the editor.

### Development workflow

One GitHub Issue per feature or task, one `feature/<issue>-<short-name>` branch, one Pull Request. Work is not done directly on `main`.

## Development Status

Abyss is an MVP in active development and has not been released. The core loop (menu, run, rooms, seals, boss, relic choice, next level) is implemented and covered by headless tests. Current work (Issue #55) is MVP polish: the controls guide and the balance of enemy difficulty scaling. Balance values may still change after playtesting.

Known limits:

- Keyboard and mouse only: no gamepad bindings and no control rebinding.
- One playable character (the Mage) with one spell.
- Balance and polish are not final.

## Roadmap

Only items tracked in the repository's GitHub Issues are listed:

- Finish the MVP polish in Issue #55 (controls guide and enemy difficulty scaling).
- Blood Monster splitting is marked out of scope in Issue #55 and noted there as a possible follow-up issue.

Nothing else is planned yet.

## License

The project's own source code is licensed under the MIT licence in [`LICENSE`](LICENSE).

The third-party art and audio under `assets/` are **not** covered by that licence. Each asset pack keeps its original author's licence, found in the licence and readme files inside its folder (e.g. `assets/audio/README.md`, `assets/effects/README.md`, `assets/characters/player/README.md`). Only the asset files the game uses are included. They may not be extracted or redistributed separately from the game except as their own licences allow.
