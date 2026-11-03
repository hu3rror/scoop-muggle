# muggle bucket

Windows 应用的 Scoop manifest 仓库。除原生 Scoop 能力外，仓库自带 `persist_external` 机制，处理把用户数据写死在系统路径的应用。

## Language

**persist_external**：
Manifest 声明的一组外部数据路径，由 bucket 接管并链接到 Scoop 的 persist 区实现持久化。
_Avoid_: external persist、persist-ext

**链接记录（external link record）**：
已应用的链接集合的快照，供后续解除或重建链接时认领真实路径。
_Avoid_: 链接状态文件、记录缓存

**条目（link entry）**：
`persist_external` 数组中的一个元素：外部路径字符串，或 `[来源, 目标名, 类型]` 元组（类型只能是 `directory`，`dir` 是别名；只建目录 Junction）。
_Avoid_: 项、item、元素

**对账（reconcile）**：
把 manifest 声明、链接记录与磁盘现状对齐为同一套链接状态的唯一动作。
_Avoid_: sync、repair、修复

**孤儿链接（orphan link）**：
链接记录中存在、但当前 manifest 不再声明的链接。
_Avoid_: 残留链接、失效链接

**外壳集成（explorer integration）**：
Manifest 通过可选 reg 导入把应用接入 Windows 资源管理器的入口（右键菜单、URL scheme）。模板放 `scripts/<app>/`，`post_install` 生成可导入 reg 文件，导入与清除均由用户手动执行。
_Avoid_: context menu 功能、右键菜单选项
