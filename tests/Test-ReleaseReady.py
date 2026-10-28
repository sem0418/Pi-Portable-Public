"""Exercise release handoff corruption/mismatch refusal using synthetic ZIPs."""
import contextlib, hashlib, importlib.util, io, json, tempfile, unittest, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('release_ready', ROOT / '.github/scripts/Release-Ready.py')
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)
d = r.d


class ReleaseReadyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='PiReleaseReady-')
        self.root = Path(self.temp.name) / 'root'
        self.out = Path(self.temp.name) / 'handoff'
        self.out.mkdir()
        self.versions = {'projectVersion': '1.1.1', 'architecture': 'win-x64',
                         'components': {n: {'version': '1.0.0'} for n in ['pi', 'node', 'git']}}
        self.source = b'synthetic source, not a native program'
        self.catalog = {'sources': [{'filename': 'fixture.tgz', 'size': len(self.source),
                                    'sha256': hashlib.sha256(self.source).hexdigest()}]}
        d.write_json(self.root / 'updater/versions.json', self.versions)
        d.write_json(self.root / d.SOURCE_FILE, self.catalog)
        self.payload = {'Pi-Portable/updater/versions.json': (self.root / 'updater/versions.json').read_bytes(),
                        'Pi-Portable/' + d.SOURCE_FILE: (self.root / d.SOURCE_FILE).read_bytes(),
                        'Pi-Portable/LICENSE': b'fixture notice',
                        'corresponding-source/fixture.tgz': self.source,
                        'corresponding-source/BUILDING.md': b'fixture recipe',
                        'corresponding-source/source-audit.json': b'{}'}
        self.build()

    def tearDown(self):
        self.temp.cleanup()

    def build(self, duplicate=False):
        self.archive = self.out / 'Pi-Portable-1.1.1-public-candidate.zip'
        entries = [{'path': n, 'bytes': len(b), 'sha256': hashlib.sha256(b).hexdigest()}
                   for n, b in self.payload.items()]
        record = {'schemaVersion': 1, 'projectVersion': '1.1.1', 'historyIncluded': False,
                  'userDataIncluded': False, 'sourceArchives': 1, 'gitPackageVersions': 1, 'files': entries}
        with zipfile.ZipFile(self.archive, 'w') as z:
            for name, data in self.payload.items():
                z.writestr(name, data)
            z.writestr('DISTRIBUTION.json', json.dumps(record))
            if duplicate:
                import warnings
                with warnings.catch_warnings():
                    warnings.simplefilter('ignore', UserWarning)
                    z.writestr('Pi-Portable/LICENSE', b'duplicate')
        self.summary = {k: v for k, v in record.items() if k != 'files'} | {
            'status': 'passed', 'archive': self.archive.name, 'archiveBytes': self.archive.stat().st_size,
            'sha256': d.sha256(self.archive), 'fileCount': len(entries),
            'sourceInventorySHA256': d.sha256(self.root / d.SOURCE_FILE)}
        d.write_json(self.out / r.SUMMARY, self.summary)
        d.write_json(self.out / r.SCAN, {'status': 'passed', 'findings': 0})

    def prepare(self):
        with contextlib.redirect_stdout(io.StringIO()):
            r.prepare(self.root, self.out, 'a' * 40, 'https://github.com/example/project/actions/runs/123')

    def test_complete_handoff_has_versioned_archive_notes_and_verifiable_checksums(self):
        self.prepare()
        ready = d.read_json(self.out / r.READY)
        self.assertFalse(self.archive.exists())
        self.assertEqual(ready['proposedTag'], 'v1.1.1')
        self.assertEqual(ready['buildCommit'], 'a' * 40)
        self.assertFalse(ready['publicationPerformed'])
        self.assertEqual(ready['status'], 'prepared-not-published')
        self.assertIn('1.0.0', (self.out / r.NOTES).read_text(encoding='utf-8'))
        with contextlib.redirect_stdout(io.StringIO()):
            r.verify(self.out)

    def test_corrupt_archive_is_refused_before_handoff(self):
        self.archive.write_bytes(self.archive.read_bytes() + b'corruption')
        with self.assertRaisesRegex(ValueError, 'checksum/size'):
            self.prepare()
        self.assertFalse((self.out / r.READY).exists())

    def test_missing_source_is_refused_even_with_rewritten_outer_checksums(self):
        del self.payload['corresponding-source/fixture.tgz']
        self.build()
        with self.assertRaisesRegex(ValueError, 'exactly the declared'):
            self.prepare()
        self.assertFalse((self.out / r.READY).exists())

    def test_duplicate_zip_names_are_refused(self):
        self.build(duplicate=True)
        with self.assertRaisesRegex(ValueError, 'Duplicate entries'):
            self.prepare()

    def test_changed_source_is_refused_even_when_zip_entries_and_outer_hash_match(self):
        self.payload['corresponding-source/fixture.tgz'] = b'changed source payload'
        self.build()
        with self.assertRaisesRegex(ValueError, 'source differs from the pinned'):
            self.prepare()

    def test_user_data_inside_zip_is_refused(self):
        self.payload['Pi-Portable/data/agent/models.json'] = b'private sentinel'
        self.build()
        with self.assertRaisesRegex(ValueError, 'Private or unapproved'):
            self.prepare()

    def test_stale_version_and_failed_scan_are_refused(self):
        self.versions['projectVersion'] = '1.1.2'
        d.write_json(self.root / 'updater/versions.json', self.versions)
        with self.assertRaisesRegex(ValueError, 'different project/source'):
            self.prepare()
        self.versions['projectVersion'] = '1.1.1'
        d.write_json(self.root / 'updater/versions.json', self.versions)
        d.write_json(self.out / r.SCAN, {'status': 'passed', 'findings': 1})
        with self.assertRaisesRegex(ValueError, 'no unreviewed findings'):
            self.prepare()

    def test_changed_notes_and_unreviewed_added_files_are_refused(self):
        self.prepare()
        notes = (self.out / r.NOTES).read_bytes()
        (self.out / r.NOTES).write_bytes(notes + b'changed')
        with self.assertRaisesRegex(ValueError, 'asset checksum/size'):
            r.verify(self.out)
        (self.out / r.NOTES).write_bytes(notes)
        (self.out / 'private.txt').write_text('private sentinel')
        with self.assertRaisesRegex(ValueError, 'Unreviewed file'):
            r.verify(self.out)

    def test_component_version_metadata_is_bound_to_zip(self):
        self.prepare()
        ready = d.read_json(self.out / r.READY)
        ready['components']['pi'] = '9.9.9'
        d.write_json(self.out / r.READY, ready)
        with self.assertRaisesRegex(ValueError, 'component versions differ'):
            r.verify(self.out)

    def test_path_traversal_in_report_and_credentialed_run_url_are_refused(self):
        self.summary['archive'] = '../outside.zip'
        d.write_json(self.out / r.SUMMARY, self.summary)
        with self.assertRaisesRegex(ValueError, 'Unsafe relative path'):
            self.prepare()
        with self.assertRaisesRegex(ValueError, 'canonical build run URL'):
            r.prepare(self.root, self.out, 'a' * 40, 'https://token@github.com/example/project/actions/runs/123')


if __name__ == '__main__':
    unittest.main(testRunner=unittest.TextTestRunner(stream=__import__('sys').stdout, verbosity=2))
