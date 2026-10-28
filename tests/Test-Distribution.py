"""Negative tests for source completeness and history/user-data exclusion.

Synthetic source bytes; actual local Git and filesystem. Native binaries and
full real source archives are checked separately in Windows distribution CI.
"""
import hashlib, importlib.util, json, shutil, subprocess, tempfile, unittest, sys, tarfile, io
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('distribution', ROOT / '.github/scripts/Distribution.py')
d = importlib.util.module_from_spec(spec); spec.loader.exec_module(d)

class DistributionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='PiDistribution-')
        self.root = Path(self.temp.name) / 'project'; self.root.mkdir()
        self.sources = Path(self.temp.name) / 'sources'; self.sources.mkdir()
        (self.root / 'tools/git/etc').mkdir(parents=True)
        (self.root / 'tools/git/etc/package-versions.txt').write_text('fixture 1.0-1\n')
        self.catalog = {'schemaVersion':2, 'gitPackageListSHA256':d.sha256(self.root/'tools/git/etc/package-versions.txt'),
                        'packages':[{'name':'fixture','version':'1.0-1','sourceId':'fixture'}],
                        'components':{}, 'sources':[]}
        versions = {'components':{}}
        for n in ['pi','node','git']:
            versions['components'][n] = {'version':'1.0.0','sha256':'a'*64}
            self.catalog['components'][n] = {'version':'1.0.0','archiveSHA256':'a'*64,'sourceIds':['fixture']}
        (self.sources/'fixture.tgz').write_bytes(b'fake compressed source payload')
        self.catalog['sources'] = [{'id':'fixture','filename':'fixture.tgz','kind':'http','url':'https://example.invalid/source.tgz',
                                   'sha256':d.sha256(self.sources/'fixture.tgz'),'size':(self.sources/'fixture.tgz').stat().st_size}]
        d.write_json(self.root/'updater/versions.json',versions)
        self.save()
        d.write_json(self.root/'licenses/security-baseline.json',{'minimumVersions':{'git':'1.0.0','node':'1.0.0'}})
    def tearDown(self):
        self.temp.cleanup()
    def save(self):
        d.write_json(self.root/d.SOURCE_FILE,self.catalog)
    def test_matching_source_bytes_pass_and_corruption_blocks(self):
        d.verify_sources(self.root,self.sources)
        (self.sources/'fixture.tgz').write_bytes(b'corrupted')
        with self.assertRaisesRegex(ValueError,'Missing/corrupt'):
            d.verify_sources(self.root,self.sources)
    def test_missing_source_blocks_even_with_valid_inventory(self):
        (self.sources/'fixture.tgz').unlink()
        with self.assertRaisesRegex(ValueError,'Missing/corrupt'):
            d.verify_sources(self.root,self.sources)
    def test_changed_component_requires_fresh_source_review(self):
        v=d.read_json(self.root/'updater/versions.json');v['components']['git']['version']='2.0.0'
        d.write_json(self.root/'updater/versions.json',v)
        with self.assertRaisesRegex(ValueError,'does not match installed'):
            d.catalog(self.root)
    def test_omitted_and_duplicate_package_coverage_block(self):
        self.catalog['packages']=[];self.save()
        with self.assertRaisesRegex(ValueError,'every shipped package'):
            d.catalog(self.root)
        self.catalog['packages']=[{'name':'fixture','version':'1.0-1','sourceId':'fixture'}]*2;self.save()
        with self.assertRaisesRegex(ValueError,'every shipped package'):
            d.catalog(self.root)
    def test_known_security_fix_floor_blocks_old_runtime_even_when_sources_match(self):
        d.write_json(self.root/'licenses/security-baseline.json',{'minimumVersions':{'git':'1.0.1'}})
        with self.assertRaisesRegex(ValueError,'predates the audited security baseline'):
            d.catalog(self.root)
    def test_package_list_change_blocks_even_same_git_version(self):
        (self.root/'tools/git/etc/package-versions.txt').write_text('fixture 1.1-1\n')
        with self.assertRaisesRegex(ValueError,'package list changed'):
            d.catalog(self.root)
    def test_unreferenced_source_id_and_duplicate_filename_block(self):
        self.catalog['packages'][0]['sourceId']='missing';self.save()
        with self.assertRaisesRegex(ValueError,'missing source'):
            d.catalog(self.root)
        self.catalog['packages'][0]['sourceId']='fixture'
        self.catalog['sources'].append(dict(self.catalog['sources'][0],id='second'));self.save()
        with self.assertRaisesRegex(ValueError,'Duplicate'):
            d.catalog(self.root)
    def test_traversal_and_credential_urls_block(self):
        for bad in ['../private.tgz','C:/private.tgz','\\\\server\\private.tgz','/private.tgz']:
            self.catalog['sources'][0]['filename']=bad;self.save()
            with self.assertRaises(ValueError):d.catalog(self.root)
        self.catalog['sources'][0]['filename']='fixture.tgz'
        self.catalog['sources'][0]['url']='https://user:secret@example.invalid/source.tgz';self.save()
        with self.assertRaisesRegex(ValueError,'credential-free'):
            d.catalog(self.root)
    def test_source_budget_stops_before_any_network(self):
        with self.assertRaisesRegex(ValueError,'source budget'):
            d.collect(self.root,Path(self.temp.name)/'out',Path(self.temp.name)/'cache',0)
        self.assertFalse((Path(self.temp.name)/'out').exists())
    def test_private_and_historical_paths_are_outside_export(self):
        for path in ['data/agent/models.json','workspace/work.txt','.git/config','updater/logs/test.log',
                     'docs/EXECUTION-LOG.md','docs/PRIVACY-MAINTENANCE.md','.github/workflows/privacy-audit.yml',
                     '.github/private-maintenance/History-Audit.py',
                     'updater/backups/version/a','tests/build-results/report.json','tests/maintenance-results/private.json',
                     'licenses/notice.json.previous']:
            self.assertFalse(d.allowed_export(path),path)
        self.assertTrue(d.allowed_export('updater/resources/defaults/models.example.json'))
    def test_real_git_export_omits_tracked_secret_and_untracked_files(self):
        def git(*args):
            subprocess.run(['git','-C',str(self.root),*args],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
        git('init','-q')
        (self.root/'runtime/pi').mkdir(parents=True)
        for i in range(101):(self.root/f'runtime/pi/file-{i}.txt').write_text('synthetic component')
        (self.root/'data/agent').mkdir(parents=True)
        (self.root/'data/agent/models.json').write_text('PRIVATE CONFIG SENTINEL')
        git('add','--all')
        (self.root/'runtime/pi/untracked.txt').write_text('NOT IN DISTRIBUTION')
        out=Path(self.temp.name)/'export';d.stage(self.root,out)
        self.assertFalse((out/'.git').exists());self.assertFalse((out/'data').exists())
        self.assertFalse((out/'runtime/pi/untracked.txt').exists())
        self.assertEqual((out/'runtime/pi/file-1.txt').read_text(),'synthetic component')
        with self.assertRaisesRegex(ValueError,'must be new'):d.stage(self.root,out)
    def test_recipe_without_upstream_source_payload_is_blocked(self):
        p=Path(self.temp.name)/'incomplete-source.tar.gz'
        info=b'pkgbase = fixture\nsource = https://example.invalid/upstream.tar.gz\n'
        recipe=b'pkgname=fixture\n'
        with tarfile.open(p,'w:gz') as t:
            for name,data in [('fixture/.SRCINFO',info),('fixture/PKGBUILD',recipe)]:
                entry=tarfile.TarInfo(name);entry.size=len(data);t.addfile(entry,io.BytesIO(data))
        proof={'sourceInfoSHA256':hashlib.sha256(info).hexdigest(),'recipeSHA256':hashlib.sha256(recipe).hexdigest()}
        with self.assertRaisesRegex(ValueError,'without its upstream source payload'):
            d.audit_package_source(p,{'filename':p.name,'packageProof':proof})
    def test_source_recipe_must_match_the_mapped_binary_package(self):
        self.catalog['sources'][0]['packageProof']={'version':'9.0-1','binaryPackages':['fixture']};self.save()
        with self.assertRaisesRegex(ValueError,'different source recipe/version'):d.catalog(self.root)
        self.catalog['sources'][0]['packageProof']={'version':'1.0-1','binaryPackages':['different']};self.save()
        with self.assertRaisesRegex(ValueError,'different source recipe/version'):d.catalog(self.root)
    def test_effective_native_component_source_and_lfs_identity_are_bound(self):
        p=self.root/'tools/git/native.exe';p.write_text('version https://git-lfs.github.com/spec/v1\noid sha256:'+'c'*64+'\nsize 12345\n')
        self.catalog['effectiveComponents']=[{'name':'fixture-native','path':'tools/git/native.exe',
            'sha256':'c'*64,'size':12345,'sourceIds':['fixture']}];self.save()
        d.catalog(self.root)
        p.write_text('version https://git-lfs.github.com/spec/v1\noid sha256:'+'d'*64+'\nsize 12345\n')
        with self.assertRaisesRegex(ValueError,'LFS identity changed'):d.catalog(self.root)
        self.catalog['effectiveComponents'][0]['sourceIds']=['missing'];self.save()
        with self.assertRaisesRegex(ValueError,'source closure is incomplete'):d.catalog(self.root)
    @unittest.skipIf(sys.platform=='win32','Linux-only refusal test; real Windows packaging runs in CI')
    def test_packaging_requires_native_windows_gate(self):
        with self.assertRaisesRegex(ValueError,'native Windows public gate'):
            d.package(self.root,self.sources,Path(self.temp.name)/'out')
    def test_scanner_review_bytes_must_match_the_installed_upstream_manifest(self):
        entry={'path':'tools/git/data.txt','size':20,'sha256':'b'*64,'rule':'fixture','line':8}
        d.write_json(self.root/'.github/scripts/secret-scan-reviewed.json',{'findings':[entry]})
        d.write_json(self.root/'updater/manifests/git.json',{'files':[{'path':'data.txt','size':20,'sha256':'a'*64}]})
        with self.assertRaisesRegex(ValueError,'original installed bytes'):d.catalog(self.root)
        d.write_json(self.root/'updater/manifests/git.json',{'files':[{'path':'data.txt','size':20,'sha256':'b'*64}]})
        d.catalog(self.root)
        entry['path']='README.md';d.write_json(self.root/'.github/scripts/secret-scan-reviewed.json',{'findings':[entry]})
        with self.assertRaisesRegex(ValueError,'original upstream payload'):d.catalog(self.root)
    def test_secret_review_cannot_hide_changed_bytes_or_other_findings(self):
        p=self.root/'tools/git/data.txt';p.write_text('known harmless upstream data')
        entry={'path':'tools/git/data.txt','rule':'fixture-rule','line':8,'size':p.stat().st_size,'sha256':d.sha256(p)}
        d.write_json(self.root/'.github/scripts/secret-scan-reviewed.json',{'schemaVersion':1,'scannerVersion':'fixture','findings':[entry]})
        finding={'File':str(p),'RuleID':'fixture-rule','StartLine':8}
        self.assertEqual(d.review_scan_findings(self.root,[finding],'fixture'),([],1))
        for changed in [dict(finding,RuleID='other-rule'),dict(finding,StartLine=9),dict(finding,File=str(self.root/'../outside.txt'))]:
            self.assertEqual(d.review_scan_findings(self.root,[changed],'fixture'),([changed],0))
        p.write_text('X'*entry['size'])
        self.assertEqual(d.review_scan_findings(self.root,[finding],'fixture'),([finding],0))
        with self.assertRaisesRegex(ValueError,'pinned scanner'):d.review_scan_findings(self.root,[finding],'another-version')
    def test_clean_export_gate_rejects_data_added_after_copy(self):
        out=Path(self.temp.name)/'export';out.mkdir();(out/'data').mkdir();(out/'data/key.txt').write_text('sentinel')
        with self.assertRaisesRegex(ValueError,'data entered'):d.assert_clean_tree(out)

if __name__=='__main__':
    unittest.main(testRunner=unittest.TextTestRunner(stream=sys.stdout,verbosity=2))

