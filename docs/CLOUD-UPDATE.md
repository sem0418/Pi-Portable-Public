# 云端更新 / Cloud update

## 职责边界

`一键更新.bat` → `updater/scripts/Entry.ps1 -Action Update` → `Invoke-PortableUpdate` → 现有目录/下载/兼容校验/事务安装函数。这个链条不变。

`.github/scripts/Invoke-Validation.ps1` 只调用入口和测试。`Publish-Update.ps1` 只验证、暂存、上传、提交和创建 PR；`Update-Licenses.ps1` 读取已安装版本并更新许可证材料，不选择软件版本。

## 启用与运行

1. 审核并合并实现 PR；手动触发入口需要先存在于默认分支。这次实现 PR 自身有只读 Windows 验证。
2. 在 GitHub Actions 设置中允许工作流运行，并允许 Actions 创建 Pull Request。工作流申请 `contents: write` 与 `pull-requests: write`；只读 PR 验证仅申请 `contents: read`。本次操作没有变更仓库设置。
3. Actions → Manual portable update → Run workflow → main。设置本次允许的变更 LFS MiB 上限（默认 512）。
4. 查运行日志和保留七天的 JSON 摘要。成功且存在差异时，审核 `portable-update/<run>-<attempt>` 草稿 PR，再由仓库主人合并。

更新工作流只接受默认分支、只有 `workflow_dispatch`，没有 cron、push 更新触发器、repository_dispatch 或 Release 追踪。PR 工作流自动测试代码变更，不调用上游更新。

Actions 内置 `GITHUB_TOKEN` 创建的 PR 通常不会再触发新的 PR 工作流；因此手动更新作业在提交前已经执行相同的完整验证。不要把缺少二次检查误读为“提交前没测”。人工创建/更新的实现 PR 则有独立的只读验证。

## 发行文件与失败处理

白名单：`.gitattributes`、`runtime/pi`、`tools/node`、`tools/git`、`updater/manifests`、`updater/versions.json`、`licenses`。使用 `git add --force --all -- <白名单>`，避免上游自身的嵌套 `.gitignore` 把新增 npm/Git 文件漏掉，同时捕获删除。再检查暂存列表是否越界。

临时、备份、日志和用户数据在忽略规则及白名单两层之外。CI 不打包整个 `data`，只上传指定测试摘要与本次执行日志。旧运行报告不作为本次通过证据。

校验要求：无未完成事务；三个完整性清单与版本一致；清单内每个文件哈希/大小正确；没有额外文件或重解析点；实际程序版本正确；现有原生/回滚/迁移测试通过；LFS 指针已还原。

更新器返回非零、测试失败或许可证抓取异常时，不执行暂存/提交。上游查询部分失败即使独立组件已经完成更新，整个 CI 也按失败处理，不推送这个 runner 的结果。runner 结束即销毁，不影响 main。

LFS 上传成功后才推送分支。若 GitHub 禁止 Token 创建 PR，已验证分支可能存在，作业明确失败并给出分支；由你开启设置或手动创建 PR。没有强推、自动合并或公开 Release。

## 时间、LFS 与账单

- 更新作业最多 50 分钟，验证作业最多 40 分钟。并发组保证一次只有一个更新，不中途取消事务；同一 PR 的旧验证可取消。
- checkout 仅取浅层历史和当前所需 LFS，不抓全部 LFS 历史，不缓存发行二进制，不上传完整便携包为 artifact。
- 已有三个 LFS 路径保留；新出现的单个 ≥10 MiB 发行文件自动记录为 LFS，仅重整当前索引，不迁移/重写历史。非 LFS 的 ≥100 MiB blob 被拒绝。
- LFS 预算对暂存中不同新 OID 的完整大小保守计数，可能高估服务器已持有对象的上传量。未变化的文件不重复进入差异。
- 普通 Git 可传输压缩/增量；LFS 改动是下载新的整个对象，并非二进制逐字节差分。Windows runner 的 LFS 下载也计入仓库所有者带宽。旧版本 LFS 对象继续占用存储。
- 本次没有读取或修改账户计费设置。账户预算/用量以 GitHub Billing 为准，MiB 门限不覆盖总历史存储、runner 分钟或下载账单。

官方依据：[手动工作流](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)、[Token 触发限制](https://docs.github.com/en/actions/how-tos/writing-workflows/choosing-when-your-workflow-runs/triggering-a-workflow)、[LFS 计费](https://docs.github.com/en/billing/concepts/product-billing/git-lfs)。

## English operational notes

Merge the implementation PR before using the manual workflow. Run **Manual portable update** on the default branch. It invokes the original updater, validates native Windows behavior, refreshes installed-version notices and opens a unique draft update PR. Review and merge manually.

The update workflow has no schedule or automatic upstream event. PR validation is read-only and does not select upstream releases. Enable Actions PR creation in repository settings if needed; this change does not modify settings for you. The built-in token may not retrigger PR CI, so all validation occurs before the update commit is created.

Only explicit distribution paths can enter the commit, including new and removed files hidden by nested upstream ignore rules. LFS upload happens before the branch push. Any updater/validation failure prevents publishing. PR API failure can leave a verified branch and is reported as failure.

Timeouts, shallow LFS checkout, limited concurrency and seven-day summary retention constrain usage. The per-run LFS cap is a conservative changed-object guard, not an account spending limit. Changed LFS binaries transfer as complete objects and historical objects continue consuming storage.
