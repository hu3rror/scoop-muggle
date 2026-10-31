只输出最终 commit message，不要解释，不要用代码块包裹。

Scoop bucket 提交格式：
- 新增 manifest：`<app>: Add version <version>`，如 `tailcat: Add version 0.6.0`
- 更新 manifest：`<app>: <描述>` 或 `<app>@<旧版本>: <描述>`，如 `wget: Update to version 1.25.0`、`wget@1.21.4: Fix moved urls`
- 多个相关 manifest：`<app-(*)>: <描述>`，如 `uutils-coreutils(-lean): Fix shims`
- 维护任务：`(chore): <描述>`，如 `(chore): Resolve redirected GitHub repository URLs in bulk`

使用英文，描述简洁，结尾不加句号。
