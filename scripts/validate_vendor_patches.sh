#!/bin/bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: ./scripts/validate_vendor_patches.sh [--strict-clean] [--compare-working-tree]

Validation modes:
  --strict-clean           Fail if vendor/strimr has staged/unstaged changes.
  --compare-working-tree   Fail if changed vendor files are not covered by patch files.
EOF
}

STRICT_CLEAN=false
COMPARE_WORKING_TREE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --strict-clean)
            STRICT_CLEAN=true
            ;;
        --compare-working-tree)
            COMPARE_WORKING_TREE=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1"
            usage
            exit 2
            ;;
    esac
    shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

STRIMR_DIR="$REPO_ROOT/vendor/strimr"
PATCH_DIR="$REPO_ROOT/vendor/Patches/strimr"
MANIFEST_PATH="$PATCH_DIR/manifest.yaml"

fail_count=0
warn_count=0

tmp_dir="$(mktemp -d)"
cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

record_fail() {
    echo "❌ $1"
    fail_count=$((fail_count + 1))
}

record_warn() {
    echo "⚠️  $1"
    warn_count=$((warn_count + 1))
}

record_pass() {
    echo "✅ $1"
}

echo "🔎 Validating Strimr vendor patch governance..."

if [[ ! -d "$REPO_ROOT/.git" ]]; then
    record_fail "Repository root not detected at $REPO_ROOT"
fi

if [[ ! -d "$STRIMR_DIR" ]]; then
    record_fail "Missing required path: vendor/strimr"
fi

if [[ ! -d "$PATCH_DIR" ]]; then
    record_fail "Missing required path: vendor/Patches/strimr"
fi

if [[ ! -f "$MANIFEST_PATH" ]]; then
    record_fail "Missing required manifest: vendor/Patches/strimr/manifest.yaml"
fi

if [[ $fail_count -gt 0 ]]; then
    echo "\nValidation failed before deeper checks."
    echo "Next steps: restore required vendor paths and manifest file, then re-run validator."
    exit 1
fi

record_pass "Required paths are present"

if [[ -d "$REPO_ROOT/vendor/Patches/Strimr" && ! "$REPO_ROOT/vendor/Patches/Strimr" -ef "$PATCH_DIR" ]]; then
    record_warn "Legacy path vendor/Patches/Strimr exists; canonical path is vendor/Patches/strimr"
fi
if [[ -d "$REPO_ROOT/vendor/patches/strimr" && ! "$REPO_ROOT/vendor/patches/strimr" -ef "$PATCH_DIR" ]]; then
    record_warn "Legacy path vendor/patches/strimr exists; canonical path is vendor/Patches/strimr"
fi

status_output="$(git -C "$STRIMR_DIR" status --porcelain)"
if [[ -n "$status_output" ]]; then
    echo "ℹ️  vendor/strimr has local changes:"
    echo "$status_output"
    if [[ "$STRICT_CLEAN" == true ]]; then
        record_fail "--strict-clean enabled and vendor/strimr is not clean"
    else
        record_warn "Working tree is dirty (allowed in default mode)"
    fi
else
    record_pass "vendor/strimr working tree is clean"
fi

shopt -s nullglob
patch_files=("$PATCH_DIR"/*.patch)
shopt -u nullglob

if [[ ${#patch_files[@]} -eq 0 ]]; then
    record_fail "No patch files found in vendor/Patches/strimr"
fi

: > "$tmp_dir/patch_names.txt"
: > "$tmp_dir/patch_pairs.tsv"
: > "$tmp_dir/patch_union.txt"

for patch_path in "${patch_files[@]}"; do
    patch_name="$(basename "$patch_path")"
    echo "$patch_name" >> "$tmp_dir/patch_names.txt"

    patch_file_list="$tmp_dir/patch_files_${patch_name}.txt"
    grep '^diff --git a/' "$patch_path" \
        | sed -E 's#^diff --git a/([^ ]+) b/.*#\1#' \
        | LC_ALL=C sort -u > "$patch_file_list"

    if [[ ! -s "$patch_file_list" ]]; then
        record_fail "Patch $patch_name does not contain any diff file entries"
        continue
    fi

    while IFS= read -r changed_file; do
        printf '%s\t%s\n' "$patch_name" "$changed_file" >> "$tmp_dir/patch_pairs.tsv"
        echo "$changed_file" >> "$tmp_dir/patch_union.txt"
    done < "$patch_file_list"
done

LC_ALL=C sort -u "$tmp_dir/patch_names.txt" -o "$tmp_dir/patch_names.txt"
LC_ALL=C sort -u "$tmp_dir/patch_union.txt" -o "$tmp_dir/patch_union.txt"

awk '
function trim(v) {
    gsub(/^[ \t]+|[ \t]+$/, "", v)
    gsub(/^"|"$/, "", v)
    return v
}
function field_value(line) {
    sub(/^[^:]*:[ \t]*/, "", line)
    return trim(line)
}
function emit_entry() {
    if (entry_started == 0) {
        return
    }
    print id "\t" file "\t" intent "\t" upstream_status "\t" upstream_ref "\t" safety_impact "\t" telemetry_impact "\t" applies_to "\t" owner "\t" last_validated > entries_file
}
BEGIN {
    entry_started = 0
    in_patches = 0
    in_files = 0
}
/^patches:[ \t]*$/ {
    in_patches = 1
    next
}
{
    if (in_patches == 0) {
        next
    }

    if ($0 ~ /^  - id:[ \t]*/) {
        emit_entry()
        entry_started = 1
        in_files = 0
        id = field_value($0)
        file = ""
        intent = ""
        upstream_status = ""
        upstream_ref = ""
        safety_impact = ""
        telemetry_impact = ""
        applies_to = ""
        owner = ""
        last_validated = ""
        next
    }

    if (entry_started == 0) {
        next
    }

    if ($0 ~ /^    files:[ \t]*$/) {
        in_files = 1
        next
    }

    if (in_files == 1 && $0 ~ /^      - /) {
        file_path = $0
        sub(/^      - /, "", file_path)
        file_path = trim(file_path)
        print file "\t" file_path > pairs_file
        next
    }

    if (in_files == 1 && $0 !~ /^      - /) {
        in_files = 0
    }

    if ($0 ~ /^    file:[ \t]*/) {
        file = field_value($0)
    } else if ($0 ~ /^    intent:[ \t]*/) {
        intent = field_value($0)
    } else if ($0 ~ /^    upstream_status:[ \t]*/) {
        upstream_status = field_value($0)
    } else if ($0 ~ /^    upstream_ref:[ \t]*/) {
        upstream_ref = field_value($0)
    } else if ($0 ~ /^    safety_impact:[ \t]*/) {
        safety_impact = field_value($0)
    } else if ($0 ~ /^    telemetry_impact:[ \t]*/) {
        telemetry_impact = field_value($0)
    } else if ($0 ~ /^    applies_to:[ \t]*/) {
        applies_to = field_value($0)
    } else if ($0 ~ /^    owner:[ \t]*/) {
        owner = field_value($0)
    } else if ($0 ~ /^    last_validated:[ \t]*/) {
        last_validated = field_value($0)
    }
}
END {
    emit_entry()
}
' entries_file="$tmp_dir/manifest_entries.tsv" pairs_file="$tmp_dir/manifest_pairs.tsv" "$MANIFEST_PATH"

if [[ ! -f "$tmp_dir/manifest_entries.tsv" || ! -s "$tmp_dir/manifest_entries.tsv" ]]; then
    record_fail "Manifest has no parsable patch entries under patches:"
else
    LC_ALL=C sort -u "$tmp_dir/manifest_entries.tsv" -o "$tmp_dir/manifest_entries.tsv"
fi

if [[ ! -f "$tmp_dir/manifest_pairs.tsv" ]]; then
    : > "$tmp_dir/manifest_pairs.tsv"
fi
LC_ALL=C sort -u "$tmp_dir/manifest_pairs.tsv" -o "$tmp_dir/manifest_pairs.tsv"

cut -f2 "$tmp_dir/manifest_entries.tsv" | LC_ALL=C sort -u > "$tmp_dir/manifest_names.txt"
cut -f2 "$tmp_dir/manifest_pairs.tsv" | LC_ALL=C sort -u > "$tmp_dir/manifest_union.txt"

required_entry_failures=0
while IFS=$'\t' read -r id file intent upstream_status upstream_ref safety_impact telemetry_impact applies_to owner last_validated; do
    missing_fields=""
    [[ -n "$id" ]] || missing_fields="$missing_fields id"
    [[ -n "$file" ]] || missing_fields="$missing_fields file"
    [[ -n "$intent" ]] || missing_fields="$missing_fields intent"
    [[ -n "$upstream_status" ]] || missing_fields="$missing_fields upstream_status"
    [[ -n "$upstream_ref" ]] || missing_fields="$missing_fields upstream_ref"
    [[ -n "$safety_impact" ]] || missing_fields="$missing_fields safety_impact"
    [[ -n "$telemetry_impact" ]] || missing_fields="$missing_fields telemetry_impact"
    [[ -n "$applies_to" ]] || missing_fields="$missing_fields applies_to"
    [[ -n "$owner" ]] || missing_fields="$missing_fields owner"
    [[ -n "$last_validated" ]] || missing_fields="$missing_fields last_validated"

    file_pair_count="$(awk -F '\t' -v patch_file="$file" '$1 == patch_file { c++ } END { print c + 0 }' "$tmp_dir/manifest_pairs.tsv")"
    if [[ "$file_pair_count" -eq 0 ]]; then
        missing_fields="$missing_fields files"
    fi

    if [[ -n "$missing_fields" ]]; then
        required_entry_failures=$((required_entry_failures + 1))
        record_fail "Manifest entry for $file is missing required fields:$missing_fields"
        continue
    fi

    case "$upstream_status" in
        local-only|candidate-upstream|needs-split)
            ;;
        *)
            required_entry_failures=$((required_entry_failures + 1))
            record_fail "Manifest entry for $file has invalid upstream_status: $upstream_status"
            ;;
    esac

    case "$safety_impact" in
        low|medium|high)
            ;;
        *)
            required_entry_failures=$((required_entry_failures + 1))
            record_fail "Manifest entry for $file has invalid safety_impact: $safety_impact"
            ;;
    esac

    if [[ "$telemetry_impact" != "none" ]]; then
        required_entry_failures=$((required_entry_failures + 1))
        record_fail "Manifest entry for $file must set telemetry_impact to none (found: $telemetry_impact)"
    fi
done < "$tmp_dir/manifest_entries.tsv"

if [[ "$required_entry_failures" -eq 0 ]]; then
    record_pass "Manifest entries include required governance metadata"
fi

comm -23 "$tmp_dir/patch_names.txt" "$tmp_dir/manifest_names.txt" > "$tmp_dir/missing_manifest_entries.txt"
comm -13 "$tmp_dir/patch_names.txt" "$tmp_dir/manifest_names.txt" > "$tmp_dir/orphan_manifest_entries.txt"

if [[ -s "$tmp_dir/missing_manifest_entries.txt" ]]; then
    record_fail "Patch files without manifest entries: $(paste -sd ', ' "$tmp_dir/missing_manifest_entries.txt")"
fi
if [[ -s "$tmp_dir/orphan_manifest_entries.txt" ]]; then
    record_fail "Manifest entries without patch files: $(paste -sd ', ' "$tmp_dir/orphan_manifest_entries.txt")"
fi
if [[ ! -s "$tmp_dir/missing_manifest_entries.txt" && ! -s "$tmp_dir/orphan_manifest_entries.txt" ]]; then
    record_pass "Patch file list matches manifest entries"
fi

comm -23 "$tmp_dir/patch_union.txt" "$tmp_dir/manifest_union.txt" > "$tmp_dir/unlisted_in_manifest.txt"
comm -13 "$tmp_dir/patch_union.txt" "$tmp_dir/manifest_union.txt" > "$tmp_dir/unlisted_in_patches.txt"

if [[ -s "$tmp_dir/unlisted_in_manifest.txt" ]]; then
    record_fail "Files present in patches but absent from manifest coverage"
    sed 's/^/   - /' "$tmp_dir/unlisted_in_manifest.txt"
fi
if [[ -s "$tmp_dir/unlisted_in_patches.txt" ]]; then
    record_fail "Files present in manifest but absent from patch coverage"
    sed 's/^/   - /' "$tmp_dir/unlisted_in_patches.txt"
fi
if [[ ! -s "$tmp_dir/unlisted_in_manifest.txt" && ! -s "$tmp_dir/unlisted_in_patches.txt" ]]; then
    record_pass "Patch file coverage matches manifest coverage"
fi

while IFS= read -r patch_name; do
    patch_tmp="$tmp_dir/patch_only_${patch_name}.txt"
    manifest_tmp="$tmp_dir/manifest_only_${patch_name}.txt"

    awk -F '\t' -v patch="$patch_name" '$1 == patch { print $2 }' "$tmp_dir/patch_pairs.tsv" | LC_ALL=C sort -u > "$patch_tmp"
    awk -F '\t' -v patch="$patch_name" '$1 == patch { print $2 }' "$tmp_dir/manifest_pairs.tsv" | LC_ALL=C sort -u > "$manifest_tmp"

    if ! cmp -s "$patch_tmp" "$manifest_tmp"; then
        record_fail "Per-patch file list mismatch for $patch_name"
        diff -u "$manifest_tmp" "$patch_tmp" | sed 's/^/   /' || true
    fi
done < "$tmp_dir/patch_names.txt"

if [[ "$COMPARE_WORKING_TREE" == true ]]; then
    working_tree_paths="$tmp_dir/working_tree_paths.txt"
    {
        git -C "$STRIMR_DIR" diff --name-only
        git -C "$STRIMR_DIR" diff --name-only --cached
    } | LC_ALL=C sort -u > "$working_tree_paths"

    if [[ -s "$working_tree_paths" ]]; then
        comm -23 "$working_tree_paths" "$tmp_dir/patch_union.txt" > "$tmp_dir/uncovered_working_tree.txt"
        if [[ -s "$tmp_dir/uncovered_working_tree.txt" ]]; then
            record_fail "Working-tree changes are not covered by patch files"
            sed 's/^/   - /' "$tmp_dir/uncovered_working_tree.txt"
        else
            record_pass "Working-tree changes are covered by patch files"
        fi
    else
        record_pass "No working-tree diffs to compare"
    fi
fi

echo ""
if [[ $fail_count -eq 0 ]]; then
    echo "✅ Validation PASSED (warnings: $warn_count)"
    echo "Next steps: run ./scripts/apply_vendor_patches.sh (or --strict) after updating patches/manifest as needed."
    exit 0
fi

echo "❌ Validation FAILED (failures: $fail_count, warnings: $warn_count)"
echo "Next steps:"
echo "  1) Reconcile vendor/Patches/strimr/*.patch with vendor/Patches/strimr/manifest.yaml."
echo "  2) Re-run ./scripts/validate_vendor_patches.sh (add --strict-clean --compare-working-tree for strict mode)."
exit 1
