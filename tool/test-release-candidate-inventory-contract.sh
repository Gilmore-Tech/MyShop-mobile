#!/usr/bin/env bash
set -euo pipefail

tool_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
inventory_tool="$tool_dir/release-candidate-inventory.mjs"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/myshop-candidate-inventory.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT

git -C "$fixture" init -q
git -C "$fixture" config user.email "candidate-contract@example.invalid"
git -C "$fixture" config user.name "Candidate Contract"
mkdir -p "$fixture/.claude/mcp"
printf 'base\n' >"$fixture/committed-only.txt"
printf 'base\n' >"$fixture/both.txt"
printf 'base\n' >"$fixture/working-only.txt"
printf 'base\n' >"$fixture/excluded.md"
printf '{}\n' >"$fixture/.claude/mcp/config.json"
git -C "$fixture" add .
git -C "$fixture" commit -qm "base"
base="$(git -C "$fixture" rev-parse HEAD)"

printf 'committed\n' >"$fixture/committed-only.txt"
printf 'committed\n' >"$fixture/both.txt"
git -C "$fixture" add committed-only.txt both.txt
git -C "$fixture" commit -qm "candidate"

printf 'working\n' >"$fixture/both.txt"
printf 'working\n' >"$fixture/working-only.txt"
printf 'working\n' >"$fixture/excluded.md"
printf '{"local":true}\n' >"$fixture/.claude/mcp/config.json"
printf '{"local":true}\n' >"$fixture/.claude/local.json"
printf 'untracked\n' >"$fixture/untracked.txt"

first="$(
  cd "$fixture"
  node "$inventory_tool" "$base" --exclude=excluded.md
)"
second="$(
  cd "$fixture"
  node "$inventory_tool" "$base" --exclude=excluded.md
)"

FIRST="$first" SECOND="$second" node <<'NODE'
const assert = require('node:assert/strict');
const first = JSON.parse(process.env.FIRST);
const second = JSON.parse(process.env.SECOND);
assert.equal(first.schemaVersion, 1);
assert.deepEqual(first.exclusions, ['excluded.md']);
assert.deepEqual(first.counts, {
  total: 6,
  committedOnly: 1,
  workingOnly: 2,
  committedAndWorking: 1,
  untracked: 2,
  excludedDeveloperLocal: 1,
  reviewRequired: 5,
});
assert.equal(first.inventorySha256, second.inventorySha256);
assert.equal(first.entries.some((entry) => entry.path === 'excluded.md'), false);
const byPath = Object.fromEntries(
  first.entries.map((entry) => [entry.path, entry]),
);
assert.equal(byPath['committed-only.txt'].state, 'committed-only');
assert.equal(byPath['working-only.txt'].state, 'working-only');
assert.equal(byPath['both.txt'].state, 'committed-and-working');
assert.equal(byPath['untracked.txt'].state, 'untracked');
assert.equal(
  byPath['.claude/mcp/config.json'].disposition,
  'repository-security-required',
);
assert.equal(
  byPath['.claude/local.json'].disposition,
  'exclude-developer-local',
);
NODE

if (
  cd "$fixture"
  node "$inventory_tool" "$base" --unsupported >/dev/null 2>&1
); then
  echo "inventory tool accepted an unsupported option" >&2
  exit 1
fi

echo "Release candidate inventory contract passed"
