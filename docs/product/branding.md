# Plinx Branding Guide

## Purpose

This file is the canonical branding and design-language guide for Plinx. It exists so future work can follow the actual product language already in the app instead of re-deciding the same visual rules.

When screenshots, old notes, or memory conflict with code, the code-backed sources named in this document win.

## Source Of Truth

### Canonical asset sources

- `assets/branding/` for reference exports, logos, app-store material, and reusable marketing assets
- `assets/branding/brand-manifest.json` for identity colors, spacing, and export rules
- `scripts/branding/generate-assets.mjs` for deterministic vector tracing and platform exports
- `PlinxApp/Resources/Assets.xcassets/` for packaged runtime assets
- `PlinxApp/Resources/LaunchScreen.storyboard` for launch-screen asset usage

### Canonical code sources

- `Packages/PlinxUI/Sources/PlinxUI/LiquidGlass/PlinxTheme.swift`
- `Packages/PlinxUI/Sources/PlinxUI/Brand/PlinxBrand.swift`
- `Packages/PlinxUI/Sources/PlinxUI/LiquidGlass/LiquidGlassButton.swift`
- `Packages/PlinxUI/Sources/PlinxUI/LiquidGlass/LiquidGlassModifiers.swift`
- `Packages/PlinxUI/Sources/PlinxUI/LiquidGlass/PlinxFocusSurface.swift`
- `Packages/PlinxUI/Sources/PlinxUI/Mascot/PlinxLoadingStateView.swift`
- `PlinxApp/App/ThemeExtensions.swift`
- `PlinxApp/App/AppearanceSetup.swift`
- `PlinxApp/Views/Common/PlinxBrandLogoView.swift`
- `PlinxApp/Views/Common/PlinxBrandedLoadingView.swift`
- `PlinxApp/Views/Auth/SignInView.swift`
- `PlinxApp/Views/ParentalGateView.swift`
- `PlinxApp/Views/RootTabView.swift`
- `PlinxApp/Views/KidsMainTabPicker.swift`
- `PlinxApp/Views/PlinxTVFocusCoordinator.swift`
- `PlinxApp/Views/Settings/PlinxSettingsChrome.swift`

### Canonical semantic hooks

- `PlinxBrandingSemantics.fullColorLogoAssetName`
- `PlinxBrandingSemantics.parentalGateTitleColorValue`
- `PlinxBrandingSemantics.signInPrimaryButtonStyleValue`

### Code beats screenshots

Screenshots in `screenshots/` are useful references, but they are not the authority when the shipped theme has changed. If a screen is restyled, update this file and tests first; refresh screenshots second.

## Brand Definition

Plinx should feel like:

- safe for children
- calm for parents
- playful without chaos
- premium without looking corporate
- tactile and soft instead of sharp or austere

The current visual language is:

- deep dark application shell for media browsing
- restrained lime/teal ambient light on selected branded dark-shell surfaces
- translucent liquid-glass interaction surfaces
- soft rounded geometry with strong corner radii
- clear white foreground text on dark shells
- accent-driven interactive feedback, with green as the default but user-selectable accents allowed

## Brand Pillars

### 1. Safety first

The brand must communicate calm control, not stimulation overload. Even when playful, it should still feel supervised, trustworthy, and intentional.

### 2. Soft physicality

Buttons and panels should feel touchable and slightly squishy. This comes from:

- frosted material
- bright edge highlights
- depth shadows
- short, deterministic easing with a static Reduce Motion alternative
- continuous-corner geometry

### 3. Friendly contrast

Plinx relies on clear contrast, but avoids harsh neon-on-black or generic gamer styling. The palette uses softened greens, teal, white, charcoal, and muted neutrals.

### 4. Branded simplicity

The UI should not look busy. Large branded moments belong on entry, gate, and shell surfaces. Content rows themselves stay fairly restrained so poster art remains readable.

## Visual Signature

The most recognizable Plinx combination is:

- deep green-black app shell
- contextual lime/teal ambient light on entry, loading, and empty states
- full lime-to-teal color on the parental gate and other intentionally saturated brand moments
- white or very light text
- green/teal accent action affordances
- rounded translucent panels and controls
- Plink Loop mark and friendly rounded wordmark used sparingly but confidently

If a new surface does not look like it belongs beside the home screen, parental gate, settings screen, and sign-in flow, it likely needs to be adjusted.

## Logo System

### Primary runtime logo assets

- `BrandMarkColor`
- `BrandMarkWhite`
- `BrandMarkCharcoal`
- `BrandWordmarkWhite`
- `BrandLockupOnLight`
- `BrandLockupOnDark`
- `BrandLockupWhite`
- `BrandLockupStackedOnGradient`

### Preferred usage

Use `BrandLockupOnLight` when:

- the logo sits on a neutral or softened surface
- the logo appears inside a contained hero panel
- the background is light enough or desaturated enough for the full-color mark to read clearly

Use `BrandLockupOnDark` when the logo sits directly on the dark shell. Use
`BrandLockupWhite` when the logo sits on the canonical lime-to-teal gradient or
another saturated brand-color surface. This keeps both the loop and wordmark
clearly visible instead of layering the gradient loop over a similar gradient.
Use `BrandWordmarkWhite` below the hero loading beacon when the animated mark
and wordmark need to remain independent. Use
`BrandLockupStackedOnGradient` when:

- the background is a dedicated saturated gradient
- the surface is a full-screen branded moment
- the logo is functioning as a centered gate emblem

### Logo behavior rules

- Never substitute Strimr branding or upstream app art.
- Never reconstruct the loop or wordmark from live text, symbols, or ad hoc shapes.
- Never recolor the logo ad hoc in SwiftUI.
- Never stretch, crop, rotate, outline, or shadow the logo differently per screen unless the asset itself was designed for that purpose.
- Do not use the logo as repeated decoration in content-heavy browsing screens.
- Keep the logo as a hero or anchor element, not background wallpaper.

### Sizing guidance from current app usage

- `PlinxBrandLogoView` defaults to `maxWidth: 240`
- sign-in uses a 280-point lockup on compact layouts and a 380-point lockup
  on spacious iPad layouts so the identity leads the connection headline
- the home header lockup fills the existing chrome row: 195 by 52 points at
  the default button size, capped at 56 points high
- the home header uses the approved lockup mark and wordmark with the internal
  gap reduced by 50% to keep the identity compact in the tab chrome
- tvOS sign-in uses a much larger logo treatment

Default rule:

- 220-280 pt max width for standard hero/logo moments on iPhone and iPad
- larger only for dedicated onboarding, app-transition, or tvOS hero layouts

The persistent tvOS shell uses a compact 220 by 52-point lockup. Child screens
never repeat that root identity; detail screens use a
secondary context row for Back, title, and local filters.

## Loading hierarchy

Loading is semantic rather than screen-specific. Use `PlinxLoadingStateView`
and choose one role:

| Role | Presentation |
|---|---|
| `appTransition` | Full identity beacon plus the canonical app-owned wordmark, reserved for launch/session hydration/first load |
| `content` | Regular beacon inside an established page; delayed briefly to prevent flashes |
| `inline` | Compact logo-free perimeter inside an existing action or row |
| `playback` | High-contrast medium beacon on black video for preparation and buffering |

Visible and spoken labels must arrive as caller-resolved
`LocalizedStringResource` values. Never pass a localization key as ordinary
display text. Indeterminate native full-screen spinners are not part of the
Plinx language; determinate progress bars and genuinely compact action progress
remain valid.

Loading and focus transitions use 180-240 ms easing. Reduce Motion renders a
static complete loading perimeter and suppresses focus scaling. Do not add
random tilt, repeated bounce, or independently animated logo pieces.

## Selection and focus

Selection is persistent state; focus is the live remote target. They must be
visually distinct:

- selection uses an accent fill, indicator, or checkmark that remains visible
- live focus adds the shared brighter gradient ring, restrained scale, and shadow
- shape, ring, and/or icon changes accompany color so focus is never conveyed by color alone
- exactly one element should be visibly focused after a tvOS screen settles

The Apple TV root shell is persistent and owns the Plinx lockup, primary
destinations, and Settings action. Moving focus across destinations does not
switch screens; Select activates one. Only the active tab stack is mounted, so
hidden content cannot remain a focus candidate. Its compact glass capsule is a
top-layer overlay rather than a reserved full-width band: the capsule stays
centered independently of the leading logo, while heroes and backgrounds can
continue behind both. Scrollable foreground content reserves only enough
initial clearance to remain readable and focusable.

Main-navigation selection never uses a title underline on iOS, iPadOS, or
tvOS. Accent fill plus icon/text color and the shared ring provide the selected
cue. On tvOS, the ring, fill, content, shadow, and optional scale form one focus
surface so the ring always follows the scaled outer shape. Reduce Motion keeps
the fill and ring while resolving the scale to 1.0.

## Settings surfaces

Settings remains parent-gated. iPhone and iPad keep touch-native grouped
navigation over the ambient shell. tvOS uses large dark-glass rows with the
shared focus surface, deterministic first-focus restoration, and explicit Move
Up/Move Down actions instead of drag-only reordering. Legal, privacy, support,
and source links stay inside this gated surface and never appear in kid-facing
navigation. Focused tvOS Settings controls remain at 1.0 scale with white
content, a 14% accent tint, a 3-point accent-gradient ring, and a restrained
shadow; do not layer the native bright focus plate over this treatment.

### Clear-space rule

Maintain clear space around the mark equal to at least 25% of its width. For a
lockup, use at least the height of the lowercase `i` dot. Do not let labels,
controls, or cards sit tightly against the identity.

## Color System

## Core theme palette

From `PlinxTheme.Palette.default`:

| Token | Current value | Role |
|---|---|---|
| `primary` | `PlinxBrand.lime` / `#9EEE73` | primary identity color |
| `secondary` | `PlinxBrand.teal` / `#399E91` | secondary identity color |
| `accent` | `PlinxBrand.teal` | package default before the user tint override |
| `background` | `PlinxBrand.shell` / `#0B120E` | global dark shell |
| `surface` | `PlinxBrand.surface` / `#18211D` | elevated dark surface |
| `onPrimary` | `PlinxBrand.shell` | text/icons on lime surfaces |
| `success` | `PlinxBrand.teal` | positive states |
| `warning` | `.yellow` | caution/error-supportive states |

Important implementation note:

The runtime brand expression is not driven only by `PlinxTheme.Palette.default`. The app also uses:

- root `.tint()` from the selected `PlinxAccentColor`
- `PlinxBrand.gradient` and `PlinxAmbientBackground`
- `Color.brandPrimary`, `Color.brandSecondary`, and `Color.appBackground`

That means branding decisions must consider theme tokens and app-level overrides together.

## Canonical dark-shell tokens

From `ThemeExtensions.swift`:

| Token | Value | Usage |
|---|---|---|
| `Color.appBackground` | `PlinxBrand.shell` / `#0B120E` | default screen background |
| `brandPrimary` | `.accentColor` | accent underline/highlight stripe |
| `brandSecondary` | `Color(white: 0.82)` | section headers, supporting light-neutral text |

Rules:

- Use `appBackground` for dark-shell screen roots.
- Use white for dominant titles on dark surfaces.
- Use `brandSecondary` for supporting titles and metadata where a neutral light-gray is needed.
- Do not introduce purple-tinted neutrals for section titles or dark-shell chrome.

## Identity gradient

From `PlinxBrand.gradient`:

- top color: lime `#9EEE73`
- bottom color: teal `#399E91`
- direction: top to bottom

This is the canonical identity gradient and should be used for:

- the loop mark
- default app-icon background

## Documentation site

The public documentation site uses the same identity endpoints as the app:

- lime `#9EEE73` for high-emphasis actions on the dark hero and primary links
  in dark mode
- teal `#399E91` for primary links in light mode and the hero action hover
- shell `#0B120E` for dark navigation and foreground text on lime

Do not substitute a separate teal or green palette for the website. Supporting
hover shades may be derived from the two identity endpoints, but every primary
accent must resolve to lime or teal.

The sticky navigation bar must remain opaque enough to preserve text and logo
contrast while content scrolls beneath it. Use a near-opaque white surface in
light mode and the canonical shell in dark mode. Do not make the navigation
transparent over the homepage hero.
- contained sign-in portal surfaces
- the parental gate
- selected dedicated marketing artwork

Do not replace it with arbitrary green gradients.

## Contextual ambient treatment

`PlinxAmbientBackground` keeps `#0B120E` as the stable base and introduces:

- a large lime source near the top-leading edge at 4-6% opacity
- a large teal source near the bottom-trailing edge at 6-8% opacity
- no required motion or meaning
- no placement beneath dense poster grids or controls when contrast suffers

Use it for sign-in surroundings, launch/hero loading, and spacious empty
states. The parental gate deliberately uses the full identity gradient instead.
Pure black remains appropriate for video playback.
- subtle dark vertical overlay for depth

Use this richer treatment for:

- onboarding
- sign-in/auth
- large hero brand-first moments

Do not use it behind dense content browsing surfaces; it is too loud for content-heavy screens.

### Guided portal sign-in

The sign-in surface uses the guided portal direction:

- a dark `appBackground` shell around one luminous, continuous-corner portal
- the full-color Plinx logo as the first brand landmark
- an explicit “Grown-up step” cue before Plex authentication
- a short title and outcome-oriented follow-up that explains profile selection comes next
- one oversized, bottom-anchored primary action with a dark teal base and accent-aware stroke/glow
- errors contained inside the portal immediately above the primary action

The compact portal must remain centered and width-constrained on iPhone,
expand vertically for Dynamic Type, and scroll rather than clip on compact-height
devices. The user-selectable accent may tint interactive emphasis, but it must
not replace the foundational green-to-teal portal gradient.

On iPad, the sign-in surface is an edge-to-edge branded screen rather than an
iPhone-sized card centered inside a dark surround. Use the full canvas for the
gradient, increase the logo and display type modestly, and give the primary
action a wider target while preserving the centered reading order. Keep the
compact rounded portal treatment for iPhone widths.

On tvOS, adapt the same hierarchy to one wide, overscan-safe portal:

- keep the full-color logo inside the portal as its first landmark
- place the large QR plate before the grown-up instructions in reading order
- preserve the grown-up cue, connection title, and kid-profile next-step copy
- keep the status and Refresh Code action grouped directly beneath the
  instructions instead of separating them with flexible empty space
- make Refresh Code the initial focus target and give it a dark-teal glass
  base, accent edge, inset white outline, subtle scale, and restrained glow;
  suppress the platform focus plate so the control remains recognizably Plinx
  while still reading clearly from couch distance
- align the status and action to the instruction column and keep the action
  narrower than that column rather than spanning the remaining portal width
- keep errors inside the instruction column instead of moving them below the
  portal or changing the portal's overall position

## User accent palette

From `PlinxAccentColor`:

| Accent | Current value |
|---|---|
| `orange` | system orange |
| `red` | `Color(red: 0.93, green: 0.15, blue: 0.15)` |
| `blue` | `Color(red: 0.2, green: 0.5, blue: 0.98)` |
| `green` | `Color(red: 16/255, green: 185/255, blue: 129/255)` |
| `teal` | `Color(red: 0.18, green: 0.72, blue: 0.72)` |
| `pink` | `Color(red: 0.95, green: 0.35, blue: 0.6)` |
| `yellow` | `Color(red: 0.98, green: 0.8, blue: 0.1)` |
| `purple` | `Color(red: 0.6, green: 0.28, blue: 0.98)` |

Rules for accent behavior:

- `green` is the default and the strongest expression of the current brand.
- User accent can change controls and emphasis, but must not change the foundational brand gradient.
- Accent applies to selected tabs, toggles, strokes, icons, pills, and button emphasis.
- New feature UIs should respond to `.accentColor` rather than hard-coding green.
- Even when accent is purple, the app should still read as Plinx because the shell, gradients, logo, and geometry remain constant.

## Color usage rules

### Preferred combinations

- dark shell + white title + accent control
- brand gradient + dark shell-colored text for the parental gate
- ambient shell + full-color identity for hero loading
- charcoal card + white label + muted gray secondary text
- accent stroke + low-opacity accent fill for interactive cards or buttons

### Avoid

- white backgrounds for normal browsing/settings shells unless the entire surface is a deliberate full-screen branded exception
- generic iOS blue buttons when the app already has accent-aware controls
- using orange as the dominant shell brand
- multicolor rainbow UI elements outside intentional content art or accent-picker contexts

## Typography

## Canonical scale

From `PlinxTheme.Typography.default`:

| Style | Size | Weight | Tracking | Line height |
|---|---:|---|---:|---:|
| `display` | 36 | semibold | 0.0 | 1.3 |
| `title` | 24 | medium | 0.01 | 1.3 |
| `heading` | 18 | medium | 0.01 | 1.3 |
| `body` | 15 | regular | 0.015 | 1.45 |
| `caption` | 12 | regular | 0.03 | 1.4 |
| `button` | 16 | medium | 0.02 | 1.2 |

Implementation note:

- Typography uses the SF Rounded system design throughout the app.
- The app root applies `.fontDesign(.rounded)` so upstream system text inherits
  the same friendly treatment without modifying Strimr.
- Timers, PINs, and other numeric information may retain monospaced digits.
- Do not swap in random font families or novelty typefaces.
- The personality comes from weight, spacing, surface treatment, and color, not from decorative type.

## Usage rules

Use `display` for:

- major hero brand moments
- splash-like screens
- rare oversized emphasis

Use `title` for:

- sign-in headlines
- major section/screen titles when the brand moment is large and spacious

Use `heading` for:

- section headers
- secondary hero labels
- grouped feature headings

Use `body` for:

- explanatory copy
- subtitles
- normal settings descriptions

Use `caption` for:

- metadata
- card support text
- auxiliary labels

Use `button` for:

- LiquidGlass buttons
- primary interactive labels
- affordance copy that should read crisply at a glance

## Typography behavior rules

- Keep line lengths short in brand-first surfaces.
- Favor medium-to-bold weight over all-caps shouting.
- Use white or near-white on dark shells.
- Use dark green-charcoal text on the bright brand gradient when a heading needs strong contrast.
- Do not use tiny low-contrast helper copy on kid-facing screens.

## Geometry And Surface Language

## Corner-radius system

Current canonical radii from the design system and shell:

| Context | Current value |
|---|---:|
| default glass surfaces | 22 |
| compact glass | 12 |
| hero glass | 28 |
| many action cards/buttons in app shell | 14-18 |
| auth hero container | 34 |

Rules:

- Prefer continuous-corner rounded rectangles.
- Small controls may go to 12.
- Standard interactive surfaces should live roughly in the 14-22 range.
- Hero or brand-first containers may go larger.
- Avoid sharp rectangles or tiny radii unless a native control makes it unavoidable.

## Material system

Plinx uses frosted glass and layered translucency, especially for controls and overlays:

- `.thinMaterial`
- `.ultraThinMaterial`
- white highlight stroke
- dark depth shadow

This is a signature behavior, not optional decoration.

Use liquid glass for:

- buttons
- floating tab chrome
- quick-action sheets
- overlay controls
- selective hero/support surfaces

Do not cover every panel in glass just because the modifier exists. Content browsing still needs visual restraint.

## Liquid glass specifications

From the default glass token:

- corner radius: 22
- highlight opacity: 0.45
- shadow opacity: 0.25
- highlight offset: `(-4, -6)`
- shadow offset: `(6, 8)`
- highlight blur: `10`
- shadow blur: `12`

Compact variant:

- corner radius: 12
- lighter/smaller highlight and shadow

Hero variant:

- corner radius: 28
- stronger highlight and shadow

Rules:

- Use the existing variants before inventing new ones.
- If a new variant is necessary, document why the existing three are insufficient.

## Motion And Interaction

## Motion personality

Motion should feel:

- springy
- tactile
- soft
- slightly playful
- never chaotic

Current canonical springs:

| Token | Current value |
|---|---|
| `interactive` | `.spring(response: 0.3, dampingFraction: 0.7)` |
| `bouncy` | `.spring(response: 0.5, dampingFraction: 0.5)` |
| `gentle` | `.spring(response: 0.6, dampingFraction: 0.85)` |
| `snappy` | `.spring(response: 0.25, dampingFraction: 0.8)` |

## Interaction rules

- `LiquidGlassButton` is the canonical branded button.
- Branded interactions should trigger the Plinx feedback pattern:
  - haptic
  - spring-scale press
- Do not promise or synthesize UI audio unless a respectful, user-controlled bundled sound is designed and tested.
- Selected or emphasized controls may tilt, lift, or glow slightly.
- Back buttons and tab items may have subtle playful motion when the setting allows it.

## Media-detail actions

Play, Watch, and Download use `PlinxMediaDetailActionStyle`: a continuous
rounded rectangle with a translucent material base, light accent fill, and
solid accent border. Play is the wide, 70-point primary action; Restart uses a
matching 70-by-70-point rounded square. On iPhone and iPad, Watch and Download
use 64-by-64-point secondary controls so they are easier for children to
target. Apple TV uses the same treatment with a 68-by-68-point Watch control.
The treatment uses Plinx's user-selected accent. Secondary controls use large,
plain SF Symbols rather than circle-contained glyphs: a checkmark for Watch
and a downward arrow for Download.

Watchlist and Shuffle are intentionally hidden from Plinx media details on iOS,
iPadOS, and tvOS. The rows are not exposed through Strimr's public view API, so
this is a deliberately narrow paired-source exception rather than a generic
upstream behavior change. Ratings and metadata remain upstream-owned.

## Playful animation settings

The product already supports a user preference via `PlinxAnimationPreference.playfulAnimationsEnabled`.

Rules:

- Playfulness must degrade gracefully when disabled.
- Disable ornamental motion before disabling clarity-preserving motion.
- Never make critical navigation depend on animation.

## App Chrome

## Global shell

Current shell pattern:

- dark or black root background
- white primary labels
- accent-selected interaction states
- transparent navigation bar
- transparent tab environment with custom floating picker

From `AppearanceSetup`:

- navigation bars are transparent
- title text is white
- navigation button tint follows current accent
- tab tint follows current accent
- unselected tab items are muted white

This is canonical. Do not reintroduce opaque default UIKit bars for normal kid-facing shells.

## Floating tab picker

The bottom navigation should feel:

- docked but floating
- soft-cornered
- glassy
- playful when selected

Rules:

- selected tab state should use accent emphasis
- inactive tabs should stay readable but clearly secondary
- the bar itself should read as a distinct branded object, not a default system bar

## Header treatment

Section headers in content areas should use:

- large white or near-white main label
- `brandSecondary` for supporting metadata
- accent underline or accent-led emphasis sparingly

Do not turn every section header into a full gradient or decorated banner.

## Surface Patterns By Screen Type

## 1. Full-screen branded moments

Examples:

- parental gate
- splash/loading
- sign-in/onboarding

Required traits:

- intentional surface-role pairing: white identity on saturated brand color,
  full-color identity on the dark shell
- centered logo moment
- strong vertical spacing
- minimal competing UI
- large clear action affordance

These are the highest-intensity brand surfaces in the product.

## Loading system

Plinx loading states use one visual language at three intentional scales:

- **Compact** is the app-wide default for individual controls, cards, rows,
  pagination, and other local waits. It is a 20-point rounded-square gradient
  perimeter on iPhone and iPad, 30 points on tvOS, with no logo and no
  background plate.
- **Regular** is for video-level buffering and deliberate local waits that need
  more presence. It uses a thicker high-contrast perimeter, a translucent
  center, and a restrained Plinx mark so the underlying video remains legible.
- **Hero identity** is reserved for full-page branded loading. It promotes the
  existing animated rounded-square beacon to hero scale—approximately the size
  of the previous static logo—with the full-color Plink Loop centered inside.
  The outlined white `Plinx` wordmark sits directly beneath the beacon. Keep the
  perimeter animation and Reduce Motion behavior; do not add a second static
  logo or visible loading copy.

The app exposes two semantic loading contexts rather than allowing screens to
assemble these pieces independently:

- **App transition** fills the ambient shell with the hero identity. Launch,
  session hydration, and the initial empty home load use the same centered
  footprint so state changes do not move or resize the brand.
- **Content** centers the regular indicator with optional contextual copy. It
  is used when navigation or screen identity is already visible and never adds
  a second lockup.

Do not place the Plinx logo in compact indicators; the mark becomes noise at
inline sizes. Do not use the hero beacon inside video tiles, buttons, cards,
rows, or navigation chrome. Do not show a visible buffering caption over video;
keep that status available to assistive technology. Home hero loading also
keeps its loading status in accessibility semantics instead of displaying
redundant “Loading home” copy.

`PlinxProgressViewStyle` is installed at the app root. Indeterminate
`ProgressView` instances therefore use the compact logo-free treatment by
default, while an explicit large control maps to regular. Determinate download
and watch progress remains linear and must keep its numeric semantic value.
Pull-to-refresh keeps the native gesture but replaces its activity presentation
with a scaled regular Plinx square and hides the native spinner.
Reduce Motion replaces the perimeter-chasing highlight with a static complete
gradient perimeter for square indicators and stops the hero identity pulse. It
does not hide the loading state. The square and loop never rotate.

The static OS launch storyboard uses the same shell, ambient treatment, center
point, and approximate hero footprint because launch screens cannot animate.
The first active app loading state adds motion without relocating the identity.

## 2. Dark-shell browsing screens

Examples:

- home
- library
- search
- downloads
- settings

Required traits:

- dark root shell
- media art or content cards as the visual focus
- white typography for main content labels
- restrained neutral secondaries
- accent only for interactivity and emphasis

These surfaces should feel calm and content-led, not promotional.

## 3. Overlay and action surfaces

Examples:

- quick actions
- close buttons
- small floating controls
- pills and hero metadata badges

Required traits:

- glass or softened dark material
- strong corner radius
- white foreground labels/icons
- accent stroke or accent fill at low opacity

## Key Screen Rules

## Sign-in

Current sign-in language:

- dark shell with restrained ambient lime/teal light
- contained canonical-gradient portal on compact layouts
- white horizontal lockup on the compact colored portal
- dark-surface full-color lockup on spacious dark-shell layouts
- white title/subtitle
- accent-stroked, glass-adjacent CTA

Rules:

- Sign-in should feel welcoming and premium, not utilitarian.
- The Plinx lockup is the primary landmark. Use 34-point connection-title type
  on compact layouts and 44-point type on spacious iPad layouts so the title
  remains clearly secondary to the logo.
- The primary CTA should remain visually lighter and friendlier than a harsh solid fill button.
- Subtitle copy can explain the task, but should stay short and centered.

## Parental gate

Current parental gate language:

- full lime-to-teal brand gradient
- centered white stacked logo
- dark shell-colored text for headings and challenge content
- oversized challenge typography
- `LiquidGlassButton(treatment: .brand)` for the green Unlock action, preserving
  the shared glass geometry, highlight/shadow tokens, haptics, and press motion

Rules:

- This surface must feel clearly separate from kid browsing mode.
- The gate should look authoritative but not scary.
- Avoid clutter, extra copy, or unnecessary links.

## Home

Current home language:

- dark shell
- white section titles
- colorful poster art providing most of the visual saturation
- floating navigation chrome
- small accent affordances instead of broad accent floods

Rules:

- Let media art carry the color richness.
- Brand should frame the experience, not compete with cover art.
- The home lockup should consume the height already reserved by the search and
  settings controls. Scale it with that chrome row, capped at 56 points high,
  without pushing the first content section down.
- Section titles should remain large and readable, with enough spacing to breathe.
- On tvOS, the main header is a persistent top overlay: use 52-point controls,
  22-point icons, footnote labels, 108-point minimum tab widths, and 16-point
  corners. Center the controls-width glass capsule independently of the leading
  220 by 52-point lockup; do not leave empty glass or a separator spanning the
  hero.
- On tvOS, hero artwork should overscan to the top-right edge and blend only on the left and bottom into the dark shell. Keep the clear-logo layer above those fades with no dark rectangular backing.
- On tvOS, text metadata belongs in the leading safe area, sized to its content with continuous corners and a softly feathered dark edge. It must reserve the trailing logo area rather than overlap it.
- On tvOS library detail screens, Recommended/Browse/Collections controls sit below the hero metadata and before the first content section, never in front of the artwork.
- On tvOS, hero artwork should overscan slightly past the top and right edges so the shell background never peeks through there.
- On tvOS, the hero is a bounded pinned region: artwork reaches the physical top and right edges, metadata and artwork share one bottom guide, and vertical content clips at that guide instead of painting over the hero.
- tvOS selected media tiles should scale up slightly and use a 4-point solid accent border around the scaled outer artwork bounds plus a short, fully fading accent glow. Reserve at least 24 points around horizontal carousels for the halo; only horizontal carousel clipping may be disabled.

## Settings

Current settings language:

- dark shell
- softened charcoal grouped panels
- white text with muted gray support labels
- accent icons and toggles
- touch-only close controls on iOS and iPadOS

Rules:

- Settings should feel parent-safe and serious, but still clearly part of Plinx.
- Use accent for the actionable part of each setting, not as page wallpaper.
- Group panels should feel soft and elevated, never harsh or sterile.
- On tvOS, use a near-full-screen parent modal with large grouped rows,
  30-point primary labels, and readable supporting copy. Do not add an X close
  control: the persistent main navigation is the primary exit, and Menu pops
  one Settings subpage or closes the Settings root.
- While Settings or its parental gate is visible, Settings—not the originating
  content tab—owns the selected navigation appearance. Selecting any content
  destination immediately closes and relocks Settings, then restores that
  tab's saved navigation and focus state. Selecting Settings again is a no-op.
- Focused Settings rows keep their normal geometry: use a dark row, white
  text/icons, 14% accent fill, a 3-point accent-gradient outer ring, and a
  restrained shadow with no native white focus plate.
- tvOS rating choices use neutral text and a selected checkmark. Accent outlines communicate focus; never place accent-colored rating text on an accent-colored pill.

## Profile Selection

Current profile-switcher language:

- dark shell background
- fixed-height profile tiles for every account state
- green outline and soft glow for the active profile
- subtle glass or charcoal tile fill, never a full bright selection box
- compact native destructive logout icon in the authentication toolbar

Rules:

- Keep every profile tile the same height, even when a profile has no username or email.
- Use the active-state border and glow to indicate selection, not tile scaling or oversized fill.
- Keep logout compact and clearly destructive; it should not inherit the oversized home-shell chrome treatment.

## Content Cards And Media Tiles

## Card priorities

Card design should prioritize:

1. artwork readability
2. title legibility
3. content-type clarity
4. progress/status clarity

Branding on cards is intentionally restrained.

## Card rules

- Poster and tile art should retain rounded corners.
- Progress and metadata overlays should stay compact.
- Brand overlays should not obscure content art.
- Accent-colored status chips are allowed, but should be small and meaningful.
- Use neutral or white text first; use accent only when it communicates state or action.

## Card geometry

Current patterns in the app rely on:

- portrait cards for movies/TV
- landscape cards for clips/other videos
- rounded rectangles rather than hard edges

That distinction is part of the experience and should not be blurred casually.

## Buttons And Controls

## Primary branded button

Use `LiquidGlassButton` first when a branded action is needed.

Characteristics:

- white text
- glass treatment
- haptic feedback
- spring press feedback
- rounded continuous corners

Player-mode selection surfaces should follow the same rules:

- use accent-aware glass rows and modal controls
- avoid default system blue checkmarks, tints, and selection glyphs
- keep audio, subtitle, and track choices visually aligned with the rest of the Plinx shell
- prefer branded accent strokes and soft fills over bright flat selection states

## Secondary button pattern

Where the app uses custom secondary buttons instead of `LiquidGlassButton`, match the established shell treatment:

- low-opacity accent fill
- accent stroke
- white foreground text
- rounded corners
- springy press behavior

## Close and chrome buttons

Current shell buttons use:

- icon-only treatment
- `ultraThinMaterial`
- accent stroke
- accent icon color
- larger tap targets

Rules:

- Icon buttons must stay large and obvious for children and parents.
- Do not shrink shell buttons into tiny toolbar affordances.

## Copy And Tone

## Copy voice

Plinx copy should be:

- warm
- direct
- reassuring
- short
- low-jargon

## Do

- tell the user what to do next
- keep labels concrete
- use plain, parent-friendly wording
- make kid-facing labels simple and readable

## Avoid

- corporate marketing language inside the app
- clever jokes that reduce clarity
- overloaded instructional paragraphs
- link-like “learn more” patterns on kid-facing surfaces

## Accessibility And Readability

## Required behavior

- maintain strong contrast on dark-shell surfaces
- keep touch targets large
- preserve readable type sizing
- avoid accent-only meaning where a label or icon is needed
- support motion reduction through the existing playful-animation preference where appropriate

## Contrast rules

- white or near-white on dark shell is preferred
- dark green-charcoal on bright gradient is preferred
- muted gray is only for secondary/supporting text, never the main action

## Brand Do / Don't

## Do

- keep the dark shell + green-teal brand surface relationship intact
- use the logo as a hero anchor, not wallpaper
- use accent for interaction emphasis
- use soft glass and rounded geometry consistently
- let media art stay prominent in browsing flows
- keep branded full-screen moments sparse and confident

## Don't

- introduce Strimr branding anywhere in shipped Plinx surfaces
- replace the canonical green gradient with arbitrary alternatives
- use sharp-cornered panels for core branded surfaces
- flood content-heavy screens with giant brand gradients
- hard-code random colors when `.accentColor`, `appBackground`, `brandPrimary`, or the brand gradient already cover the case
- create visually unrelated feature islands with their own style system

## Implementation Rules For Future Work

When building a new screen:

1. Decide whether it is a full-screen branded moment or a dark-shell content moment.
2. Reuse existing logo, theme, accent, and glass patterns before introducing new ones.
3. Use the existing typography scale before inventing one-off font styling.
4. Use accent for state and interaction, not for constant saturation.
5. Validate that the new screen still looks like it belongs next to sign-in, parental gate, home, and settings.

When changing branding:

1. Update code
2. Update this file
3. Update tests and screenshots as needed

## Brand-Sensitive Files To Review Together

Changes in these files usually imply a branding review:

- `Packages/PlinxUI/Sources/PlinxUI/LiquidGlass/PlinxTheme.swift`
- `Packages/PlinxUI/Sources/PlinxUI/Brand/PlinxBrand.swift`
- `Packages/PlinxUI/Sources/PlinxUI/LiquidGlass/LiquidGlassButton.swift`
- `Packages/PlinxUI/Sources/PlinxUI/LiquidGlass/LiquidGlassModifiers.swift`
- `PlinxApp/App/ThemeExtensions.swift`
- `PlinxApp/App/AppearanceSetup.swift`
- `PlinxApp/Views/Common/PlinxBrandedLoadingView.swift`
- `PlinxApp/Views/Common/PlinxBrandLogoView.swift`
- `PlinxApp/Views/Auth/`
- `PlinxApp/Views/ParentalGateView.swift`
- `PlinxApp/Views/RootTabView.swift`
- `PlinxApp/Views/KidsMainTabPicker.swift`
- `PlinxApp/Resources/Assets.xcassets/`
- `assets/branding/`

## Test Requirements For Branding Changes

Run these when branding, theme, assets, or branded shell behavior changes:

- `PlinxApp/UnitTests/BrandingAssetsTests.swift`
- `PlinxApp/UITests/BrandingUITests.swift`
- relevant `Packages/PlinxUI` snapshot tests
- targeted UI tests for changed surfaces

Recommended additions when the visual language evolves materially:

- add or refresh snapshot coverage for any new branded component
- refresh at least one representative screenshot for the changed surface

## Documentation Update Rule

If any of the following changes, update this file in the same PR:

- logo asset policy
- full-screen brand gradient
- accent palette
- typography scale
- glass tokens
- button style rules
- app shell chrome
- branded auth, loading, settings, or parental gate conventions

This file is meant to prevent repeated explanation. If a reviewer or contributor would otherwise need to ask “what is the Plinx look supposed to be here?”, the answer should already live here.
