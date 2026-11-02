# Player sprites — Craftpix Swordsman

Source: Craftpix.net Swordsman character pack (levels 1–3). Original filenames and
pack folders are preserved. Use is subject to the Craftpix license
(https://craftpix.net/file-licenses/). Put the pack's license or readme file here
if it came with one.

## Layout

```
level_<N>/
  With_shadow/   # sprite sheets used by the Player scene
  Parts/         # separated layers (body, head, sword, ...) — currently level 1 only, unused
```

`Without_shadow/` and `Tiled_files/` are not used. Tiled_files holds Tiled `.tmx` data, not Godot assets.

## Sheet format (same for every level)

- Frame size: 64×64 px
- Rows, top to bottom: `down`, `left`, `right`, `up`
- Columns: animation frames

| Sheet (`Swordsman_lvl<N>_<name>_with_shadow.png`) | Godot animation | Frames | Loop |
|---|---|---|---|
| Idle | `idle_<dir>` | 12 | yes |
| Walk | `walk_<dir>` | 6 | yes |
| Run | `run_<dir>` | 8 | yes |
| attack | `attack_<dir>` | 8 | no |
| Walk_Attack | `walk_attack_<dir>` | 6 | no |
| Run_Attack | `run_attack_<dir>` | 8 | no |
| Hurt | `hurt_<dir>` | 5 | no |
| Death | `death_<dir>` | 7 | no |

## Generating SpriteFrames

```
godot --headless --path . --import
godot --headless --path . --script res://tools/build_player_sprite_frames.gd -- <N>
```

This writes `scenes/player/sprite_frames/player_level_<N>.tres`. To change the
player's visuals, assign a different resource to the Player's exported
`sprite_frames` property.
