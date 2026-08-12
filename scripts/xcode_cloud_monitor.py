#!/usr/bin/env python3
"""Inspect and deliberately manage Xcode Cloud through App Store Connect.

Status checks are read-only. Workflow changes and build starts require both an
explicit operation and --apply. The client never prints the private key,
generated JWT, or Authorization header.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import time
from typing import Any
import urllib.error
import urllib.parse
import urllib.request


API_ORIGIN = "https://api.appstoreconnect.apple.com"
DEFAULT_CONFIG = Path.home() / ".config" / "plinx" / "xcode-cloud.env"
DEFAULT_LIMIT = 10
FAILURE_STATUSES = {"FAILED", "ERRORED"}


class MonitorError(RuntimeError):
    """A safe-to-display monitor error."""


def base64url(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def _read_der_length(data: bytes, offset: int) -> tuple[int, int]:
    if offset >= len(data):
        raise MonitorError("Invalid ECDSA signature returned by OpenSSL.")
    first = data[offset]
    offset += 1
    if first < 0x80:
        return first, offset
    count = first & 0x7F
    if count == 0 or count > 2 or offset + count > len(data):
        raise MonitorError("Invalid ECDSA signature returned by OpenSSL.")
    return int.from_bytes(data[offset : offset + count], "big"), offset + count


def der_ecdsa_to_jose(signature: bytes, component_size: int = 32) -> bytes:
    """Convert an ASN.1 DER ECDSA signature to the JWT R || S form."""
    if not signature or signature[0] != 0x30:
        raise MonitorError("Invalid ECDSA signature returned by OpenSSL.")
    sequence_length, offset = _read_der_length(signature, 1)
    if offset + sequence_length != len(signature):
        raise MonitorError("Invalid ECDSA signature returned by OpenSSL.")

    components: list[bytes] = []
    for _ in range(2):
        if offset >= len(signature) or signature[offset] != 0x02:
            raise MonitorError("Invalid ECDSA signature returned by OpenSSL.")
        length, value_offset = _read_der_length(signature, offset + 1)
        value = signature[value_offset : value_offset + length]
        offset = value_offset + length
        value = value.lstrip(b"\x00") or b"\x00"
        if len(value) > component_size:
            raise MonitorError("ECDSA signature component is too large.")
        components.append(value.rjust(component_size, b"\x00"))

    if offset != len(signature):
        raise MonitorError("Invalid ECDSA signature returned by OpenSSL.")
    return b"".join(components)


def load_env_file(path: Path) -> dict[str, str]:
    if not path.is_file():
        raise MonitorError(
            f"Missing Xcode Cloud config: {path}. Copy the documented example "
            "to this local-only path and fill in its identifiers."
        )

    values: dict[str, str] = {}
    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise MonitorError(f"Invalid config line {line_number} in {path}.")
        name, value = line.split("=", 1)
        name = name.strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        if not re.fullmatch(r"[A-Z][A-Z0-9_]*", name):
            raise MonitorError(f"Invalid config key on line {line_number} in {path}.")
        values[name] = value
    return values


def resolved_config(path: Path) -> dict[str, str]:
    values = load_env_file(path)
    for name in (
        "PLINX_ASC_KEY_ID",
        "PLINX_ASC_ISSUER_ID",
        "PLINX_ASC_KEY_PATH",
        "PLINX_XCODE_CLOUD_PRODUCT_ID",
    ):
        if os.environ.get(name):
            values[name] = os.environ[name]

    missing = [
        name
        for name in ("PLINX_ASC_KEY_ID", "PLINX_ASC_ISSUER_ID", "PLINX_ASC_KEY_PATH")
        if not values.get(name)
    ]
    if missing:
        raise MonitorError(f"Missing required config value(s): {', '.join(missing)}.")

    key_id = values["PLINX_ASC_KEY_ID"]
    if not re.fullmatch(r"[A-Za-z0-9]+", key_id):
        raise MonitorError("PLINX_ASC_KEY_ID contains unexpected characters.")
    issuer_id = values["PLINX_ASC_ISSUER_ID"]
    if not re.fullmatch(r"[A-Fa-f0-9-]{16,}", issuer_id):
        raise MonitorError("PLINX_ASC_ISSUER_ID does not look like an issuer ID.")

    key_path = Path(values["PLINX_ASC_KEY_PATH"]).expanduser().resolve()
    validate_private_key_path(key_path)
    values["PLINX_ASC_KEY_PATH"] = str(key_path)
    return values


def validate_private_key_path(path: Path) -> None:
    if not path.is_file():
        raise MonitorError(f"App Store Connect private key not found: {path}.")
    file_stat = path.stat()
    if file_stat.st_uid != os.getuid():
        raise MonitorError("The App Store Connect private key must be owned by the current user.")
    if stat.S_IMODE(file_stat.st_mode) & 0o077:
        raise MonitorError(
            f"Private key permissions are too open: {path}. Run chmod 600 on the key."
        )


def create_jwt(key_id: str, issuer_id: str, key_path: Path) -> str:
    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {
        "iss": issuer_id,
        "iat": now,
        "exp": now + 120,
        "aud": "appstoreconnect-v1",
    }
    encoded_header = base64url(json.dumps(header, separators=(",", ":")).encode("utf-8"))
    encoded_payload = base64url(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    signing_input = f"{encoded_header}.{encoded_payload}".encode("ascii")

    openssl = shutil.which("openssl")
    if not openssl:
        raise MonitorError("OpenSSL is required to sign App Store Connect requests.")
    try:
        result = subprocess.run(
            [openssl, "dgst", "-sha256", "-sign", str(key_path)],
            input=signing_input,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )
    except subprocess.CalledProcessError as exc:
        raise MonitorError(
            "OpenSSL could not sign the App Store Connect request. Verify that "
            "the selected file is the matching unencrypted .p8 key."
        ) from exc

    signature = base64url(der_ecdsa_to_jose(result.stdout))
    return f"{encoded_header}.{encoded_payload}.{signature}"


def safe_apple_error(body: bytes, status: int) -> str:
    try:
        payload = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return f"App Store Connect returned HTTP {status}."
    errors = payload.get("errors") if isinstance(payload, dict) else None
    if not isinstance(errors, list):
        return f"App Store Connect returned HTTP {status}."
    messages = []
    for error in errors[:5]:
        if not isinstance(error, dict):
            continue
        title = str(error.get("title") or "Request failed")
        detail = str(error.get("detail") or "").strip()
        messages.append(f"{title}: {detail}" if detail else title)
    return "; ".join(messages) or f"App Store Connect returned HTTP {status}."


class AppStoreConnectClient:
    def __init__(self, key_id: str, issuer_id: str, key_path: Path):
        self.key_id = key_id
        self.issuer_id = issuer_id
        self.key_path = key_path

    def request(
        self,
        method: str,
        path: str,
        query: dict[str, Any] | None = None,
        body: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        if not path.startswith("/v1/") or ".." in path:
            raise MonitorError("Refusing an unexpected App Store Connect API path.")
        if method not in {"GET", "POST", "PATCH"}:
            raise MonitorError(f"Refusing unsupported App Store Connect method: {method}.")
        if method == "GET" and body is not None:
            raise MonitorError("Refusing a request body on a read operation.")
        url = f"{API_ORIGIN}{path}"
        if query:
            url = f"{url}?{urllib.parse.urlencode(query, doseq=True)}"
        token = create_jwt(self.key_id, self.issuer_id, self.key_path)
        headers = {
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
            "User-Agent": "Plinx-Xcode-Cloud/1",
        }
        encoded_body = None
        if body is not None:
            headers["Content-Type"] = "application/json"
            encoded_body = json.dumps(body, separators=(",", ":")).encode("utf-8")
        request = urllib.request.Request(
            url,
            data=encoded_body,
            headers=headers,
            method=method,
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                try:
                    return json.load(response)
                except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                    raise MonitorError("App Store Connect returned invalid JSON.") from exc
        except urllib.error.HTTPError as exc:
            raise MonitorError(safe_apple_error(exc.read(), exc.code)) from exc
        except urllib.error.URLError as exc:
            raise MonitorError(f"Could not reach App Store Connect: {exc.reason}.") from exc

    def get(self, path: str, query: dict[str, Any] | None = None) -> dict[str, Any]:
        return self.request("GET", path, query=query)

    def apply_plan(self, plan: dict[str, Any]) -> dict[str, Any]:
        method = str(plan["method"])
        path = str(plan["path"])
        if method == "PATCH" and not re.fullmatch(r"/v1/ciWorkflows/[A-Za-z0-9-]+", path):
            raise MonitorError("Refusing a workflow update outside the supported endpoint.")
        if method == "POST" and path != "/v1/ciBuildRuns":
            raise MonitorError("Refusing a build start outside the supported endpoint.")
        if method not in {"PATCH", "POST"}:
            raise MonitorError("Refusing a non-management operation in apply mode.")
        return self.request(method, path, body=plan["body"])


def validate_resource_id(value: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9-]{1,128}", value):
        raise MonitorError("The workflow ID contains unexpected characters.")
    return value


def validate_container_file_path(value: str) -> str:
    path = Path(value)
    if path.is_absolute() or ".." in path.parts:
        raise MonitorError("The project or workspace path must be repository-relative.")
    if path.suffix not in {".xcodeproj", ".xcworkspace"}:
        raise MonitorError("The container path must end in .xcodeproj or .xcworkspace.")
    normalized = path.as_posix()
    if normalized in {".", ""}:
        raise MonitorError("The project or workspace path cannot be empty.")
    return normalized


def workflow_update_plan(workflow_id: str, attributes: dict[str, Any]) -> dict[str, Any]:
    workflow_id = validate_resource_id(workflow_id)
    return {
        "method": "PATCH",
        "path": f"/v1/ciWorkflows/{workflow_id}",
        "body": {
            "data": {
                "type": "ciWorkflows",
                "id": workflow_id,
                "attributes": attributes,
            }
        },
    }


def build_start_plan(workflow_id: str) -> dict[str, Any]:
    workflow_id = validate_resource_id(workflow_id)
    return {
        "method": "POST",
        "path": "/v1/ciBuildRuns",
        "body": {
            "data": {
                "type": "ciBuildRuns",
                "attributes": {},
                "relationships": {
                    "workflow": {
                        "data": {"type": "ciWorkflows", "id": workflow_id}
                    }
                },
            }
        },
    }


def mutation_plan(args: argparse.Namespace) -> dict[str, Any] | None:
    if args.set_container:
        workflow_id, container_path = args.set_container
        return workflow_update_plan(
            workflow_id,
            {"containerFilePath": validate_container_file_path(container_path)},
        )
    if args.enable_workflow:
        return workflow_update_plan(args.enable_workflow, {"isEnabled": True})
    if args.disable_workflow:
        return workflow_update_plan(args.disable_workflow, {"isEnabled": False})
    if args.start_workflow:
        return build_start_plan(args.start_workflow)
    return None


def resource_name(resource: dict[str, Any]) -> str:
    attributes = resource.get("attributes") or {}
    return str(attributes.get("name") or attributes.get("title") or resource.get("id") or "Unknown")


def classify_build(build: dict[str, Any]) -> str:
    attributes = build.get("attributes") or {}
    progress = attributes.get("executionProgress")
    completion = attributes.get("completionStatus")
    if progress != "COMPLETE":
        return "running"
    if completion == "SUCCEEDED":
        return "succeeded"
    if completion in FAILURE_STATUSES:
        return "failed"
    return "completed"


def build_summary(build: dict[str, Any], product: dict[str, Any]) -> dict[str, Any]:
    attributes = build.get("attributes") or {}
    commit = attributes.get("sourceCommit") or {}
    issue_counts = attributes.get("issueCounts") or {}
    return {
        "id": build.get("id"),
        "product": resource_name(product),
        "number": attributes.get("number"),
        "state": classify_build(build),
        "completionStatus": attributes.get("completionStatus"),
        "createdDate": attributes.get("createdDate"),
        "startedDate": attributes.get("startedDate"),
        "finishedDate": attributes.get("finishedDate"),
        "commitSha": commit.get("commitSha"),
        "commitMessage": commit.get("message"),
        "issueCounts": issue_counts,
    }


def select_products(products: list[dict[str, Any]], selector: str | None) -> list[dict[str, Any]]:
    if not selector:
        return products
    normalized = selector.casefold()
    matches = [
        product
        for product in products
        if product.get("id") == selector or resource_name(product).casefold() == normalized
    ]
    if not matches:
        raise MonitorError(f"No Xcode Cloud product matched {selector!r}.")
    return matches


def collect_action_diagnostics(
    client: AppStoreConnectClient, build_id: str
) -> list[dict[str, Any]]:
    actions = client.get(f"/v1/ciBuildRuns/{build_id}/actions", {"limit": 200}).get("data", [])
    diagnostics: list[dict[str, Any]] = []
    for action in actions:
        attributes = action.get("attributes") or {}
        completion = attributes.get("completionStatus")
        if completion not in FAILURE_STATUSES:
            continue
        action_id = str(action.get("id"))
        issues = client.get(f"/v1/ciBuildActions/{action_id}/issues", {"limit": 200}).get("data", [])
        test_results = []
        if attributes.get("actionType") == "TEST":
            test_results = client.get(
                f"/v1/ciBuildActions/{action_id}/testResults", {"limit": 200}
            ).get("data", [])
        failed_tests = []
        for result in test_results:
            result_attributes = result.get("attributes") or {}
            if result_attributes.get("status") != "FAILURE":
                continue
            file_source = result_attributes.get("fileSource") or {}
            failed_tests.append(
                {
                    "className": result_attributes.get("className"),
                    "name": result_attributes.get("name"),
                    "message": result_attributes.get("message"),
                    "fileSource": file_source.get("path"),
                    "lineNumber": file_source.get("lineNumber"),
                }
            )
        diagnostics.append(
            {
                "actionId": action_id,
                "name": attributes.get("name") or attributes.get("actionType") or action_id,
                "completionStatus": completion,
                "issues": [
                    {
                        "issueType": (issue.get("attributes") or {}).get("issueType"),
                        "message": (issue.get("attributes") or {}).get("message"),
                        "fileSource": ((issue.get("attributes") or {}).get("fileSource") or {}).get("path"),
                        "lineNumber": ((issue.get("attributes") or {}).get("fileSource") or {}).get("lineNumber"),
                    }
                    for issue in issues
                ],
                "failedTests": failed_tests,
            }
        )
    return diagnostics


def print_human_report(report: dict[str, Any]) -> None:
    products = report["products"]
    if not products:
        print("No Xcode Cloud products were returned.")
        return
    for product in products:
        print(f"{product['name']} ({product['id']})")
        for workflow in product.get("workflows", []):
            state = "enabled" if workflow["isEnabled"] else "disabled"
            container = workflow.get("containerFilePath") or "no project/workspace"
            print(f"  workflow {workflow['name']} [{workflow['id']}] {state}: {container}")
        builds = product["builds"]
        if not builds:
            print("  No build runs found.")
            continue
        for build in builds:
            number = build.get("number") or "?"
            status = build.get("completionStatus") or build["state"].upper()
            sha = (build.get("commitSha") or "")[:12]
            created = build.get("createdDate") or "unknown time"
            print(f"  #{number} {status} {sha} {created} [{build['id']}]")
            message = (build.get("commitMessage") or "").splitlines()[0]
            if message:
                print(f"    {message}")
            for action in build.get("diagnostics", []):
                print(f"    {action['name']}: {action['completionStatus']}")
                if not action["issues"]:
                    print("      No structured issues returned; inspect the build log artifact in Xcode.")
                for issue in action["issues"]:
                    location = issue.get("fileSource") or ""
                    if issue.get("lineNumber"):
                        location = f"{location}:{issue['lineNumber']}"
                    prefix = f"{location}: " if location else ""
                    print(f"      {prefix}{issue.get('message') or issue.get('issueType') or 'Unknown issue'}")
                for test in action.get("failedTests", []):
                    location = test.get("fileSource") or ""
                    if test.get("lineNumber"):
                        location = f"{location}:{test['lineNumber']}"
                    prefix = f"{location}: " if location else ""
                    name = ".".join(filter(None, (test.get("className"), test.get("name"))))
                    message = test.get("message") or name or "Unknown test failure"
                    print(f"      {prefix}{message}")


def run_monitor(args: argparse.Namespace) -> int:
    config = resolved_config(args.config)
    client = AppStoreConnectClient(
        config["PLINX_ASC_KEY_ID"],
        config["PLINX_ASC_ISSUER_ID"],
        Path(config["PLINX_ASC_KEY_PATH"]),
    )
    products = client.get("/v1/ciProducts", {"limit": 200}).get("data", [])
    selector = args.product or config.get("PLINX_XCODE_CLOUD_PRODUCT_ID")
    products = select_products(products, selector)

    report: dict[str, Any] = {"products": []}
    found_failure = False
    for product in products:
        product_id = str(product["id"])
        workflows = client.get(
            f"/v1/ciProducts/{product_id}/workflows", {"limit": 200}
        ).get("data", [])
        builds = client.get(
            f"/v1/ciProducts/{product_id}/buildRuns",
            {"limit": args.limit, "sort": "-createdDate"},
        ).get("data", [])
        summaries = []
        for build in builds:
            summary = build_summary(build, product)
            if summary["state"] == "failed":
                found_failure = True
                if args.details:
                    summary["diagnostics"] = collect_action_diagnostics(client, str(build["id"]))
            summaries.append(summary)
        report["products"].append(
            {
                "id": product_id,
                "name": resource_name(product),
                "workflows": [
                    {
                        "id": workflow.get("id"),
                        "name": resource_name(workflow),
                        "isEnabled": (workflow.get("attributes") or {}).get("isEnabled"),
                        "containerFilePath": (workflow.get("attributes") or {}).get(
                            "containerFilePath"
                        ),
                    }
                    for workflow in workflows
                ],
                "builds": summaries,
            }
        )

    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print_human_report(report)
    return 2 if args.fail_on_failure and found_failure else 0


def run_operation(args: argparse.Namespace) -> int:
    plan = mutation_plan(args)
    if plan is None:
        return run_monitor(args)
    if not args.apply:
        print(json.dumps({"dryRun": True, **plan}, indent=2, sort_keys=True))
        return 0

    config = resolved_config(args.config)
    client = AppStoreConnectClient(
        config["PLINX_ASC_KEY_ID"],
        config["PLINX_ASC_ISSUER_ID"],
        Path(config["PLINX_ASC_KEY_PATH"]),
    )
    response = client.apply_plan(plan)
    data = response.get("data") or {}
    result = {
        "applied": True,
        "type": data.get("type"),
        "id": data.get("id"),
        "attributes": data.get("attributes") or {},
    }
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--config",
        type=Path,
        default=DEFAULT_CONFIG,
        help=f"Local credential config (default: {DEFAULT_CONFIG})",
    )
    parser.add_argument("--product", help="Xcode Cloud product ID or exact product name")
    parser.add_argument("--limit", type=positive_limit, default=DEFAULT_LIMIT)
    parser.add_argument("--details", action="store_true", help="Fetch issues for failed actions")
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON")
    parser.add_argument(
        "--fail-on-failure",
        action="store_true",
        help="Exit with status 2 when a returned build failed",
    )
    management = parser.add_mutually_exclusive_group()
    management.add_argument(
        "--set-container",
        nargs=2,
        metavar=("WORKFLOW_ID", "PROJECT_OR_WORKSPACE"),
        help="Plan or apply a workflow project/workspace path update",
    )
    management.add_argument(
        "--enable-workflow",
        metavar="WORKFLOW_ID",
        help="Plan or apply enabling a workflow",
    )
    management.add_argument(
        "--disable-workflow",
        metavar="WORKFLOW_ID",
        help="Plan or apply disabling a workflow",
    )
    management.add_argument(
        "--start-workflow",
        metavar="WORKFLOW_ID",
        help="Plan or apply a manual Xcode Cloud build start",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Perform the selected management operation; otherwise print a dry run",
    )
    args = parser.parse_args(argv)
    if args.apply and not any(
        (args.set_container, args.enable_workflow, args.disable_workflow, args.start_workflow)
    ):
        parser.error("--apply requires a management operation")
    return args


def positive_limit(value: str) -> int:
    limit = int(value)
    if not 1 <= limit <= 200:
        raise argparse.ArgumentTypeError("limit must be between 1 and 200")
    return limit


def main(argv: list[str] | None = None) -> int:
    try:
        return run_operation(parse_args(argv or sys.argv[1:]))
    except MonitorError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    except Exception:
        # Avoid a traceback that could include a request object carrying the
        # short-lived Authorization header.
        print("error: unexpected Xcode Cloud client failure; no credentials were printed", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("error: interrupted", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
