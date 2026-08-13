import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const siteDirectory = path.resolve(scriptDirectory, '..');
const repositoryRoot = path.resolve(siteDirectory, '..');
const sourceDirectory = path.join(repositoryRoot, 'docs');
const generatedDirectory = path.join(siteDirectory, '.generated', 'docs');
const privacyPolicyPath = path.join(repositoryRoot, 'PRIVACY_POLICY.md');

if (!fs.statSync(sourceDirectory).isDirectory()) {
  throw new Error(`Canonical documentation directory is missing: ${sourceDirectory}`);
}

fs.rmSync(generatedDirectory, {recursive: true, force: true});
fs.mkdirSync(path.dirname(generatedDirectory), {recursive: true});
fs.cpSync(sourceDirectory, generatedDirectory, {recursive: true});

// The repository-root policy remains the legal source; this generated wrapper
// makes that exact prose available in the public documentation IA.
const privacyDestination = path.join(generatedDirectory, 'user', 'privacy-policy.md');
const privacyPolicy = fs.readFileSync(privacyPolicyPath, 'utf8');
fs.writeFileSync(
  privacyDestination,
  `---\nsidebar_position: 7\n---\n\n${privacyPolicy}`,
);
