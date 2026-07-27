#!/bin/bash
set -euo pipefail

# Verifies the Plinx <-> Strimr source-integration contract without changing
# either checkout. --quick validates the configured source seam surface; --full
# additionally validates the local sibling's branch, cleanliness, exact pin,
# ancestry, and linear downstream patch stack.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_ROOT/config/release-dependencies.env"
PROJECT_FILE="$PROJECT_ROOT/PlinxApp/project.yml"
STRIMR_DIR="$(dirname "$PROJECT_ROOT")/strimr"
MODE="quick"

usage() {
  cat <<'EOF'
Usage: scripts/verify_strimr_integration_contract.sh [--quick | --full] [--strimr-dir PATH]

  --quick              Check configured source paths and required seam tokens.
  --full               Also require a clean sibling on the configured branch and
                       exact commit, with the configured upstream base as an
                       ancestor and no merge commits in the downstream stack.
  --strimr-dir PATH    Override the default sibling path (../strimr).
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

require_config_value() {
  value_name="$1"
  value="$2"
  [ -n "$value" ] || fail "$value_name is missing from $CONFIG_FILE"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --quick)
      MODE="quick"
      ;;
    --full)
      MODE="full"
      ;;
    --strimr-dir)
      [ "$#" -ge 2 ] || fail "--strimr-dir requires a path"
      STRIMR_DIR="$2"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "unknown option: $1"
      ;;
  esac
  shift
done

[ -f "$CONFIG_FILE" ] || fail "missing pairing config: $CONFIG_FILE"
[ -f "$PROJECT_FILE" ] || fail "missing XcodeGen project file: $PROJECT_FILE"

# shellcheck disable=SC1090
source "$CONFIG_FILE"

require_config_value "STRIMR_COMMIT" "${STRIMR_COMMIT:-}"
require_config_value "STRIMR_BRANCH" "${STRIMR_BRANCH:-}"
require_config_value "STRIMR_UPSTREAM_BASE" "${STRIMR_UPSTREAM_BASE:-}"
require_config_value "STRIMR_REQUIRED_SEAMS" "${STRIMR_REQUIRED_SEAMS:-}"
require_config_value "STRIMR_REQUIRED_PROJECT_SOURCES" "${STRIMR_REQUIRED_PROJECT_SOURCES:-}"

[ -d "$STRIMR_DIR" ] || fail "Strimr sibling not found at $STRIMR_DIR"
if ! git -C "$STRIMR_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  fail "Strimr sibling is not a Git work tree: $STRIMR_DIR"
fi

check_project_sources() {
  while IFS= read -r project_source; do
    [ -z "$project_source" ] && continue
    if ! grep -F -- "path: $project_source" "$PROJECT_FILE" >/dev/null; then
      fail "PlinxApp/project.yml no longer includes required Strimr source path: $project_source"
    fi
  done <<EOF
$STRIMR_REQUIRED_PROJECT_SOURCES
EOF
}

check_required_seams() {
  while IFS='|' read -r relative_path required_token; do
    [ -z "$relative_path" ] && continue
    [ -n "$required_token" ] || fail "invalid seam record for $relative_path in $CONFIG_FILE"

    seam_file="$STRIMR_DIR/$relative_path"
    [ -f "$seam_file" ] || fail "required Strimr seam file is missing: $relative_path"
    if ! grep -F -- "$required_token" "$seam_file" >/dev/null; then
      fail "required Strimr seam token is missing: $relative_path -> $required_token"
    fi
  done <<EOF
$STRIMR_REQUIRED_SEAMS
EOF
}

check_project_sources
check_required_seams
echo "Strimr pairing quick checks passed."

if [ "$MODE" = "quick" ]; then
  exit 0
fi

status_output="$(git -C "$STRIMR_DIR" status --porcelain --untracked-files=all)"
if [ -n "$status_output" ]; then
  echo "$status_output" >&2
  fail "Strimr sibling has uncommitted or untracked changes; the full contract requires a clean tree"
fi

current_branch="$(git -C "$STRIMR_DIR" symbolic-ref --quiet --short HEAD || true)"
[ -n "$current_branch" ] || fail "Strimr sibling is detached; expected branch $STRIMR_BRANCH"
[ "$current_branch" = "$STRIMR_BRANCH" ] || fail "Strimr branch is $current_branch; expected $STRIMR_BRANCH"

current_commit="$(git -C "$STRIMR_DIR" rev-parse HEAD)"
[ "$current_commit" = "$STRIMR_COMMIT" ] || fail "Strimr HEAD is $current_commit; expected exact pin $STRIMR_COMMIT"

if ! git -C "$STRIMR_DIR" cat-file -e "$STRIMR_UPSTREAM_BASE^{commit}" 2>/dev/null; then
  fail "configured upstream base is unavailable in the sibling checkout: $STRIMR_UPSTREAM_BASE"
fi

if ! git -C "$STRIMR_DIR" merge-base --is-ancestor "$STRIMR_UPSTREAM_BASE" "$STRIMR_COMMIT"; then
  fail "configured upstream base $STRIMR_UPSTREAM_BASE is not an ancestor of the pinned commit"
fi

merge_commits="$(git -C "$STRIMR_DIR" rev-list --merges "$STRIMR_UPSTREAM_BASE..$STRIMR_COMMIT")"
if [ -n "$merge_commits" ]; then
  echo "$merge_commits" >&2
  fail "downstream Strimr patch stack contains merge commits; rebase it to a linear stack"
fi

echo "Strimr pairing full checks passed: $STRIMR_BRANCH at exact pin $STRIMR_COMMIT."
