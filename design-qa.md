# Option 3 Guided Portal — Design QA

**Comparison target**

- Source visual truth: `<local capture path omitted>`
- Rendered implementation: `<local capture path omitted>`
- Normalized implementation: `<local capture path omitted>`
- Full-view comparison: `<local capture path omitted>`
- Viewport: compact iPhone, 390 × 844 points, portrait
- Pixels and normalization: source 390 × 844 px; simulator capture 1170 × 2532 px at 3×; implementation downsampled to 390 × 844 px before comparison; comparison canvas 780 × 844 px
- State: signed out, idle, default green accent, standard Dynamic Type, no customer data or credentials

**Findings**

- No actionable P0, P1, or P2 differences remain.
- The native status bar moves the implementation portal down slightly relative to the concept, which intentionally omitted device chrome. The portal proportions, hierarchy, logo, grown-up cue, title, next-step copy, and primary-action location remain equivalent after accounting for that chrome.
- The production CTA is intentionally a little darker than the generated concept. Its accent-aware outline and glow preserve the concept's depth while keeping white text and the Plex icon readable across accent choices.

**Required Fidelity Surfaces**

- Fonts and typography: the production screen uses rounded system typography with matching bold display hierarchy, semibold badge text, centered wrapping, and a restrained body weight. The title wraps at the same semantic break as the source. Badge and CTA text cap at Accessibility 1 while the screen itself remains scrollable at larger sizes.
- Spacing and layout rhythm: the portal width, continuous corner radius, logo placement, badge-to-title rhythm, and bottom action zone align closely with the source. The iPad implementation remains centered and width-constrained in code.
- Colors and visual tokens: the dark shell, lime-to-teal portal gradient, pale green grown-up cue, white display text, mint supporting copy, and dark teal CTA are all retained. Interactive emphasis uses the selected Plinx accent without replacing the foundational portal palette.
- Image quality and asset fidelity: the implementation uses the real full-color Plinx brand asset. The Plex/account and safety marks use native SF Symbols rather than improvised shapes. The logo remains sharp and correctly proportioned in the simulator capture.
- Copy and content: “Grown-up step,” “Connect your Plex library,” “You’ll choose a kid profile next.,” and “Continue with Plex” match the selected direction and clearly separate the parent authentication step from the upcoming kid-profile step.

**Focused Region Evidence**

- No additional crop was needed. At 390 × 844 normalization, the logo edges, badge icon and label, display typography, supporting copy, CTA icon, border, glow, and corner geometry are all legible in the 780 × 844 side-by-side comparison.

**Comparison History**

1. Pass 1 found P1 rectangular overlay drift and P2 hierarchy/spacing drift. The implementation was rebuilt as one continuous-corner portal with a dark shell and a dedicated grown-up cue.
2. Pass 2 found P2 geometry and primary-action placement differences. Portal width, internal spacing, logo scale, and bottom action anchoring were adjusted; the revised simulator capture aligned those regions with the source.
3. Pass 3 found P2 CTA depth and emphasis drift. A dark teal gradient, accent-aware stroke, inner highlight, and restrained glow were added. The final comparison shows the intended oversized, high-contrast primary action without overpowering the portal.
4. The final comparison found no actionable P0/P1/P2 differences.

**Interaction and Accessibility Checks**

- The existing Plex authentication action remains wired to `startSignIn()`; only presentation changed.
- A deterministic UI test confirms the primary action exists and remains hittable, scrolling the sign-in surface when needed.
- A large accessibility text capture confirmed that the portal expands and scrolls rather than clipping. The badge and action-label caps were added afterward to protect their shape and reachability.
- A yellow-accent capture confirmed the action keeps a dark base and readable white foreground under a high-risk alternate accent.
- VoiceOver order, measured contrast, Reduce Motion behavior, and physical-device keyboard interaction remain runtime verification items rather than compliance claims.

**Open Questions / Evidence Limits**

- A fresh post-build iPad screenshot could not be accepted because the newly installed iOS runtimes became stuck on the simulator's one-time “Waiting on System App” migration screen. This does not affect the matched iPhone source target or the successful universal iOS build, but iPad portrait/landscape visual acceptance should be repeated once Simulator finishes migration.
- The last code-only adjustment caps badge and CTA Dynamic Type at Accessibility 1; it does not change the standard-size implementation used in the final visual comparison.

**Implementation Checklist**

- [x] Match the selected Option 3 sign-in hierarchy and composition.
- [x] Use real Plinx brand assets and current color semantics.
- [x] Preserve the production Plex authentication action.
- [x] Keep the primary action large, readable, and reachable.
- [x] Add localized copy, deterministic UI assertions, and branding guidance.
- [ ] Repeat iPad portrait/landscape captures after the simulator migration completes.

**Follow-up Polish**

- P3: verify the exact portal width and vertical breathing room on a fresh 13-inch iPad portrait and landscape capture.
- P3: run VoiceOver, contrast measurement, and Reduce Motion checks on physical hardware before release.

## tvOS Extension

**Comparison target**

- Platform source capture: `<local capture path omitted>`
- Option 3 style truth: `<local capture path omitted>`
- Rendered implementation: `<local capture path omitted>`
- Full-view comparison: `<local capture path omitted>`
- Viewport: Apple TV 1080p, 1920 × 1080 points/pixels, 1×, no density normalization
- State: signed out, UI-test fixture, deterministic non-authentication QR payload, default green accent, Refresh Code initially focused, no credentials or customer data

**Findings**

- No actionable P0, P1, or P2 differences remain.
- The tvOS adaptation intentionally changes the source iPhone portal from a vertical composition into a wide living-room composition. The logo, grown-up cue, connection title, next-step copy, foundational gradient, and dark shell remain visually continuous with Option 3.
- Compared with the previous tvOS surface, the hierarchy is clearer, the QR code is more prominent, and the focused action is visible without relying on the platform's subtle default focus treatment.

**Required Fidelity Surfaces**

- Fonts and typography: rounded system display and body faces preserve the Option 3 hierarchy at couch-readable sizes. The title remains on one line at 1080p, supporting copy is clearly separated, and no text truncates.
- Spacing and layout rhythm: the single wide portal stays inside the tvOS overscan-safe area. The logo is centered inside the portal, the QR and instruction columns have a stable 64-point relationship, and the status/action stack no longer collides after the second pass.
- Colors and visual tokens: the dark shell, lime-to-teal portal, pale green badge, mint next-step copy, white foregrounds, and dark teal action all map to the selected direction. The focused action uses a white outline plus restrained accent glow so high-risk accent colors cannot replace the contrast-bearing dark base.
- Image quality and asset fidelity: the real full-color Plinx logo is crisp at 1080p. The QR code is generated at integer scale with no interpolation, and SF Symbols supply the shield and refresh icons.
- Copy and content: the screen now explains that Plex connection is a grown-up step and that kid-profile selection follows. The QR instruction remains direct, while the refresh/status language preserves the existing authentication model.
- States and interaction: Refresh Code is the only focusable action in this state and receives initial focus. Its outline, scale, and glow are contained inside the portal; the production action still cancels the current attempt and requests a new Plex code.

**Focused Region Evidence**

- No extra crop was required. The 1920 × 1080 implementation capture is sharp enough to inspect logo edges, QR modules, badge/icon alignment, text wrapping, portal stroke, and the complete focused control. The 3840 × 1080 side-by-side comparison preserves both full-resolution surfaces.

**Comparison History**

1. tvOS pass 1 removed the P1 old-system/Strimr visual drift by moving the complete QR flow into one Option 3 portal on a dark shell and adding the grown-up hierarchy.
2. tvOS pass 1 also exposed a P2 spacing issue: the focused Refresh Code treatment crowded the “Waiting for Plex” label. The status/action gap was increased and focus scale reduced from 1.045 to 1.025.
3. The verified pass shows clear separation between status and action, an overscan-safe focus halo, no clipping, and no remaining actionable P0/P1/P2 findings.

**tvOS Evidence Limits**

- The deterministic fixture verifies initial focus presentation and containment without making a network request. Remote activation would intentionally start a live Plex PIN request and was not invoked for the credential-free capture.
- VoiceOver speech order, physical Siri Remote navigation, measured contrast, and Reduce Motion remain physical-runtime checks rather than compliance claims.

**tvOS Implementation Checklist**

- [x] Carry Option 3's visual language into a 1080p, remote-first layout.
- [x] Preserve automatic production sign-in and manual refresh behavior.
- [x] Keep Refresh Code initially focused with an explicit visible state.
- [x] Keep the portal and focus halo inside the tvOS safe area.
- [x] Add a deterministic, credential-free QR preview for UI-test captures.
- [x] Update branding and UI-testing documentation.

## tvOS Refresh Action and Rhythm Cleanup

**Comparison target**

- Fresh pre-change evidence: `<local capture path omitted>`
- Final implementation: `<local capture path omitted>`
- Full-view comparison: `<local capture path omitted>`
- Focused comparison: `<local capture path omitted>`
- Viewport: Apple TV 1080p, 1920 × 1080 points/pixels, 1×
- State: signed out, deterministic UI-test fixture, default green accent, Refresh Code initially focused, no credentials or customer data

**Audit findings**

- P1 interaction styling: the previous SwiftUI `Button` retained a large platform focus plate. Its pale slab extended well beyond the dark-teal control, competed with the QR code and title, and looked like system fallback UI rather than Plinx.
- P2 layout and typography: a flexible spacer split the instruction column into a top copy cluster and a bottom status/action cluster. The resulting dead space weakened reading order and made the status and button appear detached.
- P2 alignment: the previous action expanded across nearly the full instruction column and began left of the copy alignment line. This made the text column feel optically unstable even though the individual labels were technically left aligned.

**Implemented resolution**

- Replaced the platform-styled button wrapper with a focusable, accessibility-button-trait Plinx surface that retains remote activation while disabling the native focus plate.
- Grouped “Waiting for Plex” and Refresh Code directly beneath the supporting copy with a deliberate 32-point section break and 14-point internal gap.
- Constrained the action to 560 × 82 points, aligned it to the copy column, and preserved a large couch-readable target.
- Kept a dark-teal gradient base, accent edge, inset white focus ring, 1.018 focus scale, and short accent halo. Focus remains unmistakable without producing a second floating card.
- Preserved the generated QR, real Plinx logo, SF Symbol refresh icon, localization, production refresh action, and credential-free fixture behavior.

**Final comparison**

- Fonts and typography: title, body, supporting copy, status, and action now read as one continuous top-to-bottom sequence. No text truncates or collides.
- Spacing and layout: the QR plate and complete instruction stack share a balanced vertical center. The action aligns to the instruction column, and the portal retains ample overscan-safe breathing room.
- Colors and surfaces: the action now uses the same dark-teal/accent/white vocabulary as the rest of the Option 3 portal. The large translucent system plate is gone.
- Icons and assets: the real Plinx logo and generated QR remain sharp; the shield and refresh SF Symbols stay optically aligned with their labels.
- Focus and accessibility: the final screenshot confirms the custom white ring and restrained halo are visible at 1080p. The surface remains focusable for activation and exposes the button trait and existing accessibility identifier.
- No actionable P0, P1, or P2 visual differences remain in the focused idle state.

**Evidence limits**

- The simulator capture verifies the initial focused state and containment. Physical Siri Remote activation, VoiceOver speech order, measured contrast, alternate accent colors, and Reduce Motion remain runtime checks rather than compliance claims.

final result: passed

# Plinx Loop Identity Refactor — Design QA

**Comparison target**

- Approved identity board: `/Users/philipdavis/Repos/Plinx/assets/branding/references/plinx-loop-selected.png`
- Production source isolations: `/Users/philipdavis/Repos/Plinx/assets/branding/source/plinx-loop.png` and `/Users/philipdavis/Repos/Plinx/assets/branding/source/plinx-wordmark.png`
- Rendered documentation site: `/Users/philipdavis/.codex/visualizations/2026/07/28/019fa6e1-9a7e-75a3-a46e-517d3e59ea47/plinx-loop-refactor/website-home-desktop-final.jpg`
- Full-view comparison: `/Users/philipdavis/.codex/visualizations/2026/07/28/019fa6e1-9a7e-75a3-a46e-517d3e59ea47/plinx-loop-refactor/brand-reference-vs-website-final.png`
- Mobile documentation capture: `/Users/philipdavis/.codex/visualizations/2026/07/28/019fa6e1-9a7e-75a3-a46e-517d3e59ea47/plinx-loop-refactor/website-home-mobile-viewport.jpg`
- Desktop viewport: 1440 × 1000 CSS pixels
- Mobile viewport: 390 × 844 CSS pixels
- State: documentation home, local production content, no account or customer data

**Findings**

- The generated production mark and exact `Plinx` wordmark preserve the selected loop silhouette, friendly upright forms, lime-to-teal palette, and dark-shell contrast. No actionable P0, P1, or P2 identity-fidelity differences remain.
- The shell stays `#0B120E` in object-dense app and website regions. Large static ambient lime and teal light is limited to branded/spacious surfaces and remains decorative.
- The website navbar, hero, favicon, social preview, release artwork, iOS/iPadOS icons, tvOS layered icons, Top Shelf artwork, launch treatment, sign-in, parental gate, home header, and branded loaders now use the Plinx Loop system.
- iOS/iPadOS and tvOS asset catalogs compile independently without warnings or errors. The Any, Dark, and Tinted iOS masters are opaque 1024 × 1024 sRGB images; tinted artwork is grayscale. tvOS front layers retain transparency, back layers are opaque, and Top Shelf exports match the catalog dimensions.
- The iOS target builds successfully for the simulator. The tvOS target builds successfully for an arm64 Apple TV simulator. A generic dual-architecture tvOS simulator build continues to fail in the existing LibDovi dependency because its XCFramework has no x86_64 slice; this is outside the Plinx-owned visual patch.

**Required fidelity surfaces**

- Fonts and typography: the app root and Plinx semantic styles default to SF Rounded while retaining Dynamic Type. PIN and media-number call sites can continue to opt into monospaced digits.
- Spacing and layout rhythm: the horizontal lockup remains legible at the approximately 35-point home-header slot. Mark safe areas are held across app icons, navbar placement, Top Shelf, and marketing layouts.
- Colors and visual tokens: canonical lime `#9EEE73`, teal `#399E91`, shell `#0B120E`, white, and charcoal are shared through `PlinxBrand` and the reproducible asset manifest.
- Image quality and asset fidelity: all visible brand art is generated from the approved ImageGen isolations. SVG silhouettes are source-traced rather than manually redrawn, and web/marketing PNGs are generated from the same masters.
- Interaction and accessibility: compact loading remains logo-free, regular and hero tiers use the loop without rotating it, Reduce Motion remains supported, brand images expose the `Plinx` accessibility label, and navigation/content hierarchy is unchanged.

**Comparison history**

1. The initial website pass exposed a P2 contrast issue on the secondary “Build from source” action over the ambient hero. The border and label were raised to white while preserving the transparent secondary hierarchy.
2. The desktop and 390 × 844 follow-up captures show no horizontal overflow, clipping, malformed wordmark text, or actionable P0/P1/P2 mismatch.
3. Native source, asset, and compile checks pass. Fresh iPhone, iPad, and Apple TV implementation captures could not be produced because the installed iOS 26.5 and tvOS 26.5 simulator runtimes remain stuck on `Waiting on System App` during first-boot migration.

**Open evidence limits**

- Repeat the specified iPhone, iPad, and Apple TV runtime captures when Simulator finishes system-app migration. The app bundles cannot be installed or launched until that external runtime state clears.
- Physical-device VoiceOver order, measured contrast, Siri Remote focus behavior, and icon parallax remain release-device checks rather than compliance claims.

final result: blocked

# Plinx Loop Contrast and tvOS Icon Cleanup — Design QA

**Comparison target**

- Reported iPhone sign-in capture: `/Users/philipdavis/.codex/visualizations/2026/07/28/019fa6e1-9a7e-75a3-a46e-517d3e59ea47/plinx-loop-cleanup/01-sign-in-before.png`
- Corrected white-lockup contrast swatch: `/Users/philipdavis/.codex/visualizations/2026/07/28/019fa6e1-9a7e-75a3-a46e-517d3e59ea47/plinx-loop-cleanup/03-sign-in-lockup-contrast-after.png`
- Corrected tvOS layered-icon composite: `/Users/philipdavis/.codex/visualizations/2026/07/28/019fa6e1-9a7e-75a3-a46e-517d3e59ea47/plinx-loop-cleanup/02-tvos-icon-after.png`
- Corrected 1280 × 768 tvOS App Store composite: `/Users/philipdavis/.codex/visualizations/2026/07/28/019fa6e1-9a7e-75a3-a46e-517d3e59ea47/plinx-loop-cleanup/04-tvos-app-store-icon-after.png`

**Findings and resolution**

- P1 identity fidelity: traced wordmark paths previously used the default nonzero fill rule, filling the `P` counter. Generated SVG groups now use even-odd fill and clipping, and the generator samples the rasterized counter to prevent regression.
- P1 contrast: compact sign-in previously used a gradient loop on the lime-to-teal portal. It now selects a dedicated white horizontal lockup whose loop and exact `Plinx` wordmark are both white. Generated-asset validation rejects any non-white visible pixel in that treatment.
- P1 tvOS identity: the layered foreground previously contained only a small centered loop. Regular and App Store icon stacks now use a prominent centered horizontal loop-and-wordmark foreground spanning approximately 72% of the icon width, with transparent foreground and opaque shell/ambient background layers.
- The tvOS composite shows an open `P` counter, clear shell contrast, balanced optical centering, and a silhouette that remains readable at icon scale.
- iOS/iPadOS and tvOS asset catalogs compile independently after regeneration. The iOS and arm64 tvOS targets build successfully, and the iOS test bundle compiles successfully.

**Evidence limits**

- A fresh in-app iPhone screenshot remains unavailable because two installed iOS simulator devices stalled in `Waiting on System App`; the nominally booted alternate device would not accept an app install. No simulator was erased or reset.
- The contrast swatch uses the production-generated `BrandLockupWhite` vector over the canonical brand gradient, but it is not a substitute for final runtime capture on a functioning simulator or device.

final result: blocked

# Parental Gate and Home Loading Surface-Role Correction — Design QA

**Comparison target**

- Reported parental-gate implementation: `/var/folders/vz/xjfy40v50nq3ct410zysfb4r0000gn/T/codex-clipboard-6bd06d57-e352-411a-9256-c42be6ba0134.png`
- Reported home-loading implementation: `/var/folders/vz/xjfy40v50nq3ct410zysfb4r0000gn/T/codex-clipboard-3933dc72-b384-4423-8b01-26b389004212.png`
- Parental-gate production-asset surface preview: `/Users/philipdavis/.codex/visualizations/2026/07/28/019fa6e1-9a7e-75a3-a46e-517d3e59ea47/plinx-surface-role-correction/05-parental-gate-surface-preview.png`
- Home-loading production-asset surface preview: `/Users/philipdavis/.codex/visualizations/2026/07/28/019fa6e1-9a7e-75a3-a46e-517d3e59ea47/plinx-surface-role-correction/06-home-loading-surface-preview.png`
- Parental-gate combined comparison: `/Users/philipdavis/.codex/visualizations/2026/07/28/019fa6e1-9a7e-75a3-a46e-517d3e59ea47/plinx-surface-role-correction/07-parental-gate-before-vs-surface-preview.png`
- Home-loading combined comparison: `/Users/philipdavis/.codex/visualizations/2026/07/28/019fa6e1-9a7e-75a3-a46e-517d3e59ea47/plinx-surface-role-correction/08-home-loading-before-vs-surface-preview.png`
- Viewport: 794 × 896 pixels, compact portrait modal/full-screen states
- Density normalization: source and previews are compared at the same pixel dimensions
- State: parental math gate with entered answer; home initial loading; no account or customer data

**Findings and implemented resolution**

- P1 surface-role mismatch: the parental gate had been changed from a bright branded moment into a near-black panel with a white identity. The implementation now restores the canonical lime-to-teal gradient, keeps the all-white stacked identity on that saturated surface, and returns challenge typography to shell-colored foregrounds.
- P1 action affordance: the Unlock button previously read as a dim disabled-looking glass outline. An initial correction introduced a one-off lime capsule, which did not belong to the shared component language. The final implementation uses the reusable `LiquidGlassButton` with its canonical `.brand` treatment, retaining shared glass geometry, highlights, depth, haptics, and press motion.
- P1 loading hierarchy: home loading previously rendered a large static white lockup, a second tiny animated mark inside a square, and redundant loading copy. An initial correction incorrectly replaced the established animation with a pulsing standalone mark. The final implementation promotes the existing animated rounded-square `PlinxLoadingIndicator` to `.hero` size, keeps the full-color loop centered inside it, places the outlined white `Plinx` wordmark beneath it, and removes visible loading text while retaining an accessibility loading label.
- P2 system consistency: dark-shell hydration now uses the dark-surface full-color lockup instead of the white stacked gradient treatment.

**Required fidelity surfaces**

- Fonts and typography: the gate retains SF Rounded and Dynamic Type; the visual preview uses approximate system rendering only and is not a runtime font-fidelity claim.
- Spacing and layout rhythm: the gate preserves its existing challenge flow and control order. The home loader is a vertically centered hero beacon/wordmark pair with a 24-point relationship.
- Colors and visual tokens: the gate uses canonical lime `#9EEE73`, teal `#399E91`, shell `#0B120E`, and white. Dark-shell loading uses the lime-to-teal mark and white outlined wordmark.
- Image quality and asset fidelity: previews and implementation use production-generated outlined SVG assets. No live-text logo, symbol approximation, or handcrafted replacement is used.
- Copy and content: parental-gate copy remains unchanged. Visible “Loading home”/“Loading your shows…” copy is removed from the home hero state; loading remains exposed to assistive technology.

**Comparison history and evidence limits**

1. The reported screenshots establish the P1 over-dark gate and duplicate loading hierarchy.
2. The first correction restored the gate palette but used a one-off Unlock control and replaced the established loading animation rather than enlarging it.
3. The second correction moves Unlock into `LiquidGlassButton(treatment: .brand)` and restores the existing animated beacon at hero size with the green loop centered inside.
4. Updated production-asset comparisons confirm the corrected palette, component treatment, beacon scale, and content hierarchy at the same pixel dimensions.
5. iOS, arm64 tvOS, iOS test-bundle, asset-catalog, and PlinxUI package checks pass.
6. Fresh runtime screenshots remain blocked because the installed iOS simulator runtime stalls at `Waiting on System App` and will not accept the built app. The production-asset surface previews are not represented as runtime captures.

final result: blocked
