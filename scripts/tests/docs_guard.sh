#!/bin/bash

if [ -z "${BASH_VERSION:-}" ]; then
  exec /bin/bash "$0" "$@"
fi

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
  "docs/product/branding.md"
  "docs/security/privacy-and-safety.md"
  "docs/release/app-store.md"
  "docs/release/open-source-compliance.md"
  "docs/maintenance/cleanup-roadmap.md"
  "docs/maintenance/upstream-strimr.md"
  "docs/welcome.md"
  "docs/user/getting-started.md"
  "docs/user/parent-guide.md"
  "docs/maintenance/current-dependencies.mdx"
  "config/release-dependencies.env"
  "website/package.json"
  "website/docusaurus.config.ts"
  "website/sidebars.ts"
  "website/src/plugins/dependencyStatus.mjs"
)

check_required_files() {
  info "Checking required documentation files"
  for file in "${required_files[@]}"; do
    [[ -f "$file" ]] || fail "Missing required file: $file"
  done
  pass "Required documentation files exist"
}

existing_tracked_files() {
  while IFS= read -r -d '' file; do
    [[ "$file" != "AGENTS.md" && -e "$file" ]] && printf '%s\0' "$file"
  done < <(git ls-files -z)
}

scan_tracked_regex() {
  local regex="$1"
  local label="$2"
  local output

  output=$(
    existing_tracked_files \
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
    existing_tracked_files \
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
    {
      while IFS= read -r -d '' file; do
        [[ "$file" == docs/* || "$file" == website/* ]] && continue
        printf '%s\0' "$file"
      done < <(existing_tracked_files)
    } \
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

  local word_1='co'"pilot"
  local phrase_1='A''I[[:space:]]+tools'
  local phrase_2='coding[[:space:]]+a''gents'
  local phrase_3='a''gent[-[:space:]]+instruction'
  local phrase_4='co''pilot-instructions'
  local forbidden_agent_regex="(${word_1}|${phrase_1}|${phrase_2}|${phrase_3}|${phrase_4})"

  local legacy_local='.local''_dev/'
  local legacy_dev_regex='(?<!docs/)(?<!\.\./)devel''opment/'
  local legacy_vendor='ven''dor/strimr'

  scan_tracked_regex "$forbidden_agent_regex" "Direct instruction-style references found outside AGENTS.md"
  scan_tracked_fixed "$legacy_local" "Legacy local-dev path reference found in tracked files"
  scan_tracked_regex_with_glob_exclude "$legacy_dev_regex" "Legacy top-level development path reference found in tracked files"
  scan_tracked_fixed "$legacy_vendor" "Legacy Strimr vendor path reference found in tracked files"

  pass "Forbidden references are absent"
}

# Plinx absorbed Strimr's source, so the sibling-checkout pairing (pin keys,
# seam verifier, release sibling check, Strimr-only runners) must not return.
# docs/maintenance/ keeps the historical records that describe it.
check_retired_strimr_pairing() {
  info "Checking that the retired Strimr pairing machinery stays removed"

  # Split literals keep this guard from matching its own source.
  local machinery_regex='(verify_strimr_''integration_contract|verify_release_''dependency_state|STRIMR_''(COMMIT|BRANCH|UPSTREAM_BASE|REQUIRED_SEAMS|REQUIRED_PROJECT_SOURCES)\b|scripts/strimr''/)'
  local sibling_regex='(?<![.\w])\.\./(\.\./)?strimr''\b'
  local output

  output=$(
    {
      while IFS= read -r -d '' file; do
        [[ "$file" == docs/maintenance/* ]] && continue
        printf '%s\0' "$file"
      done < <(existing_tracked_files)
    } \
    | xargs -0 rg -n --pcre2 --color never "$machinery_regex" --glob '!AGENTS.md' \
    || true
  )
  if [[ -n "$output" ]]; then
    echo "$output"
    fail "Retired Strimr pairing machinery is referenced; see docs/maintenance/upstream-strimr.md"
  fi

  scan_tracked_regex_with_glob_exclude "$sibling_regex" \
    "A sibling Strimr checkout is referenced outside docs/; that source now lives in PlinxApp/Core and PlinxApp/Platform"

  pass "Retired Strimr pairing machinery is absent"
}

check_dependency_documentation_contract() {
  info "Checking dependency documentation contract"

  local env_file="config/release-dependencies.env"
  local project_file="PlinxApp/project.yml"

  # shellcheck disable=SC1091
  source "$env_file"
  [[ "${STRIMR_FORK_BASE:-}" =~ ^[0-9a-f]{40}$ ]] \
    || fail "STRIMR_FORK_BASE in $env_file must be a 40-character lowercase Git SHA"

  # The dependency-status page renders the current Swift package pins; narrative
  # documentation links there instead of copying moving revisions.
  local revision output
  while IFS= read -r revision; do
    output=$(rg -n -F --color never -- "$revision" docs || true)
    if [[ -n "$output" ]]; then
      echo "$output"
      fail "Current Swift package revision $revision is duplicated in narrative documentation"
    fi
  done < <(rg -o --no-filename -r '$1' '^\s+revision:\s*"?([0-9a-f]{40})"?\s*$' "$project_file")

  rg -F -q -- "current-dependencies" docs/architecture/strimr-integration.md \
    || fail "docs/architecture/strimr-integration.md must link to the generated dependency status page"
  rg -F -q -- "upstream-strimr" docs/architecture/strimr-integration.md \
    || fail "docs/architecture/strimr-integration.md must link to the upstream provenance page"

  pass "Dependency documentation contract is intact"
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
  check_retired_strimr_pairing
  check_dependency_documentation_contract
  check_pr_diff_requirements
  pass "Docs guard passed"
}

main "$@"
