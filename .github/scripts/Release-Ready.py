"""Prepare and verify release handoff files. Never calls a publication API."""
from __future__ import annotations
import argparse, hashlib, importlib.util, json, re, sys, urllib.parse, zipfile
from pathlib import Path

spec = importlib.util.spec_from_file_location('distribution', Path(__file__).with_name('Distribution.py'))
d = importlib.util.module_from_spec(spec)
spec.loader.exec_module(d)

SUMMARY = 'public-distribution-summary.json'
SCAN = 'secret-scan-summary.json'
NOTES = 'RELEASE-NOTES.md'
CHECKSUMS = 'SHA256SUMS.txt'
READY = 'release-ready.json'
MAX_ARCHIVE_BYTES = 1900 * 1024 * 1024


def regular(directory, name):
    d.safe_relative(name)
    if '/' in name:
        d.fail('Release assets must be plain filenames')
    path = Path(directory) / name
    if not path.is_file() or path.is_symlink():
        d.fail('Missing or non-regular release asset: ' + name)
    return path


def validate_reports(directory):
    summary = d.read_json(regular(directory, SUMMARY))
    scan = d.read_json(regular(directory, SCAN))
    if (summary.get('status') != 'passed' or summary.get('historyIncluded') is not False
            or summary.get('userDataIncluded') is not False):
        d.fail('A successful clean native distribution report is required')
    if scan.get('status') != 'passed' or scan.get('findings') != 0:
        d.fail('Release handoff requires a passing secret scan with no unreviewed findings')
    archive = regular(directory, summary['archive'])
    if (not 0 < archive.stat().st_size <= MAX_ARCHIVE_BYTES
            or archive.stat().st_size != summary['archiveBytes']
            or d.sha256(archive) != summary['sha256']):
        d.fail('Release archive checksum/size differs from the native report')
    return summary, archive


def audit_archive(archive, summary):
    with zipfile.ZipFile(archive) as z:
        names = z.namelist()
        if len(names) != len(set(names)) or 'DISTRIBUTION.json' not in names:
            d.fail('Duplicate entries or missing distribution inventory')
        record = json.loads(z.read('DISTRIBUTION.json'))
        for key in ('schemaVersion', 'projectVersion', 'historyIncluded', 'userDataIncluded',
                    'sourceArchives', 'gitPackageVersions'):
            if record.get(key) != summary.get(key):
                d.fail('ZIP inventory differs from the native report: ' + key)
        entries = record['files']
        if (len(entries) != summary['fileCount'] or len({f['path'] for f in entries}) != len(entries)
                or set(names) != {f['path'] for f in entries} | {'DISTRIBUTION.json'}):
            d.fail('Unexpected/missing release ZIP entries')
        source_files = set()
        for entry in entries:
            name = entry['path']
            d.safe_relative(name)
            if name.startswith('Pi-Portable/'):
                if not d.allowed_export(name[len('Pi-Portable/'):]):
                    d.fail('Private or unapproved application file in ZIP')
            elif name.startswith('corresponding-source/') and len(Path(name).parts) == 2:
                source_files.add(name.split('/', 1)[1])
            else:
                d.fail('Unexpected release ZIP root')
            info = z.getinfo(name)
            if info.is_dir() or (info.external_attr >> 16) & 0o170000 == 0o120000:
                d.fail('Non-regular release ZIP entry')
            h = hashlib.sha256()
            with z.open(name) as f:
                while chunk := f.read(1024 * 1024):
                    h.update(chunk)
            if info.file_size != entry['bytes'] or h.hexdigest() != entry['sha256']:
                d.fail('Release ZIP entry checksum/size differs')
        source_inventory = json.loads(z.read('Pi-Portable/' + d.SOURCE_FILE))
        if hashlib.sha256(z.read('Pi-Portable/' + d.SOURCE_FILE)).hexdigest() != summary['sourceInventorySHA256']:
            d.fail('Release ZIP source inventory differs from the native report')
        if source_files != {s['filename'] for s in source_inventory['sources']} | {'BUILDING.md', 'source-audit.json'}:
            d.fail('Release ZIP does not deliver exactly the declared corresponding sources')
        by_path = {f['path']: f for f in entries}
        for source in source_inventory['sources']:
            entry = by_path['corresponding-source/' + source['filename']]
            if source['size'] != entry['bytes'] or source['sha256'] != entry['sha256']:
                d.fail('Release ZIP source differs from the pinned source inventory')
        if len(source_inventory['sources']) != summary['sourceArchives']:
            d.fail('Release source archive count differs')
        versions = json.loads(z.read('Pi-Portable/updater/versions.json'))
        if versions.get('projectVersion') != summary['projectVersion'] or versions.get('architecture') != 'win-x64':
            d.fail('Release ZIP installed version differs from the native report')
        return versions


def release_notes(versions, summary, commit, run_url):
    v = versions['projectVersion']
    c = versions['components']
    return f'''# Pi-Portable {v} — Windows x64

Windows 便携 Pi 工具箱，解压即可使用；目标电脑无需另装 Node.js 或 Git。
Portable Pi for Windows x64; Node.js and Git are included.

| 组件 / Component | 版本 / Version |
|---|---|
| Pi | {c['pi']['version']} |
| Node.js | {c['node']['version']} |
| PortableGit | {c['git']['version']} |

包含原有一键更新、修复、环境检查、会话维护和六个 Windows Skills。现有更新器仍负责
全部上游检查、下载校验和事务回滚；云端更新按需手动运行。没有定时上游追踪。

下载 `{summary['archive']}`，完整解压后进入 `Pi-Portable/`，双击 `启动 Pi.bat`。
在 Pi 中用 `/login` 配置自己的账户，再用 `/model` 选择模型。不要在 ZIP 预览中运行。
ZIP 安装可使用原有一键更新；Git 同步需要真实克隆。

完整包同时包含运行文件、{summary['sourceArchives']} 份精确源码/构建材料、原始许可证和
`DISTRIBUTION.json` 逐文件清单。再分发时保留 `corresponding-source/` 和许可证。
Keep the matching source directory and original notices with redistributed copies.

已执行原生 Windows Server 2022 / PowerShell 5.1、程序启动、完整清单、中文/空格路径、
现有回归、源码字节、敏感信息扫描和 ZIP 逐文件校验。物理 U 盘、exFAT/FAT、换盘符、
异常拔盘、真实模型/OAuth 及全部第三方源码重编译未执行；测试细节见包内
`Pi-Portable/docs/VALIDATION.md`。目标为 Windows 10/11 x64，CI 不替代全部桌面实机验收。

本包不包含用户数据或项目 Git 历史。独立社区项目，不代表上游官方发行。
The bundle excludes user data and private project history; this is an independent community build.

SHA-256: `{summary['sha256']}`

完整性记录见同版本 `SHA256SUMS.txt` 与包内 `DISTRIBUTION.json`。
Integrity records: the matching SHA256SUMS.txt and the bundled DISTRIBUTION.json.
'''


def prepare(root, directory, commit, run_url):
    root, directory = Path(root), Path(directory)
    if not re.fullmatch('[a-f0-9]{40}', commit):
        d.fail('An exact build commit is required')
    url = urllib.parse.urlsplit(run_url)
    if (url.scheme != 'https' or url.netloc != 'github.com' or url.query or url.fragment
            or not re.fullmatch(r'/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/actions/runs/[0-9]+', url.path)):
        d.fail('A credential-free canonical build run URL is required')
    if (directory / READY).exists():
        d.fail('Release handoff already exists; use a fresh build output')
    summary, archive = validate_reports(directory)
    versions = d.read_json(root / 'updater/versions.json')
    version = versions['projectVersion']
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version) or versions.get('architecture') != 'win-x64':
        d.fail('Expected a versioned win-x64 release')
    if summary['projectVersion'] != version or summary['sourceInventorySHA256'] != d.sha256(root / d.SOURCE_FILE):
        d.fail('Release reports belong to different project/source bytes')
    canonical = directory / f'Pi-Portable-{version}-win-x64.zip'
    if archive != canonical:
        if canonical.exists():
            d.fail('Release filename already exists')
        archive.rename(canonical)
    summary['archive'] = canonical.name
    d.write_json(directory / SUMMARY, summary)
    (directory / NOTES).write_bytes(release_notes(versions, summary, commit, run_url).encode('utf-8'))
    assets = [canonical.name, NOTES, SUMMARY, SCAN]
    checksum_text = ''.join(d.sha256(directory / name) + '  ' + name + '\n' for name in sorted(assets))
    (directory / CHECKSUMS).write_bytes(checksum_text.encode('ascii'))
    d.write_json(directory / READY, {
        'schemaVersion': 1, 'status': 'prepared-not-published', 'projectVersion': version,
        'proposedTag': 'v' + version, 'title': f'Pi-Portable {version} (Windows x64)',
        'buildCommit': commit, 'buildRun': run_url, 'archive': canonical.name,
        'components': {name: c['version'] for name, c in versions['components'].items()},
        'assets': [{'name': name, 'bytes': (directory / name).stat().st_size,
                    'sha256': d.sha256(directory / name)} for name in sorted(assets + [CHECKSUMS])],
        'validationLimits': ['physical USB/filesystem/drive-letter/eject tests not executed',
                             'live model/OAuth not executed', 'full third-party rebuild not executed'],
        'publicationPerformed': False})
    try:
        verify(directory)
    except Exception:
        (directory / READY).unlink(missing_ok=True)
        raise


def verify(directory):
    directory = Path(directory)
    ready = d.read_json(regular(directory, READY))
    if (ready.get('schemaVersion') != 1 or ready.get('status') != 'prepared-not-published'
            or ready.get('publicationPerformed') is not False):
        d.fail('Invalid prepared release handoff state')
    assets = ready['assets']
    expected = {ready['archive'], NOTES, SUMMARY, SCAN, CHECKSUMS}
    if len(assets) != len(expected) or {a['name'] for a in assets} != expected:
        d.fail('Missing or duplicate release handoff assets')
    if {p.name for p in directory.iterdir()} != expected | {READY}:
        d.fail('Unreviewed file in release handoff directory')
    for asset in assets:
        path = regular(directory, asset['name'])
        if path.stat().st_size != asset['bytes'] or d.sha256(path) != asset['sha256']:
            d.fail('Release handoff asset checksum/size differs: ' + asset['name'])
    summary, archive = validate_reports(directory)
    if (ready['projectVersion'] != summary['projectVersion'] or ready['archive'] != archive.name
            or ready['proposedTag'] != 'v' + summary['projectVersion']
            or archive.name != f"Pi-Portable-{summary['projectVersion']}-win-x64.zip"):
        d.fail('Release handoff versions differ')
    expected_checksums = ''.join(d.sha256(directory / name) + '  ' + name + '\n'
                                 for name in sorted(expected - {CHECKSUMS}))
    if (directory / CHECKSUMS).read_text(encoding='ascii') != expected_checksums:
        d.fail('Release checksum list differs')
    versions = audit_archive(archive, summary)
    if ready['components'] != {name: c['version'] for name, c in versions['components'].items()}:
        d.fail('Release handoff component versions differ from the ZIP')
    print('Release handoff verified; no tag or Release created:', archive.name, flush=True)
    return ready


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['prepare', 'verify'])
    parser.add_argument('--directory', required=True, type=Path)
    parser.add_argument('--root', type=Path)
    parser.add_argument('--commit')
    parser.add_argument('--run-url')
    args = parser.parse_args()
    if args.action == 'prepare':
        if args.root is None or args.commit is None or args.run_url is None:
            parser.error('prepare requires --root, --commit and --run-url')
        prepare(args.root, args.directory, args.commit, args.run_url)
    else:
        verify(args.directory)


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
