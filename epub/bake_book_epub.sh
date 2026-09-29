#!/usr/bin/env bash

# ============================================================
# Build the EPUB.
#
#   epub/bake_book_epub.sh --version=v1.0.0
#   epub/bake_book_epub.sh --version=v1.0.0             # every language
#   epub/bake_book_epub.sh --version=v1.0.0 --lang=nl   # just Dutch
#   epub/bake_book_epub.sh --auto        # version from the latest v* tag
#   epub/bake_book_epub.sh               # prompts
#
# Run it from the repo root. Everything configurable lives in book.yaml, and
# per language in manuscript/<lang>/book.yaml.
# ============================================================

set -euo pipefail

# shellcheck source=lib/book_meta.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/book_meta.sh"

OUTDIR="versions"
TEMPLATE="epub/metadata.xml.tpl"
RELEASE_SCRIPT="epub/make_releases_md.js"
CSS="epub/style.css"

usage() {
  cat <<'EOF'
Usage: epub/bake_book_epub.sh [options]

  --auto           Take the version from the latest git tag (for CI)
  --version=VER    Use VER as the version string
  --lang=CODES     Build only these languages: --lang=nl or --lang=nl,fr.
                   --lang=all builds every folder in manuscript/. Without
                   it: the publish: list in book.yaml, or every language
  -h, --help       Show this message

With neither --auto nor --version, the script prompts for a version number.
EOF
}

VERSION=""
BUILD_LANG=""
for arg in "$@"; do
  case "$arg" in
    # --match='v*' is load-bearing: a bare `git describe` returns the closest
    # tag by commit distance, which picks up things like backup/* tags — and a
    # tag with a slash in it turns the output path into a subdirectory.
    --auto)      VERSION=$(git describe --tags --abbrev=0 --match='v*' 2>/dev/null || echo "v0.0.0-auto") ;;
    --version=*) VERSION="${arg#*=}" ;;
    --lang=*)    BUILD_LANG="${arg#*=}" ;;
    -h|--help)   usage; exit 0 ;;
    *)           echo "❌ Unknown option: $arg" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  # Without the `|| true` an EOF on stdin — which is what a CI job or a script
  # gives you — would kill the run under `set -e` before the message below
  # ever printed, leaving no output at all to explain the failure.
  read -r -p "Enter version number (e.g. v1.0.0): " VERSION || true
  [[ -z "$VERSION" ]] && {
    echo "❌ No version given. Use --version=VER or --auto when not on a terminal." >&2
    exit 1
  }
fi

for f in "$TEMPLATE" "$RELEASE_SCRIPT"; do
  [[ -f "$f" ]] || { echo "❌ Missing $f — run this from the repo root." >&2; exit 1; }
done

# Every option except the language and the version goes to each language's
# build unchanged; the version is passed already resolved, so a prompt or a
# git lookup happens once, not once per language.
PASS_ARGS=()
for arg in "$@"; do
  case "$arg" in --lang=*|--version=*|--auto) ;; *) PASS_ARGS+=("$arg") ;; esac
done
build_languages "${BASH_SOURCE[0]}" "$BUILD_LANG" --version="$VERSION" ${PASS_ARGS[@]+"${PASS_ARGS[@]}"}

use_language "$BUILD_LANG"
require_real_identifier

SLUG=$(read_meta slug)
COVER=$(read_meta cover)
GH_OWNER=$(read_meta github.owner)
GH_REPO=$(read_meta github.repo)
EDITION_TEXT=$(read_meta edition-text)
CONTENTS_TEXT=$(read_meta contents-text)

[[ -n "$SLUG" ]] || { echo "❌ book.yaml has no 'slug'." >&2; exit 1; }
[[ -f "$COVER" ]] || { echo "❌ Cover image not found: $COVER (set 'cover' in book.yaml)" >&2; exit 1; }

RELEASES_MD="$MS_DIR/front/20_releases.md"
BUILD_INFO_MD="$MS_DIR/front/30_build_info.md"
CONTENTS_MD="$MS_DIR/front/40_contents.md"

# ------------------------------------------------------------
# 📜 Release history and build stamp
# ------------------------------------------------------------
# Both are generated, both are gitignored, and both are built here rather than
# in the CI workflow — so that what you get locally is what CI gets.
if [[ -n "$GH_OWNER" && -n "$GH_REPO" && "$GH_OWNER" != *__* ]]; then
  echo "📜 Fetching release history..."
  node "$RELEASE_SCRIPT" "$GH_OWNER" "$GH_REPO" "$RELEASES_MD" "${EDITION_TEXT:-Current edition}" || true
else
  echo "📜 No github: owner/repo in book.yaml — skipping release history."
  rm -f "$RELEASES_MD"
fi

mkdir -p "$(dirname "$BUILD_INFO_MD")"
{
  printf '<div style="text-align:center;font-size:0.8em;">\n'
  printf 'Built %s' "$(date -u '+%Y-%m-%d %H:%M UTC')"
  COMMIT=$(git rev-parse --short HEAD 2>/dev/null || true)
  [[ -n "$COMMIT" ]] && printf ' · commit %s' "$COMMIT"
  printf '\n</div>\n'
} > "$BUILD_INFO_MD"

# ------------------------------------------------------------
# 🏷  EPUB metadata, rendered from book.yaml
# ------------------------------------------------------------
# -t html so that &, < and > in the title or blurb are escaped into valid XML.
# --wrap=none so that a long name is not folded across two lines, which would
# put a newline inside <dc:creator>.
META="$TMPDIR_BUILD/metadata.xml"
pandoc /dev/null \
  --from=markdown \
  "${META_ARGS[@]}" \
  --metadata=build-date:"$(date -u '+%Y-%m-%d')" \
  --template="$TEMPLATE" \
  --wrap=none \
  -t html > "$META"

# ------------------------------------------------------------
# 📚 Assemble
# ------------------------------------------------------------
# Order is front matter, then chapters in filename order, then back matter.
# $MS_DIR/*.md does not match subdirectories, so the three sets are disjoint
# by construction and draft/ is never picked up.
collect_inputs() {
  shopt -s nullglob
  INPUTS=("$MS_DIR"/front/*.md "$MS_DIR"/*.md "$MS_DIR"/back/*.md)
  shopt -u nullglob
}

# A stale contents page from the last build must not list itself.
rm -f "$CONTENTS_MD"
collect_inputs

[[ ${#INPUTS[@]} -eq 0 ]] && { echo "❌ No .md files found in $MS_DIR/." >&2; exit 1; }

# An EPUB page is XML, and XML forbids "--" inside a comment. pandoc copies
# <!-- notes --> into the EPUB as they are, so one "--with-extras" in a note
# turns that page into an error message in Apple Books. Catch it here instead.
BAD_COMMENTS=$(perl -0ne 'while (/<!--(.*?)-->/sg) { if ($1 =~ /--/) { print "   $ARGV\n"; last } }' "${INPUTS[@]}")
if [[ -n "$BAD_COMMENTS" ]]; then
  echo "❌ A <!-- comment --> contains a double hyphen (--), which breaks the EPUB page:" >&2
  echo "$BAD_COMMENTS" >&2
  echo "   Reword it without '--', e.g. 'the with-extras option'." >&2
  exit 1
fi

# ------------------------------------------------------------
# 📑 Contents page
# ------------------------------------------------------------
# pandoc always puts its own contents page straight after the cover, before
# the title and copyright page. So the build leaves that one out of the reading
# order (no --toc below; e-readers still get it as their contents menu) and
# writes a contents page into the front matter instead, after the title page.
#
# pandoc makes the list itself, from the same files in the same order as the
# real build, so every link points at the id the real build gives that heading.
# Headings marked {.unlisted} — title page, acknowledgments — are left out.
printf '$table-of-contents$\n' > "$TMPDIR_BUILD/toc.tpl"
TOC_LIST=$(pandoc "${INPUTS[@]}" --from=markdown -t markdown \
  --toc --toc-depth=1 --template="$TMPDIR_BUILD/toc.tpl" --wrap=none)

if [[ -n "$TOC_LIST" ]]; then
  printf '# %s {#contents .unlisted}\n\n%s\n' "${CONTENTS_TEXT:-Contents}" "$TOC_LIST" > "$CONTENTS_MD"
  collect_inputs
fi

mkdir -p "$OUTDIR"
OUTFILE="$OUTDIR/${SLUG}_${VERSION}_${BOOK_LANG}.epub"

echo "⚙️  Building EPUB $VERSION ($BOOK_LANG)..."

PANDOC_ARGS=(
  "${INPUTS[@]}"
  --resource-path="$MS_DIR:images"
  --epub-cover-image="$COVER"
  --epub-metadata="$META"
  # Marks the text itself with its language, which e-readers use for
  # hyphenation and text-to-speech.
  --metadata=lang:"$BOOK_LANG"
  # The opening pages are cover, then front/ (title and copyright page, then
  # the contents page above), then chapter one. pandoc's own title page would
  # come out empty, and --toc would put its contents page before front/, so
  # neither is used. The reader's contents menu is still built, to this depth.
  --epub-title-page=false
  --toc-depth=1
  --output="$OUTFILE"
)
# Genuinely optional, unlike the version of this line it replaces.
[[ -f "$CSS" ]] && PANDOC_ARGS+=(--css="$CSS")

pandoc "${PANDOC_ARGS[@]}"

echo
echo "🎉 EPUB built successfully:"
echo "   → $OUTFILE"
echo
