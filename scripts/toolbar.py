"""Where the toolbar's buttons are, for the QEMU tests to click them by name.

The labels come from Main.toolbar's source (the buttons shown when nothing asks
"Restart?"), in order, and the buttons from a screenshot: each one has a
2 UI pixel border in Ui.elm's outline colour (or the focus colour), so along a
row just inside the top border they are runs of that colour, 6 UI pixels apart.
Adding, removing or renaming a toolbar button needs no change here.
"""

import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

OUTLINE = (157, 143, 134)  # Color.outlineColor
FOCUSED = (70, 120, 255)  # Color.focusedUiColor
TOP = 8  # the toolbar row's padding, in UI pixels
SPACING = 6  # between buttons


def labels():
    src = open(f"{ROOT}/elm/src/Main.elm").read()
    body = src.split("\ntoolbar model =\n", 1)[1].split("\n    in\n", 1)[0]
    names = re.findall(r'\(t "([^"]+)"\)', body.split("Nothing ->", 1)[1])
    if not names:
        raise RuntimeError("found no buttons in Main.toolbar (elm/src/Main.elm)")
    return names


def _border(c):
    return any(all(abs(a - b) <= 10 for a, b in zip(c, want)) for want in (OUTLINE, FOCUSED))


def buttons(shot, s):
    """{label: (x, y)}, the middle of each toolbar button in device pixels.
    `shot` is (width, height, RGB bytes) and `s` the UI scale."""
    w, h, px = shot
    pixel = lambda x, y: tuple(px[(y * w + x) * 3:(y * w + x) * 3 + 3])
    y = TOP * s + s // 2  # in the top border
    runs = []
    x = 0
    while x < w:
        if _border(pixel(x, y)):
            x0 = x
            while x < w and _border(pixel(x, y)):
                x += 1
            if runs and abs(x0 - runs[-1][1] - SPACING * s) > s:
                break  # not the toolbar's next button (the network panel, say)
            runs.append((x0, x))
        elif runs and x - runs[-1][1] > (SPACING + 1) * s:
            break
        else:
            x += 1
    names = labels()
    if len(runs) != len(names):
        raise RuntimeError(f"expected the toolbar's {len(names)} buttons {names}, found {len(runs)} "
                           f"at {runs} along y={y}")
    # Down the left border to find the bottom.
    bottom = y
    while bottom < h and _border(pixel(runs[0][0], bottom)):
        bottom += 1
    return {name: ((x0 + x1) // 2, (TOP * s + bottom) // 2) for name, (x0, x1) in zip(names, runs)}
