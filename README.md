# LEmux

LEmux is a Linux maintenance CLI. Inspect system health, preview space you can
reclaim, manage AppImages, and use your distribution's own package manager from
one command.

[![CI](https://github.com/eliaschampi/lemux/actions/workflows/ci.yml/badge.svg)](https://github.com/eliaschampi/lemux/actions/workflows/ci.yml)
[![Releases](https://img.shields.io/github/v/release/eliaschampi/lemux)](https://github.com/eliaschampi/lemux/releases)
[![MIT license](https://img.shields.io/badge/license-MIT-green)](LICENSE)

## Install

Download the installer from the latest release and run it after the download succeeds.

```sh
curl -fsSL --proto '=https' --proto-redir '=https' -o lemux-install.sh \
  https://github.com/eliaschampi/lemux/releases/latest/download/install.sh
```

```sh
bash ./lemux-install.sh
lemux --version
```

The installer verifies the archive with the SHA-256 embedded in the script and
checks the new CLI before activating it. It installs under `~/.local` with a man
page and completions for Bash, Zsh and Fish. Add `~/.local/bin` to your PATH if
needed. Run a freshly downloaded installer to update, or use the installer
attached to a specific release to select that version. Use `--prefix` for a
different absolute installation path. An existing source installation requires
confirmation and is backed up before migration. In noninteractive sessions,
`--replace` explicitly authorizes that migration.

Requires Linux with Bash 4.4+, GNU coreutils and findutils, util-linux, procps
and AWK. The installer also needs curl and tar. Install `gio` for the Trash,
`jq` for `history`, and Git for applying `purge`. AppImage inspection needs
`readelf` (binutils) and `unsquashfs` (squashfs-tools). GitHub AppImage downloads
also need curl and jq. Port inspection uses `ss` from iproute2.

### Install from source

```sh
git clone https://github.com/eliaschampi/lemux.git
cd lemux
make install PREFIX="$HOME/.local"
```

Run `make uninstall PREFIX="$HOME/.local"` from the source directory to remove
a source installation.

The native package backends are apt, dnf, pacman, and zypper. CI exercises the
CLI and removal of a disposable package on Debian, Fedora, Arch, and openSUSE.

## Check your system

```sh
lemux check
lemux check --fix
lemux status --watch
lemux history --json
```

`check` reports clock source, audio, Wi-Fi, Bluetooth, services, packages,
available memory and pressure, disks, temperatures, and journal usage. Missing
tools and unavailable service managers are reported when relevant. `check --fix` shows detected repairs in a checklist. Use the arrow keys, Space
and Enter to select them. In scripts, `-y check --fix` applies every offered
repair. These include masked PipeWire sockets,
failed NetworkManager and Bluetooth services, interrupted apt installs, and
oversized archived journals. Radio switches and boot settings are left to the
user. Low memory is diagnosed using available RAM, swap and kernel pressure
metrics.

`status` samples CPU, disk I/O and network activity over a second and shows
memory, swap, storage, temperature and battery when those counters are available.
Its health score is a heuristic. `history` shows operations recorded under
`$XDG_STATE_HOME/lemux` or `~/.local/state/lemux`.

## Explain an occupied port

`lemux why` lists local TCP listeners and bound UDP sockets. Use `lemux why 8000`
to see the addresses, visible PIDs, commands, executable paths, working directories
and parent processes. `lemux why 8000 --kill` asks before sending SIGTERM. When
several processes share the port, choose one with `--pid PID`. Process details
depend on your permissions.

## Reclaim space

| Command | Behavior |
|---|---|
| `lemux analyze ~/Documents` | Shows the largest top-level directories and individual files on one filesystem. |
| `lemux clean` | Opens a checklist in a terminal. Use ↑/↓ to navigate, Space to toggle, and Enter to preview. Run `lemux clean --apply` to select and clear. |
| `lemux clean --deep` | Estimates native package downloads and shader, font and compiler caches. Applying also expires system caches under `/var/cache` using the distribution’s tmpfiles rules. |
| `lemux clean --logs` | Lists npm logs and offers to vacuum archived journal files to 200M. |
| `lemux clean --bash-history` | Selects saved `~/.bash_history`. Open Bash sessions can write their history back later. |
| `lemux clean --packages --orphans --journal` | Adds the native package cache, orphaned packages and archived journals to the preview. `--trash` adds the user Trash. |
| `lemux purge ~/Projects` | Finds build artifacts beside project markers. Git-tracked paths and nested repositories are kept. Recent artifacts require `--all`. |
| `lemux installers` | Lists downloaded installers. With `--apply`, moves candidates that match installed packages or identical managed AppImages to the Trash. `--all` includes other installers. |
| `lemux remove <id>` | Previews removal by exact package or application ID. Matching user files go to the Trash on `--apply`. |
| `lemux optimize` | Previews DNS, desktop and font cache refreshes and eligible TRIM. Add `--apply` to run the listed steps. |

Category flags can be combined. For example, `lemux clean --browser --basic --apply`
clears browser, development and thumbnail caches. Scripts without category flags
retain the previous cache set. Trash, orphaned packages and saved Bash history
require an explicit selection.

Put one absolute path or glob per line in `~/.config/lemux/protect` to keep
files during cleanup. The list accepts `~/` and full-line comments. If the Trash
is unavailable, LEmux reports the failure and leaves the file in place. Reported
user-file sizes are apparent bytes. Filesystems may reclaim a different amount.

## Manage AppImages and updates

```sh
lemux app install ~/Downloads/Example.AppImage --name example
lemux app update example ~/Downloads/Example-new.AppImage
lemux app rollback example
lemux app list
lemux update --apps
```

Use `lemux remove --appimage <id>` to preview removing a managed AppImage, its
launcher and its command link. Add `--apply` to execute and `--purge` to
include matching user files. The existing spelling `lemux app remove <id>`
has the same preview and flags. General `lemux remove <id>` covers all matching
installation backends and user data.

To install from a GitHub release, pass `owner/repo` to `app install`. Add
`--from owner/repo` when installing a local file to opt in to GitHub updates.
An update may also set that source with `app update <id> --from owner/repo`.
GitHub downloads require a published SHA-256 digest and one compatible asset.
LEmux reads AppImage metadata without executing it, creates a desktop launcher,
and retains one previous managed version for rollback. Launching any downloaded
application requires trusting its publisher.

`lemux update` upgrades native packages after confirmation, then updates
available Flatpak, Snap and managed AppImages. `--apps` limits it to managed
AppImages.

## LEmux and Mole

[Mole for Linux](https://github.com/tw93/Mole/tree/linux) inspired LEmux's CLI.
Both cover cleanup, removal, disk analysis and live status. LEmux's focus is
diagnosis and guided repair for Linux services and devices, plus AppImage
management with digest checks and rollback.

Run `lemux <command> --help` or `man lemux` for flags and exit codes.
Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md)
and [LICENSE](LICENSE).
