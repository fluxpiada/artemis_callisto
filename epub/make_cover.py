#!/usr/bin/env python3
"""
Make the EPUB cover: your cover art with the title and the author on it.

    uv run --with pillow epub/make_cover.py --lang=nl
    uv run --with pillow epub/make_cover.py --lang=fr --font="/path/to/Font.ttf"

Without uv:  pip install pillow,  then  python3 epub/make_cover.py --lang=nl
(on Windows:  py epub/make_cover.py --lang=nl).

Run it from the repo root, once per language, and again whenever the title
changes. It reads title, byline and cover-art from book.yaml plus
manuscript/<lang>/book.yaml — through pandoc, exactly as the build does — and
writes images/cover_<lang>.jpg. Commit that file; point cover: at it. The build
itself never runs this, so CI needs no Python.

Written and tested on macOS. The Windows and Linux font paths below are there
but have not been tried on those systems.
"""

import argparse
import os
import subprocess
import sys
import tempfile

try:
    from PIL import Image, ImageDraw, ImageFont, ImageStat
except ImportError:
    sys.exit("❌ Pillow is not installed. Use: uv run --with pillow epub/make_cover.py"
             " — or: pip install pillow")

# 1:1.6 is what most e-book stores ask for.
WIDTH, HEIGHT = 1600, 2560
MARGIN = 140
INK = (240, 230, 210)  # warm off-white

# First one that exists wins. --font skips the list.
SERIF_FONTS = [
    "/System/Library/Fonts/Supplemental/Didot.ttc",
    "/System/Library/Fonts/Palatino.ttc",
    "/System/Library/Fonts/Supplemental/Baskerville.ttc",
    "/System/Library/Fonts/Supplemental/Georgia.ttf",
    r"C:\Windows\Fonts\pala.ttf",
    r"C:\Windows\Fonts\georgia.ttf",
    r"C:\Windows\Fonts\times.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSerif-Regular.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf",
]


def read_meta(lang, keys):
    """Values from the merged config, rendered by pandoc like the build does."""
    if not os.path.isfile("book.yaml"):
        sys.exit("❌ Missing book.yaml — run this from the repo root.")
    args = ["pandoc", os.devnull, "--from=markdown", "--metadata-file=book.yaml"]
    lang_yaml = os.path.join("manuscript", lang, "book.yaml")
    if os.path.isfile(lang_yaml):
        args.append("--metadata-file=" + lang_yaml)
    # One key per line, so a value can never run into the next one.
    with tempfile.NamedTemporaryFile("w", suffix=".tpl", delete=False, encoding="utf-8") as tpl:
        tpl.write("\n".join(f"${k}$" for k in keys) + "\n")
    try:
        out = subprocess.run(args + ["--template=" + tpl.name, "--wrap=none", "-t", "plain"],
                             capture_output=True, text=True, encoding="utf-8", check=True).stdout
    except FileNotFoundError:
        sys.exit("❌ pandoc is not installed. See https://pandoc.org/installing.html")
    finally:
        os.unlink(tpl.name)
    lines = out.split("\n")
    return {k: (lines[i].strip() if i < len(lines) else "") for i, k in enumerate(keys)}


def pick_font(path):
    if path:
        if not os.path.isfile(path):
            sys.exit(f"❌ Font not found: {path}")
        return path
    for candidate in SERIF_FONTS:
        if os.path.isfile(candidate):
            return candidate
    sys.exit("❌ No serif font found. Pass one with --font=/path/to/Font.ttf")


def wrap(draw, text, font, max_width):
    lines, line = [], ""
    for word in text.split():
        trial = f"{line} {word}".strip()
        if draw.textlength(trial, font=font) <= max_width or not line:
            line = trial
        else:
            lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines


def fit_title(draw, text, font_path, max_width, max_lines=3):
    """Largest size at which the title fits in max_lines lines."""
    for size in range(170, 60, -6):
        font = ImageFont.truetype(font_path, size)
        lines = wrap(draw, text, font, max_width)
        if len(lines) <= max_lines and all(draw.textlength(l, font=font) <= max_width for l in lines):
            return font, lines
    font = ImageFont.truetype(font_path, 60)
    return font, wrap(draw, text, font, max_width)


def draw_block(draw, lines, font, top, bottom, spacing=1.25):
    """Centre the lines horizontally, and as a block between top and bottom."""
    ascent, descent = font.getmetrics()
    line_h = int((ascent + descent) * spacing)
    y = top + (bottom - top - line_h * len(lines)) // 2
    for line in lines:
        x = (WIDTH - draw.textlength(line, font=font)) / 2
        draw.text((x, y), line, font=font, fill=INK)
        y += line_h


def main():
    ap = argparse.ArgumentParser(description="Make images/cover_<lang>.jpg from cover-art in book.yaml.")
    ap.add_argument("--lang", required=True, help="language folder, e.g. nl")
    ap.add_argument("--font", help="path to a .ttf/.ttc/.otf to use instead of the default serif")
    ap.add_argument("--out", help="output file (default: images/cover_<lang>.jpg)")
    opts = ap.parse_args()

    if not os.path.isdir(os.path.join("manuscript", opts.lang)):
        sys.exit(f"❌ No manuscript/{opts.lang}/ folder.")

    meta = read_meta(opts.lang, ["title", "byline", "cover-art"])
    for key in ("title", "byline", "cover-art"):
        if not meta[key]:
            sys.exit(f"❌ book.yaml has no '{key}'.")
    if not os.path.isfile(meta["cover-art"]):
        sys.exit(f"❌ Cover art not found: {meta['cover-art']} (set 'cover-art' in book.yaml)")

    art = Image.open(meta["cover-art"]).convert("RGB")
    # Full width, unless that would make it too tall to leave room for text.
    scale = min(WIDTH / art.width, HEIGHT * 0.6 / art.height)
    art = art.resize((round(art.width * scale), round(art.height * scale)), Image.LANCZOS)

    # Background: the painting's own average colour, darkened well below the
    # text, so the cover looks of a piece with the art.
    avg = ImageStat.Stat(art).mean
    background = tuple(int(c * 0.22) for c in avg)
    cover = Image.new("RGB", (WIDTH, HEIGHT), background)
    draw = ImageDraw.Draw(cover)

    # Title above the art, author below: a third of the free space for the author.
    free = HEIGHT - art.height
    author_band = max(360, int(free * 0.36))
    art_top = HEIGHT - author_band - art.height
    cover.paste(art, ((WIDTH - art.width) // 2, art_top))

    font_path = pick_font(opts.font)
    title_font, title_lines = fit_title(draw, meta["title"], font_path, WIDTH - 2 * MARGIN)
    draw_block(draw, title_lines, title_font, MARGIN // 2, art_top)

    author_font = ImageFont.truetype(font_path, 72)
    draw_block(draw, [meta["byline"]], author_font, art_top + art.height, HEIGHT - MARGIN // 3)

    out = opts.out or os.path.join("images", f"cover_{opts.lang}.jpg")
    cover.save(out, "JPEG", quality=90, optimize=True)
    print(f"🖼  Cover written: {out}  ({WIDTH}×{HEIGHT}, {os.path.basename(font_path)})")
    print(f"   Point cover: at it in book.yaml or manuscript/{opts.lang}/book.yaml.")


if __name__ == "__main__":
    main()
