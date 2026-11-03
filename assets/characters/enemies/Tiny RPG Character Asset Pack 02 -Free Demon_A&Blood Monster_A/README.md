# Enemy sprites — Tiny RPG Character Asset Pack 02 (free: Demon_A, Blood Monster_A)

Source: Zerie, https://zerie.itch.io/tiny-rpg-character-asset-pack-02
The download did not include a license file; use is subject to the terms on the
itch.io page above. Original filenames and folders are preserved.

## Used

- `Characters(100x100 split)/<Name>/<Name> with shadows/<Name>_Idle.png` and `_Walk.png`
  → `scenes/enemies/sprite_frames/{demon,blood_monster}.tres`
  (built with `tools/build_tiny_rpg_sprite_frames.gd`).

Not imported (`.gdignore`): `Aseprite file/` and the shadowless `<Name>/<Name>/` strips.
Attack01/Attack02, Hurt and Death strips are imported but not used yet.

## Sheet format

- Horizontal strips of 100×100 px frames, side view facing right (mirrored in game
  via `Enemy.side_view`). The character is ~20 px tall, feet near y = 60.
- Frames: Idle 6, Walk 8, Attack01/02 8 (Demon 7), Hurt 4, Death 4.
- `<Name>.png` is all strips combined (rows: Idle, Walk, Attack01, Attack02, Hurt, Death).
