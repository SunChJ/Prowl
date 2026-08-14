#!/usr/bin/env python3
"""Tests for the fixture generator's width guarantee.

The corpus tests validate the fixtures that were committed; they never execute
the generator, so nothing held it to the one promise it makes — that a redacted
row occupies the same columns the terminal captured. These do.

Run with `make test-scripts`, or directly:

    python3 -m unittest discover -s scripts -p 'test_*.py'
"""

from __future__ import annotations

import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent / "make-detection-fixture.py"

_spec = importlib.util.spec_from_file_location("make_detection_fixture", SCRIPT)
fixture = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fixture)


class CellWidth(unittest.TestCase):
    def test_ascii_counts_one_cell_per_character(self):
        self.assertEqual(fixture.cell_width("claude"), 6)

    def test_ideographs_count_two_cells(self):
        # len() is 1 here, which is exactly the confusion this replaces.
        self.assertEqual(fixture.cell_width("猫"), 2)
        self.assertEqual(fixture.cell_width("メモ"), 4)

    def test_combining_marks_occupy_no_cell(self):
        self.assertEqual(fixture.cell_width("é"), 1)

    def test_joiner_is_refused_rather_than_guessed(self):
        with self.assertRaises(fixture.WidthError):
            fixture.cell_width("\U0001f469‍\U0001f4bb")

    def test_variation_selector_is_refused(self):
        with self.assertRaises(fixture.WidthError):
            fixture.cell_width("❤️")


class Substitute(unittest.TestCase):
    def test_narrowing_replacement_pads_to_hold_the_border(self):
        line = "│ user  猫猫  │"
        out = fixture.substitute(line, "猫猫", "cat")
        self.assertEqual(fixture.cell_width(out), fixture.cell_width(line))
        self.assertTrue(out.endswith("│"))

    def test_widening_replacement_consumes_following_spaces(self):
        line = "│ me     │"
        out = fixture.substitute(line, "me", "user")
        self.assertEqual(fixture.cell_width(out), fixture.cell_width(line))

    def test_widening_beyond_the_slack_is_refused(self):
        with self.assertRaises(fixture.WidthError):
            fixture.substitute("│ me │", "me", "a much longer name")

    def test_ascii_replaced_by_ideograph_holds_the_width(self):
        line = "│ ab      │"
        out = fixture.substitute(line, "ab", "猫")
        self.assertEqual(fixture.cell_width(out), fixture.cell_width(line))


class MoneyMasking(unittest.TestCase):
    def test_multi_digit_amount_keeps_its_columns(self):
        line = "│ spent $123.45 today │"
        out, applied = fixture.mask_money(line)
        self.assertEqual(fixture.cell_width(out), fixture.cell_width(line))
        self.assertIn("$XXX.XX", out)
        self.assertEqual(applied, [("$123.45", "$XXX.XX")])

    def test_single_unit_amount_still_masks(self):
        out, _ = fixture.mask_money("cost $1.23 |")
        self.assertEqual(out, "cost $X.XX |")

    def test_several_amounts_on_one_row(self):
        line = "$9.99 and $1234.56 |"
        out, applied = fixture.mask_money(line)
        self.assertEqual(fixture.cell_width(out), fixture.cell_width(line))
        self.assertEqual(out, "$X.XX and $XXXX.XX |")
        self.assertEqual(len(applied), 2)


class EndToEnd(unittest.TestCase):
    def run_script(self, text, *args):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
            json.dump({"data": {"source": "detection", "text": text}}, handle)
            path = handle.name
        try:
            return subprocess.run(
                [sys.executable, str(SCRIPT), path, *args],
                capture_output=True,
                text=True,
            )
        finally:
            pathlib.Path(path).unlink()

    def test_amount_masking_does_not_move_the_closing_border(self):
        line = "│ Opus 5 · $123.45 · 60m │"
        result = self.run_script(line)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(fixture.cell_width(result.stdout), fixture.cell_width(line))
        self.assertIn("$XXX.XX", result.stdout)

    def test_unicode_redaction_holds_the_row(self):
        line = "│ 東京都のユーザー          │"
        result = self.run_script(line, "--redact", "東京都のユーザー=<CITY_0000>")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(fixture.cell_width(result.stdout), fixture.cell_width(line))

    def test_undecidable_replacement_fails_the_run(self):
        result = self.run_script("│ owner name │", "--redact", "owner=❤️")
        self.assertEqual(result.returncode, 1)
        self.assertIn("no width terminals agree on", result.stderr)

    def test_viewport_capture_is_still_rejected(self):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
            json.dump({"data": {"source": "screen", "text": "x"}}, handle)
            path = handle.name
        try:
            result = subprocess.run(
                [sys.executable, str(SCRIPT), path], capture_output=True, text=True
            )
        finally:
            pathlib.Path(path).unlink()
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
