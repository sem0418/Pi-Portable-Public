# 发布文件已准备 / Release handoff

本流程只准备文件，不创建 Git tag、草稿 Release、正式 Release、公共仓库或外部上传。
`main` 更新后自动进行一次只读构建；也可以在 Actions 手动运行
**Prepare source-bearing distribution**。它只取已审核的固定源码，不检查或安装新版组件。
上游更新继续使用原有手动更新器。

## 取得本次完整文件

选择 `main` 上成功的构建，下载同次运行的 **Pi-Portable-release-ready-运行编号**。
先解压 GitHub artifact 的外层传输 ZIP，得到：

| 文件 | 用途 |
|---|---|
| `Pi-Portable-1.1.1-win-x64.zip` | 可直接上传的完整运行文件与对应源码包 |
| `SHA256SUMS.txt` | ZIP、版本说明和两份摘要的 SHA-256 |
| `RELEASE-NOTES.md` | 可直接用于发布正文的中英说明、版本与测试边界 |
| `release-ready.json` | 建议版本标签、标题、构建提交及每个附件的大小和校验值 |
| `public-distribution-summary.json` | 本次完整分发与 ZIP 校验结果 |
| `secret-scan-summary.json` | 脱敏扫描结果及严格核准的上游误报数量 |

这六个文件来自同次运行，不要混用旧产物。`release-ready-metadata-运行编号` 仅供
轻量审阅，不含大 ZIP，不能代替完整产物。产物保留七天，源码中间产物保留一天；
过期后可手动重新准备。版本和具体文件名以本次 JSON 为准。

原始扫描报告不放入发布附件。运行文件不含用户数据或原项目 Git 历史，完整 ZIP
内有 `Pi-Portable/`、`corresponding-source/` 和 `DISTRIBUTION.json`。

## 文件核对

在 PowerShell 中执行 `Get-FileHash .\Pi-Portable-1.1.1-win-x64.zip -Algorithm SHA256`，
对照 `SHA256SUMS.txt`。校验对象是内层运行与源码 ZIP，不是 GitHub 外层传输 ZIP。

维护者也可用仓库中的脚本完整读回所有附件、源码与 ZIP 条目：

```powershell
python .github/scripts/Release-Ready.py verify --directory 'D:\download\extracted-artifact'
```

这个核对过程无需网络，不执行程序、不写用户目录，也不发布任何内容。Python 仅用于
维护验证，运行便携 Pi 不要求目标电脑安装 Python。

## 主人之后执行的发布步骤

准备任务到此结束。之后由主人选择分发渠道，使用 `release-ready.json` 中建议的
`v1.1.1` 标签和标题、`RELEASE-NOTES.md` 正文，上传完整 ZIP、校验文件及其他摘要。
这里的标签只是建议文本，准备任务不会在 Git 中创建它。

若公开 GitHub 仓库，从 ZIP 中干净的 `Pi-Portable/` 文件树创建新历史，并在新仓库
提供完整分发包。原私有库历史含旧用户文件，继续保持私有；不要直接改可见性，
也不要镜像或推送旧分支/标签。不能只发布内部运行目录而漏掉源码和许可证。

自动验证采用原生 Windows Server 2022 / PowerShell 5.1、真实程序、完整文件清单、
源码字节和 ZIP 校验；部分事务/模型测试使用替身。物理 U 盘、不同文件系统、换盘符、
异常拔盘、真实模型/OAuth 及全部第三方重编译未执行，发布说明如实保留这些边界。

English: use the successful `main` run's complete release-ready artifact. Extract the transport
ZIP, verify the inner application+source ZIP and use the supplied notes/checksums. The small
metadata artifact is for review only. Preparation never creates a tag or GitHub Release. Keep
the existing private history private; a public repository must start with the clean exported
tree and provide the complete matching source-bearing bundle.
