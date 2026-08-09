# Internal TestFlight Delivery

`dev` is CI-only. Push the exact `dev` commit you want testers to receive to
`dev-testflight`; `.github/workflows/build.yml` then runs its package,
integration, and Xcode checks. When they pass, the `testflight-internal` job
archives the exact pinned source tree and submits it to App Store Connect. The
archive gets a UTC-timestamp build number, so each submitted build is unique
and increasing.

The delivery uses Xcode's App Store Connect API-key support for automatic
provisioning and upload. Its export options mark every `dev` build as
internal-only: it is available to internal App Store Connect testers after
Apple finishes processing, but cannot be sent to external TestFlight testers
or submitted to App Review.

An upload job succeeding means Apple accepted the submission. Apple processes
the build asynchronously, so check the TestFlight build status and any
processing email before treating it as ready for testers.

## One-Time Account Setup

1. In App Store Connect, request API access if it is not already enabled, then
   create a dedicated team API key that can access the Plinx app and the
   developer resources required for automatic signing. Follow Apple’s current
   role guidance; do not reuse a personal Xcode session or personal API key.
2. Download the `.p8` private key once. Store it only in GitHub Actions
   secrets. It is not recoverable from App Store Connect after the download.
3. In the Plinx GitHub repository, add these Actions secrets:

   | Secret | Value |
   | --- | --- |
   | `APP_STORE_CONNECT_API_KEY_ID` | The App Store Connect API key ID |
   | `APP_STORE_CONNECT_API_ISSUER_ID` | The team issuer ID |
   | `APP_STORE_CONNECT_API_PRIVATE_KEY` | The complete contents of the downloaded `.p8` file |

4. Push the current `dev` commit to `dev-testflight` and confirm that App Store
   Connect processes the resulting build. The first delivery can create or
   refresh Apple-managed signing assets through the configured developer team.

Use a dedicated key, grant the least access compatible with signing and upload,
and revoke it immediately if the private key is exposed. GitHub masks secret
values, but workflow authors must never echo environment variables or the
private-key file.

Protect `dev`: require reviewed pull requests, restrict who can push or merge,
and keep the workflow file under code review. A person able to push arbitrary
workflow changes to `dev` can otherwise make a future workflow attempt to
expose its own delivery secrets.

Apply the same protections to `dev-testflight`, and permit only maintainers to
update it. That branch has access to the delivery secrets and is the explicit
gate between ordinary development work and TestFlight distribution.

## Promote A Build To TestFlight

After `dev` has the exact commit you want to test, fast-forward the dedicated
delivery branch from it:

```bash
git fetch origin
git push origin origin/dev:refs/heads/dev-testflight
```

This creates `dev-testflight` on first use and subsequently advances it only
when `dev` is a fast-forward update. Do not force-push the delivery branch. A
push to `dev` alone only runs CI; the ref update to `dev-testflight` is the
intentional action that queues a new internal TestFlight build.

## Export Compliance

Plinx declares `ITSAppUsesNonExemptEncryption` as `false` in both
`PlinxApp/project.yml` and the source `Info.plist`. This matches the current
binary assessment: the app uses standard platform and network encryption and
does not implement non-exempt cryptography. The archive validator checks the
final built plist before an upload proceeds.

Reassess this declaration before adding cryptographic code, a cryptography
library, or a dependency that changes the final binary’s encryption behavior.
If the declaration becomes inaccurate, stop automated delivery until the App
Store Connect export-compliance process and any required documentation are
complete.

## Local Delivery

The same archive script supports a deliberate local upload when all API-key
arguments are supplied:

```bash
./scripts/build_release_archive.sh \
  --upload-testflight \
  --api-key-path /secure/path/AuthKey_ABC123.p8 \
  --api-key-id ABC123 \
  --api-key-issuer-id YOUR-ISSUER-ID
```

The script uses `scripts/testflight_export_options.plist`, which is deliberately
restricted to internal-only TestFlight distribution. Do not change that file to
permit external testing or App Store submission as a side effect of development
delivery.

## Release Boundary

`dev-testflight` builds do not replace the release process. Continue to follow
the paired-dependency promotion, `main` merge, tag, metadata, screenshot, and
review gates in [versioning and releases](versioning-and-releases.md) and the
[App Store runbook](../release/app-store.md). A production release requires an
explicit, separately reviewed distribution step.
