# Release Workflow

This repo follows the same branching and release rule as the rest of the
MyShop repos. Keep this document as the source of truth for Codex and any
other assistant/session working in the codebase.

## Branching rule

- Do not push fixes, features, or release changes directly to `main`.
- Start all work from a feature branch.
- Merge feature branches into `staging` first.
- Test on `staging` with staging/test data.
- Merge `staging` into `main` only after the staged changes are tested and
  approved for production release.
- Production users are on `main`, so `main` must only contain changes that
  have already passed through `staging`.

## Keeping staging and main aligned

- At release time, `main` should reflect the tested state of `staging`.
- Avoid cherry-picking isolated fixes into `main` unless the same commits are
  already on `staging`, or are immediately reconciled back into `staging`.
- If a change accidentally lands on `main` first:
  1. Stop and report it.
  2. Put the same change onto a feature branch or `staging`.
  3. Re-align the branches through the normal staging → main release flow, or
     revert `main` if the change should not be in production yet.

## Testing policy

- `staging` is for validation and can use test data.
- `main` is production and must not be used for experiments.
- Before requesting a production release build, verify that the target commit on
  `main` came from tested `staging` changes.

## Codex operating rule

When working in this repo, Codex must follow:

`feature branch → staging for testing → main for production release`

Do not bypass this flow unless the user explicitly authorizes an emergency
production hotfix and explains how staging will be reconciled afterward.
