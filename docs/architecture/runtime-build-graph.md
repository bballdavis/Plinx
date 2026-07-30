# Runtime Build Graph

## Source Of Truth

`PlinxApp/project.yml` is the source of truth for the generated Xcode project. The checked-in `Plinx.xcodeproj` is local output and may be regenerated at any time.

## Build Composition

The `Plinx-iOS` target compiles:

- Plinx app code from `App`, `Views`, `Decorators`, `Adapters`, and `ViewModels`
- sibling Strimr shared source from `../../strimr/Shared`
- sibling Strimr iOS feature source from `../../strimr/Strimr-iOS/Features`
- Swift packages `PlinxCore`, `PlinxUI`, and `AetherEngine`

This is a same-module integration strategy, not a clean framework boundary. Plinx can therefore reach Strimr `internal` symbols without broadening upstream access control.

## Why Selected Strimr Files Are Replaced

`project.yml` excludes a small set of Strimr files and swaps in Plinx-owned replacements when Plinx needs different behavior or a safer implementation. Current replacement categories include:

- a fail-closed playback launcher that re-authorizes fresh metadata immediately
  before queue presentation
- Plinx-owned settings surfaces whose upstream equivalents would otherwise
  collide by filename in the shared app module
- media backdrop rendering adjustments for current SDK behavior
- a rating-label adapter for Plinx-owned rating artwork
- no-op error reporting to preserve zero-collection requirements
- branded auth/root views so no Strimr assets leak into the Plinx binary

The AetherEngine dependency is pinned to an exact revision in `project.yml`.
`Packages/PlinxCore` deliberately has no player-engine dependency, avoiding
duplicate FFmpeg product graphs.

When adding another exclusion, document:

1. why Plinx could not solve the problem in a thinner layer
2. whether the change should become an upstream Strimr patch later
3. which tests prove the replacement is safe

## Generated Project Expectations

- Run `xcodegen generate` from `PlinxApp/` or use `scripts/generate_xcodeproj.sh`.
- Treat `PlinxApp/project.yml` as canonical and `PlinxApp/Plinx.xcodeproj/` as generated local output.
- CI regenerates the project before building or testing.

## Resource Patching

`scripts/patch_resources.py` exists to ensure the generated project retains the required resource references for:

- `Assets.xcassets`
- iOS `LaunchScreen.storyboard`
- `PrivacyInfo.xcprivacy`
- `Plinx.strings`
- sibling `../../strimr/Localizable.xcstrings`

That script should reflect the current runtime layout only. It is not a place to preserve obsolete path migrations.
The generated app targets must each own a distinct resource build phase and
distinct build-file entries. Sharing a resource phase or build-file object
between `Plinx-iOS` and `Plinx-tvOS` can make Xcode copy resources into only one
bundle. Generated target ordering is not stable enough to patch the first
`PBXNativeTarget` build-phase list.

## Related Docs

- `docs/architecture/overview.md`
- `docs/architecture/strimr-integration.md`
- `docs/development/ci.md`
