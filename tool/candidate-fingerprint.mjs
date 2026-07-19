#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { lstatSync } from 'node:fs';

const [base, ...options] = process.argv.slice(2);
if (!base) {
  console.error(
    'Usage: node tool/candidate-fingerprint.mjs <base> [--exclude=<path>]...',
  );
  process.exit(2);
}

const excludes = options.map((option) => {
  if (!option.startsWith('--exclude=') || option.length === 10) {
    console.error(`Unsupported option: ${option}`);
    process.exit(2);
  }
  return option.slice(10).replace(/\/+$/, '');
});

const pathspecs = ['.', ...excludes.map((path) => `:(exclude)${path}`)];
const git = (args, encoding = null) =>
  execFileSync('git', args, {
    cwd: process.cwd(),
    encoding,
    maxBuffer: 1024 * 1024 * 1024,
  });

git(['rev-parse', '--verify', `${base}^{commit}`], 'utf8');

const diff = git(['diff', '--binary', base, '--', ...pathspecs]);
const trackedPaths = git(
  ['diff', '--name-only', '-z', base, '--', ...pathspecs],
  'utf8',
)
  .split('\0')
  .filter(Boolean);
const untrackedPaths = git(
  ['ls-files', '--others', '--exclude-standard', '-z', '--', ...pathspecs],
  'utf8',
)
  .split('\0')
  .filter(Boolean)
  .sort((left, right) => Buffer.from(left).compare(Buffer.from(right)));

const hash = createHash('sha256');
hash.update(diff);
hash.update('\0MYSHOP_UNTRACKED_V1\0');

for (const path of untrackedPaths) {
  const stat = lstatSync(path);
  const mode = stat.isSymbolicLink()
    ? '120000'
    : (stat.mode & 0o111) !== 0
      ? '100755'
      : '100644';
  const blob = git(['hash-object', '--', path], 'utf8').trim();
  hash.update(`${JSON.stringify({ path, mode, blob })}\n`);
}

console.log(
  JSON.stringify(
    {
      base: git(['rev-parse', base], 'utf8').trim(),
      trackedChanges: trackedPaths.length,
      untrackedFiles: untrackedPaths.length,
      fingerprintVersion: 'myshop-candidate-v1',
      sha256: hash.digest('hex'),
      exclusions: excludes,
    },
    null,
    2,
  ),
);
