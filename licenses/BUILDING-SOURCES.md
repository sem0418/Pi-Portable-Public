# Exact corresponding sources / 精确对应源码与重建

The public candidate ZIP contains both `Pi-Portable/` and `corresponding-source/`.
Keep them together when redistributing. Every archive is identified by size and
SHA-256 in `Pi-Portable/licenses/corresponding-source.json`; `DISTRIBUTION.json`
binds all delivered files. A web link is provenance, not a replacement for the
source bytes supplied in this ZIP. No written three-year offer is issued.

## Scope

- Original Pi v1.4.0 source release, including hydrated model data, lockfiles,
  build scripts and original notices; exact npm production tarballs used by the
  published source lock are included as well.
- Node v24.22.1 official complete source archive and its dependency notices.
- Every one of the 171 different package/version pairs in the shipped
  PortableGit package list. Split binary packages share the appropriate source
  package: 147 original source archives containing `.SRCINFO`, `PKGBUILD`,
  patches and upstream source payloads. The original package recipes, not a
  newly invented build, control compilation and installation.
- Bun 1.3.14, its fixed dependency sources, JavaScriptCore/WebKit at
  `5488984d20e0dbfe4be2c3ba8fb18eb81a5e0e8b`, ICU 73.2, and the locked Rust
  dependency closure of lol-html. WebKit includes all `Source`, `Tools`,
  `WebKitLibraries`, build configuration/workflows/scripts and root files;
  unrelated browser test corpora and websites are excluded. The uncompressed
  Git archive hash is pinned independently of compression.

These are unmodified upstream source/build materials. Pi-Portable's original
scripts are under the root MIT license; each supplied work keeps its own
license. This includes GPL, LGPL, AGPL (Berkeley DB), MPL (for example Rust
selectors), and permissive licenses. Nothing in this project restricts
modification or reverse engineering for debugging LGPL library changes.
See `BUNDLED-DEPENDENCY-NOTICES.txt`, package recipes and the original notices
inside each source archive. They remain governed by their original licenses.

## Git for Windows / MSYS2

Use the official Git for Windows SDK for the target architecture (UCRT64).
Compiler/SDK/toolchain installation is a prerequisite; the runnable portable
bundle is not a compiler SDK. Extract the source package of interest into a
separate build directory, keeping its patches, embedded source tarballs/Git
repositories and `PKGBUILD` together. Follow its original `prepare`, `build`
and `package` functions with the SDK's `makepkg` / `makepkg-mingw` tools.
The `.SRCINFO` lists the exact package version, licenses and source checksums.
Do not substitute the latest source version for the recorded package.

For assembling Git itself and the portable layout, the Git source packages
include the matching git/git-extra build and installation recipes. Git for
Windows' SDK/build-extra documentation describes the packaging process:
https://github.com/git-for-windows/build-extra . The collector's mapping
follows the official `get-sources.sh` split-package approach, with current
UCRT package names and original `.SRCINFO` checks used for verification.

## Bun / JavaScriptCore relinking

Extract the Bun source archive. Extract the supplied WebKit archive so its
`WebKit/` folder becomes `bun/vendor/WebKit/` (or set `BUN_WEBKIT_PATH` to that
folder). The source is the revision pinned by the supplied Bun build scripts,
not WebKit's latest branch. Install the upstream-required Windows C++/Clang,
CMake/Ninja, Python and Bun bootstrap toolchain as documented in that source.

The exact Bun package provides these local-source targets:

```text
bun run jsc:build
bun run build:release:local
```

The local profiles compile JavaScriptCore from the supplied source rather
than silently using a prebuilt JavaScriptCore. `build-icu.ps1` in the WebKit
source records ICU 73.2; its source archive is supplied. Other dependency
archives map to `vendor/<dependency-name>` as defined in Bun's
`scripts/build/source.ts`. Original dependency recipes and patches are in
`scripts/build/deps/`. Bun's original LICENSE table still mentions ICU 72;
the actual pinned WebKit Windows recipe uses ICU 73.2, supplied here without
editing the original upstream notice. Rust crate archives and their Cargo.lock checksums
are supplied for the lol-html dependency. The original build system can
obtain prerequisite toolchains/dev tools; no proprietary relinking key or
project signing permission is required to create your own executable.

After modifying and rebuilding Bun/JavaScriptCore, rebuild Pi from its supplied
source archive using the original `scripts/build-binaries.sh --platform
windows-x64 --offline-model-data` path, with the rebuilt Bun on PATH. The exact
Pi workflow pins Bun 1.3.14. Original Pi source, npm tarballs/lockfiles and
all application code remain available for this purpose. The resulting binary
may differ in timestamps, signatures and hashes; byte-identical reproduction
of every third-party executable is not claimed.

## Node

Extract `node-v24.22.1.tar.gz` and follow its original `BUILDING.md` and Windows
`vcbuild.bat`. Its complete source and original dependency licenses are retained.

## Verification and limits

`source-audit.json` records checks performed by the collector. Distribution CI
verifies every delivered archive hash and original Git package recipe hashes,
then runs the existing native Windows tests on the exported binary tree.
The 171 package/version pairs and their 147 source recipes have been checked; rebuilding all third-party
programs from source has **not** been performed. Toolchains, SDK installers,
and ordinary build tools are not claimed to be preinstalled/offline in this ZIP.
Source availability, native execution, fixture tests and unexecuted device/model
cases are recorded separately in the validation documentation.

中文：源码与二进制同包交付，不能只转发其中的运行目录。源码归档保留原许可证、
补丁与构建/安装配方；Git 包逐项匹配实际版本，Bun/WebKit 可用本地源码重建并重新
链接。编译器、SDK 等构建工具需要另行准备。已实际验证源码字节和原生程序运行，
没有声称已从源码重新编译所有第三方组件，也没有作出虚构的三年源码提供承诺。

## Bundled Git LFS metadata discrepancy

PortableGit 2.56.0.3 retains a stale `git-lfs 3.8.0-1` package-list row.
The shipped executable was actually run on native Windows: Git LFS 3.8.1,
Go 1.27.3, commit a662a6db. Its exact SHA-256 is bound by
`effectiveComponents` in the inventory. The supplier's original package list
and 3.8.0 package recipe are preserved as evidence; they are supplemented
with the actual 3.8.1 source commit, Go 1.27.3 complete source and all locked
Go module source ZIPs (including build/test dependencies). Module `h1` hashes
were checked against the supplied original go.sum. See Git LFS's Makefile
and Go build instructions in that source archive. No updater replacement
or manual binary substitution was used.

中文：保留 PortableGit 原始版本文本，另据 Windows 实测程序补充 Git LFS
3.8.1、Go 与依赖源码。该程序来自原更新器安装的官方 PortableGit，未单独替换。
