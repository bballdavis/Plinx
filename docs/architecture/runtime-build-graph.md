# Runtime Build Graph

## Source Of Truth

`PlinxApp/project.yml` is the source of truth for the generated Xcode project.
`PlinxApp/Plinx.xcodeproj` is a checked-in, deterministic deployment mirror so
Xcode Cloud can discover the project plus the shared `Plinx-iOS` and
`Plinx-tvOS` build schemes.

## Build Composition

Each app target compiles one module. `Plinx-iOS` compiles:

- the Plinx layer from `App`, `Views`, `Adapters`, and `ViewModels`
- the absorbed media stack from `Core` and `Platform/iOS`
- the local packages `PlinxCore` and `PlinxUI`
- the Swift packages AetherEngine, GRDB, and SwiftAssRenderer

`Plinx-tvOS` compiles the same Plinx layer and `Core` with `Platform/tvOS`.

Every remote Swift package is pinned to an exact `revision` or `exactVersion`
in `project.yml`; the
[current dependencies](../maintenance/current-dependencies.mdx) page renders
the pins. `Packages/PlinxCore` deliberately has no player-engine dependency,
avoiding duplicate FFmpeg product graphs. AetherEngine is consumed only by the
app targets.

## Target Exclusions

The tvOS target excludes some files, for two reasons only:

- they are iOS-only: downloads, the offline store and its cached services,
  Picture in Picture, and the iOS-only Plinx download and player-control views
- Plinx or upstream has a separate tvOS screen for the same concept

Do not exclude a file to replace one of its types with a same-named Plinx
type. Change the original instead, so each concept has one implementation.
Delete a file that neither target reaches.

## Generated Project Expectations

- Run `xcodegen generate` from `PlinxApp/` or use `scripts/generate_xcodeproj.sh`.
- Treat `PlinxApp/project.yml` as canonical and the checked-in
  `PlinxApp/Plinx.xcodeproj/` as its generated deployment mirror.
- Commit regenerated project output with every `project.yml` change, including
  both shared scheme files and the nested workspace descriptor. Never commit
  `xcuserdata` or other per-user state.
- Use `scripts/generate_xcodeproj.sh --check` in a clean checkout to verify the
  committed project matches a fresh generation after Xcode applies its current
  shared-scheme normalization.
- Use `scripts/generate_xcodeproj.sh --check-portable` for the same generated
  project drift gate without Xcode normalization; GitHub runs this mode on
  Ubuntu whenever project inputs change.
- Xcode Cloud needs no post-clone step: everything the project compiles is in
  the repository, and Swift packages resolve from `project.yml`.

## Resource Patching

`scripts/support/patch_resources.py` exists to ensure the generated project retains the required resource references for:

- `Assets.xcassets`
- iOS `LaunchScreen.storyboard`
- `PrivacyInfo.xcprivacy`
- `Plinx.strings`
- `Resources/Localizable.xcstrings`, which holds the string catalog that came
  with the absorbed code

That script should reflect the current runtime layout only. It is not a place to preserve obsolete path migrations.
XcodeGen does not read the `resources:` lists in `PlinxApp/project.yml`, so the
script adds those files after generation. Each generated app target must have
exactly one resource build phase and its own build-file entries. XcodeGen
already generates a resource phase per app target for the license texts in
`Core/Resources/Licenses`; the script adds the app resources to that phase and
creates a target-owned phase only when XcodeGen generated none. A second
resource phase makes Xcode warn that the target has multiple Copy Bundle
Resources build phases and mis-route the generated asset symbol source.
Sharing a resource phase or build-file object between `Plinx-iOS` and
`Plinx-tvOS` can make Xcode copy resources into only one bundle. Generated
target ordering is not stable enough to patch the first `PBXNativeTarget`
build-phase list.

## Related Docs

- `docs/architecture/overview.md`
- `docs/architecture/strimr-integration.md`
- `docs/development/ci.md`
