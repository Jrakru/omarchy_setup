#!/usr/bin/env python3
"""Preview or install the Kanata system files from a private desktop profile.

No services are started. Hardware/power reference snapshots are never applied.
Use --root with a disposable directory to rehearse without privilege.
"""
import argparse
import hashlib
import json
import os
import platform
import pwd
import shutil
import sys
import tempfile
from pathlib import Path

ALLOWED = {
    '/usr/local/bin/kanata': 0o755,
    '/usr/local/bin/kanata-caps-layer-led': 0o755,
    '/etc/systemd/system/kanata.service': 0o644,
    '/etc/systemd/system/kanata-caps-layer-led.service': 0o644,
    '/etc/polkit-1/rules.d/49-kanata.rules': 0o644,
}


def plan(profile, home, root, check_destinations=True):
    profile = profile.resolve(strict=True)
    root = root.resolve()
    meta = json.loads((profile / 'profile.json').read_text())
    if meta['source_arch'] != platform.machine():
        raise ValueError('Saved Kanata binary architecture differs from this machine')
    if not home.is_absolute() or any(c in str(home) for c in '\n\r\t %"\'\\'):
        raise ValueError('Home must be an absolute systemd-safe path without whitespace or specifiers')
    operations = []
    seen = set()
    for item in meta['system_files']:
        if not item.get('install'):
            continue
        target = item['target']
        if target not in ALLOWED or target in seen:
            raise ValueError('Unexpected or duplicate system target: ' + target)
        seen.add(target)
        source = (profile / item['path']).resolve(strict=True)
        if not source.is_relative_to(profile):
            raise ValueError('Profile source escapes profile directory')
        raw = source.read_bytes()
        if hashlib.sha256(raw).hexdigest() != item['sha256']:
            raise ValueError('Snapshot checksum mismatch: ' + item['path'])
        if target.endswith('.service'):
            raw = raw.replace(meta['source_home'].encode(), str(home).encode())
        destination = root / target.lstrip('/')
        # Neither existing destinations nor their parents may redirect writes.
        for candidate in ([destination, *destination.parents] if check_destinations else []):
            if candidate == root:
                if candidate.exists() and not candidate.is_dir():
                    raise ValueError('Installation root is not a directory')
                break
            if candidate.is_symlink():
                raise ValueError('Refusing symlink in installation path: ' + str(candidate))
            if candidate.exists() and (not candidate.is_file() if candidate == destination else not candidate.is_dir()):
                raise ValueError('Unexpected file type in installation path: ' + str(candidate))
        operations.append((destination, raw, ALLOWED[target]))
    if seen != set(ALLOWED):
        raise ValueError('Profile is missing required Kanata system files')
    return meta, operations


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', type=Path, required=True)
    parser.add_argument('--home', type=Path, required=True, help='New account home directory')
    parser.add_argument('--root', type=Path, default=Path('/'), help='Disposable rehearsal root, or /')
    parser.add_argument('--apply', action='store_true', help='Write files; default only previews')
    args = parser.parse_args(argv)
    try:
        real_root = args.root.resolve() == Path('/')
        if args.apply and real_root:
            meta = json.loads((args.profile / 'profile.json').read_text())
            machine = hashlib.sha256(Path('/etc/machine-id').read_bytes()).hexdigest()
            if machine == meta['source_machine_sha256']:
                raise ValueError('Refusing installation on the source host; use --root for rehearsal')
            if os.geteuid() != 0:
                raise ValueError('Installing into / requires sudo')
            account = next((p for p in pwd.getpwall() if p.pw_dir == str(args.home)), None)
            if account is None or account.pw_uid == 0:
                raise ValueError('--home must identify an existing non-root account')
            if not (args.home / '.config/kanata/kanata.kbd').is_file():
                raise ValueError('Restore the user Kanata configuration before installing system files')
        meta, operations = plan(args.profile, args.home, args.root,
                                check_destinations=args.apply)
        # Preflight every destination before the first write.
        if args.apply:
            for destination, raw, mode in operations:
                backup = destination.with_name(destination.name + '.before-omarchy-restore')
                if destination.exists() and (backup.exists() or backup.is_symlink()):
                    if destination.read_bytes() != raw:
                        raise ValueError('Backup already exists; review it before replacing: ' + str(backup))
        for destination, raw, mode in operations:
            print(('INSTALL ' if args.apply else 'PLAN ') + str(destination))
            if not args.apply:
                continue
            destination.parent.mkdir(parents=True, exist_ok=True)
            if destination.exists() and destination.read_bytes() != raw:
                shutil.copy2(destination, destination.with_name(destination.name + '.before-omarchy-restore'))
            # Replace the inode so an existing hardlink cannot redirect writes
            # into a file outside the installation tree.
            fd, temporary = tempfile.mkstemp(prefix='.omarchy-restore-', dir=destination.parent)
            try:
                with os.fdopen(fd, 'wb') as stream:
                    stream.write(raw)
                    stream.flush()
                    os.fsync(stream.fileno())
                    os.fchmod(stream.fileno(), mode)
                    if real_root:
                        os.fchown(stream.fileno(), 0, 0)
                os.replace(temporary, destination)
            finally:
                if os.path.exists(temporary):
                    os.unlink(temporary)
        print('No services started. Next: validate Kanata, daemon-reload, then enable it explicitly.')
        return 0
    except (ValueError, OSError, KeyError, json.JSONDecodeError) as error:
        print('restore-system: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
