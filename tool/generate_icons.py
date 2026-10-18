#!/usr/bin/env python3
"""Regenerate Android launcher icons from assets/icon/icon.svg.

Requires: inkscape (SVG rasterizing) and ImageMagick (`magick` or `convert`).

Usage:
    tool/generate_icons.py

Outputs, for every density:
    android/app/src/main/res/mipmap-<d>/ic_launcher.png            (legacy, 48dp)
    android/app/src/main/res/mipmap-<d>/ic_launcher_round.png      (legacy round)
    android/app/src/main/res/mipmap-<d>/ic_launcher_foreground.png (adaptive, 108dp)

The adaptive background colour lives in
android/app/src/main/res/values/ic_launcher_background.xml and the
<adaptive-icon> definitions in res/mipmap-anydpi-v26/, both hand-maintained.

Note: the adaptive foreground is rendered from icon_foreground.svg, which is
icon.svg minus its background rect. Keep the glyph inside the central 61% of
the 512x512 canvas (~x,y in 100..412) so it survives the adaptive-icon mask.
"""

import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/icon/icon.svg"
FG_SRC = ROOT / "assets/icon/icon_foreground.svg"
RES = ROOT / "android/app/src/main/res"
BG_RECT = '<rect width="512" height="512" rx="112" fill="url(#bg)"/>'

# density -> (legacy 48dp px, adaptive foreground 108dp px)
DENSITIES = {
    "mdpi": (48, 108),
    "hdpi": (72, 162),
    "xhdpi": (96, 216),
    "xxhdpi": (144, 324),
    "xxxhdpi": (192, 432),
}


def require(*names: str) -> str:
    for name in names:
        path = shutil.which(name)
        if path:
            return path
    sys.exit(f"error: none of {names} found on PATH")


def render(inkscape: str, svg: Path, out: Path, size: int) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [inkscape, str(svg), "-o", str(out), "-w", str(size), "-h", str(size)],
        check=True,
        capture_output=True,
    )


def circle_mask(magick: list[str], src: Path, out: Path, size: int) -> None:
    c = (size - 1) / 2
    subprocess.run(
        magick
        + [
            str(src), "-alpha", "set",
            "(", "+clone", "-alpha", "transparent",
            "-fill", "white", "-draw", f"circle {c},{c} {c},0", ")",
            "-compose", "DstIn", "-composite",
            str(out),
        ],
        check=True,
        capture_output=True,
    )


def main() -> None:
    if not SRC.is_file():
        sys.exit(f"error: missing {SRC}")

    inkscape = require("inkscape")
    magick = [require("magick", "convert")]
    if magick[0].endswith("magick"):
        magick.append("convert")

    # Derive the adaptive foreground by stripping the background rect.
    svg = SRC.read_text()
    if BG_RECT not in svg:
        sys.exit(f"error: background rect not found in {SRC}; update BG_RECT")
    FG_SRC.write_text(svg.replace(BG_RECT, ""))

    for density, (legacy_px, fg_px) in DENSITIES.items():
        out_dir = RES / f"mipmap-{density}"
        legacy = out_dir / "ic_launcher.png"
        render(inkscape, SRC, legacy, legacy_px)
        circle_mask(magick, legacy, out_dir / "ic_launcher_round.png", legacy_px)
        render(inkscape, FG_SRC, out_dir / "ic_launcher_foreground.png", fg_px)
        print(f"mipmap-{density}: {legacy_px}px legacy + {fg_px}px foreground")

    print("done")


if __name__ == "__main__":
    main()
