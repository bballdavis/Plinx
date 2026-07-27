# Option 3 Guided Portal — Design QA

**Comparison target**

- Source visual truth: `<local path>/.codex/visualizations/2026/07/26/019f9c70-3e12-77f3-9373-4e94cac0da90/plinx-visual-audit/concepts/option-3-guided-portal.png`
- Rendered implementation: `<local path>/.codex/visualizations/2026/07/26/019f9c70-3e12-77f3-9373-4e94cac0da90/plinx-option3-build/implementation-iphone-17e-final.png`
- Normalized implementation: `<local path>/.codex/visualizations/2026/07/26/019f9c70-3e12-77f3-9373-4e94cac0da90/plinx-option3-build/implementation-iphone-17e-final-normalized.png`
- Full-view comparison: `<local path>/.codex/visualizations/2026/07/26/019f9c70-3e12-77f3-9373-4e94cac0da90/plinx-option3-build/design-comparison-final.png`
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

- Platform source capture: `<local path>/.codex/visualizations/2026/07/26/019f9c70-3e12-77f3-9373-4e94cac0da90/plinx-visual-audit/captures/tvos-1080p-signIn-idle.png`
- Option 3 style truth: `<local path>/.codex/visualizations/2026/07/26/019f9c70-3e12-77f3-9373-4e94cac0da90/plinx-visual-audit/concepts/option-3-guided-portal.png`
- Rendered implementation: `<local path>/.codex/visualizations/2026/07/26/019f9c70-3e12-77f3-9373-4e94cac0da90/plinx-option3-build/implementation-tvos-1080p-verified.png`
- Full-view comparison: `<local path>/.codex/visualizations/2026/07/26/019f9c70-3e12-77f3-9373-4e94cac0da90/plinx-option3-build/design-comparison-tvos-verified.png`
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

- Fresh pre-change evidence: `<local path>/.codex/visualizations/2026/07/26/019f9c70-3e12-77f3-9373-4e94cac0da90/plinx-option3-build/audit-refresh-cleanup-01-current.png`
- Final implementation: `<local path>/.codex/visualizations/2026/07/26/019f9c70-3e12-77f3-9373-4e94cac0da90/plinx-option3-build/implementation-tvos-refresh-cleanup-final.png`
- Full-view comparison: `<local path>/.codex/visualizations/2026/07/26/019f9c70-3e12-77f3-9373-4e94cac0da90/plinx-option3-build/design-comparison-tvos-refresh-cleanup-full.png`
- Focused comparison: `<local path>/.codex/visualizations/2026/07/26/019f9c70-3e12-77f3-9373-4e94cac0da90/plinx-option3-build/design-comparison-tvos-refresh-cleanup-focus.png`
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
