# Restoring an Omarchy 4 desktop

This directory contains generic restore tooling. Personal configuration,
package inventories, captured binaries, hardware details, and exact service
snapshots belong in a **private** dotfiles repository. This repository is
public; do not copy the private profile into it.

The private profile's `RESTORE.md` is the machine-specific runbook. This guide
describes the tooling and its limits.

## System restore tool

`restore-system.py` reads a profile's `profile.json` and checks the architecture,
source checksums, allowed destination paths, and destination file types before
installing Kanata's binary, LED helper, two system units, and narrow toggle rule.
It substitutes the new account home in unit files. Existing changed files get
`.before-omarchy-restore` backups. An existing backup blocks a conflicting
overwrite. Atomic inode replacement prevents existing hardlinks redirecting
writes. Symlinks in installation paths are rejected.

It never starts services, changes group membership, installs packages, applies
power/GPU overrides, or changes the bootloader. A real installation refuses the
original source machine, requires root, and requires an existing non-root
account with its Kanata configuration already restored.

Preview (no privilege required):

```bash
python3 restore/restore-system.py --profile "$HOME/dotfiles/restore/profile" --home "$HOME"
```

Rehearse file installation in a disposable directory (no privilege required):

```bash
rehearsal_root=$(mktemp -d)
python3 restore/restore-system.py --profile "$HOME/dotfiles/restore/profile" \
  --home "$HOME" --root "$rehearsal_root" --apply
```

On the **new machine**, after reviewing the profile and user configuration:

```bash
sudo python3 restore/restore-system.py --profile "$HOME/dotfiles/restore/profile" --home "$HOME" --apply
/usr/local/bin/kanata --check --cfg "$HOME/.config/kanata/kanata.kbd"
sudo systemctl daemon-reload
sudo systemctl enable --now kanata.service
systemctl is-active kanata.service
```

Review `KEYBOARD_EVENT_DEVICE` in the saved LED helper before enabling its unit:

```bash
sudo systemctl enable --now kanata-caps-layer-led.service
systemctl is-active kanata-caps-layer-led.service
journalctl -u kanata.service -u kanata-caps-layer-led.service -b --no-pager
```

The profile is trusted input you review from your own private repository. Hashes
detect accidental drift; they are not signatures authenticating an untrusted
profile. Installation preflight prevents predictable bad-path partial writes,
but disk/permission failures during writing can still leave a partial install.
Use the backups for recovery; this tool is not a transactional OS installer.

## Verification

```bash
python3 -m unittest discover -s restore/tests -v
python3 restore/verify-profile.py --profile "$HOME/dotfiles/restore/profile" --home "$HOME"
```

`verify-profile.py` compares actual file bytes or symlink targets against the
captured manifest, plus system snapshot hashes. It works against the source
home or a same-home-path export into a temporary destination. Templated files
deliberately render differently when restoring into a different home. The
portable cheatsheet launcher is a deliberate adaptation, excluded from the
source-byte manifest and verified separately.

A passing filesystem rehearsal proves that the saved files can be rendered and
installed. It does **not** prove a working graphical login, input remapping on
new hardware, sound, video decoding, Spotify authentication, or hibernation.
Those require the real-machine checks in the private runbook.
