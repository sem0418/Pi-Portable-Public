# 快速开始与故障处理 / Quick start

## 第一次运行

下载 Releases 中完整的 `Pi-Portable-1.1.1-win-x64.zip`，完整解压后进入内部
`Pi-Portable` 文件夹。先运行 `检查环境.bat`，再双击 `启动 Pi.bat`。
无需在电脑上预装 Node.js、Git 或 Python，也无需先执行一次上游更新。

用 `/login` 配置自己的模型账户，再用 `/model` 选模型。供应商的账户、网络、费用
和配额独立于本工具。自定义供应商的参数以 `runtime/pi/docs/models.md` 为准；
不要把个人配置写回示例或启动脚本。

首次运行可能在本目录中初始化 PortableGit、创建用户目录和补齐默认 Skills，
不会覆盖已有用户文件。不要在只读目录、压缩包预览或写入受限的 U 盘中运行。

## 校验下载

在下载目录打开 PowerShell：

```powershell
Get-FileHash .\Pi-Portable-1.1.1-win-x64.zip -Algorithm SHA256
```

与同一发行版的 `SHA256SUMS.txt` 对照。不要混用不同版本的 ZIP 和校验文件。
解压后保留整个发行目录与同包对应源码；通常从内部 `Pi-Portable/` 启动。

## 常见情况

| 情况 | 处理 |
|---|---|
| 找不到 node/git/pi，或看到 Git LFS 指针文本 | 使用完整发行 ZIP；GitHub 自动源码 ZIP 不能替代它 |
| 无法写配置或创建工作区 | 重新解压到自己有写入权限的目录 |
| 模型登录、连接或额度错误 | 核对自己的供应商账户、模型权限、网络与额度 |
| 一键同步提示没有 Git 仓库 | ZIP 安装使用一键更新，不使用 Git 同步 |
| 更新或修复提示组件被修改 | 先保存改动；只有明确同意替换时才使用替换授权参数 |
| 更新中断 | 保留整个目录、日志、事务记录和备份，先运行检查，再按结果修复 |
| 换盘符后旧会话工作目录不匹配 | 用 `/resume` 选择会话，并核对新的工作区 |
| 组织策略禁止执行 | 由设备管理员判断允许的运行方式，本工具不绕过策略 |

## 保护数据

自己的 Key/OAuth、会话、报告、Skills 和工作文件保存在 `data/` 与 `workspace/`。
分享便携副本前不要把这些个人目录一起发出去。反馈只附最小、脱敏的错误说明。
移动整个目录前关闭相关进程并等待写入结束。

Windows CI 已检查中文与空格路径；物理 USB、exFAT/FAT、异常拔盘、不同盘符和
真实模型账户未纳入本次自动验收。具体边界见 [测试范围](VALIDATION.md)。

English: download the complete release ZIP, verify its SHA-256, extract everything, enter
`Pi-Portable/`, run the environment check and launcher, then use your own model account.
No preinstalled Node.js/Git/Python or initial upstream update is required. Automatic source
archives and the Git sync launcher are not substitutes for this ZIP installation workflow.
