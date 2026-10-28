# Contributing / 参与维护

Preserve Entry.ps1 / Portable.Update.ps1 / Portable.Common.ps1 as the only
upstream component update implementation. Actions may invoke, validate and
propose reviewed changes; do not introduce scheduled upstream tracking.

Use a separate branch and PR. Keep user data out of Git. Reuse tests and record
native execution, deterministic fixtures and skipped cases separately. A source
or binary change requires refreshed integrity records. Changing a shipped
component/package list invalidates the exact corresponding-source inventory;
refresh the source kit before preparing a public distribution.

Public candidates must pass native Windows validation, source-byte/recipe checks,
the history/user-data export gate, redacted secret scanning and final archive
verification. Run the manual public-distribution workflow after merge, or use its
same-repository PR validation for distribution-script/inventory changes. It does
not publish. Public repository/Release actions require explicit owner approval.

The original project code is MIT; keep all bundled works' own licenses and
copyrights. Do not add a contributor license agreement or claim third-party
copyright ownership. Submit focused changes with relevant test evidence.

中文：保留现有更新器职责；改动走 PR，用户数据不入库。组件变化后必须更新完整性
清单及对应源码材料。公开候选包需要真实 Windows、源码、脱敏扫描与归档验证通过；
准备工作流不会代替仓库主人批准公开。
