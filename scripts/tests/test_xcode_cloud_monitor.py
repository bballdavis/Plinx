#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[1] / "xcode_cloud_monitor.py"
SPEC = importlib.util.spec_from_file_location("xcode_cloud_monitor", SCRIPT)
assert SPEC and SPEC.loader
monitor = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(monitor)


class SignatureTests(unittest.TestCase):
    def test_der_signature_is_converted_to_fixed_width_jose(self) -> None:
        r = b"\x01" * 32
        s = b"\x80" + b"\x02" * 31
        der = b"\x30\x45\x02\x20" + r + b"\x02\x21\x00" + s
        self.assertEqual(monitor.der_ecdsa_to_jose(der), r + s)

    def test_invalid_der_signature_is_rejected(self) -> None:
        with self.assertRaises(monitor.MonitorError):
            monitor.der_ecdsa_to_jose(b"not-a-signature")

    def test_jwt_is_signed_with_short_lifetime_without_exposing_key(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            key_path = Path(temporary_directory) / "AuthKey_TEST.p8"
            subprocess_result = __import__("subprocess").run(
                ["openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", str(key_path)],
                capture_output=True,
                check=True,
            )
            self.assertEqual(subprocess_result.returncode, 0)
            key_path.chmod(0o600)
            token = monitor.create_jwt("TESTKEY123", "00000000-0000-0000-0000-000000000000", key_path)
            encoded_header, encoded_payload, encoded_signature = token.split(".")

            def decode(part: str) -> dict:
                padding = "=" * (-len(part) % 4)
                return json.loads(__import__("base64").urlsafe_b64decode(part + padding))

            self.assertEqual(decode(encoded_header)["alg"], "ES256")
            payload = decode(encoded_payload)
            self.assertEqual(payload["exp"] - payload["iat"], 120)
            self.assertGreater(len(encoded_signature), 40)


class ConfigTests(unittest.TestCase):
    def test_env_file_supports_comments_and_quotes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "monitor.env"
            path.write_text("# comment\nPLINX_ASC_KEY_ID='ABC123'\n", encoding="utf-8")
            self.assertEqual(monitor.load_env_file(path), {"PLINX_ASC_KEY_ID": "ABC123"})

    def test_private_key_with_group_access_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "AuthKey_TEST.p8"
            path.write_text("not a real key", encoding="utf-8")
            path.chmod(0o640)
            with self.assertRaises(monitor.MonitorError):
                monitor.validate_private_key_path(path)

    def test_owner_only_private_key_is_accepted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "AuthKey_TEST.p8"
            path.write_text("not a real key", encoding="utf-8")
            path.chmod(stat.S_IRUSR | stat.S_IWUSR)
            monitor.validate_private_key_path(path)


class BuildTests(unittest.TestCase):
    def test_build_classification(self) -> None:
        self.assertEqual(
            monitor.classify_build(
                {"attributes": {"executionProgress": "COMPLETE", "completionStatus": "SUCCEEDED"}}
            ),
            "succeeded",
        )
        self.assertEqual(
            monitor.classify_build(
                {"attributes": {"executionProgress": "COMPLETE", "completionStatus": "FAILED"}}
            ),
            "failed",
        )
        self.assertEqual(
            monitor.classify_build(
                {"attributes": {"executionProgress": "RUNNING", "completionStatus": None}}
            ),
            "running",
        )

    def test_product_can_be_selected_by_name_or_id(self) -> None:
        products = [{"id": "product-1", "attributes": {"name": "Plinx"}}]
        self.assertEqual(monitor.select_products(products, "product-1"), products)
        self.assertEqual(monitor.select_products(products, "plinx"), products)
        with self.assertRaises(monitor.MonitorError):
            monitor.select_products(products, "missing")

    def test_failed_test_action_collects_issue_and_test_location(self) -> None:
        class FakeClient:
            def get(self, path, query=None):
                if path.endswith("/actions"):
                    return {
                        "data": [
                            {
                                "id": "action-1",
                                "attributes": {
                                    "name": "Tests",
                                    "actionType": "TEST",
                                    "completionStatus": "FAILED",
                                },
                            }
                        ]
                    }
                if path.endswith("/issues"):
                    return {
                        "data": [
                            {
                                "attributes": {
                                    "issueType": "ERROR",
                                    "message": "Compile failed",
                                    "fileSource": {"path": "App.swift", "lineNumber": 12},
                                }
                            }
                        ]
                    }
                if path.endswith("/testResults"):
                    return {
                        "data": [
                            {
                                "attributes": {
                                    "status": "FAILURE",
                                    "className": "ExampleTests",
                                    "name": "testExample",
                                    "fileSource": {"path": "ExampleTests.swift", "lineNumber": 8},
                                }
                            }
                        ]
                    }
                raise AssertionError(path)

        diagnostics = monitor.collect_action_diagnostics(FakeClient(), "build-1")
        self.assertEqual(diagnostics[0]["issues"][0]["fileSource"], "App.swift")
        self.assertEqual(diagnostics[0]["failedTests"][0]["name"], "testExample")


class ManagementTests(unittest.TestCase):
    def test_container_path_must_name_a_repository_relative_xcode_container(self) -> None:
        self.assertEqual(
            monitor.validate_container_file_path("PlinxApp/Plinx.xcodeproj"),
            "PlinxApp/Plinx.xcodeproj",
        )
        for invalid in ("PlinxApp/", "../Plinx.xcodeproj", "/tmp/Plinx.xcodeproj"):
            with self.subTest(invalid=invalid), self.assertRaises(monitor.MonitorError):
                monitor.validate_container_file_path(invalid)

    def test_workflow_container_update_uses_the_supported_patch_shape(self) -> None:
        plan = monitor.workflow_update_plan(
            "workflow-1", {"containerFilePath": "PlinxApp/Plinx.xcodeproj"}
        )
        self.assertEqual(plan["method"], "PATCH")
        self.assertEqual(plan["path"], "/v1/ciWorkflows/workflow-1")
        self.assertEqual(
            plan["body"]["data"]["attributes"]["containerFilePath"],
            "PlinxApp/Plinx.xcodeproj",
        )

    def test_build_start_uses_workflow_relationship(self) -> None:
        plan = monitor.build_start_plan("workflow-1")
        self.assertEqual(plan["method"], "POST")
        self.assertEqual(plan["path"], "/v1/ciBuildRuns")
        self.assertEqual(
            plan["body"]["data"]["relationships"]["workflow"]["data"]["id"],
            "workflow-1",
        )

    def test_management_operation_is_a_dry_run_without_apply(self) -> None:
        args = monitor.parse_args(
            ["--set-container", "workflow-1", "PlinxApp/Plinx.xcodeproj"]
        )
        with mock.patch("builtins.print") as print_mock:
            self.assertEqual(monitor.run_operation(args), 0)
        rendered = print_mock.call_args.args[0]
        self.assertIn('"dryRun": true', rendered)


if __name__ == "__main__":
    unittest.main()
