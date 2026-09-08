# Strimr Contribution Plan: Download Enrollment And Access Scoping

## Problem

The generic download manager historically published a device-wide item before
the host application could persist who was allowed to use it. Its duplicate,
status, and progress helpers also matched only a Plex rating key. Two servers or
profiles can therefore affect the same UI state, and a profile switch during an
asynchronous season/show enqueue can change the credentials used by later work.

An unreadable or undecodable index is a separate recovery hazard: restoring
background tasks against an empty in-memory array can persist that empty array
over the last recoverable index.

## Generic Seam

Strimr provides a host-configured `DownloadEnrollmentContext` containing an
opaque access-scope identifier and a pre-publication authorization/enrollment
callback. The manager captures the context and a `PlexAPIContext` operation
snapshot once at the public item, season, or show boundary. Nested episode work
reuses both values.

Persisted items carry the optional generic scope. Scoped consumers use
`(server identifier, access scope identifier, rating key)` while standalone
Strimr retains its existing unscoped behavior when no provider is configured.
The manager also exposes whether its index was missing, loaded, unreadable, or
corrupt and will not restore or persist over unreadable/corrupt state.

Plinx remains responsible for interpreting the opaque scope as a Plex profile,
applying kid-content policy, and persisting its versioned ownership envelope.
If durable index publication fails after enrollment, Strimr removes the
in-memory item and folder and invokes the host rollback callback before any
transfer starts. The Plinx callback also revalidates the live SessionManager
identity at publication time, so logout or a profile switch invalidates work
that began under the earlier authorization.

## Validation

- A direct item is authorized and enrolled before `items.append`.
- Every episode in season/show batches uses the context captured at batch start.
- Equal rating keys in different server/profile scopes do not share status,
  progress, or duplicate decisions.
- Missing legacy scope remains decodable.
- Index-write failure rolls back host enrollment and never starts a transfer.
- Logout or profile change before publication rejects the captured enrollment.
- Read/decode failure preserves the existing index and skips task restoration.
- Standalone Strimr behavior is unchanged without an enrollment provider.
