# Abyss — project instructions

## Project overview
- Abyss is a small 2D top-down action roguelite built with Godot 4 (4.7) and GDScript.
- Solo course project on a limited schedule: a realistic, playable MVP comes before new features.
- Keep MVP scope and technical decisions consistent with the project documentation and GitHub Issues.

## Development workflow
- One GitHub Issue per feature/task → one branch (`feature/<issue>-<short-name>`) → one PR.
- Never implement project work directly on `main`.
- Before starting, inspect the repo, `git status`, existing Issues and relevant files.
- Use `/start-issue` to identify or create the Issue and create/switch to its branch.
- Stay within the Issue scope. If scope needs to change, explain why and ask first.
- Do not commit, push, create PRs or merge. The user does this with `/commit` and `/pr`.
- After a PR is merged, switch to `main` and pull before starting the next Issue.
- Follow the installed skills; don't duplicate their instructions here.

## Minimal changes and token efficiency
- Inspect before editing; understand and reuse the existing implementation.
- Change only what the current task requires; prefer targeted edits to full-file rewrites.
- No unrelated refactors, renames or folder reorganisation without a clear requirement.
- Don't regenerate generated assets/resources (e.g. SpriteFrames `.tres`) unless they must change.
- In reports, summarise changes and reference file paths instead of repeating file contents.
- Use targeted inspection; don't reread or reprocess large files unnecessarily.
- Preserve existing working functionality.
- Ask before destructive changes or deleting user assets.

## Godot conventions
- Use the project's Godot version and existing GDScript style (tabs, typed GDScript).
- Layout: `scenes/` (`.tscn`, generated `sprite_frames/`), `scripts/` (`.gd`), `assets/` (third-party art/audio), `tools/` (headless helper scripts).
- Use Godot resources and scene references (exports, `ExtResource`) instead of hardcoded paths where practical.
- Preserve original third-party asset files, filenames and license/credit info (see `assets/characters/player/README.md`).
- Keep gameplay systems modular and scoped to the current Issue.
- Validate when possible: `godot --headless --path . --import`, then load/run the relevant scenes headless.
- Report which tests were run and what was not tested.

## Git and repository safety
- Check `git status` before making changes.
- Don't discard, overwrite or stage unrelated user changes.
- Never use destructive Git commands (reset, force-push, clean, etc.) without explicit approval.
- Keep `.godot/` and other generated editor/cache files ignored; commit `.import` and `.uid` files.
- `CLAUDE.md` is tracked by Git; never add it to `.gitignore`.
