# Source access and redistribution / 源码获取与再分发

Use the complete release ZIP. It contains:

- `Pi-Portable/`: runnable Windows application, original project scripts, notices,
  exact versions and per-file integrity inventories.
- `corresponding-source/`: matching source archives, patches and build recipes for
  bundled components. `BUILDING.md` explains source and relinking use.
- `DISTRIBUTION.json`: delivered file sizes and SHA-256 values.

Keep corresponding source and licenses with redistributed copies of this bundle. Do not
redistribute only the inner binary directory as the complete distribution. Source bytes
are supplied directly; no written three-year offer substitutes for them. Bundled works
retain their GPL/LGPL/AGPL/MPL/MIT/BSD/Apache and other notices. This project adds no
restriction on modifications or reverse engineering needed to debug LGPL changes.
There is no warranty or claim of upstream endorsement.

The release ZIP does not contain project Git history, personal configuration, API/OAuth
credentials, sessions, workspaces, maintenance backups or old diagnostic reports.
A ZIP installation has no Git origin and uses the existing one-click upstream updater;
Git synchronization requires a real clone with its own origin.

A public repository must be created from a reviewed clean snapshot with fresh history.
Never mirror unrelated private branches, pull-request refs, caches or user directories.
A new public history does not revoke credentials that existed in another copy; their
holders must revoke them at the provider if applicable.

中文：发行包把程序、对应源码、构建材料和原始许可证一起交付。再分发时保留完整
内容；普通源码 ZIP 和内部运行目录不能替代完整分发包。个人配置、会话和工作区
由用户首次运行创建，不属于发行内容。公开仓库使用经过审核的干净文件树和新历史。
