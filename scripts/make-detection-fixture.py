#!/usr/bin/env python3
"""Turn a `prowl read --source detection` capture into a corpus fixture.

Implements steps 3, 6, and 7 of the capture-and-promotion procedure in
`supacodeTests/Fixtures/AgentScreenDetection/README.md`: it rejects a capture
that is not detector-faithful, reduces the screen to the same tail the detector
reads, and applies redactions without changing the visible width of any line.

Width matters. A fixture exists to pin how the classifier reads a real screen,
and the agent CLIs wrap, shorten, and truncate their rows to the terminal width.
A redaction that lengthens or shortens a line moves a wrap point and turns the
fixture into a screen the product would never render, so every substitution here
either preserves the line's visible width or is refused.

Usage:

    scripts/make-detection-fixture.py capture.json \\
        --redact /Users/me=/Users/usr \\
        --redact 'Acme Inc=<ORG_0000>' \\
        > supacodeTests/Fixtures/AgentScreenDetection/claude/2.1.226/idle/composer.txt

Each `--redact OLD=NEW` is applied in order. `NEW` may differ in length from
`OLD`: the difference is taken out of, or added to, that line's trailing spaces,
which are invisible on screen. A line with too little trailing slack to absorb a
longer replacement is reported and the run fails, rather than silently shifting
the row.

The redaction summary the metadata file requires (README step 5) is written to
stderr, so it does not contaminate the fixture on stdout.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata

DETECTOR_TAIL_LIMIT = 24


def canonical_tail(content: str, limit: int = DETECTOR_TAIL_LIMIT) -> str:
    """Port of `agentDetectionRecentLines(_:limit:)`.

    Starts at the `limit`-th non-empty line from the bottom when that many
    exist, and keeps every line from there down, blank lines and trailing screen
    rows included. Fewer than `limit` non-empty lines keeps the whole screen.
    """
    lines = content.split("\n")
    remaining = limit
    start = 0
    for index in range(len(lines) - 1, -1, -1):
        if not lines[index].strip():
            continue
        remaining -= 1
        if remaining == 0:
            start = index
            break
    return "\n".join(lines[start:])


class WidthError(Exception):
    """A replacement could not keep the line's visible width."""


# Sequences whose rendered width terminals do not agree on. A ZWJ sequence may
# collapse into one glyph or render as its parts; a variation selector flips a
# character between text and emoji presentation, and therefore between one cell
# and two. Refusing them is the same bargain the rest of this script makes:
# a fixture that never renders is worse than a redaction that never happens.
UNDECIDABLE_WIDTH = {"‍"}  # zero-width joiner
VARIATION_SELECTORS = [range(0xFE00, 0xFE10), range(0xE0100, 0xE01F0)]


def cell_width(text: str) -> int:
    """Visible width of `text` in terminal cells.

    `len()` counts code points, which is the same number only for the ASCII
    subset. A CJK ideograph occupies two cells, a combining mark none, and
    "CJK text replaced by an ASCII placeholder" is the common redaction on this
    fork — so measuring in code points silently narrows exactly the lines the
    corpus exists to pin.
    """
    width = 0
    for character in text:
        code = ord(character)
        if character in UNDECIDABLE_WIDTH or any(
            code in span for span in VARIATION_SELECTORS
        ):
            raise WidthError(
                f"{character!r} (U+{code:04X}) has no width terminals agree on, so the "
                f"replacement cannot be shown to preserve the row. Use a replacement "
                f"without joiners or variation selectors"
            )
        if code < 0x20 or code == 0x7F:
            raise WidthError(f"control character U+{code:04X} has no visible width")
        if unicodedata.combining(character):
            continue
        width += 2 if unicodedata.east_asian_width(character) in ("W", "F") else 1
    return width


def substitute(line: str, old: str, new: str) -> str:
    """Replace `old` with `new`, keeping every later column where it was.

    The padding is adjusted in the run of spaces immediately after the inserted
    text, never at the end of the line. Anything further along the row — the
    closing border of a box, a second column of chrome — therefore stays in its
    captured column. Absorbing the change at the end of the line instead would
    hold the line's total length while sliding all of that content sideways.

    Width is counted in terminal cells, so a two-cell ideograph replaced by a
    one-cell letter is padded by the one column it gives up.
    """
    delta = cell_width(new) - cell_width(old)
    out = ""
    rest = line

    while True:
        head, separator, tail = rest.partition(old)
        if not separator:
            return out + rest

        out += head + new
        if delta < 0:
            out += " " * (-delta)
        elif delta > 0:
            gap = len(tail) - len(tail.lstrip(" "))
            if gap < delta:
                raise WidthError(
                    f"replacing {old!r} with {new!r} widens the row by {delta} column(s), "
                    f"and only {gap} space(s) follow it; every column after this point "
                    f"would shift. Choose a replacement of {cell_width(old) + gap} cells or fewer"
                )
            tail = tail[delta:]
        rest = tail


# Money amounts carry no signal for the classifier and are account data.
MONEY = re.compile(r"\$\d+\.\d\d")


def mask_money(line: str) -> tuple[str, list[tuple[str, str]]]:
    """Mask dollar amounts digit for digit, through the same width guard.

    A fixed `$X.XX` mask silently narrowed every amount that was not a single
    unit — `$123.45` lost two columns and slid the rest of the row left, which
    is precisely the defect this script exists to prevent. Masking each digit
    with an X keeps the mask the same width as the amount for any magnitude, so
    the substitution is a no-op for layout by construction rather than by luck.
    """
    applied: list[tuple[str, str]] = []
    for amount in dict.fromkeys(MONEY.findall(line)):
        masked = re.sub(r"\d", "X", amount)
        replaced = substitute(line, amount, masked)
        if replaced != line:
            applied.append((amount, masked))
        line = replaced
    return line, applied


def parse_redaction(value: str) -> tuple[str, str]:
    old, separator, new = value.partition("=")
    if not separator or not old:
        raise argparse.ArgumentTypeError(f"expected OLD=NEW, got {value!r}")
    return old, new


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Reduce and redact a detection capture into a corpus fixture."
    )
    parser.add_argument(
        "capture", help="JSON emitted by `prowl read --source detection --json`"
    )
    parser.add_argument(
        "--redact",
        action="append",
        default=[],
        metavar="OLD=NEW",
        type=parse_redaction,
        help="literal replacement, applied in order; repeatable",
    )
    parser.add_argument(
        "--keep-money",
        action="store_true",
        help="retain dollar amounts instead of masking their digits as X",
    )
    args = parser.parse_args()

    with open(args.capture, encoding="utf-8") as handle:
        capture = json.load(handle)

    data = capture.get("data", {})
    source = data.get("source")
    if source != "detection":
        print(
            f"error: capture source is {source!r}, not 'detection'; a viewport read "
            "is not the input the classifier sees",
            file=sys.stderr,
        )
        return 2

    applied: dict[str, str] = {}
    out_lines = []
    for number, line in enumerate(canonical_tail(data["text"]).split("\n"), start=1):
        for old, new in args.redact:
            try:
                replaced = substitute(line, old, new)
            except WidthError as error:
                print(f"error: line {number}: {error}", file=sys.stderr)
                return 1
            if replaced != line:
                applied[old] = new
            line = replaced
        if not args.keep_money:
            try:
                line, masked = mask_money(line)
            except WidthError as error:
                print(f"error: line {number}: {error}", file=sys.stderr)
                return 1
            for amount, mask in masked:
                applied[amount] = mask
        # Width preservation keeps every column up to the last visible glyph, so
        # a closing box border stays where the capture put it. Past that glyph
        # the padding carries nothing, and the corpus stores lines without it.
        out_lines.append(line.rstrip())

    sys.stdout.write("\n".join(out_lines))

    if applied:
        print("redactions applied (for the metadata file):", file=sys.stderr)
        for old, new in applied.items():
            print(f'  "{old} replaced with {new}"', file=sys.stderr)
    else:
        print("no redactions applied", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
