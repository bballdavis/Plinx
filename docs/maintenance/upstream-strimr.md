# Upstream Strimr Provenance

Plinx began as a kid-safe skin over [Strimr](https://github.com/wunax/strimr),
an open-source Plex and Jellyfin client by Thomas (wunax) and contributors. On
2026-11-23 Plinx absorbed Strimr's source and became a single codebase. There is
no longer a separate Strimr directory, sibling checkout, pin, or seam contract.
See the [hard-fork plan](strimr-hard-fork-plan.md) for the decision.

| Field | Value |
|---|---|
| Absorbed upstream commit | `0235d271d6b444c45df3c071f9bd4482e2b0f6f1` (`wunax/strimr` `main`, 2026-11-21) |
| Absorbed on | 2026-11-23 |
| License | GPL-3.0, the same license as Plinx (`LICENSE`) |
| Last upstream feature review | 2026-11-23 ([commit triage](strimr-contributions/15-upstream-main-migration-plan.md)) |

## Where the upstream code lives

| Upstream path | Plinx path |
|---|---|
| `Shared/` | `PlinxApp/Core/` |
| `Strimr-iOS/Features/` | `PlinxApp/Platform/iOS/` |
| `Strimr-tvOS/Features/`, `Strimr-tvOS/Shared/` | `PlinxApp/Platform/tvOS/` |
| `Localizable.xcstrings` | `PlinxApp/Resources/Localizable.xcstrings` |
| `StrimrTests/` | `PlinxApp/CoreTests/` |

When Plinx already had its own version of a screen or helper, the upstream copy
was deleted, so each concept has one implementation. Upstream's macOS app, Top
Shelf extension, Trakt and Simkl sync, release tooling, and Sentry reporting
were not carried over.

Persisted identifiers that came from Strimr, such as the Keychain key
`strimr.plex.authToken`, keep their original names. Renaming them would sign
existing families out.

## Taking upstream changes

Upstream is a source of ideas and fixes, not a dependency. Review it on a
regular schedule:

```bash
git fetch upstream
git log --oneline 0235d271d6b444c45df3c071f9bd4482e2b0f6f1..upstream/main
```

The `upstream` remote points at `wunax/strimr` with pushes disabled. Upstream's
paths no longer match Plinx's, so port each change by hand. Keep the upstream
commit in the message (for example, `Ported from wunax/strimr@<sha>`). Record
each review here and in the triage document. Judge every change against the
kid-safety, zero-collection, and no-external-links rules in `AGENTS.md`.

## Attribution

Strimr's copyright notices stay in the files that carry them. The about and
licenses surface credits Strimr. Contributions that are generic bug fixes can
still be offered upstream as pull requests.
