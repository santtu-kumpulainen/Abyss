# Audio — sources and licenses

Only the audio files the game uses, or has planned for upcoming room objects, are tracked in Git (Issue #53). The rest of each pack stays local, and every excluded file is listed explicitly in the root `.gitignore`. Original files and filenames are preserved unmodified. The sound event catalog is `scripts/audio/sound_library.gd`.

- **Minifantasy – Dungeon Music** (`Minifantasy_Dungeon_Music/`) by Leohpaz, https://leohpaz.itch.io.
  - **License:** see `Licensing.txt`: personal and commercial use is allowed, the pack itself may not be sold or redistributed. Credits are optional but appreciated (`Acknowledgements.txt`, `Patreon_Leohpaz.url`).
  - **Tracked:** `Goblins_Den_(Regular).wav` (normal gameplay and Main Menu) and `Goblins_Dance_(Battle).wav` (miniboss and boss encounters). Both are imported with forward looping.
- **Minifantasy – Dungeon SFX** (`Minifantasy_Dungeon_SFX/`) by Leohpaz.
  - **License:** this folder ships without its own licence file. The Minifantasy licence above is assumed to apply (same author and series; permission confirmed by the project owner).
  - **Tracked:** 33 of 62 files. 24 are used now (Mage hurt, death and dash; Goblin attacks, hurt and death; Blood Monster charge; Abyss Warden slam; chest open; room doors). 9 are kept for planned room objects (chest close, crate open, sack open).
  - **Local only:** human attack, charge, jump and footstep sounds, orc jump, footsteps and charging loop, sword hit and miss.
- **Magic Spells SFX Lite** v2.1 (`magic_spells_sfx_lite/`) by Willosuna, https://willosuna.itch.io/magic-spells-sfx-lite.
  - **License:** see `LICENSE.txt`: royalty free for commercial use, attribution not required. The audio may not be resold or redistributed as a sound pack, library or collection. `README.txt` is the pack's original readme.
  - **Tracked:** the 17 used `wav/` sounds: fire, water, void and blood cast/impact, summon, teleport, debuff, portal, shadow, heal, buff, rune, shield break, magic level up.
  - **Local only:** the 25 unused WAVs, `manifest.json` and `ogg/`. The OGGs duplicate the WAVs, and `ogg/` carries a local `.gdignore` so Godot does not import them.

To start using a local-only sound, remove its line from `.gitignore` and add it to `scripts/audio/sound_library.gd`.
