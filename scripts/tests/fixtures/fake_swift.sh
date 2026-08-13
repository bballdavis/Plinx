#!/bin/bash
set -euo pipefail

case "$*" in
  *Packages/PlinxCore*)
    echo "fake PlinxCore tests executed"
    exit "${PLINX_FAKE_CORE_STATUS:-0}"
    ;;
  *Packages/PlinxUI*)
    echo "fake PlinxUI tests executed"
    exit "${PLINX_FAKE_UI_STATUS:-0}"
    ;;
  *)
    echo "unexpected fake Swift invocation" >&2
    exit 64
    ;;
esac
