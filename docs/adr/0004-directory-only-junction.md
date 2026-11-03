# persist_external 只支持目录链接（Junction）：删掉 file/SymbolicLink 与全部不可达分支

`persist_external` 的 interface 曾经声称支持 6 件事，调用点实际只用到 2 件。逐条实测（2026-11 盘点）：

- **file 类型 → SymbolicLink**：没有任何条目使用。三元组条目全部是 `directory`，纯字符串条目全部指向目录（含未安装、按 ADR-0002 清单同为目录的条目）。
- **管理员 / 开发者模式检测**（`Test-CanCreateSymlink`）：只为上面这条路径服务，0 次调用。
- **`%VAR%` 展开**：0 条源路径使用；**`$home` / `~` 展开**：0 条使用。全部源路径以 `$env:` 开头。
- **磁盘探测推断类型**（`Resolve-ExternalItemType`：物理路径 → 容器性 → 扩展名启发）：在全是目录的前提下不可达；它的存在只让「`source` 等于某文件名」变成一条会产生 Symlink 的隐藏分支。
- **记录中的 Target / LinkType 字段**：写入后无人读取（只有 Source 被用），是记录的无效载荷。

这不是「功能少」，是 interface 比实现宽：单 adapter 的假 seam。每条分支都要在文档、schema、心智模型里占一份位置，file 分支还是唯一会因权限失败的分支——用户只有在遇到管理员提示时才知道存在这条路径。

现决定：**链接通道收缩为目录 Junction**。

- 条目类型只接受 `dir` / `directory`（`dir` 为别名）；`file` 与其他值在解析时抛错，schema 的类型枚举同步收窄为 `dir` / `directory`（ADR-0001 Revision 2026-11 已更新）。
- 占位符一律创建目录；链接一律 Junction（优先 `New-DirectoryJunction`，退回 `New-Item -ItemType Junction`）。
- 删除 `Resolve-ExternalItemType`、`Test-CanCreateSymlink`、Symlink 创建分支，`Convert-ExternalPath` 只展开 `$env:VAR`（移除 `%VAR%`、`$home`、`~`）。
- 链接记录 v2：内容为源路径字符串数组；读取端兼容旧的 `{Source,Target,LinkType}` 对象（存量记录在下次 install / reset 时自动改写为 v2），`Target` / `LinkType` 不再写入。

**Status**: accepted

**Considered Options**:

- A. 保留全部分支（原状）：interface 声称 6 件事、调用点用 2 件；file 分支既无测试也无用户
- B. 只删未读字段，保留 file 类型：记录变小，但 file 分支仍无测试、无 manifest 使用，权限失败路径继续存在
- C. 收缩到目录-only（选定）：interface 与实现同宽，删除的分支不是「待实现」而是「不存在的需求」

选定 C 而非 B：保留 file 的最大成本不是代码行数，而是它让「这条路径为什么存在」永远需要解释；回收成本极低——真需要单文件持久化时，按「影响与风险」一节重开。

**影响与风险**：

- 单文件持久化（如 `~/.gitconfig` 型配置）不再支持；此类需求需新 ADR 重开，并重新引入 Symlink + 权限提示。
- 纯字符串条目的类型不再「磁盘探测」：即使目标在磁盘上是文件，也按目录建 Junction。现存的纯字符串条目全部指向目录，无回归；若未来有人在纯字符串上放文件路径，`New-ExternalPersistLink` 在建链接前抛错，源文件与 persist 区都不被改动。
- 记录格式变更对已安装用户是兼容读、渐进写：读取端归一化旧对象；`Reset` / `install` 一次后记录即为 v2。

## 关联决策

- ADR-0001：注入 schema 的条目形状与类型枚举（Revision 2026-11 同步收窄）
- ADR-0002：机制保留决策与清单（Revision 2026-11 记录本次通道收缩）
- ADR-0003：hook 字符串与注入 schema 是机制的 interface（本次收缩即 interface 变更，契约测试同步通过）
