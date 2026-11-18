# Repository instructions — codex-sync

## Purpose

Maintain a small Bash utility for bidirectional project-directory synchronization over SSH and rsync, originally extracted from `wsl-scripts/scripts/sync-codex.sh`. The original source and Fish wrappers are reference material only; never modify `wsl-scripts` as part of this project.

Read `specs/001-sync-behavior.md` before implementing or changing functionality. The specification is authoritative for CLI behavior, configuration, exclusions, deletion, and installation. If a requirement is unclear or conflicts with implementation constraints, report it rather than silently inventing behavior.

Whenever behavior, CLI options, defaults, security or exclusion rules, configuration, or tests change, update the relevant files under `specs/` in the same change so the specifications always describe implemented behavior and current test coverage. Record any needed user-documentation changes in `docs/SCRATCHPAD.md`; do not update official documentation as a side effect of implementation.

Keep the scope narrow: do not expand Git use beyond the specified optional marker-creation hint and best-effort version metadata, or add sandbox provisioning, SSH configuration management, a Python runtime, or a general-purpose synchronization framework.

## Structure and conventions

Use `bin/codex-sync` as the Bash implementation, with lightweight executable `bin/cpush` and `bin/cpull` wrappers. Include `install.sh`, `uninstall.sh`, `README.md`, `LICENSE`, `specs/`, and `tests/` where useful. Do not add boilerplate without a clear purpose.

Target Debian/Linux, Bash, rsync, and OpenSSH. Use `#!/usr/bin/env bash`, `set -euo pipefail`, careful quoting, and explicit error handling. Format with shfmt, lint with ShellCheck, and check with `bash -n`. Do not depend on Fish; wrappers must work from any shell that can execute them.

The `VERSION` constant near the top of `bin/codex-sync` is manually updated only for explicit releases, never for routine edits.

Keep configuration under `${XDG_CONFIG_HOME:-$HOME/.config}/codex-sync/`. Never place real credentials or personal host information in tracked files.

## Safety and implementation

Preserve the specification’s deletion, exclusion, validation, and assisted-creation safeguards. Review shell quoting and physical path resolution carefully, especially at SSH/rsync boundaries. Do not claim that exclude patterns guarantee secret protection.

Keep the current project's user data untouched during development. Never run a real sync against a user's SSH host or projects without explicit permission.

## Testing and delivery

Write self-contained Bash tests under `tests/`, mocking SSH/rsync where possible. Retain the safety and interaction coverage listed in the specification. Do not require a real remote host or add a testing framework.

Before reporting completion, run `bash -n`, shfmt checks, ShellCheck (when available), and tests. State which checks passed or could not run.

## Documentation

Keep `README.md` concise as the end-user entry point: purpose, requirements, installation, essential usage and configuration, `.codexignore`, important deletion and secrets warnings, and uninstall guidance. Put extended user-facing guidance in `docs/` only when it warrants a separate page. Keep detailed behavioral contracts and edge cases in `specs/`, and standing agent/developer rules in `AGENTS.md`. Do not put development instructions, testing commentary, architecture internals, or implementation notes in the README.

Do not modify `README.md` or other official user documentation unless explicitly requested. During implementation, record potential documentation additions, corrections, or removals in `docs/SCRATCHPAD.md` instead. Keep observations concise and contextual; create the file only when needed. Review them separately when requested, then clear or delete the file. The scratchpad is temporary, not a journal or backlog. Maintain the accuracy of official user documentation through these dedicated reviews.

## Language policy

Use the user's language for conversation, specifications, and reports. Use English by default for code, comments, documentation, logs, and CLI output unless explicitly requested otherwise. Specify UI language per project; never infer it from the user's language or source code.

Do not initialize Git unless explicitly requested. Preserve unrelated user changes and report deviations from the specification.
