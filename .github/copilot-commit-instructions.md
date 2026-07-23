Strictly follow Scoop Bucket commit conventions (short, clear, no trailing periods):
- In English
- If any manifest `.json` is added or updated in the `deprecated/` directory:
  Format: `<app name>: Deprecate manifest`
- If a **NEW** manifest `.json` is created/added in the `bucket/` directory:
  Format: `<app name>: Add version <version>`
- If an **EXISTING** manifest `.json` in the `bucket/` directory is updated/modified:
  Format: `<app name>@<version>: <small description>`
- For all other changes (non-manifest or general files):
  Format: `(chore): <small description>`

Rules for variable placeholders:
1. `<app name>`: Filename without `.json` extension (e.g., `git.json` -> `git`).
2. `<version>`: Extract the new `version` value from the JSON diff.
