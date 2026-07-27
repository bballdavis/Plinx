import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const siteDirectory = path.resolve(scriptDirectory, '..');
const repositoryRoot = path.resolve(siteDirectory, '..');
const sourceDirectory = path.join(repositoryRoot, 'docs');
const generatedDirectory = path.join(siteDirectory, '.generated', 'docs');

if (!fs.statSync(sourceDirectory).isDirectory()) {
  throw new Error(`Canonical documentation directory is missing: ${sourceDirectory}`);
}

fs.rmSync(generatedDirectory, {recursive: true, force: true});
fs.mkdirSync(path.dirname(generatedDirectory), {recursive: true});
fs.cpSync(sourceDirectory, generatedDirectory, {recursive: true});
