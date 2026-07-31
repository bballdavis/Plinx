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
- deterministic visual-audit surfaces through `PLINX_UI_TEST_SCREEN`

### Visual-audit fixtures

`VisualAuditUITests` captures real Plinx views without changing normal app
startup. The following `PLINX_UI_TEST_SCREEN` values are available only when
the app also receives `--ui-testing`:

- `signIn`
- `parentalGate`
- `settings`
- `profileSwitcher`
- `selectServer`
- `playerSettings`
- `downloadsGrid`
- `loadingGallery`
- `homeLoading`
- `playerBuffering`
- `refreshLoading`
- `appStoreMediaDetail`

Keep these routes deterministic and free of credentials or personal data.
When a visual-audit route needs account-backed content, capture loading or
empty states unless the test explicitly opts into the existing live-test mode.
On tvOS, the `signIn` route must not request or render a live Plex link QR
code. It renders a deterministic, credential-free preview QR payload so the
plate, hierarchy, and initial Refresh Code focus state can be captured without
network access.

`loadingGallery` renders the compact inline, regular glass, and hero video
variants together. `playerBuffering` renders the actual Plinx-owned video
overlay against a deterministic colorful frame. Branding UI tests assert that
these fixtures contain the expected Plinx accessibility identifiers and no
native activity indicator.
`homeLoading` renders the production full-screen hero identity: the existing
animated rounded-square beacon at hero scale, with the full-color loop centered
inside, the outlined white wordmark beneath it, and no visible loading caption.
`refreshLoading` provides a deterministic pull-to-refresh surface for visual
inspection of the branded refresh indicator and hidden native spinner.

The App Store and documentation inventory is captured by
`scripts/capture_app_store_screenshots.sh`. A localhost fixture service returns
fictional Plex and Youtarr data plus original abstract artwork, while the app
renders its production views and behavior. The only screenshot-specific
production-view harness is `appStoreMediaDetail`, which supplies the selected
fixture item to the real media-detail view model. The loading capture uses
`homeLoading`; all other captures use normal production routes or live fixture
loading. Keep the fixture service credential-free and capped at PG/TV-PG.

### tvOS focus rules

- every primary tvOS action must be reachable with remote UDLR navigation
- do not rely on touch, pointer, or click-only interactions on Apple TV
- keep retry and refresh affordances focusable when they are part of the recovery path
- verify the default focus path for any screen that has a single primary action
- on Home and Library, pressing up from the first content row must return focus to the visible `Home` button in the header instead of trapping focus in content
- pressing down from the header must return to the first available object below it: the first Home card, first Library tile, or the selected library-detail filter before the first media card
- empty and loading states must leave focus in the header until a real destination exists; content arrival must not steal focus
- the tvOS parental gate Select action enters the focused digit and never submits or dismisses the gate; only the explicit Unlock action submits
- `AppleTVInteractionUITests` sends real Siri Remote UDLR and Select events
  through deterministic, network-free browse fixtures. Navigation changes must
  assert the exact focused accessibility identifier for Home, Library root,
  empty content, and Library detail.

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
- AetherEngine internals
- complete live-service coverage in CI

Use live parity tests and manual verification when a change crosses those boundaries.
