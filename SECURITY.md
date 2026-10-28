# Security / 安全反馈

Do not post API keys, OAuth tokens, auth/models/settings files, session transcripts,
workspaces, personal documents, full diagnostic reports or unredacted logs in issues,
pull requests or public attachments. Report only the minimum reproducible, redacted
information. Use private vulnerability reporting if the hosting repository enables it;
otherwise contact its maintainer privately before disclosing sensitive details.

Release preparation uses a tracked-file allowlist, exact integrity inventories and a
pinned secret scanner. Personal data and project Git history are excluded from the ZIP.
Scanner findings are a check, not a guarantee that arbitrary later-added files contain
no personal information. Keep your own `data/` and `workspace/` private.

Seven existing upstream-data scanner matches are reviewed by exact SHA-256, size,
relative path, rule and line: format signatures in libmagic and keyboard names in Vim.
No files, paths or rules are globally ignored. Changed bytes or unreviewed findings
block packaging. Reports contain counts and redacted locations, never secret values.

If a credential is exposed, revoke/rotate it at its provider. Deleting a file or rewriting
Git history does not revoke it or erase all cached copies. Public repository imports must
start from clean reviewed history; do not import unrelated private history or PR refs.

中文：反馈与分享前去掉自己的 Key、OAuth、会话、个人文件和完整诊断。发行包排除
个人目录并检查完整性；扫描不是绝无隐私的证明。泄露的凭证需要在供应商处撤销，
不能只删除本地文件或提交一次删除记录。
