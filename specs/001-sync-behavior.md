# 001 — Synchronization behavior

Status: current implementation contract

## Goal

`codex-sync` synchronizes a marker-defined local project with `~/<project-name>` on an SSH-accessible host using rsync. The assistance flows below can create a missing local marker or remote push destination; the tool does not provision workspaces. Git is optional and used for a marker-creation location hint and best-effort build metadata.

## Commands

- `codex-sync push [options]`: local to remote.
- `codex-sync pull [options]`: remote to local.
- `codex-sync inspect`: read-only local inspection; accepts `--help` and `--version`, rejects transfer options and positional arguments. All other subcommands, including `ignore`, are rejected.
- `cpush` and `cpull`: executable wrappers forwarding all arguments to `codex-sync push` and `codex-sync pull`, respectively.
- `--version` prints `codex-sync` followed by the verified display version; help uses identical version text. The manually maintained VERSION identifies the intended release and is never a fallback for unknown provenance.
- Checkout metadata uses optional `git describe --tags --always --long --dirty`, matching numeric-looking tags and validating numeric `X.Y.Z-N-gHASH[-dirty]` or `HASH[-dirty]` output. A clean exact tag matching VERSION displays VERSION alone. Other valid tagged descriptions retain the tag, distance, hash and optional dirty suffix unchanged. Hash-only output displays `?.?.?-gHASH[-dirty]`. Missing Git, failed describe, invalid output or unavailable provenance displays `?.?.?`. Dirty follows Git describe semantics (tracked changes, not untracked files). Only the source root's own repository is considered, never an enclosing repository; invocation cwd does not select metadata. No hashes or release versions are invented.
- `scripts/build-metadata.sh [OUTPUT]` reads VERSION as literal data without executing application code. Without OUTPUT it prints the verified display version. With OUTPUT it stamps a separate copy's empty BUILD_METADATA constant with that complete display version, preserving an existing package stamp. Installation compares and stages these prospective bytes, retaining identical-file behavior. Packages need no Git or helper at runtime; an official clean tagged package retains its exact release version. Stamps contain no timestamps or absolute paths and are deterministic; source VERSION is never rewritten.
- Installer automation runs all tests and lint on every push to main, then builds an installer. Numeric version tag pushes build and validate an installer without the full test/lint suite. Only numeric version tags can publish draft releases; main builds are never published. See Version and release support below for the artifact provenance contract.
- Transfer options: `--dry-run/-n`, `--no-delete`, `--force/-f`, `--cleanup/-c`, `--interactive/-i`, `--progress/-p`, `--no-progress`, `--quiet/-q`, `--verbose/-v`, `--no-color`, `--help/-h`, `--version`. Short flags compose, for example `-ncp`. No positional operands or arbitrary rsync flags are accepted.
- Inspect additionally accepts `--no-color` and `-h`; transfer flags remain invalid. Quiet/verbose and progress/no-progress use the last encountered setting.
- No arguments prints usage to stderr and exits 2. Unknown commands/options and positional arguments fail with status 1.
- Help/version exit successfully as soon as encountered: top-level forms ignore trailing arguments; subcommand options are processed left to right, so an earlier invalid argument still fails. Repeated transfer flags are accepted.

`codex-sync` runtime errors are red and diagnostic warnings yellow only when stderr is a terminal and `NO_COLOR` is unset and `--no-color` was not supplied. Any value of `NO_COLOR`, including empty, disables color. Reset color immediately after each diagnostic; redirected diagnostics have no color codes. Human-facing messages use ❌ for errors, ⚠️ for warnings/prompts, ℹ️ for transfer status, and ✅ for installation/removal success. Installer messages are uncolored except for the per-command status words described under Installation; uninstaller messages are uncolored; the purge confirmation uses a plain prompt. SSH output and the final rsync output pass through unchanged; read-only comparison and preview output is captured. Help starts with `codex-sync` and the verified display version, followed by concise usage, commands, options, a default deletion warning, and a few examples. Detailed marker discovery, Git hints, remote creation, metadata directives, and other edge cases belong in README/specs rather than help. `--version` remains available.

## Local project resolution

Starting at physical cwd, search each physical parent through filesystem root for the nearest `.codexignore` entry, including dangling symlinks. Never search remote paths. Its containing directory defines the synchronization root for both directions, regardless of Git metadata; transfer that entire directory even from a nested invocation. Only the nearest marker is used, with no parent-rule merging or explicit ignore-path override. An invalid nearest entry fails rather than falling back. The marker must resolve to a readable regular file; symlinks to readable regular files and empty files are valid. Missing-marker assistance is specified below.

The root must already exist locally and cannot be filesystem root or physical HOME. Validate its basename, rather than the invocation subdirectory, as the remote project name. Accept ASCII letters, digits, underscores, hyphens, and internal dots; reject empty names, leading/trailing dots, path separators, whitespace, and shell syntax. Remote naming is flat, without nested workspace paths.

Reject project-name and path arguments before SSH or rsync. There is no child-directory lookup or global folder discovery. Do not require `.git` or create local directories.

## Configuration

Runtime configuration is read from `${XDG_CONFIG_HOME:-$HOME/.config}/codex-sync/`.

The uninstaller uses the same configuration directory for purge. Only the runtime configuration files below are used. A `project-folders` entry is neither read nor validated.

### `target-host`

An optional readable regular file (a symlink to one is accepted) containing an SSH host name or alias, optionally prefixed by `user@`. If missing, use `codex`. The exact accepted form is `^([a-zA-Z0-9_][a-zA-Z0-9_.-]*@)?[a-zA-Z0-9_][a-zA-Z0-9_.-]*$`. Trailing newlines are removed when reading the file; other whitespace, ports, IPv6 literals, and shell syntax are rejected. Existing non-files, unreadable files, and dangling symlinks fail. This is a host selector, not an arbitrary SSH command.

### `ignore`

An optional readable regular file of rsync-compatible exclude patterns. Symlinks to readable regular files are accepted; other existing entries fail unless the source is disabled. See Exclusions.

## Remote project resolution and validation

The remote project path is always `~/<project-name>` on the configured target host. The remote root is not independently configurable.

Before any SSH or rsync operation, complete local root, marker, ignore-file, and host validation. Before either transfer, verify the remote directory via SSH. Reject non-directory entries, dangling symlinks, and directories resolving to remote filesystem root or physical HOME.

Symlinks to directories are accepted if their physical destinations pass these checks; their targets need not be inside remote HOME. Missing directories stop the transfer except for the explicit remote push assistance below. Both `ssh` and `rsync` must be available locally before the SSH check. Transfer operands have trailing slashes and follow `--`; the remote operand is `<host>:~/<project-name>/`. SSH commands quote remote HOME paths.

## Assisted missing remote destination creation

Only a real push may offer creation when SSH confirms that `~/<project-name>` has no entry (including no dangling symlink). The check returns status 3 for absence; other failures, including SSH transport failure, stop without prompting. Existing files, dangling symlinks, and unsafe directory aliases are errors.

Require both stdin and stderr to be terminals. Prompt explicitly with the host and destination and default No `[y/N]`; accept only `y`, `Y`, `yes`, `YES`, or `Yes`. Empty input, EOF and all other responses decline. Decline and noninteractive contexts stop nonzero without mkdir or rsync. On affirmation, use SSH to run a quoted `mkdir -- "$HOME/<project-name>"` without `-p`; creation failure (including a newly appeared entry) stops. Revalidate the directory through SSH after successful creation; only a successful check allows the normal push to proceed. No local directory is created.

Pull never offers creation. Dry-run reports a missing remote destination and stops nonzero without prompting or mutating remote state, even on affirmative terminal input. Missing-local-marker assistance is a separate flow.

## Exclusions

Combine these sources in both directions, in this order (the directive below can disable only the global source):

1. Exactly three non-overridable built-in exclusion patterns: `.git/`, `.ssh/`, and `.codexignore`. No other sensitive files or generated directories are excluded automatically.
2. Optional global `${XDG_CONFIG_HOME:-$HOME/.config}/codex-sync/ignore`.
3. Required nearest local `.codexignore`, found from the physical invocation directory upward; its directory defines the local project.

Use the local marker selected by Local project resolution, including for pulls. The optional global file cannot replace it. Patterns retain rsync semantics relative to the synchronization root, apart from the metadata directive below. Ordinary synchronization never uses `--delete-excluded`; excluded destination files remain protected. Explicit cleanup is the narrow exception described below.

Credentials, private keys, environment files, and other secrets outside the built-in patterns are not automatically excluded. Users must review their files, configure exclusions, and preview with `cpush --dry-run`. Exclusions and dry runs do not guarantee that secrets cannot be transferred.

Before SSH or rsync, reject lines exactly equal to `!` or `!` followed by a carriage return in either active ignore file, including an unterminated final line. Other whitespace is not stripped for this validation.

The selected local `.codexignore` may contain the metadata directive `# codex-sync: no-global-ignore`. For recognition, remove one terminal carriage return (supporting CRLF as well as LF), then trim only leading and trailing ASCII spaces and tabs. The remaining line must match that literal exactly, case-sensitively, with no additional text or changes to internal whitespace. A final line without a newline is supported. Repeated matching directives are idempotent. Other lines retain ordinary rsync semantics.

If any line matches, pass the filtered project patterns to rsync on stdin using `--exclude-from=-` and skip the global ignore file entirely, including existence/readability and list-clearing validation, for both push and pull. Remove matching metadata lines from the project patterns supplied to rsync; keep every other project rule active, including rejection of the list-clearing `!` rule. Built-in exclusions remain mandatory. Directives in the global file or an unselected ancestor marker have no special meaning.

## Assisted missing-marker creation

Only push/pull (including dry runs) offer assistance when the entire physical cwd-to-root search finds no `.codexignore` entry. Invalid existing entries retain validation errors without prompting. Before any host configuration, SSH or rsync operation, suggest the physical Git worktree root from optional `git -C <physical-cwd> rev-parse --show-toplevel`, if it resolves to an existing physical ancestor; otherwise suggest physical cwd. Git failure or absence is harmless. Git never changes marker lookup or transfer root semantics.

Warn about reviewing sensitive files and exclusions; an empty marker does not protect secrets. Require both stdin and stderr to be terminals before prompting; otherwise fail nonzero without creation. Reject unsafe root/home locations and invalid suggested root names. Prompt explicitly with default No `[y/N]`; accept only `y`, `Y`, `yes`, `YES`, or `Yes`. Empty input, EOF and all other answers decline. On affirmation, exclusively create an empty `.codexignore` without overwriting any existing entry, including dangling symlinks or entries introduced after lookup. Creation failure is an error. Never create directories. Always stop nonzero without SSH or rsync, including after successful creation, and tell the user to review exclusions and rerun. Inspect remains read-only and fails normally for missing markers.

## Local inspection

`codex-sync inspect` shares physical root lookup, root/name safety checks, ignore source selection, directive parsing, and ignore file validation with push/pull. It does not read or validate `target-host`, check remote directories, require SSH/rsync binaries, or invoke either command. It never creates files or directories.

After successful validation, print exactly this layout (with the selected paths and patterns):

```text
Sync root: ~/my-app
Built-in:
  .codexignore
  .git/
  .ssh/
Global: ~/.config/codex-sync/ignore [disabled]
Local: ~/my-app/.codexignore
  .env
  node_modules/
```

Use the exact labels shown with no blank separator lines, with two spaces before each rule. Always show Global and Local paths on their header lines, including empty sources. An absent optional global file has no status or rule rows. Only a global source disabled by the local directive has the suffix ` [disabled]`; do not inspect that file, even for existence, or display its patterns. Color only `[disabled]` red, with a reset immediately afterward, when stdout is a terminal and `NO_COLOR` is unset and `--no-color` was not supplied. Any value of `NO_COLOR`, including empty, disables color. Under the same ANSI condition, render only the labels `Sync root:`, `Built-in:`, `Global:`, and `Local:` in bold, resetting immediately after each label. Paths and rules remain unstyled. Do not print active statuses, origin tags, duplicate source/effective-rule sections, or a footer.

For display only, replace HOME itself with `~` and its strict descendants with `~/...`; do not abbreviate paths that merely share a HOME prefix. Actual paths and synchronization behavior remain unchanged.

Show configured rules once under each origin in built-in/global/local order, sorting alphabetically within each origin (deterministic C-locale byte order), preserving duplicates. Sorting affects display only; transfer patterns retain their file order. Omit empty lines, lines containing only a carriage return, comments beginning with `#` or `;`, and matching local metadata directives; display other rule text literally, without trimming. Validation errors go to stderr with nonzero exit status. This lists configured exclusion rules without evaluating file matches; use a sync dry run for transfer previews.

## Deletion and preview

Both directions use `rsync -a --update --delete` by default. Destination-only non-excluded entries **may be permanently deleted**, even when newer than anything in the source. `--update` protects newer destination regular files with corresponding source files; it is not a deletion safeguard. Other rsync archive/update semantics (including type changes and timestamps) apply unchanged.

- Display exactly `⚠️ Sync will delete destination-only files.` before a real transfer with deletion enabled. Suppress this warning for dry runs and `--no-delete`. Quiet does not suppress safety warnings or errors.
- `--no-delete` disables ordinary destination-only deletion.
- `--force/-f` omits `--update`; it does not bypass validation, confirmation, or built-in exclusions.
- Before a non-force transfer/preview, run two read-only rsync probes with identical source, destination, exclusions and `--out-format=%i`, differing only in `--update`. Count regular-file transfer records (`<f`/`>f` plus nine attribute columns), without filenames. A positive count difference reports how many newer destination files were skipped in the comparison, with a `--force` hint. No inference is made from silent update output or filenames; probe failures stop the operation. These probes are snapshots, not a lock: concurrent changes can invalidate the comparison or preview. Force skips the probes.
- Every normal push/pull runs a successful dry-run preview before automatically applying, without confirmation. Preview uses the same archive/update, deletion, cleanup, exclusions and operands as the transfer. Preview failure stops without applying.
- Concise preview rows are `+ <relative path>` for additions (nine `+` item attributes), `~ <relative path>` for other non-directory changes, and `- <relative path>` for deletions. Existing-directory metadata records are hidden; directory creation/removal rows retain trailing slashes and count as entries. Finish with `Preview: N added, N modified, N deleted`, including zero counts. Type replacements follow rsync itemization. Paths use rsync’s default escaped `%n` notation under C locale, without decoding, link-target suffixes, whitespace splitting, or shell evaluation. Newlines and unsafe bytes use rsync escaping; literal backslash escape prefixes remain distinguishable. Tabs may remain literal and are never used as field separators. Parse only fixed-width eleven-character `%i` plus a literal separator; no progress or verbosity is enabled for this dry run. Non-record rsync notices (such as protected nonempty cleanup directories) are retained on stderr when the preview is visible and do not affect counts.
- Concise preview symbols use green `+` (ANSI 32), red `-` (31), and yellow `~` (33) only when stdout is a terminal, `NO_COLOR` is unset, and `--no-color` was not supplied. Reset immediately after each symbol; spaces, paths, status, and counts remain uncolored. Pipes and redirected stdout contain no tool-added ANSI; verbose preview records remain unchanged.
- `--dry-run/-n` performs only a non-mutating transfer preview, including planned deletions. Missing-marker assistance remains the separately specified exception.
- `--interactive/-i` requires terminal stdin and stderr before remote assistance or transfer (unless also dry-run). Run the preview, then ask `Apply this preview? [y/N]` (explicitly mention cleanup when enabled). Only `y`, `Y`, `yes`, `YES`, `Yes` affirm; EOF/default/other input stops nonzero without transfer. Preview failure prevents confirmation. Dry-run with interactive exits after preview without an apply prompt. Existing missing remote creation assistance may precede the preview.
- Before transfer/preview, print `ℹ️ <push|pull>: <source> -> <destination>` unless quiet. `--verbose/-v` prints raw itemized preview records (including directory metadata) and the summary, then adds native `-v` transfer output. `--quiet/-q` supplies rsync `--quiet` and suppresses status and preview; interactive previews remain visible even with quiet.
- Dry-run previews and comparison probes never enable progress, even with `-p`. For actual transfers, default progress is rsync's aggregate `--info=progress2` only on terminal stdout, unless quiet or verbose. `--progress/-p` explicitly enables it even redirected; `--no-progress` disables it. Quiet suppresses progress. No custom progress parser or configurable bar is needed: rsync supplies totals, rate and progress itself.
- Colors apply only to the tool's own diagnostics, inspect styling, and concise preview symbols, on the relevant terminal, with neither `NO_COLOR` (including empty) nor `--no-color`. Emoji are retained with or without colors. External output is never recolored. Rsync errors propagate nonzero.

### Explicit ignored-entry cleanup

`--cleanup/-c` enables aggressive destination cleanup in either direction using rsync `--delete-excluded` in the same transfer. This is explicit destructive authorization; combine `-ic` for a preview and default-No confirmation or `-nc` for a non-mutating preview. It removes destination entries matching the selected **local project** `.codexignore`, including matches still present in the source, while ordinary destination-only deletion continues. It never deletes source entries. `--cleanup --no-delete` is rejected rather than assigning ambiguous deletion semantics.

Built-in and active global exclusions receive explicit receiver-side `P` protection rules before other filters. These protections survive `--delete-excluded` and take precedence over project patterns, including inside ignored parent directories; protected children may leave a containing directory in place. The active global ignore is therefore never itself a cleanup target. A local no-global directive disables global protection as well as global exclusion/validation. Metadata directives are omitted from filtered stdin as in ordinary transfers.

Cleanup accepts plain rsync exclusion patterns only: active global/project non-comment patterns starting `+ ` or `- `, or containing `../`, fail before SSH. This conservative restriction avoids interpreting include-style rules or parent traversal as destructive intent. Ordinary transfers retain existing rsync ignore-file semantics. Blank lines/comments retain rsync semantics; one terminal CR is removed before generating global protection filters. Cleanup uses no shell deletion, pathname listing parser, `--copy-links`, or `--keep-dirlinks`: rsync handles patterns and treats symlinks as entries without following their directory targets. Existing local/remote root validation applies. Users must keep destination paths stable during synchronization; validation and previews are not filesystem locks.

### Version and release support

Every main push runs `bash -n` across the project shell scripts, ShellCheck, shfmt, and the full `bash tests/run.sh` suite before packaging or artifact upload. CI installs rsync, util-linux, ShellCheck and shfmt and sets `MAKESELF_DIR` to the fetched Makeself source so the optional release/snapshot archive integration tests also run. A failed check or test stops packaging and upload. Tag builds skip this full test/lint suite but retain strict tag/VERSION and exact metadata validation plus archive integrity, extraction, installation and uninstallation checks in the installer build.

The single literal `readonly VERSION=X.Y.Z` definition in `bin/codex-sync` is the canonical release version; optional build metadata determines the verified display version. `scripts/release-version.sh TAG` validates exactly one unambiguous literal readonly VERSION definition as data, requiring a numeric `X.Y.Z` tag with no prefix or leading zeros and an exact match. It never sources application code.

`.github/workflows/build-installer.yml` runs on main pushes and is reusable. `.github/workflows/release.yml` runs on numeric-looking tag pushes (GitHub glob filters); its reusable build job strictly validates the tag before packaging, so nonnumeric tags cannot publish. The tag workflow invokes the reusable build once, then its publication job waits with `needs`. Both jobs check out the triggering commit explicitly. The build fetches full history/tags, uses Makeself pinned to `release-2.5.0`, and uploads one Actions artifact with `retention-days: 1`. Main builds need only contents:read; contents:write is limited to the publication job. Checkouts do not persist credentials.

Publication downloads the exact artifact ID returned by the successful build in the same workflow run, never searches another run or selects a main artifact. Download digest validation plus a SHA-256 comparison against the build job output bind the published installer bytes to that build. The publication job revalidates the tag against canonical VERSION, requires the expected regular non-symlink installer, and uses GitHub CLI to create a draft release with tag verification. Missing/expired artifacts, version mismatch, invalid metadata, build/validation or checksum failure block publication. Reruns consume their dependency's artifact ID; no workflow_run polling or cross-run lookup is used. No third-party publication action is required. Before publication, the helper resolves the current remote tag to the triggering commit and refuses changes if it moved. Release lookup failures stop publication. An existing draft receives only `gh release upload "$RELEASE_TAG" "$archive" --clobber`, after rechecking that it remains a draft; this replaces the asset on retagged reruns without editing release metadata. An absent release uses `gh release create "$RELEASE_TAG" "$archive" --verify-tag --target "$COMMIT" --draft --title "$RELEASE_TAG"`. Published releases are refused. No Git tag is moved by automation.

`scripts/build-installer.sh MAKESELF_DIRECTORY OUTPUT_DIRECTORY [RELEASE_TAG]` is runnable locally with a Makeself 2.5.0 source directory. It creates `codex-sync-snapshot.run` without a tag, or `codex-sync-X.Y.Z.run` with a validated release tag. It stamps git-describe metadata into a temporary allowlisted payload containing only install.sh, uninstall.sh and the three commands. Release builds additionally require the verified display version to equal the tag (clean exact-tag provenance). Snapshot builds retain best-effort metadata, including unknown provenance. It checks the archive, extracts and compares the entire payload, executes the archive startup installer, verifies all three installed commands and versions, and uninstalls them, all under temporary HOME, XDG_CONFIG_HOME and TMPDIR directories. It never installs into the caller's HOME or rewrites source VERSION. Successful output remains in the requested directory; temporary fixtures are removed on exit.

## Installation

`install.sh [--force]` copies `codex-sync`, `cpush`, and `cpull` to `$HOME/.local/bin`, without sudo, Fish setup, or editing shell startup files.

`install.sh --help` prints usage and exits 0; it ignores trailing arguments. Otherwise only a single optional `--force` is accepted; invalid arguments exit 2.

Preflight **all three** target paths before making changes:

- If absent, install.
- Use `cmp -s` for existing regular files; identical executables are not rewritten. Identical files lacking executable permission receive mode 755 without rewriting their contents.
- A differing regular file is a managed script only when its first two lines are exactly `#!/usr/bin/env bash` and `# codex-sync`. All three installable scripts carry this marker immediately after the shebang. This marker is an identification convention, not proof of authenticity.
- When any command exists, report installed versus incoming version and all three command names with identical/different/new file status before confirmations, including with `--force`. Compare the prepared stamped bytes so equal version labels still distinguish identical and different files. Read exactly one literal, single-quoted `BUILD_METADATA` assignment from regular, non-symlink managed files; accept only the display-version grammar above. Never execute/source installed commands or their helpers, follow their symlinks for metadata, infer versions from filenames, or use VERSION as a provenance fallback. Missing, empty, duplicate, malformed or unreadable metadata displays `?.?.?` without blocking installation. These labels are informational claims, not authentication. Incoming metadata comes from the existing best-effort build preparation, shared with `--version`.
- The version line uses `ℹ️ codex-sync (<version> → <version>)`, without installed/incoming labels, a colon after codex-sync, or an overall comparison status. Per-command statuses are `identical`, `different; replace`, or `new`. The version line remains uncolored. In each per-command line, color only the status word `identical` green or `different` yellow/amber, resetting immediately afterward; explanatory suffixes remain plain. Unknown and new statuses remain neutral. Apply color only when stderr is a terminal and `NO_COLOR` is unset (even an empty value disables color). Command names, paths and all other installer output remain uncolored. Redirected stderr contains no ANSI codes; the installer has no `--no-color` option.
- Managed updates use only the version header and per-command statuses above, without a separate warning heading or indented target-path list. Unrelated collisions retain their separate warning and path list. Ask once per nonempty group: update managed scripts, then explicitly replace unrelated files or symlinks, each defaulting to No `[y/N]`. Accept only `y`, `Y`, `yes`, `YES`, or `Yes`; EOF and other answers decline.
- Require terminal stdin and stderr for confirmations; otherwise fail without changes unless `--force` explicitly overrides both confirmations.
- Symlinks (including dangling links and links to directories) are always collisions, never managed or identical; replacement replaces the link, not its referent. Other non-regular entries and directories fail even with `--force`.
- Complete all preflight checks and confirmations before modifying any target. Stage all changed commands with mode 755 before moving them into place; unchanged executables retain their permissions and identity. The final three-file replacement is not atomic as a group.
- If all three prepared files are byte-identical, skip staging and replacement, including with `--force`. Report `✅ No changes in <target>` when no permission repair is needed; otherwise restore executable permissions in place and report that repair. No confirmation is required for either case.
- Never manage user configuration files.

Installation is by copy, not symlink. It does not edit `PATH`.

## Uninstall

`uninstall.sh [--purge]` checks `$HOME/.local/bin/{codex-sync,cpush,cpull}`. It accepts either no arguments or the single option `--purge`; all other argument combinations (including `--help`) print usage to stderr and exit 2.

Missing entries are skipped. A regular, non-symlink file is removed if its first two lines match the same managed header used by installation. Contents are not compared with the source files: modified scripts retaining the header are removed without confirmation. Symlinks, non-regular entries, and files without that header are preserved with a warning and result in status 1. Successful removals are reported individually. Removal failures stop the script under `set -e`; earlier removals are not rolled back. Without `--purge`, configuration is preserved. Project `.codexignore` files are never targeted.

With `--purge`, command removal happens first, followed by optional recursive removal of exactly `${XDG_CONFIG_HOME:-$HOME/.config}/codex-sync`, matching runtime configuration resolution. Unset or empty `XDG_CONFIG_HOME` falls back to `$HOME/.config`; relative values remain relative to the invocation directory. Purge applies only if this entry is a directory and is not itself a symlink; absent entries, files, and symlinks are silently skipped. Parent components are not checked for symlinks.

For an eligible configuration directory, only stdin must be a terminal. The Bash `read -r -p` prompt is `Remove configuration <path>? [y/N] `. Unlike the other confirmations, the read uses default IFS whitespace handling, and only `y`, `Y`, and lowercase `yes` affirm. Affirmation runs `rm -r -- <path>` without a further prompt and reports success. A negative or unrecognized answer preserves configuration without adding an error status; EOF exits 1. Nonterminal stdin preserves configuration with a warning and sets status 1. Purge can proceed even if unrelated command entries were preserved; that earlier status remains 1.

## Tests and coverage

Self-contained Bash tests use isolated temporary HOME/config/project directories and mocked SSH/rsync. Remote-command tests execute the generated SSH expressions against a temporary remote HOME. No live host or user installation is required. The test assertions are grouped below:

- `test-project-lookup.sh`, `test-root-resolution.sh`, `test-ignore-lookup.sh`: marker-defined physical roots, nested/symlinked invocation, nearest-wins selection, flat remote names, invalid nearest entries, root/name safety, positional-argument rejection, and unused `project-folders` entries.
- `test-invalid-input.sh`, `test-local-remote-validation.sh`: invalid names/options/hosts and validation failures preventing transfers in both directions.
- `test-exclusions.sh`, `test-ignore-directive.sh`: XDG host/ignore configuration, required readable local markers, empty/optional sources, cumulative mandatory exclusions, list-clearing rejection, exact directive recognition (spaces/tabs, CRLF, repeated and unterminated lines), disabled global validation, retained local rules, and ineffective near matches/global/ancestor directives.
- `test-ignore-creation.sh`: default/negative/affirmative responses, noninteractive refusal, optional Git hint and fallback, exclusive file/symlink race protection, dry-run stop behavior, read-only inspect, and no SSH/rsync after assistance.
- `test-inspect-command.sh`, `test-color.sh`: exact report layout, grouping/sorting/duplicates/literal rules, empty/absent/disabled sources, strict HOME abbreviation, shared validation, local-only execution, argument rejection, informational options, emoji diagnostics, terminal styling, redirection, `NO_COLOR` (including empty), and unchanged external output.
- `test-remote-creation.sh`: real remote-check expressions, existing/missing/invalid entries and unsafe aliases, shell-safe HOME quoting, all accepted responses and default/negative/EOF refusal, noninteractive/dry-run/pull refusal, SSH/mkdir/revalidation failures, and transfer only after successful validation.
- `test-transfer.sh`: direction, trailing slashes, default host and deletion, dry-run, no-delete and combined options, with warnings only for real deleting transfers.
- `test-installation.sh`: fresh-install silence, compact managed-update output without a redundant warning/path list, copies/header markers, version summaries (known/unknown/malformed/duplicate stamps, same-version identical/different files, symlinks and installed-code non-execution), unchanged-file identity, no-change success without staging/reinstalling (including force), and permission restoration, managed/header-near-match/unrelated collisions, symlink referent preservation, directory refusal, all confirmations before changes, noninteractive/force handling, staging failure cleanup, and uninstall/config preservation assertions. Modified managed commands are removed, matching the uninstall contract; version assertions match the checkout or stamped version.

Interactive and terminal-color cases require util-linux `script` and are skipped if unavailable. Unreadable-file checks are skipped when the executing user can still read mode-000 files.

`test-uninstall-purge.sh` covers unset, empty, custom (including spaces), and relative XDG configuration paths, affirmative/default/negative confirmation, noninteractive refusal, preservation of the unselected directory, and configuration symlink protection. Interactive cases require util-linux `script`.

`tests/run.sh` runs every `test-*.sh` in filename order and stops at the first failure. `test-installation.sh` invokes installation and removal only inside its temporary HOME. Syntax, formatting and lint checks can inspect scripts without executing them; individual behavior tests can be run separately when installation/removal execution is out of scope.

`test-cli-improvements.sh` uses mocked SSH and a remote-operand adapter to real local rsync, entirely within temporary fixtures. It covers newer-file detection and force in both directions, ordinary deletion, cleanup dry runs, nested built-in/global protection, source preservation, symlink target preservation, traversal/include-style refusal, disabled global directive handling, incompatible flags, composed options, quiet/progress overrides, nonterminal interactive refusal, failed-probe blocking, transfer failure propagation, filename/equal-mtime false-positive prevention, CRLF global protection, and terminal cleanup approval/decline. No SSH host is contacted. Existing mock-only transfer tests also retain operand/exclusion and warning assertions. Installation tests execute only under their isolated temporary HOME.

`test-build-metadata.sh` reads and strictly validates the canonical VERSION as literal data without executing application code, so current-release expectations follow release bumps while fixed historical tags remain covered. It uses mock Git responses without initializing repositories to cover clean tags, distance/hash/dirty output, malformed output, failures, enclosing-repository rejection, help, cwd independence, deterministic output, source symlink protection, installation/reinstallation, and packages without Git/build tooling.

`test-help.sh` checks the version header, concise command/option/example sections, absence of internal detail paragraphs, shared subcommand help, and unchanged version output without SSH/rsync.

`test-preview.sh` covers concise counts and signs, symbol-only terminal colors in both directions, plain output with pipes/redirection/verbose/`--no-color`/`NO_COLOR` (including empty), directory metadata filtering and directory creation/removal, escaped newlines and literal backslash escapes, spaces and symlink names, both directions, automatic apply, dry-run combinations, quiet/verbose, interactive refusal, preview failure blocking, and progress restricted to actual transfers. Real local rsync adapter coverage in `test-cli-improvements.sh` checks update/deletion/cleanup semantics against the same preview options.

`test-install-color.sh` covers equal, different, and unknown version pairs in the exact parenthesized header format without installed/incoming labels, a colon after codex-sync, or an overall status, byte differences with equal versions, plain version lines and exact terminal styling restricted to each per-command status word, redirected stderr, and empty/nonempty `NO_COLOR`, using only temporary HOME installations.

`test-build-installer.sh` reads the same validated canonical VERSION for current-release expectations and covers strict tag syntax, version-independent VERSION mismatch/duplicates, rejection of executable VERSION expressions without evaluating them, and rejection of non-exact release metadata before packaging. With `MAKESELF_DIR` pointing to Makeself 2.5.0, it also exercises real release and snapshot archives, allowlisted contents, metadata preservation, unchanged sources and isolated installation/removal. No repository is initialized. Workflow syntax can be checked with actionlint.

`test-release.sh` runs a copied release helper with mocked Git in temporary fixtures. It checks major/minor/patch bumps, canonical VERSION-only edits, the commit message `build: bump version`, annotated tag and explicit atomic push arguments, interactive selection and default-No cancellation, preflight rejection, and mutation-failure handling. It performs no real Git mutations or release.

`test-publish-release.sh` uses mocked GitHub CLI calls and temporary archives to cover draft replacement, new draft creation, published-release refusal, retagged reruns, moved remote tags, lookup failures, draft status changes, malformed digests, altered/missing/symlinked archives and VERSION mismatch. No release or tag is changed.
