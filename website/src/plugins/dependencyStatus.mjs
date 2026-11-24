import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const pluginDirectory = path.dirname(fileURLToPath(import.meta.url));
const defaultRepositoryRoot = path.resolve(pluginDirectory, '../../..');
const commitPattern = /^[0-9a-f]{40}$/;
const xcodePattern = /^\d+(?:\.\d+){1,2}$/;

function fail(message) {
  throw new Error(`Unable to load Plinx dependency status: ${message}`);
}

function readRequiredEnvironmentValue(source, name) {
  const match = source.match(new RegExp(`^${name}=([^\\r\\n]+)$`, 'm'));
  if (!match) {
    fail(`${name} is missing from config/release-dependencies.env`);
  }

  const value = match[1].trim().replace(/^['"]|['"]$/g, '');
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

export function readDependencyStatus(repositoryRoot = defaultRepositoryRoot) {
  const dependencyConfigPath = path.join(repositoryRoot, 'config/release-dependencies.env');
  const projectPath = path.join(repositoryRoot, 'PlinxApp/project.yml');
  const dependencyConfig = fs.readFileSync(dependencyConfigPath, 'utf8');
  const project = fs.readFileSync(projectPath, 'utf8');

  const strimrCommit = readRequiredEnvironmentValue(dependencyConfig, 'STRIMR_COMMIT');
  const strimrBranch = readRequiredEnvironmentValue(dependencyConfig, 'STRIMR_BRANCH');
  const strimrUpstreamBase = readRequiredEnvironmentValue(dependencyConfig, 'STRIMR_UPSTREAM_BASE');
  const xcodeVersion = readRequiredProjectOption(project, 'xcodeVersion');
  const aetherMatch = project.match(/AetherEngine:\s*\n\s*url:[^\n]+\n\s*revision:\s*([0-9a-f]{40})/);

  if (!commitPattern.test(strimrCommit)) fail('STRIMR_COMMIT must be a 40-character lowercase Git SHA');
  if (!commitPattern.test(strimrUpstreamBase)) fail('STRIMR_UPSTREAM_BASE must be a 40-character lowercase Git SHA');
  if (!aetherMatch) fail('AetherEngine revision is missing or malformed in PlinxApp/project.yml');
  if (!xcodePattern.test(xcodeVersion)) fail('xcodeVersion in PlinxApp/project.yml must contain a semantic Xcode version');

  return {
    strimr: {
      branch: strimrBranch,
      commit: strimrCommit,
      upstreamBase: strimrUpstreamBase,
    },
    aetherEngine: {
      revision: aetherMatch[1],
    },
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
