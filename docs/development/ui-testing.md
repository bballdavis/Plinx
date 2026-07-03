# UI Testing Strategy

## Approach

Plinx uses layered UI verification:

| Layer | Tool | Scope |
|---|---|---|
| Logic | Swift Testing | Pure layout rules and content-type decisions |
| Component rendering | SnapshotTesting | Pixel-diff rendering for reusable UI across devices |
| Critical user paths | XCUITest | Navigation, launch, branding, and flow verification |
| Live smoke | XCUITest with live Plex data | Real-data rendering checks |

## Package Test Structure

```text
Packages/
  PlinxCore/Tests/PlinxCoreTests/
  PlinxUI/Tests/PlinxUITests/
```

`PlinxUI` tests are organized into:

```text
Tests/PlinxUITests/
├── Fixtures/
├── Logic/
├── Snapshots/
├── PlinxUITests.swift
└── SnapshotHarnessTests.swift
```

## What We Verify

### Logic tests

- aspect ratios for portrait vs landscape content
- card width/layout rules
- progress-bar visibility and clamping assumptions
- fixture integrity before snapshot runs

### Snapshot tests

- movie, TV, clip, and continue-watching cards
- section-row layouts
- placeholder states
- truncation behavior
- device-specific regressions on compact and regular widths

### App UI tests

- launch
- branding surfaces
- tab/navigation behavior
- library browsing
- quick actions
- targeted smoke behavior

### tvOS focus rules

- every primary tvOS action must be reachable with remote UDLR navigation
- do not rely on touch, pointer, or click-only interactions on Apple TV
- keep retry and refresh affordances focusable when they are part of the recovery path
- verify the default focus path for any screen that has a single primary action

### Live smoke checks

- live home content renders expected sections
- Other Videos content keeps landscape geometry
- Movies/TV content keeps portrait geometry
- section types remain visually distinct

## Device Coverage

Snapshot/device coverage intentionally spans:

- compact iPhone width
- standard iPhone width
- large iPad width

This catches regressions that only appear at one size class.

## Common Commands

```bash
./scripts/ui_tests.sh --core
./scripts/ui_tests.sh --ui
./scripts/ui_tests.sh --snapshots
./scripts/ui_tests.sh --record
./scripts/ui_tests.sh --live
```

## Re-Recording Snapshots

Use recording mode only when a visual change is intentional:

```bash
./scripts/ui_tests.sh --record
```

Review the generated images before committing them.

## What Is Intentionally Out Of Scope

- generic network/server correctness beyond the mocked test boundary
- MPVKit internals
- complete live-service coverage in CI

Use live parity tests and manual verification when a change crosses those boundaries.
