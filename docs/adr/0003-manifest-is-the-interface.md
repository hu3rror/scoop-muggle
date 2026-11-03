# manifest 是 persist_external 机制的 interface：hook 字符串与注入 schema 由 CI 契约测试压住

persist_external 机制**对外没有函数级 API**。它的全部用户触点只有两类文本：每个 manifest 手写的两处 hook 字符串（`post_install` 调 `Invoke-PersistExternalInstall`、`pre_uninstall` 调 `Invoke-PersistExternalUninstall`；自 ADR-0005 起裸调用，函数从 hook 作用域读 `$dir`/`$persist_dir`/`$manifest`），以及 `persist_external` 字段的条目形状（由注入 schema 描述，见 ADR-0001）。这两处文本就是机制的 interface：任何改动（脚本函数改名、参数增删、条目形状调整）都必须让文本形态与实现同时变化，否则用户的安装/卸载链路在运行时才炸。

此前这两处零测试：函数或参数改错、kind 写错、manifest 漏写 hook，全要到 `scoop install` / `scoop uninstall` 那一刻才暴露。失败位置是全链路最贵的一刻（用户机器、真实数据路径、卸载时还要删链接）。

**Status**: accepted（hook 调用形态由 ADR-0005 修订）

**Considered Options**:

- A. 文档约定 + 运行时兜底：写清 hook 格式，脚本入口对未知参数静默容忍。缺点：人不会逐字读文档；容忍未知参数等于把改错成本推迟到用户机器——这正是 2026-11 之前 `-PersistDir` 参数漂移的教训（脚本加了新参数，21 条 hook 没跟上，rename/reinstall 才暴露）
- B. 脚本内自检：函数入口校验参数名。能抓参数错，但发生在用户机器上；且函数名写错（dot-source 后未定义）直接 CommandNotFound，脚本内无法兜底
- C. 选 A + CI 契约测试（选定）：把「字符串 ↔ 实现」的对账前移到提交阶段

选定 C 的代价：契约测试只校字符串形状，不校验条目在目标机上能否建成链接（那是运行时环境变量的事，与契约无关）。

**契约内容**（`scripts/persist-external-hooks.Tests.ps1`，Pester 自动发现 `scripts/*.Tests.ps1`，`bin\test.ps1` 从仓库根递归运行而无需额外入口，CI 直接吃）：

- 声明 `persist_external` 的 manifest 必须同时有 `post_install` 与 `pre_uninstall`，且各自调用对应的 `Invoke-PersistExternal{Install,Uninstall}` 函数；
- 函数必须存在（由 hook dot-source 的脚本定义）；调用文本不得带 `-参数`，必须裸调用（ADR-0005）；
- hook 文本必须先 dot-source 脚本（保证函数存在）；
- 对全部声明 `persist_external` 的 manifest 逐条解析校验。

规则：改 hook 文本 = 改 interface；契约测试红时，要么同步 manifest，要么同步脚本并改写契约——不允许以删改测试放行（与仓库测试纪律一致）。
