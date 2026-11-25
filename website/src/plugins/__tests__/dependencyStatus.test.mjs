import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {readDependencyStatus} from '../dependencyStatus.mjs';

const forkBase = 'a'.repeat(40);
const aetherRevision = 'c'.repeat(40);
const assRevision = 'd'.repeat(40);

function makeRepository({environment, project}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'plinx-docs-'));
  fs.mkdirSync(path.join(root, 'config'), {recursive: true});
  fs.mkdirSync(path.join(root, 'PlinxApp'), {recursive: true});
  fs.writeFileSync(path.join(root, 'config/release-dependencies.env'), environment);
  fs.writeFileSync(path.join(root, 'PlinxApp/project.yml'), project);
  return root;
}

const validEnvironment = `# comment\nSTRIMR_FORK_BASE=${forkBase}\n`;
const validProject = [
  'options:',
  '  xcodeVersion: "27.2"',
  'packages:',
  '  PlinxCore:',
  '    path: ../Packages/PlinxCore',
  '  AetherEngine:',
  '    url: https://github.com/wunax/AetherEngine',
  `    revision: ${aetherRevision}`,
  '  GRDB:',
  '    url: https://github.com/groue/GRDB.swift',
  '    exactVersion: 7.12.0',
  '  SwiftAssRenderer:',
  '    url: https://github.com/wunax/swift-ass-renderer',
  `    revision: ${assRevision}`,
  '',
  'settings:',
  '  base:',
  '    PRODUCT_NAME: Plinx',
  '',
].join('\n');

test('reads the current dependency status from canonical configuration', () => {
  const root = makeRepository({environment: validEnvironment, project: validProject});
  assert.deepEqual(readDependencyStatus(root), {
    strimr: {forkBase},
    packages: [
      {name: 'AetherEngine', url: 'https://github.com/wunax/AetherEngine', pinKind: 'revision', pin: aetherRevision},
      {name: 'GRDB', url: 'https://github.com/groue/GRDB.swift', pinKind: 'exactVersion', pin: '7.12.0'},
      {name: 'SwiftAssRenderer', url: 'https://github.com/wunax/swift-ass-renderer', pinKind: 'revision', pin: assRevision},
    ],
    xcode: {version: '27.2'},
  });
});

test('reads the repository configuration', () => {
  const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../..');
  const status = readDependencyStatus(repositoryRoot);
  assert.match(status.strimr.forkBase, /^[0-9a-f]{40}$/);
  assert.ok(status.packages.some((dependency) => dependency.name === 'AetherEngine'));
});

test('rejects a missing absorbed Strimr base', () => {
  const root = makeRepository({environment: '# no keys\n', project: validProject});
  assert.throws(() => readDependencyStatus(root), /STRIMR_FORK_BASE is missing/);
});

test('rejects a malformed absorbed Strimr base', () => {
  const root = makeRepository({
    environment: validEnvironment.replace(forkBase, 'not-a-sha'),
    project: validProject,
  });
  assert.throws(() => readDependencyStatus(root), /STRIMR_FORK_BASE must be/);
});

test('rejects a missing AetherEngine revision', () => {
  const root = makeRepository({
    environment: validEnvironment,
    project: 'options:\n  xcodeVersion: "27.2"\npackages: {}\n',
  });
  assert.throws(() => readDependencyStatus(root), /AetherEngine revision is missing/);
});

test('rejects a Swift package without an exact pin', () => {
  const root = makeRepository({
    environment: validEnvironment,
    project: validProject.replace('exactVersion: 7.12.0', 'from: 7.0.0'),
  });
  assert.throws(() => readDependencyStatus(root), /GRDB in PlinxApp\/project.yml must be pinned/);
});

test('rejects a missing Xcode version', () => {
  const root = makeRepository({
    environment: validEnvironment,
    project: validProject.replace('options:\n  xcodeVersion: "27.2"\n', ''),
  });
  assert.throws(() => readDependencyStatus(root), /xcodeVersion is missing/);
});
