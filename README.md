# Pi-Portable

[English](README.en.md) · [快速开始](docs/QUICKSTART.md) · [测试范围](docs/VALIDATION.md) · [源码与许可证](SOURCE-ACCESS.md)

面向 Windows x64 的便携 Pi 工具箱，包含 Pi、Node.js、PortableGit/Git Bash 和六个 Windows Skills。下载完整发行包后即可运行，目标电脑无需另装 Node.js、Git 或 Python。

当前工程版本 **1.1.1**，内含 Pi **1.4.0**、Node.js **24.22.1**、PortableGit **2.56.0.3**。这是独立社区发行，不代表上游官方项目。

## 下载与启动

1. 在本项目的 **Releases** 页面下载 `Pi-Portable-1.1.1-win-x64.zip` 和 `SHA256SUMS.txt`。普通的 **Source code (zip/tar.gz)** 不是可运行发行包。
2. 完整解压到可写目录，例如 `D:\Apps\Pi-Portable-1.1.1\`。保留同包的 `Pi-Portable/`、`corresponding-source/` 和 `DISTRIBUTION.json`；不要在压缩包预览中运行。
3. 打开内部 `Pi-Portable` 文件夹，双击 **启动 Pi.bat**。
4. 在 Pi 内输入 `/login`，配置自己的模型账户；再输入 `/model` 选择模型。模型选择器中 Ctrl+S 可保存默认模型。

模型服务的网络条件、账户、配额和费用由所用供应商决定。本发行包不附带可供共享的 API Key、OAuth 或用户会话。

需要 Windows 10/11 x64、自带的 64 位 Windows PowerShell 5.1 和可写目录。完整包同时包含对应源码，因此体积约 1.95 GB；解压前为完整内容与运行数据预留足够磁盘空间。

## 常用入口

| 入口 | 用途 |
|---|---|
| 启动 Pi.bat | 使用本目录内的运行环境启动 Pi |
| 检查环境.bat | 检查程序、配置路径和默认 Skills |
| 一键更新.bat | 使用原有更新器检查官方版本、校验下载、备份、替换与回滚 |
| 一键修复.bat | 检查并修复缺失组件，恢复缺失的默认资源 |
| 一键删除对话历史.bat | 独立管理本机的对话历史 |
| 一键同步.bat | 仅供有 Git origin 的真实仓库克隆同步；普通 ZIP 安装不使用此入口 |

现有更新器继续负责全部 Pi、Node.js、PortableGit 上游更新。没有定时上游检查或自动追踪 Release。自定义供应商配置见 `runtime/pi/docs/models.md`；示例位于 `updater/resources/defaults/models.example.json`。

## 个人数据与迁移

自己的模型配置、Key/OAuth、会话、自定义 Skills 和报告保存在 `data/`；工作文件保存在 `workspace/`。这些内容由首次运行按需创建，不属于发行包，也不应提交或转发。

移动前关闭 Pi、Node、Git 和 Bash，等待写入结束，再复制整个目录。启动器只改变当前进程环境，不写永久 PATH。外部绝对路径、宿主系统凭证和系统钥匙串不会自动变得便携，OAuth 可能需要重新登录。

更新或修复发现被修改的受管组件时会停止。先备份并理解改动，再决定是否明确使用 `-AllowComponentReplacement`；不要通过强制重置覆盖用户数据。故障时保留恢复日志和备份，详见 [快速开始与故障处理](docs/QUICKSTART.md)。

## 六个 Windows Skills

`windows-diagnostics`、`malware-triage`、`file-organizer`、`network-troubleshooting`、`disk-health`、`windows-repair`。在 Pi 中可输入 `/skill:名称` 明确调用。

默认诊断以只读检查为主，文件整理支持预览、日志与撤销。不会自动关闭 Defender、格式化磁盘或提权。缺失或拒绝访问的证据会如实标记。

## 完整性、测试与源码

用 PowerShell 的 `Get-FileHash -Algorithm SHA256` 核对下载 ZIP 与 `SHA256SUMS.txt`。自动验证覆盖原生 Windows Server 2022 / PowerShell 5.1、真实程序、完整清单、中文/空格路径、源码字节及 ZIP 内容；[测试范围](docs/VALIDATION.md)说明模拟测试和未执行项目。不能把 CI 结果理解为已完成所有桌面电脑、物理 U 盘或真实模型账户测试。

完整 ZIP 随二进制提供匹配的第三方源码、许可证和构建材料。再分发时保留完整内容，不能只转发内部运行目录。根目录 MIT 仅覆盖本项目原创代码；捆绑软件各自保留适用许可证，见 [源码获取](SOURCE-ACCESS.md)和 [第三方声明](licenses/THIRD-PARTY-NOTICES.md)。


下载完整发行包：[Releases](https://github.com/sem0418/Pi-Portable-Public/releases/latest)。
