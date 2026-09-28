#!/usr/bin/env bash

# ============================================================
# Build the PDF in Shunn manuscript format.
# https://www.shunn.net/format/story/
#
# Run it from the repo root. Everything configurable lives in book.yaml, and
# per language in manuscript/<lang>/book.yaml.
# ============================================================

set -euo pipefail

# shellcheck source=lib/book_meta.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/book_meta.sh"

OUTDIR="versions"
TEMPLATE="pdf/shunn.latex"
FILTER="pdf/shunn.lua"

VERSION=""
BUILD_LANG=""
CLASSIC=false
PAPERSIZE="letter"
TITLEPAGE=false
EXTRAS=false
FONT=""

usage() {
  cat <<'EOF'
Usage: pdf/bake_book_pdf.sh [options]

  --auto           Take the version from the latest git tag (for CI)
  --version=VER    Use VER as the version string
  --lang=CODE      Build manuscript/CODE/ (default: lang: in book.yaml)
  --font=NAME      Typeset in NAME (e.g. --font="Georgia"). Overrides the
                   mainfont: key in book.yaml
  --list-fonts     List font families installed on this machine, then exit
  --classic        Shunn Classic: monospace face, emphasis underlined
  --a4             A4 paper instead of the US Letter the spec assumes
  --title-page     Novel format: a separate title page, page 1 = first text page
  --with-extras    Append the back matter after the end marker
  -h, --help       Show this message

Font resolution order: --font=  >  mainfont: in book.yaml  >  the built-in
fallback chain. An explicitly requested font that isn't installed is an error,
never a silent substitution.

With no --auto or --version, the script prompts for a version number.
EOF
}

list_fonts() {
  if command -v fc-list >/dev/null 2>&1; then
    fc-list : family | tr ',' '\n' | sort -u | sed '/^$/d'
  else
    echo "❌ fc-list not found. On macOS: brew install fontconfig" >&2
    exit 1
  fi
}

for arg in "$@"; do
  case "$arg" in
    # See the note in epub/bake_book_epub.sh: the --match is load-bearing.
    --auto)         VERSION=$(git describe --tags --abbrev=0 --match='v*' 2>/dev/null || echo "v0.0.0-auto") ;;
    --version=*)    VERSION="${arg#*=}" ;;
    --lang=*)       BUILD_LANG="${arg#*=}" ;;
    --font=*)       FONT="${arg#*=}" ;;
    --list-fonts)   list_fonts; exit 0 ;;
    --classic)      CLASSIC=true ;;
    --a4)           PAPERSIZE="a4" ;;
    --title-page)   TITLEPAGE=true ;;
    --with-extras)  EXTRAS=true ;;
    -h|--help)      usage; exit 0 ;;
    *)              echo "❌ Unknown option: $arg" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  read -r -p "Enter version number (e.g. v1.0.0): " VERSION || true
  [[ -z "$VERSION" ]] && {
    echo "❌ No version given. Use --version=VER or --auto when not on a terminal." >&2
    exit 1
  }
fi

for f in "$TEMPLATE" "$FILTER"; do
  [[ -f "$f" ]] || { echo "❌ Missing $f — run this from the repo root." >&2; exit 1; }
done

use_language "$BUILD_LANG"

SLUG=$(read_meta slug)
[[ -n "$SLUG" ]] || { echo "❌ book.yaml has no 'slug'." >&2; exit 1; }

# ------------------------------------------------------------
# 🔤 Pick a font that actually exists on this machine
# ------------------------------------------------------------
font_available() {
  printf '\\documentclass{article}\\usepackage{fontspec}\\setmainfont{%s}\\begin{document}x\\end{document}\n' \
    "$1" > "$TMPDIR_BUILD/probe.tex"
  xelatex -halt-on-error -interaction=batchmode \
    -output-directory="$TMPDIR_BUILD" "$TMPDIR_BUILD/probe.tex" >/dev/null 2>&1
}

MAINFONT=""

# --font= beats mainfont: in book.yaml, which beats the fallback chain below.
[[ -z "$FONT" ]] && FONT=$(read_meta mainfont)

if [[ -n "$FONT" ]]; then
  # An explicit choice is honoured or refused — never quietly swapped out.
  font_available "$FONT" || {
    echo "❌ Font not installed: $FONT"
    echo "   Run 'pdf/bake_book_pdf.sh --list-fonts' to see what's available."
    exit 1
  }
  MAINFONT="$FONT"
  echo "🔤 Using font: $MAINFONT (set explicitly)"
fi

if [[ -z "$MAINFONT" ]]; then
  # Nothing was asked for, so fall back. The chains exist so that a CI box
  # without the Microsoft fonts still produces near-identical pagination.
  if $CLASSIC; then
    CANDIDATES=("Courier New" "Liberation Mono" "Nimbus Mono PS" "TeX Gyre Cursor" "DejaVu Sans Mono")
  else
    CANDIDATES=("Times New Roman" "Liberation Serif" "Nimbus Roman" "TeX Gyre Termes" "DejaVu Serif")
  fi

  for candidate in "${CANDIDATES[@]}"; do
    if font_available "$candidate"; then MAINFONT="$candidate"; break; fi
  done
  [[ -z "$MAINFONT" ]] && {
    echo "❌ None of these fonts are installed: ${CANDIDATES[*]}"
    echo "   Set one with --font=NAME or mainfont: in $BOOK_CONFIG."
    exit 1
  }
  echo "🔤 Using font: $MAINFONT (fallback chain)"
fi

# ------------------------------------------------------------
# 📚 Assemble the manuscript
# ------------------------------------------------------------
# Chapters are the numbered files directly in manuscript/<lang>/. Front matter
# and back matter live in subdirectories, so they are excluded here by the
# shape of the glob rather than by counting digits in filenames.
shopt -s nullglob
CHAPTERS=("$MS_DIR"/[0-9]*_*.md)
shopt -u nullglob
[[ ${#CHAPTERS[@]} -eq 0 ]] && {
  echo "❌ No chapter files found. Chapters are $MS_DIR/NN_Name.md" >&2
  exit 1
}

INPUTS=("${CHAPTERS[@]}")
if $EXTRAS; then
  # The end marker closes the story; back matter follows it, as it should.
  printf '::: theend\n:::\n' > "$TMPDIR_BUILD/theend.md"
  INPUTS+=("$TMPDIR_BUILD/theend.md")
  shopt -s nullglob
  INPUTS+=("$MS_DIR"/back/*.md)
  shopt -u nullglob
fi

# ------------------------------------------------------------
# 🔢 Word count, rounded the way Shunn asks
# ------------------------------------------------------------
RAW_WORDS=$(pandoc "${CHAPTERS[@]}" -t plain --wrap=none | wc -w | tr -d ' ')

if   (( RAW_WORDS < 17500 )); then STEP=100     # short story: nearest hundred
elif (( RAW_WORDS < 40000 )); then STEP=500     # novella: nearest five hundred
else                               STEP=1000    # novel: nearest thousand
fi
ROUNDED=$(( (RAW_WORDS + STEP / 2) / STEP * STEP ))
GROUPED=$(printf '%d' "$ROUNDED" | sed -e :a -e 's/\(.*[0-9]\)\([0-9]\{3\}\)/\1,\2/;ta')

# The phrase is configurable so a Dutch cover sheet can say "ongeveer … woorden".
WORDCOUNT_TEXT=$(read_meta wordcount-text)
[[ "$WORDCOUNT_TEXT" == *%s* ]] || WORDCOUNT_TEXT="about %s words"
PLACEHOLDER='%s'
WORDCOUNT="${WORDCOUNT_TEXT//"$PLACEHOLDER"/$GROUPED}"
echo "🔢 ${RAW_WORDS} words → ${WORDCOUNT}"

# ------------------------------------------------------------
# ⚙️ Build
# ------------------------------------------------------------
mkdir -p "$OUTDIR"

SUFFIX="manuscript"
$CLASSIC && SUFFIX="manuscript_classic"
OUTFILE="$OUTDIR/${SLUG}_${VERSION}_${BOOK_LANG}_${SUFFIX}.pdf"

echo "⚙️  Building Shunn-format PDF $VERSION ($BOOK_LANG)..."

PANDOC_ARGS=(
  "${INPUTS[@]}"
  --from=markdown
  "${META_ARGS[@]}"
  --template="$TEMPLATE"
  --lua-filter="$FILTER"
  # Without this, a fenced block becomes \begin{Shaded}, whose macros come
  # from pandoc's own template — which we replace. Plain verbatim needs no
  # package and is what a manuscript wants anyway.
  --no-highlight
  --resource-path="$MS_DIR:images:."
  --pdf-engine=xelatex
  --variable=mainfont:"$MAINFONT"
  --variable=papersize:"$PAPERSIZE"
  --variable=wordcount:"$WORDCOUNT"
  --output="$OUTFILE"
)
$CLASSIC   && PANDOC_ARGS+=(--metadata=classic:true)
$TITLEPAGE && PANDOC_ARGS+=(--variable=titlepage:true)

pandoc "${PANDOC_ARGS[@]}"

echo
echo "🎉 PDF built successfully:"
echo "   → $OUTFILE"
echo
