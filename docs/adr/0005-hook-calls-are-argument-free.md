# hook 调用形态改为无参：persist_external 函数从调用作用域读 `$dir`/`$persist_dir`/`$manifest`

Scoop 的 `Invoke-HookScript` 在当前作用域展开 hook 文本，`$dir`、`$persist_dir`、`$manifest` 在 `post_install` 与 `pre_uninstall` 都是可读变量（官方文档化的 hook 变量，见 [App-Manifests](https://github.com/ScoopInstaller/Scoop/wiki/App-Manifests)）。因此 hook 里把这三个值再作为参数传给脚本没有信息增益，只增加漂移面：此前 `Invoke-PersistExternalInstall` 新增 `-PersistDir` 时，21 个 manifest 的 hook 没有同步，直到 rename/reinstall 才暴露（ADR-0003 记录）。删掉参数后，脚本新增读取任何 hook 作用域变量都不会再需要动 manifest。

但 hook 文本不是唯一的调用方：`scoop uninstall` 与 `scoop update` 的 `pre_uninstall` 读的是安装时保存的 `scoop-manifest.json`（`libexec/scoop-uninstall.ps1` 与 `libexec/scoop-update.ps1` 里对 `Invoke-HookScript` 的调用），已安装用户的旧文本会继续以 `-Manifest $manifest -Dir $dir -PersistDir $persist_dir` 的带参形态调用。若函数签名删参，这些调用会在卸载/升级链路上报 `NamedParameterNotFound` 并中止。故兼容参数必须保留。

**Status**: accepted

**Considered Options**:

- A. 不收：hook 继续传参，靠 ADR-0003 的契约测试压住漂移。缺点：每个 manifest 复述 Scoop 已有变量；脚本每新增一个读取变量都要同步 42 条 hook。
- B. 无参规范形态 + 保留旧参数（选定）：新 manifest 写 dot-source + 裸调用；函数保留 `-Manifest`/`-PersistDir`/`-Dir` 为可选兼容参数，承接已安装版本保存的旧文本。
- C. 彻底无参：破坏所有已安装用户的 uninstall 与 update 链路。否决。

选定 B 的实现约束（均有 spike 实测）：

- 参数不能命名为 `Manifest`/`PersistDir`/`Dir`。PowerShell 变量名大小写不敏感，同名参数会遮蔽 hook 作用域变量，函数内读到的就是未绑定的 `$null`。实现用 `[Alias()]` 把旧名映射到 `Legacy*` 参数，函数内按 `$PSBoundParameters` 判断走兼容分支。
- 裸调用时 `$manifest`/`$persist_dir`/`$dir` 缺失，函数抛出带变量名的明确错误，而不是把 `$null` 静默送进对账逻辑。
- `Uninstall` 的 `-PersistDir` 缺省时仍从 `-Dir` 推导（兼容旧版 `pre_uninstall` 文本没有 `$persist_dir` 的形态）。

**契约变更**（`scripts/persist-external-hooks.Tests.ps1`）：

- hook 文本必须裸调用函数，不得带 `-参数`；
- 仍校验函数存在、dot-source 存在、`persist_external` manifest 成对声明 hook。

**运行时测试**（`scripts/persist-external-runtime.Tests.ps1`）：在临时目录中用真实 Junction 验证裸调用能读到 hook 作用域值、数据迁移与记录文件行为完整，以及旧 `-Manifest/-Dir/-PersistDir` 调用形态继续可用。
