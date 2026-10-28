"""Prepare a history-free distribution with exact-version corresponding sources.

This module never discovers or installs newer Pi/Node/Git versions. Only the
existing Entry.ps1 updater does that. All downloads here are source/tool bytes
pinned in the reviewed corresponding-source inventory.
"""
from __future__ import annotations
import argparse, concurrent.futures, gzip, hashlib, json, os, re, shutil
import subprocess, sys, tarfile, tempfile, urllib.parse, urllib.request, zipfile
from pathlib import Path, PurePosixPath

BLOCK = 'PUBLIC REDISTRIBUTION BLOCKED: '
SOURCE_FILE = 'licenses/corresponding-source.json'
ROOT_FILES = {'.gitattributes', '.gitignore', 'LICENSE', 'README.md', 'README.en.md',
              'CHANGELOG.md', 'SECURITY.md', 'CONTRIBUTING.md', 'SOURCE-ACCESS.md'}
ROOTS = ('runtime/pi/', 'tools/node/', 'tools/git/', 'updater/resources/',
         'updater/scripts/', 'updater/manifests/', 'licenses/', 'docs/',
         '.github/scripts/', '.github/workflows/', '.github/ISSUE_TEMPLATE/')
UPDATER_FILES = {'updater/versions.json', 'updater/source-manifest.json',
                 'updater/skills-manifest.json'}


def fail(message):
    raise ValueError(BLOCK + message)


def read_json(path):
    with Path(path).open(encoding='utf-8-sig') as f:
        return json.load(f)


def write_json(path, value):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def sha256(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        while chunk := f.read(1024 * 1024):
            h.update(chunk)
    return h.hexdigest()


def safe_relative(value):
    p = PurePosixPath(value)
    if not value or p.is_absolute() or '..' in p.parts or '\\' in value or ':' in value or '\0' in value:
        fail('Unsafe relative path')
    return p


def catalog(root):
    root = Path(root)
    path = root / SOURCE_FILE
    if not path.is_file():
        fail('Exact corresponding-source inventory is missing.')
    m = read_json(path)
    if m.get('schemaVersion') != 2:
        fail('Unsupported source inventory schema')
    versions = read_json(root / 'updater/versions.json')
    for name in ('pi', 'node', 'git'):
        actual = versions['components'][name]
        expected = m['components'][name]
        if actual['version'] != expected['version'] or actual['sha256'] != expected['archiveSHA256']:
            fail('Source inventory does not match installed ' + name)
    security_path = root / 'licenses/security-baseline.json'
    if not security_path.is_file():
        fail('Reviewed publication security baseline is missing')
    baseline = read_json(security_path)
    def version_tuple(value):
        if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){2,3}', value):
            fail('Invalid publication security version')
        parts = tuple(int(x) for x in value.split('.'))
        return parts + (0,) * (4 - len(parts))
    for name, minimum in baseline['minimumVersions'].items():
        if version_tuple(versions['components'][name]['version']) < version_tuple(minimum):
            fail(name + ' predates the audited security baseline; run the existing updater before publication.')
    packages_path = root / 'tools/git/etc/package-versions.txt'
    if sha256(packages_path) != m['gitPackageListSHA256']:
        fail('PortableGit package list changed; source review must be refreshed.')
    actual_packages = {tuple(line.split()) for line in packages_path.read_text().splitlines() if line.strip()}
    declared = [(p['name'], p['version']) for p in m['packages']]
    if len(declared) != len(set(declared)) or set(declared) != actual_packages:
        fail('Source inventory does not cover exactly every shipped package/version.')
    ids, filenames = set(), set()
    for source in m['sources']:
        name = source['filename']
        safe_relative(name)
        if '/' in name or name in filenames or source['id'] in ids:
            fail('Duplicate or nested source archive filename/id')
        if not re.fullmatch('[a-f0-9]{64}', source['sha256']) or not 0 < source['size'] <= 2_000_000_000:
            fail('Invalid source archive digest/size')
        if source['kind'] == 'http':
            u = urllib.parse.urlsplit(source['url'])
            if u.scheme != 'https' or u.username or u.password or u.fragment:
                fail('Source URLs must use credential-free HTTPS.')
        elif source['kind'] == 'git-snapshot':
            if not re.fullmatch('[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', source['repository']):
                fail('Invalid source repository')
            if not re.fullmatch('[a-f0-9]{40}', source['commit']):
                fail('Source repository must be pinned to a commit')
            for entry in source['include']:
                safe_relative(entry)
            if not re.fullmatch('[a-f0-9]{64}', source['uncompressedTarSHA256']):
                fail('Missing reproducible source tree archive digest')
        else:
            fail('Unknown source retrieval method')
        ids.add(source['id']); filenames.add(name)
    if any(p['sourceId'] not in ids for p in m['packages']):
        fail('Package refers to a missing source archive')
    by_id = {x['id']: x for x in m['sources']}
    for entry in m['packages']:
        proof = by_id[entry['sourceId']].get('packageProof')
        if proof:
            normalized = entry['name'].replace('mingw-w64-ucrt-x86_64-', 'mingw-w64-x86_64-')
            if (entry['version'].replace('~', ':') != proof['version'].replace('~', ':') or
                (entry['name'] not in proof['binaryPackages'] and normalized not in proof['binaryPackages'])):
                fail('Package mapped to a different source recipe/version: ' + entry['name'])
    for component in m['components'].values():
        if not component['sourceIds'] or any(x not in ids for x in component['sourceIds']):
            fail('Component source closure is incomplete')
    for native in m.get('effectiveComponents', []):
        safe_relative(native['path'])
        if not native['sourceIds'] or any(x not in ids for x in native['sourceIds']):
            fail('Effective native component source closure is incomplete')
        payload = root / native['path']
        if not payload.is_file():
            fail('Effective native component is missing: ' + native['name'])
        if payload.stat().st_size <= 1024:
            # Collection on Linux deliberately leaves LFS pointers unhydrated.
            # The full Windows gate checks every real payload byte separately.
            pointer = payload.read_text(encoding='ascii')
            match = re.fullmatch(r'version https://git-lfs.github.com/spec/v1\noid sha256:([a-f0-9]{64})\nsize ([0-9]+)\n?', pointer)
            if not match or match[1] != native['sha256'] or int(match[2]) != native['size']:
                fail('Effective native component LFS identity changed: ' + native['name'])
        elif payload.stat().st_size != native['size'] or sha256(payload) != native['sha256']:
            fail('Effective native component bytes changed: ' + native['name'])
    review_path = root / '.github/scripts/secret-scan-reviewed.json'
    if review_path.is_file():
        manifests = {}
        managed = {'tools/git/': 'git', 'tools/node/': 'node', 'runtime/pi/': 'pi'}
        for entry in read_json(review_path)['findings']:
            safe_relative(entry['path'])
            prefix = next((p for p in managed if entry['path'].startswith(p)), None)
            if prefix is None:
                fail('Scanner exceptions must describe an original upstream payload')
            component = managed[prefix]
            if component not in manifests:
                records = read_json(root / ('updater/manifests/' + component + '.json'))['files']
                manifests[component] = {f['path']: f for f in records}
            original = manifests[component].get(entry['path'][len(prefix):])
            if not original or original['size'] != entry['size'] or original['sha256'] != entry['sha256']:
                fail('Scanner review does not match the original installed bytes: ' + entry['path'])
    for notice in m.get('noticeFiles', []):
        safe_relative(notice['path'])
        p = root / notice['path']
        if not p.is_file() or sha256(p) != notice['sha256']:
            fail('Required dependency notice changed or is missing: ' + notice['path'])
    return m


def verify_sources(root, directory):
    m = catalog(root)
    directory = Path(directory)
    expected = {x['filename'] for x in m['sources']}
    for source in m['sources']:
        p = directory / source['filename']
        if not p.is_file() or p.is_symlink() or p.stat().st_size != source['size'] or sha256(p) != source['sha256']:
            fail('Missing/corrupt source archive: ' + source['filename'])
    actual = {p.name for p in directory.iterdir() if p.is_file() and p.name not in {'source-audit.json', 'BUILDING.md'}}
    if actual != expected:
        fail('Unexpected/missing files in source delivery directory')
    return m


def run(args, cwd=None):
    result = subprocess.run([str(x) for x in args], cwd=cwd, text=True, encoding='utf-8',
                            errors='replace', stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            env={**os.environ, 'GIT_TERMINAL_PROMPT': '0'})
    if result.returncode:
        raise RuntimeError('Command failed: ' + str(args[0]) + '\n' + result.stderr[-2500:])
    return result.stdout


def download(url, output, expected, limit):
    output = Path(output)
    if output.is_file() and output.stat().st_size <= limit and sha256(output) == expected:
        return
    output.parent.mkdir(parents=True, exist_ok=True)
    partial = output.with_name(output.name + '.partial')
    last = None
    for _ in range(3):
        try:
            request = urllib.request.Request(url, headers={'User-Agent': 'Pi-Portable-source-preparation'})
            h, size = hashlib.sha256(), 0
            with urllib.request.urlopen(request, timeout=60) as response, partial.open('wb') as f:
                while chunk := response.read(1024 * 1024):
                    size += len(chunk)
                    if size > limit:
                        fail('Download exceeds pinned size limit')
                    h.update(chunk); f.write(chunk)
            if h.hexdigest() != expected:
                fail('Downloaded SHA-256 mismatch: ' + output.name)
            partial.replace(output)
            return
        except Exception as e:
            last = e
            partial.unlink(missing_ok=True)
    raise last


def git_snapshot(source, output, cache):
    repo = Path(cache) / ('git-' + source['commit'])
    repo.mkdir(parents=True, exist_ok=True)
    if not (repo / '.git').exists():
        run(['git', 'init', '-q', repo])
        run(['git', '-C', repo, 'remote', 'add', 'origin', 'https://github.com/' + source['repository'] + '.git'])
    run(['git', '-c', 'credential.helper=', '-C', repo, 'fetch', '--depth=1', '--filter=blob:none', 'origin', source['commit']])
    root = run(['git', '-C', repo, 'ls-tree', source['commit']]).splitlines()
    directories = {line.split('\t', 1)[1] for line in root if line.split()[1] == 'tree'}
    selected = [p for p in source['include'] if p in directories]
    run(['git', '-C', repo, 'sparse-checkout', 'init', '--cone'])
    run(['git', '-C', repo, 'sparse-checkout', 'set', '--'] + selected)
    run(['git', '-c', 'credential.helper=', '-C', repo, 'checkout', '--detach', source['commit']])
    partial = Path(output).with_name(Path(output).name + '.partial')
    command = ['git', '-C', str(repo), 'archive', '--format=tar', '--prefix=WebKit/', source['commit'], '--'] + source['include']
    h = hashlib.sha256()
    with tempfile.TemporaryFile() as err:
        proc = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=err)
        with partial.open('wb') as f, gzip.GzipFile(filename='', mode='wb', fileobj=f, mtime=0, compresslevel=6) as z:
            while chunk := proc.stdout.read(1024 * 1024):
                h.update(chunk); z.write(chunk)
        if proc.wait():
            fail('Could not archive the pinned WebKit source tree')
    if h.hexdigest() != source['uncompressedTarSHA256'] or sha256(partial) != source['sha256']:
        partial.unlink(missing_ok=True)
        fail('Generated source archive differs from the reviewed source tree')
    partial.replace(output)


def open_tar(path):
    if str(path).endswith('.zst'):
        proc = subprocess.Popen(['zstd', '-dc', str(path)], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        return tarfile.open(fileobj=proc.stdout, mode='r|'), proc
    return tarfile.open(path, mode='r|gz'), None


def audit_package_source(path, source):
    archive, proc = open_tar(path)
    srcinfo = recipe = None
    members = set()
    source_root = None
    try:
        for member in archive:
            members.add(member.name.rstrip('/'))
            if member.name.endswith('/.SRCINFO'):
                srcinfo = archive.extractfile(member).read()
                source_root = member.name.rsplit('/', 1)[0]
            elif member.name.endswith('/PKGBUILD'):
                recipe = archive.extractfile(member).read()
    finally:
        archive.close()
        if proc and proc.wait():
            fail('Source archive decompression failed')
    if not srcinfo or not recipe:
        fail('Source package lacks .SRCINFO/PKGBUILD: ' + source['filename'])
    declared_sources = []
    for line in srcinfo.decode('utf-8').splitlines():
        fields = line.strip().split(' = ', 1)
        if len(fields) == 2 and (fields[0] == 'source' or fields[0].startswith('source_')):
            declared_sources.append(fields[1])
    for value in declared_sources:
        if '::' in value:
            local, url = value.split('::', 1)
        else:
            url = value
            local = urllib.parse.urlsplit(value).path.rsplit('/', 1)[-1]
            if url.startswith(('git+', 'hg+')):
                local = local.removesuffix('.git')
        expected = source_root + '/' + local
        if expected not in members and not any(n.startswith(expected + '/') for n in members):
            fail('Source recipe supplied without its upstream source payload: ' + source['filename'])
    proof = source['packageProof']
    if hashlib.sha256(srcinfo).hexdigest() != proof['sourceInfoSHA256'] or hashlib.sha256(recipe).hexdigest() != proof['recipeSHA256']:
        fail('Source recipe changed: ' + source['filename'])
    return {'filename': source['filename'], 'status': 'passed', 'recipeSHA256': proof['recipeSHA256'],
            'sourceInfoSHA256': proof['sourceInfoSHA256'], 'sourceEntriesPresent': len(declared_sources)}


def collect(root, output, cache, max_mib):
    m = catalog(root)
    if sum(s['size'] for s in m['sources']) > max_mib * 1024 * 1024:
        fail('Pinned source bytes exceed this run\'s source budget')
    output, cache = Path(output), Path(cache)
    output.mkdir(parents=True, exist_ok=True); cache.mkdir(parents=True, exist_ok=True)
    def one(source):
        p = output / source['filename']
        cached = cache / source['filename']
        if not p.exists() and cached.is_file() and sha256(cached) == source['sha256']:
            shutil.copyfile(cached, p)
        if not p.exists() or sha256(p) != source['sha256']:
            if source['kind'] == 'http':
                download(source['url'], p, source['sha256'], source['size'])
            else:
                git_snapshot(source, p, cache)
        if p.stat().st_size != source['size'] or sha256(p) != source['sha256']:
            fail('Source size/hash differs: ' + source['filename'])
        if source.get('packageProof'):
            return audit_package_source(p, source)
        return {'filename': source['filename'], 'status': 'passed', 'sha256': source['sha256']}
    records = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
        for item in ex.map(one, m['sources']):
            records.append(item)
            if len(records) % 50 == 0:
                print('Verified source archives:', len(records), flush=True)
    shutil.copyfile(Path(root) / 'licenses/BUILDING-SOURCES.md', output / 'BUILDING.md')
    write_json(output / 'source-audit.json', {'status': 'passed', 'archives': records,
               'gitPackageVersions': len(m['packages']), 'sourceInventorySHA256': sha256(Path(root) / SOURCE_FILE),
               'note': 'Exact bytes and original source recipe metadata verified. No upstream software version discovery or installation.'})
    verify_sources(root, output)
    print('Corresponding source collection passed:', len(records), 'archives,', len(m['packages']), 'Git package versions.')


def allowed_export(path):
    safe_relative(path)
    if path in {'docs/EXECUTION-LOG.md', 'docs/PRIVACY-MAINTENANCE.md', '.github/workflows/privacy-audit.yml'}:
        return False
    if any(x == '.git' for x in PurePosixPath(path).parts) or path.endswith(('.previous', '.partial')) or '.tmp-' in path:
        return False
    if path in ROOT_FILES or path in UPDATER_FILES:
        return True
    if '/' not in path and path.endswith('.bat'):
        return True
    if path.startswith('tests/'):
        return len(PurePosixPath(path).parts) == 2 and path.endswith(('.ps1', '.cjs', '.py'))
    return path.startswith(ROOTS)


def stage(root, output):
    root, output = Path(root).resolve(), Path(output).resolve()
    if output.exists():
        fail('Export destination must be new; no existing user folder is overwritten.')
    files = run(['git', '-c', 'core.quotepath=false', '-C', root, 'ls-files', '-z']).split('\0')
    selected = [p for p in files if p and allowed_export(p)]
    if len(selected) < 100:
        fail('Unexpectedly incomplete repository checkout')
    for path in selected:
        src = root / path
        if not src.is_file() or src.is_symlink() or (hasattr(src, 'is_junction') and src.is_junction()):
            fail('Non-regular/missing export file: ' + path)
        dst = output / path
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
        if sha256(src) != sha256(dst):
            fail('Export copy hash differs: ' + path)
    assert_clean_tree(output)
    return selected


def assert_clean_tree(root):
    root = Path(root)
    for item in root.rglob('*'):
        path = item.relative_to(root).as_posix()
        parts = PurePosixPath(path).parts
        if item.is_symlink() or (hasattr(item, 'is_junction') and item.is_junction()):
            fail('Link/reparse point in export')
        if parts[0] in {'data', 'workspace'} or '.git' in parts or path.startswith(('updater/downloads/', 'updater/backups/', 'updater/staging/', 'updater/logs/', 'updater/sync-tools/', 'updater/sync-backups/')):
            fail('Private history/user/maintenance data entered the export: ' + path)
        if item.is_file() and not allowed_export(path):
            fail('File outside public export allowlist: ' + path)



def review_scan_findings(root, findings, scanner_version):
    root = Path(root).resolve()
    policy = read_json(root / '.github/scripts/secret-scan-reviewed.json')
    if policy.get('schemaVersion') != 1 or policy.get('scannerVersion') != scanner_version:
        fail('Secret-scan review does not match the pinned scanner')
    reviewed = {}
    for entry in policy['findings']:
        safe_relative(entry['path'])
        if not re.fullmatch('[a-f0-9]{64}', entry['sha256']) or entry['line'] < 1 or entry['size'] < 1:
            fail('Invalid exact-byte secret-scan review')
        key = (entry['path'], entry['rule'], entry['line'])
        if key in reviewed:
            fail('Duplicate secret-scan review')
        reviewed[key] = entry
    unmatched, accepted, hashes = [], 0, {}
    for finding in findings:
        try:
            relative = Path(finding['File']).resolve().relative_to(root).as_posix()
        except (ValueError, KeyError):
            unmatched.append(finding); continue
        key = (relative, finding.get('RuleID'), finding.get('StartLine'))
        entry = reviewed.get(key)
        payload = root / relative
        if entry and payload.is_file() and not payload.is_symlink() and payload.stat().st_size == entry['size']:
            if relative not in hashes: hashes[relative] = sha256(payload)
            if hashes[relative] == entry['sha256']:
                accepted += 1
                continue
        unmatched.append(finding)
    return unmatched, accepted


def scanner(root, output, tool_cache):
    root, output, tool_cache = Path(root), Path(output), Path(tool_cache)
    spec = catalog(root)['scanner']['windows' if os.name == 'nt' else 'linux']
    tool_cache.mkdir(parents=True, exist_ok=True)
    archive = tool_cache / spec['filename']
    download(spec['url'], archive, spec['sha256'], spec['size'])
    executable = tool_cache / ('gitleaks.exe' if os.name == 'nt' else 'gitleaks')
    if os.name == 'nt':
        with zipfile.ZipFile(archive) as z:
            match = [n for n in z.namelist() if PurePosixPath(n).name == 'gitleaks.exe']
            if len(match) != 1: fail('Scanner executable missing')
            executable.write_bytes(z.read(match[0]))
    else:
        with tarfile.open(archive) as t:
            match = [n for n in t.getmembers() if n.isfile() and PurePosixPath(n.name).name == 'gitleaks']
            if len(match) != 1: fail('Scanner executable missing')
            executable.write_bytes(t.extractfile(match[0]).read())
        executable.chmod(0o700)
    output.parent.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run([str(executable), 'dir', str(root), '--redact=100', '--no-banner',
                           '--report-format=json', '--report-path', str(output), '--exit-code=2',
                           '--max-target-megabytes=20', '--log-level=error'], capture_output=True, text=True)
    findings = read_json(output) if output.is_file() else None
    if proc.returncode not in (0, 2) or not isinstance(findings, list):
        fail('Secret scanner could not complete; no candidate may be published')
    unmatched, accepted = review_scan_findings(root, findings, catalog(root)['scanner']['version'])
    if unmatched or (proc.returncode == 0 and findings) or (proc.returncode == 2 and not findings):
        # Never echo a secret/match from scanner output or the report.
        locations = [{'rule': x.get('RuleID'), 'file': x.get('File'), 'line': x.get('StartLine')} for x in unmatched]
        fail('Secret scan failed; unreviewed redacted findings require review: ' + json.dumps(locations))
    return {'tool': 'gitleaks', 'version': catalog(root)['scanner']['version'], 'status': 'passed',
            'findings': 0, 'rawFindings': len(findings), 'reviewedFalsePositives': accepted,
            'review': 'exact path/byte hash/size/rule/line only; no path, glob or rule exclusions'}


def package(root, sources, output):
    root, sources, output = Path(root), Path(sources), Path(output)
    assert_clean_tree(root)
    m = verify_sources(root, sources)
    if os.name != 'nt':
        fail('Packaging requires the native Windows public gate.')
    powershell = Path(os.environ['SystemRoot']) / 'System32/WindowsPowerShell/v1.0/powershell.exe'
    run([powershell, '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
         '-File', root / '.github/scripts/Test-PublicRelease.ps1', '-Root', root,
         '-SourcesDirectory', sources], cwd=root)
    output.mkdir(parents=True, exist_ok=True)
    # A standalone package command must perform the same secret gate as CI.
    with tempfile.TemporaryDirectory(prefix='PiPublicScanner-') as tool_cache:
        scan = scanner(root, Path(tool_cache) / 'secret-scan-redacted.json', tool_cache)
    write_json(output / 'secret-scan-summary.json', scan)
    project_version = read_json(root / 'updater/versions.json')['projectVersion']
    dest = output / ('Pi-Portable-' + project_version + '-public-candidate.zip')
    if dest.exists(): fail('Candidate archive already exists; use a new output directory.')
    entries = [('Pi-Portable/' + p.relative_to(root).as_posix(), p) for p in sorted(root.rglob('*')) if p.is_file()]
    entries += [('corresponding-source/' + s['filename'], sources / s['filename']) for s in m['sources']]
    entries += [('corresponding-source/' + n, sources / n) for n in ('BUILDING.md', 'source-audit.json')]
    inventory = []
    with zipfile.ZipFile(dest, 'w', allowZip64=True) as z:
        for name, path in entries:
            digest = sha256(path)
            stored = name.startswith('corresponding-source/') and path.name not in {'BUILDING.md', 'source-audit.json'}
            z.write(path, name, compress_type=zipfile.ZIP_STORED if stored else zipfile.ZIP_DEFLATED, compresslevel=6)
            inventory.append({'path': name, 'bytes': path.stat().st_size, 'sha256': digest})
        record = {'schemaVersion': 1, 'projectVersion': project_version, 'historyIncluded': False,
                  'userDataIncluded': False, 'sourceArchives': len(m['sources']),
                  'gitPackageVersions': len(m['packages']), 'files': inventory}
        z.writestr('DISTRIBUTION.json', json.dumps(record, ensure_ascii=False, indent=2))
    if dest.stat().st_size > 1900 * 1024 * 1024:
        dest.unlink(); fail('Combined binary+source archive exceeds the 1900 MiB publication limit')
    with zipfile.ZipFile(dest) as z:
        if set(z.namelist()) != {x['path'] for x in inventory} | {'DISTRIBUTION.json'}:
            fail('Candidate archive has unexpected/missing entries')
        for entry in inventory:
            h = hashlib.sha256()
            with z.open(entry['path']) as f:
                while chunk := f.read(1024 * 1024): h.update(chunk)
            if h.hexdigest() != entry['sha256']:
                fail('Candidate archive byte verification failed')
    digest = sha256(dest)
    (output / 'SHA256SUMS.txt').write_text(digest + '  ' + dest.name + '\n', encoding='ascii')
    write_json(output / 'public-distribution-summary.json', {k: v for k, v in record.items() if k != 'files'} | {
        'status': 'passed', 'archive': dest.name, 'archiveBytes': dest.stat().st_size,
        'sha256': digest, 'fileCount': len(inventory), 'sourceInventorySHA256': sha256(root / SOURCE_FILE),
        'publication': 'not-published; owner approval required',
        'rebuildOfThirdPartyPrograms': 'not-executed; exact source/build material supplied'})
    print('Verified combined binary/source archive:', dest.name, digest, flush=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('action', choices=['metadata', 'collect', 'verify', 'stage', 'scan', 'package'])
    p.add_argument('--root', required=True, type=Path)
    p.add_argument('--output', type=Path)
    p.add_argument('--sources', type=Path)
    p.add_argument('--cache', type=Path)
    p.add_argument('--max-source-mib', type=int, default=1800)
    args = p.parse_args()
    if args.action == 'metadata':
        m = catalog(args.root)
        print('Source inventory metadata matches installed versions:', len(m['packages']), 'Git package versions. Source BYTES NOT VERIFIED in metadata-only mode.')
    elif args.action == 'collect':
        collect(args.root, args.output, args.cache, args.max_source_mib)
    elif args.action == 'verify':
        m = verify_sources(args.root, args.sources)
        print('Exact corresponding-source bytes verified:', len(m['sources']), 'archives.')
    elif args.action == 'stage':
        print('Exported tracked public files:', len(stage(args.root, args.output)))
    elif args.action == 'scan':
        print(json.dumps(scanner(args.root, args.output, args.cache)))
    elif args.action == 'package':
        package(args.root, args.sources, args.output)

if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print(str(exc) if str(exc).startswith(BLOCK) else BLOCK + str(exc), file=sys.stderr)
        sys.exit(1)

