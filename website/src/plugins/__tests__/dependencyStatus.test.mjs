import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {readDependencyStatus} from '../dependencyStatus.mjs';

const strimrCommit = 'a'.repeat(40);
const upstreamBase = 'b'.repeat(40);
const aetherRevision = 'c'.repeat(40);

function makeRepository({environment, project, xcode = '26.5'}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'plinx-docs-'));
  fs.mkdirSync(path.join(root, 'config'), {recursive: true});
  fs.mkdirSync(path.join(root, 'PlinxApp'), {recursive: true});
  fs.writeFileSync(path.join(root, 'config/release-dependencies.env'), environment);
  fs.writeFileSync(path.join(root, 'PlinxApp/project.yml'), project);
  fs.writeFileSync(path.join(root, '.xcode-version'), xcode);
  return root;
}

const validEnvironment = `STRIMR_COMMIT=${strimrCommit}\nSTRIMR_BRANCH=dev-plinx\nSTRIMR_UPSTREAM_BASE=${upstreamBase}\n`;
const validProject = `packages:\n  AetherEngine:\n    url: https://github.com/wunax/AetherEngine\n    revision: ${aetherRevision}\n`;

test('reads the current dependency status from canonical configuration', () => {
  const root = makeRepository({environment: validEnvironment, project: validProject});
  assert.deepEqual(readDependencyStatus(root), {
    strimr: {branch: 'dev-plinx', commit: strimrCommit, upstreamBase},
    aetherEngine: {revision: aetherRevision},
    xcode: {version: '26.5'},
  });
});

test('rejects a malformed configured Strimr revision', () => {
  const root = makeRepository({
    environment: validEnvironment.replace(strimrCommit, 'not-a-sha'),
    project: validProject,
  });
  assert.throws(() => readDependencyStatus(root), /STRIMR_COMMIT must be/);
});

test('rejects a missing AetherEngine revision', () => {
  const root = makeRepository({environment: validEnvironment, project: 'packages: {}\n'});
  assert.throws(() => readDependencyStatus(root), /AetherEngine revision is missing/);
});
