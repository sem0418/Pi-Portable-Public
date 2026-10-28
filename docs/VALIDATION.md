# 测试范围 / Validation scope

发行准备流程在原生 Windows Server 2022、64 位 Windows PowerShell 5.1 中运行，
并在独立的中文和空格路径副本上执行回归。每次交付以同次构建生成的版本、校验值和
摘要为依据；旧报告不代表后来版本已经通过。

| 检查 | 覆盖 |
|---|---|
| 原生运行 | 实际 Pi、Node/npm/npx、Git/Bash、Git LFS 和启动入口 |
| 完整性 | 三个组件全部已记录文件、Git LFS 还原、项目源码清单与 SHA-256 |
| 常用入口 | Check、健康 Repair、Launch 与默认资源初始化 |
| 路径与迁移 | 中文/空格路径，真实本地 Git/LFS 同步与合成用户数据迁移 |
| 更新与回滚 | 原有事务和真实文件系统；网络、解包、程序探针故障通过替身注入 |
| Pi 工具调用 | 真实 Pi 程序及本地模型协议替身，不使用真实模型账户 |
| 源码交付 | 固定版本源码字节、包配方、声明的源码载荷和许可证材料 |
| 分发目录 | 明确文件白名单；排除用户数据、私有历史、维护目录和旧测试报告 |
| 敏感信息扫描 | 固定扫描器；仅认可精确字节、路径、规则和行号匹配的上游误报 |
| ZIP 与发布附件 | 每个条目的大小和哈希、对应源码覆盖、版本说明与附件清单 |

当前套件包含 Core 19、文件整理 8、Package 12、Pi 协议 8 与迁移后 8、
ReleasePipeline 10 个检查。Windows 汇总的 7 通过/4 跳过引用子套件，不能相加
当成互不重复的测试总数。分发负向测试和发布附件负向测试另在 Linux/Windows 执行。
具体通过状态以本次成功构建的原始摘要为准。

未执行：物理 U 盘、不同文件系统和盘符、异常拔盘/断电、真实模型账户与 OAuth、
完整系统诊断采集、全部第三方程序重编译。目标是 Windows 10/11 x64；Server CI
不能替代所有桌面系统和设备验收，也不证明真实模型总能自动选对 Skill。

敏感信息扫描不能证明任意文件绝无隐私。个人资料可能没有密钥特征，因此还采用
用户目录排除、干净导出和新历史检查；捆绑软件的公开版权人信息属于许可证材料。

English: native programs and full byte inventories are checked separately from synthetic
network/model fixtures. Physical devices, drive-letter changes, live credentials/OAuth,
extended diagnostics and full third-party rebuilds are not certified by these CI results.
