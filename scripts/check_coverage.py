#!/usr/bin/env python3
"""Gate an Xcode result bundle's target line coverage using exact line counts."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation, localcontext
from fractions import Fraction
import json
from pathlib import Path
import subprocess
import sys
from typing import Any, Sequence

DEFAULT_TARGET = "BetterMonitor.app"
# xccov serializes a binary coverage value as JSON decimal text. This permits a
# sub-trillionth representation difference; the integer line counts decide the gate.
LINE_COVERAGE_TOLERANCE = Decimal("0.000000000001")
MAX_MINIMUM_DECIMAL_PLACES = 18


class CoverageError(Exception):
    """An xccov report cannot be trusted for a coverage decision."""


@dataclass(frozen=True)
class Coverage:
    covered_lines: int
    executable_lines: int
    line_coverage: Decimal


def parse_minimum(value: str) -> Fraction:
    """Parse a percentage without converting it through binary floating point."""
    try:
        minimum = Decimal(value)
    except (InvalidOperation, ValueError) as error:
        raise argparse.ArgumentTypeError("minimum must be a decimal percentage") from error

    if not minimum.is_finite() or minimum < 0 or minimum > 100:
        raise argparse.ArgumentTypeError("minimum must be a finite percentage from 0 to 100")
    if minimum.is_zero():
        return Fraction(0)

    sign, digits, exponent = minimum.as_tuple()
    if exponent < -MAX_MINIMUM_DECIMAL_PLACES:
        raise argparse.ArgumentTypeError(
            f"minimum supports at most {MAX_MINIMUM_DECIMAL_PLACES} decimal places"
        )

    numerator = int("".join(map(str, digits)))
    if sign:
        numerator = -numerator
    if exponent >= 0:
        return Fraction(numerator * 10**exponent)
    return Fraction(numerator, 10 ** (-exponent))


def _require_count(target: dict[str, Any], field: str) -> int:
    if field not in target:
        raise CoverageError(f"target is missing {field}")
    value = target[field]
    if isinstance(value, bool) or not isinstance(value, int):
        raise CoverageError(f"target {field} must be an integer")
    return value


def _require_line_coverage(target: dict[str, Any]) -> Decimal:
    if "lineCoverage" not in target:
        raise CoverageError("target is missing lineCoverage")
    value = target["lineCoverage"]
    if isinstance(value, bool) or not isinstance(value, (int, Decimal)):
        raise CoverageError("target lineCoverage must be a finite number")

    coverage = Decimal(value)
    if not coverage.is_finite():
        raise CoverageError("target lineCoverage must be finite")
    if coverage < 0 or coverage > 1:
        raise CoverageError("target lineCoverage must be between 0 and 1")
    return coverage


def _target_report(report: Any, target_name: str) -> dict[str, Any]:
    if not isinstance(report, dict):
        raise CoverageError("xccov report must be a JSON object")
    targets = report.get("targets")
    if not isinstance(targets, list):
        raise CoverageError("xccov report must contain a targets list")

    matching_targets = [
        target
        for target in targets
        if isinstance(target, dict) and target.get("name") == target_name
    ]
    if not matching_targets:
        raise CoverageError(f"target {target_name!r} was not found")
    if len(matching_targets) != 1:
        raise CoverageError(f"target {target_name!r} appears more than once")
    return matching_targets[0]


def _load_coverage(result_bundle: Path, target_name: str) -> Coverage:
    command = ["xcrun", "xccov", "view", "--report", "--json", str(result_bundle)]
    try:
        result = subprocess.run(command, capture_output=True, check=False, text=True)
    except OSError as error:
        raise CoverageError(f"could not run xccov: {error}") from error

    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        suffix = f": {detail}" if detail else ""
        raise CoverageError(f"xccov failed with exit code {result.returncode}{suffix}")
    if not isinstance(result.stdout, str):
        raise CoverageError("xccov did not produce text output")

    try:
        report = json.loads(
            result.stdout,
            parse_float=Decimal,
            parse_constant=Decimal,
        )
    except (json.JSONDecodeError, InvalidOperation, ValueError) as error:
        raise CoverageError(f"xccov produced malformed JSON: {error}") from error

    target = _target_report(report, target_name)
    covered_lines = _require_count(target, "coveredLines")
    executable_lines = _require_count(target, "executableLines")
    if executable_lines <= 0:
        raise CoverageError("target executableLines must be positive")
    if covered_lines < 0 or covered_lines > executable_lines:
        raise CoverageError("target coveredLines must be between 0 and executableLines")

    line_coverage = _require_line_coverage(target)
    with localcontext() as context:
        context.prec = 50
        expected_coverage = Decimal(covered_lines) / Decimal(executable_lines)
    if abs(line_coverage - expected_coverage) > LINE_COVERAGE_TOLERANCE:
        raise CoverageError(
            "target lineCoverage is inconsistent with coveredLines/executableLines"
        )

    return Coverage(covered_lines, executable_lines, line_coverage)


def _format_percentage(covered_lines: int, executable_lines: int) -> str:
    with localcontext() as context:
        context.prec = 50
        percentage = Decimal(covered_lines) * Decimal(100) / Decimal(executable_lines)
    return f"{percentage:.12f}".rstrip("0").rstrip(".")


def _format_minimum(minimum: Fraction) -> str:
    with localcontext() as context:
        context.prec = 50
        value = Decimal(minimum.numerator) / Decimal(minimum.denominator)
    formatted = f"{value:f}"
    return formatted.rstrip("0").rstrip(".") if "." in formatted else formatted


def _meets_minimum(coverage: Coverage, minimum: Fraction) -> bool:
    return (
        coverage.covered_lines * 100 * minimum.denominator
        >= coverage.executable_lines * minimum.numerator
    )


def parse_arguments(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Check target line coverage from an Xcode result bundle."
    )
    parser.add_argument("result_bundle", type=Path, help="path to the .xcresult bundle")
    parser.add_argument(
        "--target",
        default=DEFAULT_TARGET,
        help=f"exact xccov target name (default: {DEFAULT_TARGET})",
    )
    parser.add_argument(
        "--minimum",
        required=True,
        type=parse_minimum,
        help="minimum line coverage percentage, compared exactly from line counts",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_arguments(argv)
    try:
        coverage = _load_coverage(args.result_bundle, args.target)
    except CoverageError as error:
        print(f"Coverage check failed: {error}", file=sys.stderr)
        return 1

    percentage = _format_percentage(coverage.covered_lines, coverage.executable_lines)
    minimum = _format_minimum(args.minimum)
    print(
        f"Coverage for {args.target}: {coverage.covered_lines}/{coverage.executable_lines} "
        f"lines ({percentage}%); minimum {minimum}%"
    )
    if not _meets_minimum(coverage, args.minimum):
        print(
            f"Coverage check failed: {percentage}% is below minimum {minimum}%",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
