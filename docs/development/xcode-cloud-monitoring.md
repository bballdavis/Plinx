# Xcode Cloud Monitoring And Management

Plinx uses a local App Store Connect API client to inspect Xcode Cloud build
runs and perform a narrow set of explicit management operations. Status checks
are read-only. Workflow project-path changes, enabling or disabling workflows,
and manual build starts require a specific command plus `--apply`; without
`--apply`, the client only prints the proposed request.

## Credential Boundary

Never commit an App Store Connect `.p8` key or paste its contents into a chat,
terminal transcript, issue, or pull request. Keep the key and its config
outside the repository with owner-only permissions.

Use a dedicated App Store Connect API key with the least role that can perform
the intended Plinx Xcode Cloud operations. A monitoring-only key does not need
write access; the management key must be allowed to manage Xcode Cloud
workflows. Record the key ID and issuer ID, then store the downloaded key in a
private local directory. Team API keys apply across all apps in the App Store
Connect account, so revoke the key immediately if it is lost or exposed.

The monitor generates a new ES256 JWT in memory for each API request. Tokens
expire after two minutes and are never printed or written to disk.

## Local Setup

Create the private config directory and copy the example:

```bash
mkdir -p "$HOME/.config/plinx"
cp config/xcode-cloud-monitor.env.example "$HOME/.config/plinx/xcode-cloud.env"
chmod 600 "$HOME/.config/plinx/xcode-cloud.env"
chmod 600 /absolute/path/to/AuthKey_YOUR_KEY_ID.p8
```

Edit `~/.config/plinx/xcode-cloud.env` and set:

- `PLINX_ASC_KEY_ID`: the App Store Connect API key ID
- `PLINX_ASC_ISSUER_ID`: the issuer ID shown under Users and Access → Integrations
- `PLINX_ASC_KEY_PATH`: the absolute path to the matching `.p8` file
- `PLINX_XCODE_CLOUD_PRODUCT_ID`: optional; pin this after initial discovery

The client refuses a key that is not owned by the current user or is readable
by a group or other users.

## Read Recent Builds

```bash
./scripts/xcode_cloud_monitor.py
```

On the first run, omit `PLINX_XCODE_CLOUD_PRODUCT_ID` to list every accessible
Xcode Cloud product, workflow ID, project/workspace path, and recent build.
Copy the Plinx product ID into the local config afterward.

Fetch structured issues for failed actions:

```bash
./scripts/xcode_cloud_monitor.py --details
```

Machine-readable output and a failure exit status are available for scheduled
monitoring:

```bash
./scripts/xcode_cloud_monitor.py \
  --details \
  --json \
  --fail-on-failure
```

The failure exit status is `2`. Configuration, authentication, and network
errors use status `1`.

## Project And Workflow Setup

Xcode Cloud requires a project or workspace that is continuously present in
the repository. Plinx therefore commits the deterministic
`PlinxApp/Plinx.xcodeproj` generated from canonical `PlinxApp/project.yml`.
After this project is merged into the branch App Store Connect scans, set:

```text
Project or Workspace: PlinxApp/Plinx.xcodeproj
Xcode Version: 26.5
Archive scheme: Plinx-iOS
```

`PlinxApp/ci_scripts/ci_post_clone.sh` runs automatically because it is beside
the project. It clones the sibling Strimr repository at the exact commit from
`config/release-dependencies.env` and verifies the source integration contract.

The same project-path change can be planned through the API after a status
command reveals the workflow ID:

```bash
./scripts/xcode_cloud_monitor.py \
  --set-container WORKFLOW_ID PlinxApp/Plinx.xcodeproj
```

Review the JSON dry run, then deliberately apply it:

```bash
./scripts/xcode_cloud_monitor.py \
  --set-container WORKFLOW_ID PlinxApp/Plinx.xcodeproj \
  --apply
```

Enable or disable a workflow, or start a manual build, with the same dry-run
boundary:

```bash
./scripts/xcode_cloud_monitor.py --enable-workflow WORKFLOW_ID
./scripts/xcode_cloud_monitor.py --disable-workflow WORKFLOW_ID
./scripts/xcode_cloud_monitor.py --start-workflow WORKFLOW_ID
```

Append `--apply` only after reviewing the operation. The client intentionally
does not expose workflow deletion, artifact distribution, TestFlight group
changes, or App Store submission.

## Codex Scheduled Monitor

Test the command manually before scheduling it. A project-scoped Codex task can
then run it periodically in an isolated worktree and report only new running or
failed builds. Keep the computer powered on and the desktop app running for a
local scheduled task.

A safe unattended task should remain read-only:

> Check the newest Plinx Xcode Cloud build with
> `./scripts/xcode_cloud_monitor.py --limit 1 --details --json`. Report a new failure or
> a build still running; otherwise report no change. Do not modify files, push,
> restart builds, or distribute artifacts.

Fixing failures and applying management operations should be separate,
deliberate tasks. Keep code fixes in an isolated worktree, run focused local
tests, and require review before pushing. Never give an unattended task
`--apply` access or permission to print, copy, upload, or modify the App Store
Connect private key.

## Verification

The credential-free monitor tests run with:

```bash
python3 -m unittest scripts/tests/test_xcode_cloud_monitor.py
```

They cover config parsing, private-key permission checks, ECDSA signature
encoding, build classification, product selection, management request shapes,
and dry-run behavior without contacting Apple or reading a real key.
