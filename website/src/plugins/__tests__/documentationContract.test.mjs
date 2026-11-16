import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

const directory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(directory, '../../../..');
const read = (relativePath) => fs.readFileSync(path.join(repositoryRoot, relativePath), 'utf8');

test('every active Strimr contribution plan is navigable and the retired plan is archived', () => {
  const sidebar = read('website/sidebars.ts');
  const plans = fs.readdirSync(path.join(repositoryRoot, 'docs/maintenance/strimr-contributions'))
    .filter((entry) => entry.endsWith('.md'));
  assert.ok(plans.length > 0, 'missing contribution plans');
  for (const file of plans) {
    assert.ok(
      sidebar.includes(`strimr-contributions/${file.replace(/^\d+-/, '').replace(/\.md$/, '')}`),
      `${file} is not in the sidebar`,
    );
  }
  assert.match(sidebar, /label: 'Retired plans'/);
  assert.match(sidebar, /recently-added-hub-classification/);
});

test('public documentation navigation includes required family and contributor routes', () => {
  const sidebar = read('website/sidebars.ts');
  for (const route of [
    'user/product-tour',
    'user/apple-tv',
    'user/privacy-policy',
    'development/xcode-cloud-monitoring',
    'release/app-store',
  ]) {
    assert.match(sidebar, new RegExp(`'${route}'`));
  }
});

test('the root privacy policy is the single source for the generated privacy route', () => {
  const preparation = read('website/scripts/prepare-content.mjs');
  assert.match(preparation, /PRIVACY_POLICY\.md/);
  assert.match(preparation, /privacy-policy\.md/);
  assert.ok(fs.existsSync(path.join(repositoryRoot, 'PRIVACY_POLICY.md')));
  assert.ok(!fs.existsSync(path.join(repositoryRoot, 'docs/user/privacy-policy.md')));
});
