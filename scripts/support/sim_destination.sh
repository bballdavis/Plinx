#!/bin/bash

# Chooses a simulator destination that matches the requested device as closely
# as possible.

select_simulator_destination() {
    local requested_name="$1"
    local sim_platform="${2:-iOS}"  # iOS or tvOS
    local available_devices
    local selected_line
    local family_pattern=""
    local runtime_version=""
    local line=""

    SIM_UDID=""
    SIM_NAME=""
    SIM_STATUS=""
    SIM_OS_VERSION=""
    SIM_BUILD_DESTINATION=""
    SIM_DESTINATION=""

    if [ "$requested_name" = "generic" ]; then
        SIM_DESTINATION="generic/platform=${sim_platform} Simulator"
        return 0
    fi

    if ! available_devices=$(xcrun simctl list devices available 2>/dev/null); then
        return 1
    fi

    if printf '%s' "$requested_name" | grep -Eq '^[0-9A-Fa-f-]{36}$'; then
        selected_line=$(printf '%s\n' "$available_devices" | grep -F "$requested_name" | head -1 || true)
    else
        selected_line=$(printf '%s\n' "$available_devices" | grep -F "$requested_name" | head -1 || true)
    fi

    if [ -z "$selected_line" ]; then
        case "$requested_name" in
            *iPad*) family_pattern="iPad" ;;
            *iPhone*) family_pattern="iPhone" ;;
            *"Apple TV"*|*AppleTV*) family_pattern="Apple TV" ;;
        esac

        if [ -n "$family_pattern" ]; then
            selected_line=$(printf '%s\n' "$available_devices" | awk -v family="$family_pattern" 'index($0, family) && /Booted/ { print; exit }')
            if [ -z "$selected_line" ]; then
                selected_line=$(printf '%s\n' "$available_devices" | awk -v family="$family_pattern" 'index($0, family) { print; exit }')
            fi
        fi
    fi

    if [ -z "$selected_line" ]; then
        return 1
    fi

    local selected_trimmed
    local current_runtime=""
    local trimmed_line=""
    runtime_version=""
    selected_trimmed=$(printf '%s' "$selected_line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
    while IFS= read -r line; do
        trimmed_line=$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')

        case "$trimmed_line" in
            "-- ${sim_platform} "*)
                current_runtime=${trimmed_line#-- ${sim_platform} }
                current_runtime=${current_runtime% --}
                ;;
            *)
                if [ "$trimmed_line" = "$selected_trimmed" ]; then
                    runtime_version="$current_runtime"
                    break
                fi
                ;;
        esac
    done <<< "$available_devices"

    SIM_UDID=$(printf '%s' "$selected_trimmed" | grep -oE '[A-F0-9-]{36}' | head -1)
    SIM_STATUS=$(printf '%s' "$selected_line" | grep -oE '\((Booted|Shutdown)\)' | tr -d '()' | head -1)
    SIM_NAME=$(printf '%s' "$selected_trimmed" | sed -E 's/[[:space:]]+\([A-F0-9-]{36}\)[[:space:]]+\((Booted|Shutdown)\)$//')
    SIM_OS_VERSION="$runtime_version"
    if [ -n "$SIM_OS_VERSION" ]; then
        SIM_BUILD_DESTINATION="platform=${sim_platform} Simulator,OS=$SIM_OS_VERSION,name=$SIM_NAME"
    else
        SIM_BUILD_DESTINATION="platform=${sim_platform} Simulator,name=$SIM_NAME"
    fi
    SIM_DESTINATION="$SIM_BUILD_DESTINATION"
}