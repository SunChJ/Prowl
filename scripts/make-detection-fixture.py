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


def substitute(line: str, old: str, new: str) -> str:
    """Replace `old` with `new`, keeping every later column where it was.

    The padding is adjusted in the run of spaces immediately after the inserted
    text, never at the end of the line. Anything further along the row — the
    closing border of a box, a second column of chrome — therefore stays in its
    captured column. Absorbing the change at the end of the line instead would
    hold the line's total length while sliding all of that content sideways.
    """
    delta = len(new) - len(old)
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
                    f"would shift. Choose a replacement of {len(old) + gap} characters or fewer"
                )
            tail = tail[delta:]
        rest = tail


# Money amounts carry no signal for the classifier and are account data.
MONEY = re.compile(r"\$\d+\.\d\d")


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
        help="retain dollar amounts instead of masking them as $X.XX",
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
            masked = MONEY.sub("$X.XX", line)
            if masked != line:
                applied["<dollar amounts>"] = "$X.XX"
            line = masked
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
