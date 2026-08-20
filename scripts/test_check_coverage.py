#!/usr/bin/env python3
"""Focused tests for the production xccov coverage gate."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import unittest
from unittest import mock


SCRIPT_PATH = Path(__file__).with_name("check_coverage.py")
SPEC = importlib.util.spec_from_file_location("check_coverage", SCRIPT_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"could not load {SCRIPT_PATH}")
check_coverage = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = check_coverage
SPEC.loader.exec_module(check_coverage)


class CheckCoverageTests(unittest.TestCase):
    def report(
        self,
        *,
        covered: object = 523,
        executable: object = 5700,
        line_coverage: object = 0.09175438596491228,
        name: str = "BetterMonitor.app",
    ) -> dict[str, object]:
        return {
            "targets": [
                {
                    "name": name,
                    "coveredLines": covered,
                    "executableLines": executable,
                    "lineCoverage": line_coverage,
                }
            ]
        }

    def invoke(
        self,
        report: object | None = None,
        *,
        arguments: list[str] | None = None,
        returncode: int = 0,
        stderr: str = "",
        stdout: str | None = None,
    ) -> tuple[int, str, str, mock.Mock]:
        xccov_stdout = json.dumps(report, allow_nan=True) if stdout is None else stdout
        result = subprocess.CompletedProcess(
            ["xcrun", "xccov"], returncode, xccov_stdout, stderr
        )
        captured_stdout = io.StringIO()
        captured_stderr = io.StringIO()
        command_arguments = ["test-result.xcresult", "--minimum", "9.17"]
        if arguments is not None:
            command_arguments = arguments
        with mock.patch.object(check_coverage.subprocess, "run", return_value=result) as run:
            with contextlib.redirect_stdout(captured_stdout), contextlib.redirect_stderr(
                captured_stderr
            ):
                code = check_coverage.main(command_arguments)
        return code, captured_stdout.getvalue(), captured_stderr.getvalue(), run

    def assert_failure(self, report: object, message: str) -> tuple[str, str]:
        code, stdout, stderr, _ = self.invoke(report)
        self.assertNotEqual(code, 0)
        self.assertEqual(stdout, "")
        self.assertIn("Coverage check failed:", stderr)
        self.assertIn(message, stderr)
        return stdout, stderr

    def test_baseline_523_of_5700_passes_9_17_percent(self) -> None:
        code, stdout, stderr, run = self.invoke(self.report())

        self.assertEqual(code, 0)
        self.assertEqual(stderr, "")
        self.assertIn("523/5700 lines", stdout)
        self.assertIn("9.175438596491%", stdout)
        self.assertIn("minimum 9.17%", stdout)
        self.assertEqual(
            run.call_args.args[0],
            [
                "xcrun",
                "xccov",
                "view",
                "--report",
                "--json",
                "test-result.xcresult",
            ],
        )
        self.assertEqual(
            run.call_args.kwargs["timeout"], check_coverage.XCCOV_TIMEOUT_SECONDS
        )

    def test_exact_minimum_boundary_passes(self) -> None:
        code, stdout, stderr, _ = self.invoke(
            self.report(covered=917, executable=10_000, line_coverage=0.0917)
        )

        self.assertEqual(code, 0)
        self.assertEqual(stderr, "")
        self.assertIn("917/10000 lines (9.17%)", stdout)

    def test_coverage_below_minimum_fails(self) -> None:
        code, stdout, stderr, _ = self.invoke(
            self.report(covered=916, executable=10_000, line_coverage=0.0916)
        )

        self.assertNotEqual(code, 0)
        self.assertIn("916/10000 lines (9.16%)", stdout)
        self.assertIn("below minimum 9.17%", stderr)

    def test_integral_minimums_preserve_zeroes_and_gate_correctly(self) -> None:
        code, stdout, stderr, _ = self.invoke(
            self.report(covered=10, executable=100, line_coverage=0.1),
            arguments=["test-result.xcresult", "--minimum", "10"],
        )

        self.assertEqual(code, 0)
        self.assertEqual(stderr, "")
        self.assertIn("10/100 lines (10%); minimum 10%", stdout)

        code, stdout, stderr, _ = self.invoke(
            self.report(covered=99, executable=100, line_coverage=0.99),
            arguments=["test-result.xcresult", "--minimum", "100"],
        )

        self.assertNotEqual(code, 0)
        self.assertIn("99/100 lines (99%); minimum 100%", stdout)
        self.assertIn("below minimum 100%", stderr)

    def test_line_coverage_at_tolerance_boundary_passes(self) -> None:
        code, stdout, stderr, _ = self.invoke(
            stdout=(
                '{"targets":[{"name":"BetterMonitor.app","coveredLines":1,'
                '"executableLines":2,"lineCoverage":0.500000000001}]}'
            )
        )

        self.assertEqual(code, 0)
        self.assertEqual(stderr, "")
        self.assertIn("1/2 lines (50%)", stdout)

    def test_line_coverage_beyond_tolerance_fails(self) -> None:
        code, stdout, stderr, _ = self.invoke(
            stdout=(
                '{"targets":[{"name":"BetterMonitor.app","coveredLines":1,'
                '"executableLines":2,"lineCoverage":0.5000000000011}]}'
            )
        )

        self.assertNotEqual(code, 0)
        self.assertEqual(stdout, "")
        self.assertIn("lineCoverage is inconsistent with coveredLines/executableLines", stderr)

    def test_explicit_target_is_selected(self) -> None:
        code, stdout, stderr, _ = self.invoke(
            self.report(name="BetterMonitorTests.xctest"),
            arguments=[
                "test-result.xcresult",
                "--target",
                "BetterMonitorTests.xctest",
                "--minimum",
                "9.17",
            ],
        )

        self.assertEqual(code, 0)
        self.assertEqual(stderr, "")
        self.assertIn("Coverage for BetterMonitorTests.xctest", stdout)

    def test_missing_target_fails(self) -> None:
        self.assert_failure(self.report(name="Other.app"), "was not found")

    def test_malformed_json_fails(self) -> None:
        code, stdout, stderr, _ = self.invoke(stdout="{not valid json")

        self.assertNotEqual(code, 0)
        self.assertEqual(stdout, "")
        self.assertIn("malformed JSON", stderr)

    def test_xccov_failure_fails(self) -> None:
        code, stdout, stderr, _ = self.invoke(
            self.report(), returncode=2, stderr="unable to read result bundle"
        )

        self.assertNotEqual(code, 0)
        self.assertEqual(stdout, "")
        self.assertIn("xccov failed with exit code 2", stderr)
        self.assertIn("unable to read result bundle", stderr)

    def test_xccov_timeout_fails(self) -> None:
        timeout = subprocess.TimeoutExpired(
            ["xcrun", "xccov"], check_coverage.XCCOV_TIMEOUT_SECONDS
        )
        captured_stdout = io.StringIO()
        captured_stderr = io.StringIO()
        with mock.patch.object(check_coverage.subprocess, "run", side_effect=timeout) as run:
            with contextlib.redirect_stdout(captured_stdout), contextlib.redirect_stderr(
                captured_stderr
            ):
                code = check_coverage.main(
                    ["test-result.xcresult", "--minimum", "9.17"]
                )

        self.assertNotEqual(code, 0)
        self.assertEqual(captured_stdout.getvalue(), "")
        self.assertIn(
            "Coverage check failed: xccov timed out after 60 seconds",
            captured_stderr.getvalue(),
        )
        self.assertEqual(
            run.call_args.kwargs["timeout"], check_coverage.XCCOV_TIMEOUT_SECONDS
        )

    def test_incomplete_report_fails(self) -> None:
        report = self.report()
        target = report["targets"][0]
        self.assertIsInstance(target, dict)
        target.pop("lineCoverage")

        self.assert_failure(report, "missing lineCoverage")

    def test_type_invalid_line_coverage_fails(self) -> None:
        self.assert_failure(
            self.report(line_coverage="0.09175438596491228"),
            "lineCoverage must be a finite number",
        )

    def test_type_invalid_count_fails(self) -> None:
        self.assert_failure(
            self.report(executable="5700"),
            "executableLines must be an integer",
        )

    def test_nonfinite_line_coverage_fails(self) -> None:
        self.assert_failure(self.report(line_coverage=float("nan")), "lineCoverage must be finite")

    def test_out_of_range_line_coverage_fails(self) -> None:
        self.assert_failure(self.report(line_coverage=1.1), "lineCoverage must be between 0 and 1")

    def test_inconsistent_line_coverage_fails(self) -> None:
        self.assert_failure(
            self.report(line_coverage=0.5),
            "lineCoverage is inconsistent with coveredLines/executableLines",
        )

    def test_nonpositive_executable_lines_fails(self) -> None:
        self.assert_failure(
            self.report(covered=0, executable=0, line_coverage=0),
            "executableLines must be positive",
        )

    def test_negative_covered_lines_fails(self) -> None:
        self.assert_failure(
            self.report(covered=-1, executable=100, line_coverage=0),
            "coveredLines must be between 0 and executableLines",
        )

    def test_covered_lines_above_executable_lines_fails(self) -> None:
        self.assert_failure(
            self.report(covered=101, executable=100, line_coverage=1),
            "coveredLines must be between 0 and executableLines",
        )


if __name__ == "__main__":
    unittest.main()
