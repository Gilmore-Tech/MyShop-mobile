# /commit — Smart Conventional Commit

Analyse staged changes, generate a conventional commit message, validate it, and commit.

## Instructions

1. Run `git diff --staged --stat` to see what files are staged.
2. Run `git diff --staged` to see the actual changes.
3. Analyse the changes and determine:
   - **type:** feat, fix, refactor, docs, test, chore, perf, style, ci
   - **scope:** api, scoring, worker, mobile, admin, common, database, config, infra, ci, ussd, docs
   - **subject:** imperative mood, lowercase, no period, max 72 chars
4. If the change touches living docs (architecture.md, CHANGELOG.md, projectstatus.md), remind the developer to verify doc updates are included.
5. Generate the commit message in this format:
   ```
   type(scope): subject

   Body explaining WHY (not what) if the change is non-trivial.

   Refs #issue-number (if applicable)
   ```
6. Show the proposed commit message and ask for confirmation.
7. If confirmed, run `git commit -m "message"`.

## Rules

- If no files are staged, prompt the developer to stage files first.
- If the changes span multiple scopes, use the primary scope and mention others in the body.
- Breaking changes get a `!` after the scope: `feat(api)!: change response format`
- Documentation-only changes: `docs: description` (no scope needed)
- If changes include new env vars, remind to update `.env.example`.
- Never commit `.env`, `node_modules`, or secrets.

## Validation

Before committing, verify:
- [ ] Commit message follows conventional commit format
- [ ] Subject line ≤ 72 characters
- [ ] Type is valid (feat/fix/refactor/docs/test/chore/perf/style/ci)
- [ ] Scope matches a known scope
- [ ] No secrets or .env files in staged changes
