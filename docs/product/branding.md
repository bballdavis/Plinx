# Plinx Branding Guide

## Purpose

This file is the canonical branding and design-language guide for Plinx. It exists so future work can follow the actual product language already in the app instead of re-deciding the same visual rules.

When screenshots, old notes, or memory conflict with code, the code-backed sources named in this document win.

## Source Of Truth

### Canonical asset sources

- `assets/branding/` for reference exports, logos, app-store material, and reusable marketing assets
- `PlinxApp/Resources/Assets.xcassets/` for packaged runtime assets
- `PlinxApp/Resources/LaunchScreen.storyboard` for launch-screen asset usage

### Canonical code sources

- `Packages/PlinxUI/Sources/PlinxUI/LiquidGlass/PlinxTheme.swift`
- `Packages/PlinxUI/Sources/PlinxUI/LiquidGlass/LiquidGlassButton.swift`
- `Packages/PlinxUI/Sources/PlinxUI/LiquidGlass/LiquidGlassModifiers.swift`
- `PlinxApp/App/ThemeExtensions.swift`
- `PlinxApp/App/AppearanceSetup.swift`
- `PlinxApp/Views/Common/PlinxBrandLogoView.swift`
- `PlinxApp/Views/Common/PlinxBrandedLoadingView.swift`
- `PlinxApp/Views/Auth/SignInView.swift`
- `PlinxApp/Views/ParentalGateView.swift`
- `PlinxApp/Views/RootTabView.swift`
- `PlinxApp/Views/KidsMainTabPicker.swift`

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
- bright green-teal branded full-screen surfaces for onboarding, loading, and parental gate
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
- spring animation
- continuous-corner geometry

### 3. Friendly contrast

Plinx relies on clear contrast, but avoids harsh neon-on-black or generic gamer styling. The palette uses softened greens, teal, white, charcoal, and muted neutrals.

### 4. Branded simplicity

The UI should not look busy. Large branded moments belong on entry, gate, and shell surfaces. Content rows themselves stay fairly restrained so poster art remains readable.

## Visual Signature

The most recognizable Plinx combination is:

- black or near-black app shell
- bright green-to-teal brand gradient on full-screen branded surfaces
- white or very light text
- green/teal accent action affordances
- rounded translucent panels and controls
- Plinx chevron logo used sparingly but confidently

If a new surface does not look like it belongs beside the home screen, parental gate, settings screen, and sign-in flow, it likely needs to be adjusted.

## Logo System

### Primary logo assets

- `LogoFullColor`
- `LogoFullWhite`
- `LogoDark`
- `LogoStackedFullWhite`

### Preferred usage

Use `LogoFullColor` when:

- the logo sits on a neutral or softened surface
- the logo appears inside a contained hero panel
- the background is light enough or desaturated enough for the full-color mark to read clearly

Use `LogoStackedFullWhite` or another white logo variant when:

- the background is the saturated Plinx brand gradient
- the surface is a full-screen branded moment
- the logo is functioning as a centered splash/loading/gate emblem

### Logo behavior rules

- Never substitute Strimr branding or upstream app art.
- Never recolor the logo ad hoc in SwiftUI.
- Never stretch, crop, rotate, outline, or shadow the logo differently per screen unless the asset itself was designed for that purpose.
- Do not use the logo as repeated decoration in content-heavy browsing screens.
- Keep the logo as a hero or anchor element, not background wallpaper.

### Sizing guidance from current app usage

- `PlinxBrandLogoView` defaults to `maxWidth: 240`
- sign-in expands logo usage to about `280`
- tvOS sign-in uses a much larger logo treatment

Default rule:

- 220-280 pt max width for standard hero/logo moments on iPhone and iPad
- larger only for dedicated onboarding or tvOS hero layouts

### Clear-space rule

Maintain clear space around the logo equal to at least the height of the chevron mark’s inner opening. In practice, do not let labels, controls, or cards sit tightly against the logo.

## Color System

## Core theme palette

From `PlinxTheme.Palette.default`:

| Token | Current value | Role |
|---|---|---|
| `primary` | `.blue` | theme primary; supporting highlight color, not the app shell accent |
| `secondary` | `.orange` | secondary brand accent, supporting only |
| `accent` | `.pink` | theme default interactive accent before user tint override |
| `background` | `Color(red: 0.045, green: 0.07, blue: 0.055)` | global dark shell |
| `surface` | `Color(white: 0.12)` | elevated dark surface |
| `onPrimary` | `.white` | text/icons on primary interactive surfaces |
| `success` | `.green` | positive states |
| `warning` | `.yellow` | caution/error-supportive states |

Important implementation note:

The runtime brand expression is not driven only by `PlinxTheme.Palette.default`. The app also uses:

- root `.tint()` from the selected `PlinxAccentColor`
- explicit `LinearGradient.plinxBrandGreen`
- `Color.brandPrimary`, `Color.brandSecondary`, and `Color.appBackground`

That means branding decisions must consider theme tokens and app-level overrides together.

## Canonical dark-shell tokens

From `ThemeExtensions.swift`:

| Token | Value | Usage |
|---|---|---|
| `Color.appBackground` | `Color(red: 0.045, green: 0.07, blue: 0.055)` | default screen background |
| `brandPrimary` | `.accentColor` | accent underline/highlight stripe |
| `brandSecondary` | `Color(white: 0.82)` | section headers, supporting light-neutral text |

Rules:

- Use `appBackground` for dark-shell screen roots.
- Use white for dominant titles on dark surfaces.
- Use `brandSecondary` for supporting titles and metadata where a neutral light-gray is needed.
- Do not introduce purple-tinted neutrals for section titles or dark-shell chrome.

## Branded green gradient

From `LinearGradient.plinxBrandGreen`:

- top color: `Color(red: 0.619, green: 0.933, blue: 0.450)`
- bottom color: `Color(red: 0.225, green: 0.620, blue: 0.570)`
- direction: top to roughly 70% down the screen

This is the canonical full-screen Plinx brand gradient and should be used for:

- parental gate
- splash/loading surfaces
- other dedicated branded full-screen states

Do not replace it with arbitrary green gradients.

## Sign-in gradient treatment

The sign-in screen uses a more layered version of the brand gradient:

- top light green
- mid mint
- lower teal
- white radial glow at the top trailing area
- subtle dark vertical overlay for depth

Use this richer treatment for:

- onboarding
- sign-in/auth
- large hero brand-first moments

Do not use it behind dense content browsing surfaces; it is too loud for content-heavy screens.

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
- brand gradient + dark green text for safe/gate surfaces
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

- Typography uses system font as the rendering engine.
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
- Branded interactions should trigger the signature Plink feedback pattern:
  - sound
  - haptic
  - spring-scale press
- Selected or emphasized controls may tilt, lift, or glow slightly.
- Back buttons and tab items may have subtle playful motion when the setting allows it.

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

- green-teal brand gradient
- centered logo moment
- strong vertical spacing
- minimal competing UI
- large clear action affordance

These are the highest-intensity brand surfaces in the product.

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

- layered branded gradient background
- radial glow near top trailing
- contained dark translucent hero panel
- full-color logo
- white title/subtitle
- accent-stroked, glass-adjacent CTA

Rules:

- Sign-in should feel welcoming and premium, not utilitarian.
- The primary CTA should remain visually lighter and friendlier than a harsh solid fill button.
- Subtitle copy can explain the task, but should stay short and centered.

## Parental gate

Current parental gate language:

- full-screen Plinx brand gradient
- centered white stacked logo
- dark text for headings on the bright background
- oversized challenge typography
- branded unlock button

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
- Section titles should remain large and readable, with enough spacing to breathe.
- On tvOS, the main header navigation should read as a full-width centered glass bar with tighter top insets than before; do not float a small pill in the middle with excess dead space above it.
- On tvOS, hero artwork should pin to the top-right edge and blend only on the left and bottom into the dark shell; text metadata can use a dark translucent hero panel with branded continuous corners.
- On tvOS, hero artwork should overscan slightly past the top and right edges so the shell background never peeks through there.
- tvOS selected media tiles should use a solid accent border plus a short, fully fading accent glow rather than a clipped hard-edged shadow.

## Settings

Current settings language:

- dark shell
- softened charcoal grouped panels
- white text with muted gray support labels
- accent icons and toggles
- floating close/action controls

Rules:

- Settings should feel parent-safe and serious, but still clearly part of Plinx.
- Use accent for the actionable part of each setting, not as page wallpaper.
- Group panels should feel soft and elevated, never harsh or sterile.

## Profile Selection

Current profile-switcher language:

- dark shell background
- fixed-height profile tiles for every account state
- green outline and soft glow for the active profile
- subtle glass or charcoal tile fill, never a full bright selection box
- branded chrome logout control instead of a raw destructive toolbar icon

Rules:

- Keep every profile tile the same height, even when a profile has no username or email.
- Use the active-state border and glow to indicate selection, not tile scaling or oversized fill.
- Keep the logout action in the same branded chrome language used elsewhere in the app shell.

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
- haptic/audio plink
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
