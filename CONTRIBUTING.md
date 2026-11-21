# Contributing to lemux

Thanks for helping! lemux is small on purpose: every line should be easy to read and
safe to run on someone else's computer.

## Principles

1. **Preview cleanup.** Add `--apply` to run it. Explicit commands like
   `app update` and `app rollback` already identify the action.
2. **Preserve user files.** Clean rebuildable caches. Move installer and uninstall
   leftovers to the desktop Trash.
3. **Use the distribution's own tools.** Package work goes through `lib/lemux/pkg.sh`,
   which maps one function to apt, dnf, pacman and zypper.
4. **Fail closed.** `errexit` is off on purpose: probes such as `grep` fail all the
   time, and a script that dies halfway through a cleanup is worse than one that
   checks each destructive step. Every step that changes the system checks its status
   and stops the sequence when it fails.
5. **Root only for the step that needs it**, through `as_root`.

## Layout

| Path | Contents |
|---|---|
| `bin/lemux` | Entry point: option parsing and dispatch |
| `lib/lemux/core.sh` | Output, prompts, privileges, XDG paths, name and version helpers |
| `lib/lemux/pkg.sh` | Package-manager backends |
| `lib/lemux/check.sh` | `chk_*` checks and their `fix_*` repairs |
| `lib/lemux/clean.sh` | Cache targets (one line each in `clean_targets`) |
| `lib/lemux/remove.sh` | Complete uninstall |
| `lib/lemux/app.sh` | AppImage manager |
| `lib/lemux/update.sh` | One-shot update of everything |

Common changes:

- **New cache to clean:** add a label, process guard and path to `clean_targets`.
- **New check:** write `chk_name()` using `ok/warn/note`, call it from `cmd_check`; if
  lemux can repair it, write `fix_name()` and register it with `add_fix`.
- **New distribution:** extend each `case` in `pkg.sh`.

## Before opening a pull request

```sh
make lint   # shellcheck, must be clean
make test   # bats, runs against a throwaway HOME
```

To run the suite on other distributions locally (podman or docker):

```sh
podman run --rm -v "$PWD":/src:ro fedora:latest sh -c \
  'dnf -y -q install bats procps-ng jq make diffutils findutils git glib2 binutils squashfs-tools && cp -r /src /t && cd /t && bats tests'
```

Style: 2-space indentation, `[[ ]]` for tests, quote every expansion, English
identifiers and messages, one idea per function. Commit messages: short imperative
subject (`clean: add Steam shader cache`).
