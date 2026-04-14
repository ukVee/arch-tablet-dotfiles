# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A personal dotfiles repo managed by [toml-bombadil](https://oknozor.github.io/toml-bombadil/). Target: an Arch Linux Surface Go 3 running Wayfire. `bombadil.toml` at the repo root is the single source of truth — it lists each dotfile as a `{ source, target }` pair, renders templated sources with variables, and symlinks them into place.

## Common commands

```bash
bombadil link              # render templates + (re)create all symlinks. Run this after editing anything in src/ or bombadil.toml.
bombadil link -p light     # activate the `light` profile (swaps the [tn] var file from dark → light)
bombadil link -f           # force: overwrite a pre-existing target file, saving the original to a backup.
bombadil install           # one-time: symlinks bombadil.toml itself into $XDG_CONFIG_HOME/bombadil.toml. Required before `link` works.
bombadil unlink            # remove all symlinks bombadil owns
bombadil watch             # auto-relink on file changes
bombadil get dots          # introspection: print resolved dot entries. Also: prehooks, posthooks, path, profiles, vars, secrets.
bombadil add-secret -k KEY -a -f vars/secrets.toml   # store a GPG-encrypted secret var (none used in this repo yet).
```

`bombadil link` is wired into Wayfire startup, so it runs on login — it MUST succeed without sudo or password prompts. Anything that breaks that assumption (see "Root-owned targets" below) is a regression.

### First-run / fresh-machine pitfall
On a machine that already has real dotfiles in the target locations, `bombadil link` will error with `code 17, AlreadyExists, "File exists"` for every conflicting target. Fix by either deleting the conflicting target file first, or using `bombadil link -f` which moves it to a backup and then creates the symlink.

## Architecture

### Render pipeline
1. Sources live under `src/`. Files may contain Tera-style template vars like `#{{tn.bg}}`.
2. `bombadil link` reads `bombadil.toml`, merges the active profile's `vars` files, renders each source into `.dots/` (gitignored — this is the generated output, never edit), then symlinks from `target` → the rendered copy in `.dots/`.
3. `vars/previous_state.toml` is bombadil's own state snapshot between runs; don't hand-edit.

### Variables and theming
- `vars/tokyo-night-dark.toml` and `vars/tokyo-night-light.toml` both define a `[tn]` table (bg, fg, purple, blue, …) with the same keyset. Templates reference them as `{{tn.<name>}}`. The dark file is the default; `bombadil link -p light` swaps in the light file via the `[profiles.light]` entry in `bombadil.toml`. Keep the two files key-for-key in sync — if you add a key to one, add it to the other or template renders will fail.
- Only files that currently use templating: `src/wayfire.ini`, `src/waybar/style.css`. Other sources are plain copies. When adding a new themed file, use `{{tn.<key>}}` rather than hard-coded hex.
- Tera supports more than variable substitution: conditionals (`{%- if … %} … {%- endif %}`), filters, and per-dot variable scoping via a `vars = "path/to/vars.toml"` field on a `[settings.dots]` entry. None of this is used yet; reach for it before duplicating values across themed files.

### Target path rules (bombadil quirk)
- Relative `target` values resolve against `$HOME`.
- `target` values starting with `/` are absolute — used here for `/etc/...` drop-ins.
- Bombadil creates the symlink *at* `target` pointing to the rendered copy in `.dots/`. If `target` is a directory path, the directory itself becomes a symlink — which collides with pacman-managed dirs. **Always point `/etc` targets at individual files inside a drop-in dir, never at the dir itself.** The existing `systemd_hibernate` / `systemd_power_lid` entries follow this pattern.

### Root-owned targets (`/etc/systemd/**`)
`bombadil link` runs as the normal user, so writes to `/etc` only work because of a one-time POSIX ACL grant:

```bash
sudo mkdir -p /etc/systemd/sleep.conf.d /etc/systemd/logind.conf.d
sudo setfacl    -m u:ukv:rwx /etc/systemd/sleep.conf.d /etc/systemd/logind.conf.d
sudo setfacl -d -m u:ukv:rwx /etc/systemd/sleep.conf.d /etc/systemd/logind.conf.d
```

Do **not** add an install hook that runs `sudo` or `systemctl daemon-reload` — it would prompt for a password at login and break Wayfire startup. Daemon reloads are manual after a `bombadil link` that touches systemd drop-ins. Do not run `sudo bombadil link` as a workaround; under sudo, `$HOME` becomes `/root` and bombadil cannot find its config. If you genuinely need it: `sudo -E env HOME="$HOME" bombadil link`.

### Surface Go 3 lid-close workaround
systemd-logind does not see `SW_LID` events on this hardware, so lid-close is handled via acpid:
- `src/system/acpi/events/lid-close` → `/etc/acpi/events/lid-close` registers the event.
- `src/system/acpi/lid-close.sh` → `/usr/local/bin/lid-close.sh` is the handler. It checks battery capacity and picks `systemctl hibernate` (≤30%) vs `systemctl suspend-then-hibernate`.
- `src/system/systemd/lid_powerbtn_behavior/10-surface.conf` sets `HandleLidSwitch=ignore` so logind stays out of the way; the power button is the real suspend trigger.
- `src/system/systemd/suspend-then-hibernate/10-surface.conf` tunes hibernate delay / sleep state.

If you rename the script target, also update `src/system/acpi/events/lid-close` (the `action=` line is a hard-coded path, not a template).

## Conventions

- Editing a dotfile = edit the file under `src/`, then `bombadil link`. Never edit the live file at the target — it's a symlink into `.dots/` which gets overwritten on every render.
- When adding a new dotfile, register it in `bombadil.toml`'s `[settings.dots]` table; nothing is auto-discovered.
- `.gitignore` excludes `.claude` and `.dots`. `vars/previous_state.toml` is currently tracked but is runtime state — don't stage changes to it.
