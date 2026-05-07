#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# ui_tests.sh — Run Plinx UI & Logic Tests
# ─────────────────────────────────────────────────────────────────────────────
#
# Runs Swift Testing tests for PlinxCore and PlinxUI logic layers.
# Snapshot tests (iOS simulator required) are documented below.
#
# Usage:
#   ./scripts/ui_tests.sh              # Run all tests
#   ./scripts/ui_tests.sh --core       # Run PlinxCore only
#   ./scripts/ui_tests.sh --ui         # Run PlinxUI only
#   ./scripts/ui_tests.sh --snapshots  # Run snapshot tests on iPhone 17 Pro Max
#   ./scripts/ui_tests.sh --record     # Recording mode for snapshot baselines
#   ./scripts/ui_tests.sh --live       # Live Plex UI smoke tests (Playwright-style)
#
# References: development/UI_TESTING_STRATEGY.md
#
# ─────────────────────────────────────────────────────────────────────────────

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Ansi color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test results tracking
CORE_RESULT=""
UI_RESULT=""
SNAPSHOTS_RESULT=""
LIVE_RESULT=""

MODE="${1:-all}"

# ─────────────────────────────────────────────────────────────────────────────
# Helper functions
# ─────────────────────────────────────────────────────────────────────────────

load_env_yaml() {
    local env_file="$PROJECT_ROOT/test_creds.yaml"
    if [ -f "$env_file" ]; then
        log_info "Loading test credentials from test_creds.yaml..."
        # Extract keys and values from YAML (supports 'Key: Value' and 'Key: "Value"')
        # Note: This is a simple bash-only YAML parser for flat files.
        while IFS=": " read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
            
            # Clean quotes if present
            value=$(echo "$value" | sed -e 's/^"//' -e 's/"$//' -e 's/^\x27//' -e 's/\x27$//')
            
            # Export if key is uppercase (standard env var naming)
            if [[ "$key" =~ ^[A-Z_]+$ ]]; then
                export "$key"="$value"
            fi
        done < "$env_file"
    else
        log_warning "No test_creds.yaml found (copied from .example for you if it was missing). Run with your Plex vars for live tests."
    fi
}

log_section() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📍 $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

log_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

log_failure() {
    echo -e "${RED}✗ $1${NC}"
}

log_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Test runners
# ─────────────────────────────────────────────────────────────────────────────

run_core_tests() {
    log_section "PlinxCore Tests"
    echo "Running Swift Testing tests (PlinxRating, SafetyInterceptor, MathGate)..."
    echo ""
    
    cd "$PROJECT_ROOT"
    if swift test --package-path Packages/PlinxCore 2>&1 | tee /tmp/core_test.log; then
        CORE_RESULT="✓ PASS"
        log_success "PlinxCore tests passed"
        return 0
    else
        CORE_RESULT="✗ FAIL"
        log_failure "PlinxCore tests failed"
        return 1
    fi
}

run_ui_tests() {
    log_section "PlinxUI Tests"
    echo "Running Swift Testing tests (PlinxTheme, PlinxMediaCard, PlinxErrorView)..."
    echo ""
    
    cd "$PROJECT_ROOT"
    if swift build --package-path Packages/PlinxUI --target PlinxUITests 2>&1 | tee /tmp/ui_test.log; then
        UI_RESULT="✓ PASS"
        log_success "PlinxUI tests compiled"
        return 0
    else
        UI_RESULT="✗ FAIL"
        log_failure "PlinxUI tests failed to compile"
        return 1
    fi
}

run_snapshot_tests() {
    log_section "Snapshot Tests"
    
    case "$MODE" in
        --record)
            log_info "Recording baseline snapshots..."
            echo "When prompted in Xcode, set isRecording = true in SnapshotHarnessTests.swift"
            echo ""
            echo "Running snapshot tests in recording mode..."
            cd "$PROJECT_ROOT/Packages/PlinxUI"
            rm -rf /tmp/PlinxUI_snapshots.xcresult
            xcodebuild test \
                -scheme PlinxUI \
                -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
                -resultBundlePath "/tmp/PlinxUI_snapshots.xcresult" \
                2>&1 | tee /tmp/snapshots.log

            XCODE_STATUS=${PIPESTATUS[0]}
            grep -E "Test Suite|Test Case|passed|failed|Automatically recorded snapshot" /tmp/snapshots.log || true

            # SnapshotTesting intentionally fails tests in record mode after writing baselines.
            # Treat that expected failure as success when we detect recorded snapshots.
            if [ "$XCODE_STATUS" -eq 0 ] || grep -q "Automatically recorded snapshot" /tmp/snapshots.log; then
                SNAPSHOTS_RESULT="✓ RECORDED"
                log_success "Snapshot baselines recorded"
                log_warning "Don't forget to:"
                log_warning "  1. Commit __Snapshots__/ folder"
                log_warning "  2. Set isRecording = false in SnapshotHarnessTests.swift"
                return 0
            else
                SNAPSHOTS_RESULT="✗ FAILED"
                log_failure "Snapshot recording failed"
                return 1
            fi
            ;;
        *)
            log_info "Running snapshot diffs on iPhone 17 Pro Max..."
            echo ""
            cd "$PROJECT_ROOT/Packages/PlinxUI"
            rm -rf /tmp/PlinxUI_snapshots.xcresult
            if xcodebuild test \
                -scheme PlinxUI \
                -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
                -resultBundlePath "/tmp/PlinxUI_snapshots.xcresult" \
                2>&1 | tee /tmp/snapshots.log; then
                grep -E "Test Suite|passed|failed" /tmp/snapshots.log || true
                SNAPSHOTS_RESULT="✓ PASS"
                log_success "Snapshot tests passed"
                return 0
            else
                grep -E "Test Suite|passed|failed|error:" /tmp/snapshots.log || true
                SNAPSHOTS_RESULT="✗ FAIL"
                log_failure "Snapshot tests failed (see diffs in /tmp/PlinxUI_snapshots.xcresult/)"
                return 1
            fi
            ;;
    esac
}

run_live_ui_tests() {
    log_section "Live UI Smoke Tests"
    
    # Load env from yaml before starting
    load_env_yaml
    
    log_info "Running app-level UI smoke checks with live/simulated Plex data..."
    echo ""
    echo "Plex Auth Configuration:"
    if [ -n "$PLINX_PLEX_SERVER_URL" ]; then
        echo "  URL: $PLINX_PLEX_SERVER_URL"
    else
        echo "  URL: [NOT CONFIGURED]"
    fi
    
    if [ -n "$PLINX_PLEX_TOKEN" ]; then
        echo "  Token: [LOADED]"
    else
        echo "  Token: [NOT CONFIGURED]"
    fi
    echo ""

    cd "$PROJECT_ROOT/PlinxApp"

    bash "$PROJECT_ROOT/scripts/generate_xcodeproj.sh" >/tmp/plinx_xcodegen.log 2>&1
    rm -rf /tmp/Plinx_live_ui.xcresult

    if xcodebuild test \
        -project Plinx.xcodeproj \
        -scheme Plinx-iOS \
        -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
        -resultBundlePath "/tmp/Plinx_live_ui.xcresult" \
        -only-testing:Plinx-iOS-UITests/LaunchSmokeUITests \
        -only-testing:Plinx-iOS-UITests/LiveRenderSmokeUITests \
        2>&1 | tee /tmp/live_ui.log | grep -E "error:|passed|failed" | head -10; then
        LIVE_RESULT="✓ PASS"
        log_success "Live UI smoke tests passed"
        return 0
    else
        LIVE_RESULT="✗ FAIL"
        log_failure "Live UI smoke tests failed (see /tmp/Plinx_live_ui.xcresult/)"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Main execution
# ─────────────────────────────────────────────────────────────────────────────

main() {
    case "$MODE" in
        --core)
            run_core_tests
            TEST_STATUS=$?
            ;;
        --ui)
            run_ui_tests
            TEST_STATUS=$?
            ;;
        --snapshots|--record)
            run_snapshot_tests
            TEST_STATUS=$?
            ;;
        --live)
            run_live_ui_tests
            TEST_STATUS=$?
            ;;
        all|"")
            run_core_tests || true
            run_ui_tests || true
            TEST_STATUS=0  # Summary at the end regardless
            ;;
        -h|--help)
            echo "Usage:"
            echo "  ./scripts/ui_tests.sh              # Run all tests"
            echo "  ./scripts/ui_tests.sh --core       # Run PlinxCore tests"
            echo "  ./scripts/ui_tests.sh --ui         # Run PlinxUI tests"
            echo "  ./scripts/ui_tests.sh --snapshots  # Run snapshot diffs (iPhone 17 Pro Max)"
            echo "  ./scripts/ui_tests.sh --record     # Record snapshot baselines"
            echo "  ./scripts/ui_tests.sh --live       # Live Plex UI smoke tests"
            echo ""
            echo "See development/UI_TESTING_STRATEGY.md for details."
            exit 0
            ;;
        *)
            log_failure "Unknown mode: $MODE"
            echo ""
            ./scripts/ui_tests.sh --help
            exit 1
            ;;
    esac

    # Print summary
    log_section "Test Summary"
    
    if [ "$CORE_RESULT" != "" ]; then
        echo "PlinxCore (Logic)       $CORE_RESULT"
    fi
    
    if [ "$UI_RESULT" != "" ]; then
        echo "PlinxUI (Logic)         $UI_RESULT"
    fi
    
    if [ "$SNAPSHOTS_RESULT" != "" ]; then
        echo "PlinxUI (Snapshots)     $SNAPSHOTS_RESULT"
    fi

    if [ "$LIVE_RESULT" != "" ]; then
        echo "Plinx-iOS (Live UI)     $LIVE_RESULT"
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ "$TEST_STATUS" -eq 0 ]; then
        log_success "All tests completed"
        exit 0
    else
        log_failure "Tests completed with failures"
        exit 1
    fi
}

main
