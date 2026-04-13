# /commit — Smart Commit with Conventional Format

## Usage
```
/commit                 # Auto-generate commit message from staged changes
/commit "message"       # Use provided message, validate format
```

## What This Command Does

1. **Analyses staged changes:**
   - Reads `git diff --staged --stat` for file list
   - Reads `git diff --staged` for content changes
   - Determines the type, scope, and description

2. **Generates commit message following convention:**

```
type(scope): subject

Types: feat, fix, refactor, style, test, chore, docs
Scopes: client, provider, core, ui, api, domain, melos, ci
```

3. **Scope inference rules:**
   - Files in `apps/client_app/` → scope: `client`
   - Files in `apps/provider_app/` → scope: `provider`
   - Files in `packages/myshop_core/` → scope: `core`
   - Files in `packages/myshop_ui/` → scope: `ui`
   - Files in `packages/myshop_api/` → scope: `api`
   - Files in `packages/myshop_domain/` → scope: `domain`
   - Files in `melos.yaml` or root config → scope: `melos`
   - Files in `.github/` → scope: `ci`
   - Multiple scopes → use the primary scope (most files changed)

4. **Pre-commit checks:**
   - Verify no `print()` statements in staged Dart files
   - Verify no hardcoded color hex values in staged widget files
   - Verify no `TODO` without ticket reference (e.g., `// TODO(MSP-42): ...`)
   - Warn if test files are missing for new screen/provider files

5. **Prompts for confirmation before executing `git commit`**

## Examples

```bash
# Auto-generated
feat(client): add ride booking screen with fare estimate display

# Multi-file
refactor(core): extract currency formatter to shared GHS utility

# Test addition
test(provider): add widget tests for artisan bid submission screen
```
