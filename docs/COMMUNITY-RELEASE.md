# 发布完整发行包 / Complete distribution

普通用户从 Releases 下载完整 `Pi-Portable-版本-win-x64.zip`，核对 SHA-256 后解压运行。
自动生成的源码 ZIP 不能代替完整运行包。安装步骤见 [快速开始](QUICKSTART.md)。

维护者在发布前使用 **Prepare source-bearing distribution** 成功产生的同次构建附件。
该流程只获取已审核的固定版本源码，不选择或安装新版 Pi/Node/Git。上游更新继续由
原有手动更新器负责。具体文件和核对方法见 [发布文件核对](RELEASE-READY.md)。

完整 ZIP 同时提供运行文件、匹配源码、原始许可证、构建材料和逐文件清单；发布时
不要只拿出内部运行目录。版本正文使用同次构建的 `RELEASE-NOTES.md`，并保留
真实测试范围和未执行项目，不把模型协议替身或 Server CI 描述为所有实机认证。

公开仓库从经过检查的干净文件树建立新历史，禁止镜像私人历史、用户目录或旧 PR
引用。发布前同时检查分支、标签、PR 引用、附件和提交作者信息；公开的上游版权人
与许可证信息应保留。已泄露凭证仍需要在供应商端撤销，不能靠一次删除提交解决。

English: publish only a complete, verified, source-bearing release from one successful build.
Use matching notes and checksums, preserve attribution and test limitations, and create public
history from a reviewed clean snapshot rather than mirroring private refs.
