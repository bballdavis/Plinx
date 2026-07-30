# Strimr Contribution Plan: Explicit Default-Server Preference

## Recommendation

Coordinate through an issue, especially with upstream issue `#71` concerning
multiple servers. The proposal should distinguish the server used now from the
server the user intentionally made the default.

## Gap and Evidence

Current upstream remembers the most recently selected server under
`strimr.plex.serverIdentifier`; it has no explicit default preference. Fork
commit `2838051` adds a default identifier, but mixes in Plinx legacy-key
migration and does not provide a complete upstream interaction.

## Proposed Change

1. Add an observable optional `defaultServerIdentifier` stored under a
   Strimr-owned key.
2. During server selection, provide a localized “Make this my default server”
   control and pass that intent to `SessionManager`.
3. Prefer the explicit default during automatic connection when it is still
   available; otherwise use the normal reachable-server fallback.
4. Do not overwrite the default merely because the session temporarily falls
   back to another server.
5. Offer a way to clear or replace the preference from the same server-selection
   flow.
6. If upstream chooses a new key, migrate only its existing Strimr
   last-selection value; never include Plinx keys.

## Scope Exclusions

- Plinx bundle identifiers, defaults keys, UI-test tokens, or direct-server
  bootstrap
- Automatic preference changes caused by transient reachability
- A full multi-server account-management redesign

## Validation

- No preference, valid preference, missing preference, and unreachable default.
- Temporary fallback followed by recovery without changing the stored default.
- Replace and clear actions, persistence across launch, and localized UI.
- Multiple connections representing the same Plex resource.

## Upstream Shape

- Issue: comment/proposal on `#71`, or `Add an explicit default Plex server`
- Branch: `feat/default-server-preference`
- Commit: `feat: add an explicit default server preference`
- PR: `feat: add default server selection`
- Dependency: resolve expected behavior with the maintainer before coding.
