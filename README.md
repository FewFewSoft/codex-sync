# codex-sync

Synchronize local project directories with a remote host using SSH and rsync.

**Requirements:** Linux, Bash, OpenSSH, and rsync (also required on the remote host).

## Installation

Download `codex-sync-X.Y.Z.run` from [Releases](https://github.com/FewFewSoft/codex-sync/releases), then run:

```bash
chmod +x codex-sync-X.Y.Z.run
./codex-sync-X.Y.Z.run
```

Alternatively, install from source with `./install.sh`.

Commands are installed in `~/.local/bin`. Ensure this directory is in your `PATH`.

## Configuration

Configure your SSH connection in `~/.ssh/config`:

```sshconfig
Host codex
  HostName 192.168.1.100
  User codex
```

The default SSH alias is `codex`. To use another alias, write it to `${XDG_CONFIG_HOME:-$HOME/.config}/codex-sync/target-host`.

Create a `.codexignore` file at your project's root to define exclusions:

```gitignore
.env
node_modules/
```

## Usage

Run these commands from within your project:

```bash
cpush                  # Push project to remote host
cpull                  # Pull project from remote host
cpush -n               # Preview without transferring
cpush -i               # Preview and ask for confirmation
cpull --no-delete      # Preserve destination-only files
codex-sync inspect     # Inspect active exclusions
```

Use `codex-sync --help` for all available options.

## Safety

**Synchronization deletes destination-only files by default.** Every transfer shows a preview before proceeding automatically. Use `-n` to preview without applying changes or `-i` to require confirmation.

Newer destination files are protected from overwrites by default, but not from deletion when absent from the source.

Only `.git/`, `.ssh/`, and `.codexignore` are automatically excluded. **Review `.codexignore` carefully to avoid transferring secrets.**

## Uninstallation

From the source directory:

```bash
./uninstall.sh
```

Use `./uninstall.sh --purge` to also request removal of the configuration directory.
