#!/usr/bin/env python3
"""Check captured desktop bytes and system snapshots without invoking services."""
import argparse
import hashlib
import json
import os
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', required=True, type=Path)
    parser.add_argument('--home', default=Path.home(), type=Path,
                        help='Source host home or isolated exported home')
    args = parser.parse_args()
    failures = []
    live = json.loads((args.profile / 'live-files.json').read_text())
    for item in live:
        path = args.home / item['target']
        try:
            if item['kind'] == 'symlink':
                raw = os.readlink(path).encode()
            else:
                if path.is_symlink():
                    raise ValueError('unexpected symlink')
                raw = path.read_bytes()
            if hashlib.sha256(raw).hexdigest() != item['sha256']:
                failures.append(item['target'] + ': content differs from capture')
        except (OSError, ValueError) as error:
            failures.append(item['target'] + ': ' + str(error))
    meta = json.loads((args.profile / 'profile.json').read_text())
    for item in meta['system_files']:
        path = args.profile / item['path']
        try:
            if hashlib.sha256(path.read_bytes()).hexdigest() != item['sha256']:
                failures.append(item['path'] + ': snapshot checksum mismatch')
        except OSError as error:
            failures.append(item['path'] + ': ' + str(error))
    for failure in failures:
        print('FAIL ' + failure)
    print(f'Checked {len(live)} captured user targets and {len(meta["system_files"])} system snapshots; '
          f'{len(failures)} failures. Runtime behavior is not tested by this command.')
    return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(main())
