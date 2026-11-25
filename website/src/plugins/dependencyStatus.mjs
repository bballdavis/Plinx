import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const pluginDirectory = path.dirname(fileURLToPath(import.meta.url));
const defaultRepositoryRoot = path.resolve(pluginDirectory, '../../..');
const commitPattern = /^[0-9a-f]{40}$/;
const versionPattern = /^\d+(?:\.\d+){1,2}$/;
const xcodePattern = /^\d+(?:\.\d+){1,2}$/;

function fail(message) {
  throw new Error(`Unable to load Plinx dependency status: ${message}`);
}

function unquote(value) {
  return value.trim().replace(/^['"]|['"]$/g, '');
}

function readRequiredEnvironmentValue(source, name) {
  const match = source.match(new RegExp(`^${name}=([^\\r\\n]+)$`, 'm'));
  if (!match) {
    fail(`${name} is missing from config/release-dependencies.env`);
  }

  const value = unquote(match[1]);
  if (!value) {
    fail(`${name} is empty in config/release-dependencies.env`);
  }
  return value;
}

function readRequiredProjectOption(source, name) {
  const match = source.match(
    new RegExp(`^options:\\r?\\n(?:^[ \\t]+.*(?:\\r?\\n|$))*?^[ \\t]+${name}:\\s*["']?([^"'\\s]+)["']?\\s*$`, 'm'),
  );
  if (!match) {
    fail(`${name} is missing from PlinxApp/project.yml`);
  }

  const value = match[1].trim();
  if (!value) {
    fail(`${name} is empty in PlinxApp/project.yml`);
  }
  return value;
}

// Reads the remote Swift packages from the top-level `packages:` block of
// project.yml. Local `path:` packages are part of the repository and skipped.
function readRemotePackages(source) {
  const packages = [];
  let inPackages = false;
  let current = null;

  const flush = () => {
    if (current?.url) packages.push(current);
    current = null;
  };

  for (const line of source.split(/\r?\n/)) {
    if (/^packages:\s*$/.test(line)) {
      inPackages = true;
      continue;
    }
    if (!inPackages) continue;
    if (/^[^\s#]/.test(line)) {
      flush();
      inPackages = false;
      continue;
    }

    const name = line.match(/^ {2}([A-Za-z0-9_.-]+):\s*$/);
    if (name) {
      flush();
      current = {name: name[1], url: '', pinKind: '', pin: ''};
      continue;
    }
    if (!current) continue;

    const field = line.match(/^ {4}(url|revision|exactVersion|version|from|branch):\s*(.+?)\s*$/);
    if (!field) continue;
    if (field[1] === 'url') {
      current.url = unquote(field[2]);
    } else {
      current.pinKind = field[1];
      current.pin = unquote(field[2]);
    }
  }
  flush();

  for (const dependency of packages) {
    const exactRevision = dependency.pinKind === 'revision' && commitPattern.test(dependency.pin);
    const exactVersion = dependency.pinKind === 'exactVersion' && versionPattern.test(dependency.pin);
    if (!exactRevision && !exactVersion) {
      fail(`${dependency.name} in PlinxApp/project.yml must be pinned to an exact revision or exactVersion`);
    }
  }
  return packages;
}

export function readDependencyStatus(repositoryRoot = defaultRepositoryRoot) {
  const dependencyConfigPath = path.join(repositoryRoot, 'config/release-dependencies.env');
  const projectPath = path.join(repositoryRoot, 'PlinxApp/project.yml');
  const dependencyConfig = fs.readFileSync(dependencyConfigPath, 'utf8');
  const project = fs.readFileSync(projectPath, 'utf8');

  const strimrForkBase = readRequiredEnvironmentValue(dependencyConfig, 'STRIMR_FORK_BASE');
  const xcodeVersion = readRequiredProjectOption(project, 'xcodeVersion');
  const packages = readRemotePackages(project);

  if (!commitPattern.test(strimrForkBase)) fail('STRIMR_FORK_BASE must be a 40-character lowercase Git SHA');
  if (!packages.some((dependency) => dependency.name === 'AetherEngine' && dependency.pinKind === 'revision')) {
    fail('AetherEngine revision is missing or malformed in PlinxApp/project.yml');
  }
  if (!xcodePattern.test(xcodeVersion)) fail('xcodeVersion in PlinxApp/project.yml must contain a semantic Xcode version');

  return {
    strimr: {
      forkBase: strimrForkBase,
    },
    packages,
    xcode: {
      version: xcodeVersion,
    },
  };
}

export default function dependencyStatusPlugin() {
  return {
    name: 'plinx-dependency-status',
    loadContent() {
      return readDependencyStatus();
    },
    contentLoaded({content, actions}) {
      actions.setGlobalData(content);
    },
  };
}
