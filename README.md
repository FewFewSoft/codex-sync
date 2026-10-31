# codex-sync

Synchronize existing local project directories with matching directories on a remote host over SSH and rsync.

**Requirements:** Debian/Linux, Bash, OpenSSH, and rsync. The remote host must be accessible over SSH and have rsync installed.

## Installation

Download `codex-sync-X.Y.Z.run` from this repository's **Releases** page, then run it (replace `X.Y.Z` with the release version):

```bash
chmod +x codex-sync-X.Y.Z.run
./codex-sync-X.Y.Z.run
```

Version-tag installers are prepared as draft releases and become available on the Releases page after publication. Existing published releases are never replaced automatically.

Development installers are also available as artifacts from successful main-branch Actions builds for one day. Their version may include revision metadata or show unknown provenance.

Alternatively, from the source directory:

```bash
./install.sh
```

Both methods use the same installer and copy the commands into `~/.local/bin` without `sudo` or changes to your shell configuration.

When commands already exist, the installer shows `ℹ️ codex-sync (<version> → <version>)` plus whether each command is identical or needs replacement. Managed updates then proceed to confirmation without a separate warning or path list. Unavailable version information appears as `?.?.?`. On terminals, each command’s `identical` status word is green and `different` is amber; unknown statuses remain uncolored. Command names, the version line, and paths stay plain. `NO_COLOR` (including an empty value) disables color, and redirected output has no color codes. If all three commands are already identical and executable, installation reports success with no changes. Replacement requires terminal confirmation (`[y/N]`, default No), or explicit `--force` for unattended installation.

Ensure that directory is in your `PATH`:
```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Configuration

Optional configuration files live in `${XDG_CONFIG_HOME:-$HOME/.config}/codex-sync/`:

| File | Purpose | Example contents |
|---|---|---|
| `target-host` | SSH host name or alias; defaults to `codex` | `my-sandbox` |
| `ignore` | Global rsync exclusion patterns, one per line | `*.log` |

### target-host

Use `~/.ssh/config` to configure connection details for your host alias.

Example:
```
Host codex
  HostName 192.168.254.1
  Port 22
  User codex
```

### ignore

You can use a global `ignore` in addition to mandatory local `.codexignore`.

See [samples/ignore](samples/ignore) for example global patterns. Samples are not activated automatically; review them for your own files.

## Usage

Use `codex-sync --help` for a concise command reference and the current version, or `codex-sync --version` for the version alone. Checkout builds may include a Git tag, commit distance/hash, and tracked-file dirty status; installing from a checkout preserves this revision information. Git is optional. Unknown versions show `?.?.?`, followed by `-gHASH` when a Git hash is available (and `-dirty` for tracked modifications). Official tagged releases retain their exact release version after installation.

```bash
cpush                        # Push the current project folder
cpull                        # Pull the current project folder
cpush -n                     # Preview changes, including planned deletions
cpull -f                     # Allow overwriting newer destination files
cpush -ic                    # Preview and confirm cleanup of project-ignore matches
cpull -vp                    # Raw verbose rsync output and aggregate progress
cpull --no-delete            # Pull while preserving destination-only files
codex-sync inspect           # Show local exclusion rules and their sources
```

**Both push and pull delete destination-only files by default. Deletions may be permanent.** Preview with `--dry-run` before syncing, or use `--no-delete` to preserve destination-only files. Newer destination files are preserved by default; `--force/-f` allows overwriting them. This protection does not prevent deletion of destination-only files. A warning reports newer files detected by read-only comparisons and suggests `--force`; files can change between comparison and transfer.

Excluded destination files are preserved during ordinary sync. **`--cleanup/-c` also permanently removes destination entries matching the local `.codexignore`, even if present in the source.** Source entries, built-in exclusions, and active global exclusions remain protected. Use `-nc` to preview or `-ic` to preview and confirm (default No). Cleanup cannot combine with `--no-delete`; it rejects include-style `+ `/`- ` rules and parent-traversal patterns. Protected children can leave ignored directories in place.

Every push and pull first shows relative paths with `+` added, `~` modified, and `-` deleted, followed by counts, then applies automatically. On terminals, only the symbols are colored: green `+`, yellow `~`, and red `-`; paths stay uncolored. Directory metadata changes are hidden; directory creation and removal are included in the counts. Unusual filenames use rsync’s escaped notation (for example, `\#012` for a newline). The preview is a snapshot; files can change before transfer.

`--interactive/-i` previews then asks before applying; it requires a terminal. `--dry-run/-n` always stops after preview. Short flags compose, such as `-nic`. Progress appears during actual transfers only, automatically on terminals; `--progress/-p` enables aggregate rsync progress explicitly, and `--no-progress` disables it. `--verbose/-v` shows raw itemized preview records and native rsync transfer output. `--quiet/-q` suppresses ordinary status, preview, and progress, while retaining safety warnings and interactive previews. For quiet/verbose and progress/no-progress, the last option wins. `--no-color` or `NO_COLOR` disables terminal colors; redirected output is uncolored.

The remote destination is `~/<project-name>` on the configured host. If it is missing, a real push in a terminal offers to create it with default-No confirmation. Pulls and dry runs never create remote directories.

## .codexignore and secrets

Every project needs a `.codexignore`, even for pulls. The nearest marker in the physical current directory or its parents defines the entire project root. If none exists, terminal usage offers to create an empty marker, suggesting the Git worktree root when available or the current directory otherwise, then stops so you can review exclusions and rerun.

Patterns use rsync exclusion syntax relative to the synchronization root. Exclusion can only be added; by design the list-clearing `!` rule is not allowed.

Global ignore rules can be disabled, add `# codex-sync: no-global-ignore` on its own line in the project `.codexignore`. Surrounding spaces or tabs are allowed. This directive is metadata; ordinary rules in the same file and the built-in exclusions still apply.

`codex-sync inspect` shows the synchronization root and sorted exclusion rules grouped by source. Use `cpush --dry-run` to preview a transfer.

Only `.git/`, `.ssh/`, and `.codexignore` are automatically excluded. **Other credentials, private keys, environment files, and secrets are not automatically detected or excluded.** Review your project, add appropriate exclusions, and preview with `cpush --dry-run`. Exclusion rules and dry runs won't verify that secrets cannot be transferred, review remains your responsibility.

## Uninstallation

From the source directory:

```bash
./uninstall.sh
```

Removes regular installed commands carrying the codex-sync header, including modified copies. Unrelated entries and symlinks are preserved with a warning and a nonzero exit status. Configuration and project `.codexignore` files are preserved by default.

Use `./uninstall.sh --purge` to also offer removal of `${XDG_CONFIG_HOME:-$HOME/.config}/codex-sync` with terminal confirmation; command removal happens before the prompt. Project `.codexignore` files are preserved.
