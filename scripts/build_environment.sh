#!/bin/bash

# Shared build/cache locations for local Plinx tooling.
# Source this file from build and test scripts; do not execute it directly.

PLINX_ENV_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLINX_PROJECT_ROOT="$(cd "$PLINX_ENV_SCRIPT_DIR/.." && pwd)"
PLINX_USER_HOME="${HOME:?HOME must be set}"

# Keep one reusable cache per checkout family outside the repository. Override
# these when an isolated cache is required (for example, in CI).
PLINX_CACHE_ROOT="${PLINX_CACHE_ROOT:-$PLINX_USER_HOME/Library/Caches/Plinx}"
PLINX_XCODE_DERIVED_DATA_PATH="${PLINX_XCODE_DERIVED_DATA_PATH:-$PLINX_CACHE_ROOT/DerivedData}"
PLINX_SWIFTPM_SCRATCH_ROOT="${PLINX_SWIFTPM_SCRATCH_ROOT:-$PLINX_CACHE_ROOT/SwiftPM}"

# Repo-local outputs remain separate because archives and compliance bundles
# are deliverables, not reusable compiler caches.
PLINX_REPO_BUILD_ROOT="${PLINX_REPO_BUILD_ROOT:-$PLINX_PROJECT_ROOT/build}"
