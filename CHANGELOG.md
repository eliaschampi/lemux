# Changelog

## [0.1.0] — 2026-11-23

- Select cleanup categories and detected repairs with arrow keys and Space.
  Clean supports separate browser, development, deep cache, log and Bash history options.
- Diagnose local TCP and UDP ports with `lemux why [PORT]` and optionally send
  SIGTERM to a selected owner after confirmation.
- Read AppImage icons from PNG, SVG, .DirIcon and common theme directories.
  Desktop entries follow the selected version on update and rollback.
- Use `remove --appimage` for managed-only removal. The `app remove` alias now
  previews changes and requires `--apply`. General removal still includes user data.
- Recognize managed installer duplicates through symlinks and keep shared desktop
  directories during removal. Move cleanup guidance into command-specific help.

## [0.0.2] — 2026-11-21

- Publish a standalone `install.sh` with each release. It checks the archive's
  SHA-256 and CLI version before activating it at a user prefix.
- Reuse the installer to update LEmux. Earlier releases remain available and
  migration from a source installation asks for consent and keeps a backup.

## [0.0.1] — 2026-11-21

First public release of LEmux for Linux.

- Inspect system clocks, audio, Wi-Fi, Bluetooth, services, memory pressure,
  storage, temperatures, package health and journal usage. Apply selected
  repairs interactively with `lemux check --fix`.
- Preview cache cleanup, project artifact removal, installers and desktop
  maintenance. Keep protected paths and mounted directories out of deletion.
- Uninstall exact application IDs using apt, dnf, pacman, zypper, Flatpak,
  Snap or the built-in AppImage manager. Recover matching user files from the
  desktop Trash.
- Install and update type-2 AppImages with non-executing metadata inspection,
  SHA-256 checks for GitHub assets, and rollback to one previous version.
- Monitor system activity, analyze disk usage, and read the operation history.
- Install with a man page and Bash, Zsh and Fish completions.

[0.0.1]: https://github.com/eliaschampi/lemux/releases/tag/v0.0.1
[0.0.2]: https://github.com/eliaschampi/lemux/releases/tag/v0.0.2
[0.1.0]: https://github.com/eliaschampi/lemux/releases/tag/v0.1.0
