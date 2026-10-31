"""Run the shipped migration against disposable files and simulated ZFS/systemd.

rsync/checksum/permissions are real; no mounts, pool or services are touched.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

MOCK = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
base = pathlib.Path(os.environ['FIXTURE'])
name, args = pathlib.Path(sys.argv[0]).name, sys.argv[1:]
registry = base / 'mounts.json'
mounts = json.loads(registry.read_text())
def data(ds): return base / 'pool' / ds.replace('/', '_')
if name == 'zfs':
    op = args[0]
    if op == 'list':
        sys.exit(0 if data(args[-1]).exists() else 1)
    if op == 'create': data(args[-1]).mkdir()
    elif op == 'rename': data(args[1]).rename(data(args[2]))
    elif op == 'set': pass
    elif op != 'list': raise RuntimeError('unexpected zfs mutation: ' + op)
elif name == 'id':
    print('1000')
elif name == 'systemctl':
    sys.exit(1 if 'is-active' in args else 0)
elif name == 'mountpoint': sys.exit(0 if args[-1] in mounts else 1)
elif name == 'findmnt':
    if '-M' in args:
        value = mounts.get(args[args.index('-M') + 1])
        if value: print(value); sys.exit(0)
    elif '-S' in args and args[args.index('-S') + 1] in mounts.values(): sys.exit(0)
    sys.exit(1)
elif name == 'mount':
    ds, target = args[-2:]
    p = pathlib.Path(target)
    p.rmdir()
    p.symlink_to(data(ds))
    mounts[target] = ds
elif name == 'umount':
    target = args[-1]
    pathlib.Path(target).unlink()
    pathlib.Path(target).mkdir()
    mounts.pop(target)
elif name == 'rsync':
    if (base / 'fail-copy').exists(): sys.exit(23)
    if (base / 'fail-sync').exists() and args[-1].rstrip('/') == str(base / 'ssd'): sys.exit(23)
    if (base / 'fail-verify').exists() and '--itemize-changes' in args:
        print('>fc........ mismatch'); sys.exit(0)
    os.execv(os.environ['REAL_RSYNC'], ['rsync', *args])
elif name in ('sync', 'chown'): pass
else: raise RuntimeError(name)
registry.write_text(json.dumps(mounts))
'''


class Migration(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for name in ['pool', 'bin', 'state', 'run', 'host']:
            (self.root / name).mkdir()
        (self.root / 'mounts.json').write_text('{}')
        for ds in ['storage', 'games', 'media', 'archives/deltachat',
                   'archives/cold-backups', 'nixos-archive', 'sync']:
            self.dataset(ds).mkdir()
        games = self.dataset('games')
        for name in ['public', 'private/xsy', 'private/shj', 'private/ly',
                     'private/lys', 'incoming', 'library']:
            (games / name).mkdir(parents=True, exist_ok=True)
            (games / name / 'payload').write_text(name)
        (games / 'library/.hidden').write_text('keep')
        os.link(games / 'library/payload', games / 'library/hardlink')
        (games / 'private/shj').chmod(0o700)
        (games / '.unknown').write_text('keep too')
        media = self.dataset('media')
        (media / 'movie').write_text('video')
        (media / 'movie').chmod(0o600)
        media.chmod(0o700)
        (self.dataset('sync') / 'state').mkdir()
        (self.dataset('sync') / 'state/config.xml').write_text('<configuration/>')
        (self.dataset('sync') / 'state/key.pem').write_text('fixture identity')
        mock = self.root / 'bin/mock'
        mock.write_text(MOCK.replace("#!/usr/bin/env python3", "#!" + sys.executable, 1))
        mock.chmod(0o755)
        for name in ['zfs', 'systemctl', 'mountpoint', 'findmnt', 'mount',
                     'umount', 'rsync', 'sync', 'chown', 'id']:
            (self.root / 'bin' / name).symlink_to(mock)
        source = (Path(__file__).resolve().parents[1] / 'migrate-layout.sh').read_text()
        source = source.replace('/srv/storage', str(self.root / 'host'))
        source = source.replace('/var/lib/storage-syncthing', str(self.root / 'ssd'))
        self.script = self.root / 'migration.sh'
        self.script.write_text(source)
        self.env = dict(os.environ, FIXTURE=str(self.root),
                        STATE_DIRECTORY=str(self.root / 'state'),
                        RUNTIME_DIRECTORY=str(self.root / 'run'),
                        REAL_RSYNC=shutil.which('rsync'),
                        PATH=str(self.root / 'bin') + ':' + os.environ['PATH'])

    def dataset(self, suffix):
        ds = suffix if suffix == 'storage' else 'storage/' + suffix
        return self.root / 'pool' / ds.replace('/', '_')

    def run_migration(self):
        return subprocess.run(['bash', str(self.script)], env=self.env,
                              capture_output=True, text=True, timeout=30, check=False)

    def test_preserves_sources_and_skips_completed_migration(self):
        result = self.run_migration()
        self.assertEqual(result.returncode, 0, result.stderr)
        archive = self.dataset('private/xsy') / 'archives/legacy-games'
        self.assertEqual((archive / '.unknown').read_text(), 'keep too')
        self.assertEqual((archive / 'private/lys/payload').read_text(), 'private/lys')
        self.assertEqual((archive / 'library/.hidden').read_text(), 'keep')
        self.assertEqual((archive / 'library/payload').stat().st_ino,
                         (archive / 'library/hardlink').stat().st_ino)
        self.assertEqual((self.dataset('private/shj') / 'payload').read_text(), 'private/shj')
        self.assertEqual(self.dataset('private/shj').stat().st_mode & 0o777, 0o700)
        self.assertEqual((self.dataset('public/media') / 'movie').stat().st_mode & 0o777, 0o644)
        self.assertTrue((self.dataset('games') / 'library/.hidden').exists())
        self.assertEqual((self.root / 'ssd/key.pem').read_text(), 'fixture identity')
        self.assertTrue(self.dataset('private/xsy/archives/nixos-archive').exists())
        # A completed migration must not replay old copies over newer user data.
        target = self.dataset('private/shj') / 'payload'
        target.write_text('new user data')
        self.assertEqual(self.run_migration().returncode, 0)
        self.assertEqual(target.read_text(), 'new user data')
        self.assertEqual(json.loads((self.root / 'mounts.json').read_text()), {})

    def test_copy_failure_has_no_completion_and_can_resume(self):
        failure = self.root / 'fail-copy'
        failure.touch()
        self.assertNotEqual(self.run_migration().returncode, 0)
        self.assertFalse((self.root / 'state/complete-v1').exists())
        self.assertTrue(self.dataset('games').exists())
        failure.unlink()
        result = self.run_migration()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_resume_after_all_renames(self):
        failure = self.root / 'fail-sync'
        failure.touch()
        self.assertNotEqual(self.run_migration().returncode, 0)
        self.assertFalse((self.root / 'state/complete-v1').exists())
        self.assertFalse(self.dataset('media').exists())
        self.assertTrue(self.dataset('public/media').exists())
        failure.unlink()
        result = self.run_migration()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_checksum_differences_block_completion(self):
        (self.root / 'fail-verify').touch()
        self.assertNotEqual(self.run_migration().returncode, 0)
        self.assertFalse((self.root / 'state/complete-v1').exists())

    def test_existing_destination_is_not_overwritten(self):
        target = self.dataset('public')
        target.mkdir()
        (target / 'unique').write_text('untouched')
        self.assertNotEqual(self.run_migration().returncode, 0)
        self.assertEqual((target / 'unique').read_text(), 'untouched')
        self.assertFalse((self.root / 'state/complete-v1').exists())

    def test_archive_symlink_is_rejected(self):
        (self.dataset('games') / 'private/xsy/archives').symlink_to(self.root / 'outside')
        self.assertNotEqual(self.run_migration().returncode, 0)
        self.assertFalse((self.root / 'outside').exists())


if __name__ == '__main__':
    unittest.main()
