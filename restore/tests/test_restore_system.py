import hashlib
import importlib.util
import json
import platform
import os
import contextlib
import io
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location('restore_system', Path(__file__).parents[1] / 'restore-system.py')
RESTORE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RESTORE)


class RestoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.profile = self.base / 'profile'
        self.profile.mkdir()
        self.root = self.base / 'target'
        self.meta = {'source_arch': platform.machine(), 'source_home': '/home/source',
                     'source_machine_sha256': 'not-this-host', 'system_files': []}
        for index, target in enumerate(RESTORE.ALLOWED):
            raw = (f'file {index}\nExecStart=/home/source/.config/kanata/kanata.kbd\n').encode()
            name = f'file-{index}'
            (self.profile / name).write_bytes(raw)
            self.meta['system_files'].append({'path': name, 'target': target, 'install': True,
                                             'sha256': hashlib.sha256(raw).hexdigest()})
        self.write_meta()

    def write_meta(self):
        (self.profile / 'profile.json').write_text(json.dumps(self.meta))

    def run_restore(self, apply=True):
        args = ['--profile', str(self.profile), '--home', '/home/new-user', '--root', str(self.root)]
        return RESTORE.main(args + (['--apply'] if apply else []))

    def test_preview_writes_nothing(self):
        self.assertEqual(self.run_restore(False), 0)
        self.assertFalse(self.root.exists())

    def test_source_host_is_refused_before_destination_inspection(self):
        self.meta['source_machine_sha256'] = hashlib.sha256(Path('/etc/machine-id').read_bytes()).hexdigest()
        self.write_meta()
        error = io.StringIO()
        with contextlib.redirect_stderr(error):
            result = RESTORE.main(['--profile', str(self.profile), '--home', '/home/new-user', '--apply'])
        self.assertEqual(result, 1)
        self.assertIn('Refusing installation on the source host', error.getvalue())

    def test_restore_rehomes_units_and_is_repeatable(self):
        self.assertEqual(self.run_restore(), 0)
        unit = self.root / 'etc/systemd/system/kanata.service'
        self.assertIn(b'/home/new-user/', unit.read_bytes())
        self.assertNotIn(b'/home/source/', unit.read_bytes())
        self.assertEqual((self.root / 'usr/local/bin/kanata').stat().st_mode & 0o777, 0o755)
        self.assertEqual(self.run_restore(), 0)
        self.assertFalse(unit.with_name(unit.name + '.before-omarchy-restore').exists())

    def test_tamper_fails_before_any_write(self):
        (self.profile / 'file-4').write_bytes(b'tampered')
        self.assertEqual(self.run_restore(), 1)
        self.assertFalse(self.root.exists())

    def test_missing_required_file_fails_before_any_write(self):
        self.meta['system_files'].pop()
        self.write_meta()
        self.assertEqual(self.run_restore(), 1)
        self.assertFalse(self.root.exists())

    def test_target_escape_is_rejected(self):
        self.meta['system_files'][0]['target'] = '/../../outside'
        self.write_meta()
        self.assertEqual(self.run_restore(), 1)
        self.assertFalse(self.root.exists())

    def test_source_escape_is_rejected(self):
        outside = self.base / 'outside'
        outside.write_bytes((self.profile / 'file-0').read_bytes())
        self.meta['system_files'][0]['path'] = '../outside'
        self.write_meta()
        self.assertEqual(self.run_restore(), 1)
        self.assertFalse(self.root.exists())

    def test_symlink_destination_is_rejected(self):
        self.root.mkdir()
        outside = self.base / 'outside'
        outside.mkdir()
        (self.root / 'usr').symlink_to(outside, target_is_directory=True)
        self.assertEqual(self.run_restore(), 1)
        self.assertEqual(list(outside.iterdir()), [])

    def test_existing_files_are_backed_up(self):
        unit = self.root / 'etc/systemd/system/kanata.service'
        unit.parent.mkdir(parents=True)
        unit.write_bytes(b'original')
        self.assertEqual(self.run_restore(), 0)
        self.assertEqual(unit.with_name(unit.name + '.before-omarchy-restore').read_bytes(), b'original')

    def test_hardlink_does_not_overwrite_external_file(self):
        outside = self.base / 'outside'
        outside.write_bytes(b'external-original')
        binary = self.root / 'usr/local/bin/kanata'
        binary.parent.mkdir(parents=True)
        os.link(outside, binary)
        self.assertEqual(self.run_restore(), 0)
        self.assertEqual(outside.read_bytes(), b'external-original')
        self.assertNotEqual(binary.read_bytes(), outside.read_bytes())

    def test_directory_target_fails_before_first_write(self):
        unit = self.root / 'etc/systemd/system/kanata.service'
        unit.mkdir(parents=True)
        self.assertEqual(self.run_restore(), 1)
        self.assertFalse((self.root / 'usr').exists())

    def test_existing_backup_prevents_overwrite(self):
        unit = self.root / 'etc/systemd/system/kanata.service'
        unit.parent.mkdir(parents=True)
        unit.write_bytes(b'original')
        unit.with_name(unit.name + '.before-omarchy-restore').write_bytes(b'older')
        self.assertEqual(self.run_restore(), 1)
        self.assertEqual(unit.read_bytes(), b'original')
        self.assertFalse((self.root / 'usr').exists())


if __name__ == '__main__':
    unittest.main()
