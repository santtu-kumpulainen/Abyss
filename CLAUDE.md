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


# Abyss - Development Workflow Rules

## Git and GitHub Permissions

Claude Code is authorized to:

- Create GitHub Issues.
- Add comments to existing Issues when necessary.
- Create new feature branches.
- Switch to existing branches when instructed.
- Inspect Git status, history and diffs.
- Modify project files and run tests.

Claude Code MUST NEVER:

- Stage changes (`git add`).
- Create commits (`git commit`).
- Push changes (`git push`).
- Create Pull Requests.
- Merge Pull Requests or branches.
- Delete branches.
- Rewrite Git history.

The user is responsible for all staging, commits,
pushes, Pull Requests and merges.

Claude must remind the user of the appropriate Git
commands when a development stage is complete.

## Issue and Branch Workflow

For new features:

1. Review the feature requirements.
2. Create a detailed GitHub Issue.
3. Add clarifying comments when necessary.
4. Create a feature branch using the Issue number.
5. Switch to the new branch.
6. Implement the feature.
7. Run relevant tests.
8. Review all changes.
9. Report the results and recommended Git commands.

Never create commits or Pull Requests.

## Model Selection

Use Claude Opus for:

- Architecture and system design.
- Complex gameplay mechanics.
- Large refactoring tasks.
- Difficult debugging.
- Technical decision-making.

Use Claude Sonnet for:

- Small and clearly defined implementation tasks.
- UI components.
- Documentation.
- Focused bug fixes.
- Routine tests and code reviews.

## Agent Usage

Multiple agents may be used when parallel work
provides a meaningful benefit.

Default to 1-2 agents in addition to the main agent.
Use a maximum of 3 agents unless explicitly authorized.

Avoid:
- Duplicate investigations.
- Simultaneous edits to the same files.
- Unnecessary agent delegation.
- Excessive context duplication.

The main agent is responsible for coordination
and final integration.

## Development Safety

- Explain the goal before choosing an approach.
- Inspect existing architecture before modifying it.
- Warn before destructive Docker or Git operations.
- Do not execute destructive operations without
  explicit user approval.
- Do not overwrite unrelated user changes.
- Preserve existing project functionality.
- Explain briefly what was implemented and why.

## Completion Report

At the end of each implementation task, report:

1. Changes implemented.
2. Files modified.
3. Tests executed and results.
4. Remaining issues.
5. Recommended manual Git commands.

Leave all changes uncommitted for user review.
