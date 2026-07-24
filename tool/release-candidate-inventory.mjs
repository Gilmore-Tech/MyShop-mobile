#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, lstatSync } from 'node:fs';

const [base, ...options] = process.argv.slice(2);
if (!base) {
  console.error(
    'Usage: node tool/release-candidate-inventory.mjs <base> [--exclude=<path>]...',
  );
  process.exit(2);
}

const exclusions = options.map((option) => {
  if (!option.startsWith('--exclude=') || option.length === 10) {
    console.error(`Unsupported option: ${option}`);
    process.exit(2);
  }
  return option.slice(10).replace(/\/+$/, '');
});
const pathspecs = ['.', ...exclusions.map((path) => `:(exclude)${path}`)];

const git = (args, encoding = 'utf8') =>
  execFileSync('git', args, {
    cwd: process.cwd(),
    encoding,
    maxBuffer: 1024 * 1024 * 1024,
  });

const pathSet = (args) =>
  new Set(
    git(args, null)
      .toString('utf8')
      .split('\0')
      .filter(Boolean),
  );

const baseCommit = git(['rev-parse', '--verify', `${base}^{commit}`]).trim();
const headCommit = git(['rev-parse', 'HEAD']).trim();
const repository = git(['rev-parse', '--show-toplevel']).trim();
const committed = pathSet([
  'diff',
  '--name-only',
  '-z',
  `${baseCommit}..${headCommit}`,
  '--',
  ...pathspecs,
]);
const working = pathSet([
  'diff',
  '--name-only',
  '-z',
  'HEAD',
  '--',
  ...pathspecs,
]);
const productionDelta = pathSet([
  'diff',
  '--name-only',
  '-z',
  baseCommit,
  '--',
  ...pathspecs,
]);
const untracked = pathSet([
  'ls-files',
  '--others',
  '--exclude-standard',
  '-z',
  '--',
  ...pathspecs,
]);
const paths = [...new Set([...productionDelta, ...untracked])].sort(
  (left, right) => Buffer.from(left).compare(Buffer.from(right)),
);

const entries = paths.map((path) => {
  const isUntracked = untracked.has(path);
  const inCommitted = committed.has(path);
  const inWorking = working.has(path);
  const state = isUntracked
    ? 'untracked'
    : inCommitted && inWorking
      ? 'committed-and-working'
      : inWorking
        ? 'working-only'
        : 'committed-only';
  const componentParts = path.split('/');
  const component =
    componentParts.length > 1
      ? `${componentParts[0]}/${componentParts[1]}`
      : componentParts[0];
  const exists = existsSync(path);
  const stat = exists ? lstatSync(path) : null;
  const mode =
    stat === null
      ? null
      : stat.isSymbolicLink()
        ? '120000'
        : (stat.mode & 0o111) !== 0
          ? '100755'
          : '100644';
  const blob = exists ? git(['hash-object', '--', path]).trim() : null;
  return {
    path,
    component,
    state,
    disposition: path.startsWith('.claude/')
      ? isUntracked
        ? 'exclude-developer-local'
        : 'repository-security-required'
      : 'review-required',
    mode,
    blob,
  };
});

const counts = {
  total: entries.length,
  committedOnly: entries.filter(
    (entry) => entry.state === 'committed-only',
  ).length,
  workingOnly: entries.filter(
    (entry) => entry.state === 'working-only',
  ).length,
  committedAndWorking: entries.filter(
    (entry) => entry.state === 'committed-and-working',
  ).length,
  untracked: entries.filter((entry) => entry.state === 'untracked').length,
  excludedDeveloperLocal: entries.filter(
    (entry) => entry.disposition === 'exclude-developer-local',
  ).length,
  reviewRequired: entries.filter(
    (entry) => entry.disposition !== 'exclude-developer-local',
  ).length,
};
const fingerprint = createHash('sha256');
for (const entry of entries) {
  fingerprint.update(`${JSON.stringify(entry)}\n`);
}

console.log(
  JSON.stringify(
    {
      schemaVersion: 1,
      repository,
      baseCommit,
      headCommit,
      exclusions,
      counts,
      inventorySha256: fingerprint.digest('hex'),
      entries,
    },
    null,
    2,
  ),
);
