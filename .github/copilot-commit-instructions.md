Generate a short English commit message without trailing periods based on staged files:
1. Manifest `deprecated/<app>.json`:
   `<app>: Deprecate manifest`
2. New manifest `bucket/<app>.json`:
   `<app>: Add version <version>`
3. Updated manifest `bucket/<app>.json`:
   `<app>@<version>: <summary>`
4. Non-JSON / general files (`.ps1`, `.bat`, markdown, etc.):
   `(chore): <summary>`

Rules:
- `<app>`: Filename without extension
- `<version>`: Value of `version` in JSON
