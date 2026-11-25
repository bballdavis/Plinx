# Open-Source Release Compliance

Plinx is licensed under GPL-3.0 and includes source absorbed from
[Strimr](https://github.com/wunax/strimr), which is also GPL-3.0. AetherEngine
is licensed under LGPL-3.0 with its documented App Store and DRM exception.
This document is an engineering checklist, not legal advice.

## Corresponding Source

The Plinx repository is the complete corresponding source for every build made
from it. The Strimr code Plinx absorbed lives in `PlinxApp/Core` and
`PlinxApp/Platform`; no other repository or checkout is part of a build.
Swift Package Manager fetches AetherEngine, GRDB and SwiftAssRenderer as source
at the exact pins in `PlinxApp/project.yml`. The
[current dependencies](../maintenance/current-dependencies.mdx) page shows
those pins and the absorbed upstream base.

### Releases built before the absorption

Releases built before 2026-11-23 compiled Plinx together with a pinned commit of
the `bballdavis/strimr` fork. The pinned Strimr commit for each of those
releases is in that release tag's `config/release-dependencies.env`. That fork
must stay available and read-only, with every commit a shipped build used
reachable, because those commits are the corresponding source for past
releases. Do not delete the fork, rewrite its history, or move the commits a
shipped build used.

## Required Release Materials

For every distributed binary:

- preserve copyright and license notices, including Strimr's;
- publish the exact Plinx commit used to build it;
- identify the exact Swift package revisions from `PlinxApp/project.yml`;
- include complete build instructions ([development setup](../development/setup.md));
- make the complete corresponding source available for the shipped version;
- keep source, privacy and license links behind the parental gate in the app;
- obtain legal confirmation that the selected App Store EULA and distribution
  terms are compatible with the licenses before submission.

Run `scripts/build_compliance_bundle.sh` from a clean, committed release
checkout. Keep the resulting archive with the App Store build records and
publish it at the source URL referenced by the release. The bundle contains:

- a `git archive` of the release commit, including the absorbed Strimr code;
- this checklist;
- `SOURCE-MANIFEST.txt`, naming the Plinx commit, the absorbed Strimr base, and
  each Swift package's URL and exact pin.

The script refuses a dirty tree and any remote Swift package without an exact
`revision` or `exactVersion`.

## Attribution And Notices

- `LICENSE` holds the GPL-3.0 text for Plinx, including the absorbed Strimr
  code.
- Keep Strimr's copyright notices in the files that carry them. The
  [upstream provenance page](../maintenance/upstream-strimr.md) records where
  that code came from.
- The in-app licenses screen (`PlinxLicensesSettingsView`) lists Plinx,
  Strimr and every bundled third-party component from
  `OpenSourceLicense.dependencies`, with the license texts in
  `PlinxApp/Core/Resources/Licenses`. It is reachable only from parent-gated
  Settings.
- When a dependency is added or changed, add or update its entry in
  `OpenSourceLicense` and its license text. Confirm its license is compatible
  before it ships. The SwiftAssRenderer stack (swift-ass-renderer, libass,
  FreeType, HarfBuzz, FriBidi and Fontconfig) arrived with the absorption, so
  review it before the first release that includes it.

### What the license list covers

The list names every component linked into the shipped app targets: the
packages in `PlinxApp/project.yml` and the products they pull in. Each license
text must match the `LICENSE` file of the package checkout the build resolves.

- **swift-ass-renderer** is the `wunax/swift-ass-renderer` fork, the one
  `PlinxApp/project.yml` pins and the build links. The list's link and license
  text are that fork's.
- **swift-issue-reporting** is the current name of Point-Free's
  `xctest-dynamic-overlay` package. It still ships, through swift-ass-renderer
  and combine-schedulers, so its entry and license file use the new name and
  URL.
- **Not listed, because Plinx does not link them:**
  - Sentry. Plinx links no crash-reporting or analytics SDK; upstream's
    reporter was not carried over.
  - SMBClient. Only AetherEngine's `AetherEngineSMB` product brings it in, and
    no Plinx target links that product or imports it.
  - LibTrueHD. It comes in only through AetherEngine's `TrueHDObjectAudio`
    package trait, which is off.

If a target starts linking `AetherEngineSMB`, or the TrueHD trait is turned on,
the component and its license text (and any NOTICE file) must be added to the
list before that build ships. Test-only packages are not listed.
