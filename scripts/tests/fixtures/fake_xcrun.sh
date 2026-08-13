#!/bin/bash
set -euo pipefail

if [[ "$*" == "simctl list devices available" ]]; then
  cat <<'DEVICES'
== Devices ==
-- iOS 26.5 --
    iPhone 17 Pro Max (11111111-1111-1111-1111-111111111111) (Shutdown)
    iPad (10th generation) (22222222-2222-2222-2222-222222222222) (Shutdown)
DEVICES
  exit 0
fi

echo "unexpected fake xcrun invocation: $*" >&2
exit 64
