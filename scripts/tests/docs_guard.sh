#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

info() { echo "${BLUE}[info]${NC} $*"; }
pass() { echo "${GREEN}[pass]${NC} $*"; }
fail() { echo "${RED}[fail]${NC} $*" >&2; exit 1; }

required_files=(
  "AGENTS.md"
  "docs/README.md"
  "docs/architecture/overview.md"
  "docs/architecture/repo-boundaries.md"
  "docs/architecture/runtime-build-graph.md"
  "docs/architecture/source-tree.md"
  "docs/architecture/strimr-integration.md"
  "docs/development/setup.md"
  "docs/development/testing.md"
  "docs/development/ui-testing.md"
  "docs/development/ci.md"
  "docs/development/branch-pairing.md"
  "docs/product/branding.md"
  "docs/security/privacy-and-safety.md"
  "docs/release/app-store.md"
  "docs/maintenance/cleanup-roadmap.md"
)

check_required_files() {
  info "Checking required documentation files"
  for file in "${required_files[@]}"; do
    [[ -f "$file" ]] || fail "Missing required file: $file"
  done
  pass "Required documentation files exist"
}

scan_tracked_regex() {
  local regex="$1"
  local label="$2"
  local output

  output=$(
    git ls-files -z \
    | xargs -0 rg -n --pcre2 --color never "$regex" --glob '!AGENTS.md' \
    || true
  )

  if [[ -n "$output" ]]; then
    echo "$output"
    fail "$label"
  fi
}

scan_tracked_fixed() {
  local needle="$1"
  local label="$2"
  local output

  output=$(
    git ls-files -z \
    | xargs -0 rg -n -F --color never "$needle" --glob '!AGENTS.md' \
    || true
  )

  if [[ -n "$output" ]]; then
    echo "$output"
    fail "$label"
  fi
}

scan_tracked_regex_with_glob_exclude() {
  local regex="$1"
  local label="$2"
  local output

  output=$(
    git ls-files -z \
    | xargs -0 rg -n --pcre2 --color never "$regex" --glob '!AGENTS.md' \
    || true
  )

  if [[ -n "$output" ]]; then
    echo "$output"
    fail "$label"
  fi
}

check_forbidden_content() {
  info "Checking forbidden references outside AGENTS.md"

  local copilot_word='co'"pilot"
  local ai_tools='A''I[[:space:]]+tools'
  local coding_agents='coding[[:space:]]+a''gents'
  local agent_instruction='a''gent[-[:space:]]+instruction'
  local duplicate_instruction='instruction[[:space:]]+file'
  local forbidden_agent_regex="(${copilot_word}|${ai_tools}|${coding_agents}|${agent_instruction}|${duplicate_instruction})"

  local legacy_local='.local''_dev/'
  local legacy_dev_regex='(?<!docs/)devel''opment/'
  local legacy_vendor='ven''dor/strimr'

  scan_tracked_regex "$forbidden_agent_regex" "Direct instruction-style references found outside AGENTS.md"
  scan_tracked_fixed "$legacy_local" "Legacy local-dev path reference found in tracked files"
  scan_tracked_regex_with_glob_exclude "$legacy_dev_regex" "Legacy top-level development path reference found in tracked files"
  scan_tracked_fixed "$legacy_vendor" "Legacy Strimr vendor path reference found in tracked files"

  pass "Forbidden references are absent"
}

check_pr_diff_requirements() {
  if [[ "${GITHUB_EVENT_NAME:-}" != "pull_request" || -z "${GITHUB_BASE_REF:-}" ]]; then
    info "Skipping PR diff requirement check outside pull_request context"
    return 0
  fi

  info "Checking PR diff for required docs updates"

  git fetch origin "${GITHUB_BASE_REF}" --depth=1 >/dev/null 2>&1 || true

  local base_ref="origin/${GITHUB_BASE_REF}"
  local base_commit
  base_commit="$(git merge-base HEAD "$base_ref" 2>/dev/null || true)"

  [[ -n "$base_commit" ]] || fail "Unable to determine merge-base for ${base_ref}"

  local changed_paths
  changed_paths="$(git diff --name-only "$base_commit"...HEAD)"

  local watched_regex='^(PlinxApp/|Packages/|scripts/|\.github/workflows/|README\.md$|PlinxApp/project\.yml$)'
  local docs_regex='^(AGENTS\.md$|docs/)'

  if printf '%s\n' "$changed_paths" | rg -q "$watched_regex"; then
    if ! printf '%s\n' "$changed_paths" | rg -q "$docs_regex"; then
      fail "PR changes code/structure paths without updating AGENTS.md or docs/"
    fi
  fi

  pass "PR diff includes required documentation updates"
}

main() {
  check_required_files
  check_forbidden_content
  check_pr_diff_requirements
  pass "Docs guard passed"
}

main "$@"
