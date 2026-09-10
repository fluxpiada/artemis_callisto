#!/usr/bin/env bash

# ============================================================
# Build the EPUB.
#
#   epub/bake_book_epub.sh --version=v1.0.0
#   epub/bake_book_epub.sh --auto        # version from the latest v* tag
#   epub/bake_book_epub.sh               # prompts
#
# Run it from the repo root. Everything configurable lives in book.yaml.
# ============================================================

set -euo pipefail

# shellcheck source=lib/book_meta.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/book_meta.sh"

OUTDIR="versions"
TEMPLATE="epub/metadata.xml.tpl"
RELEASE_SCRIPT="epub/make_releases_md.js"
CSS="epub/style.css"

RELEASES_MD="manuscript/front/20_releases.md"
BUILD_INFO_MD="manuscript/front/30_build_info.md"

usage() {
  cat <<'EOF'
Usage: epub/bake_book_epub.sh [options]

  --auto           Take the version from the latest git tag (for CI)
  --version=VER    Use VER as the version string
  -h, --help       Show this message

With neither --auto nor --version, the script prompts for a version number.
EOF
}

VERSION=""
for arg in "$@"; do
  case "$arg" in
    # --match='v*' is load-bearing: a bare `git describe` returns the closest
    # tag by commit distance, which picks up things like backup/* tags — and a
    # tag with a slash in it turns the output path into a subdirectory.
    --auto)      VERSION=$(git describe --tags --abbrev=0 --match='v*' 2>/dev/null || echo "v0.0.0-auto") ;;
    --version=*) VERSION="${arg#*=}" ;;
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

require_real_identifier

SLUG=$(read_meta slug)
COVER=$(read_meta cover)
GH_OWNER=$(read_meta github.owner)
GH_REPO=$(read_meta github.repo)

[[ -n "$SLUG" ]] || { echo "❌ book.yaml has no 'slug'." >&2; exit 1; }
[[ -f "$COVER" ]] || { echo "❌ Cover image not found: $COVER (set 'cover' in book.yaml)" >&2; exit 1; }

# ------------------------------------------------------------
# 📜 Release history and build stamp
# ------------------------------------------------------------
# Both are generated, both are gitignored, and both are built here rather than
# in the CI workflow — so that what you get locally is what CI gets.
if [[ -n "$GH_OWNER" && -n "$GH_REPO" && "$GH_OWNER" != *__* ]]; then
  echo "📜 Fetching release history..."
  node "$RELEASE_SCRIPT" "$GH_OWNER" "$GH_REPO" "$RELEASES_MD" || true
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
  --metadata-file="$BOOK_CONFIG" \
  --metadata=build-date:"$(date -u '+%Y-%m-%d')" \
  --template="$TEMPLATE" \
  --wrap=none \
  -t html > "$META"

# ------------------------------------------------------------
# 📚 Assemble
# ------------------------------------------------------------
# Order is front matter, then chapters in filename order, then back matter.
# manuscript/*.md does not match subdirectories, so the three sets are
# disjoint by construction and draft/ is never picked up.
shopt -s nullglob
INPUTS=(manuscript/front/*.md manuscript/*.md manuscript/back/*.md)
shopt -u nullglob

[[ ${#INPUTS[@]} -eq 0 ]] && { echo "❌ No .md files found in manuscript/." >&2; exit 1; }

mkdir -p "$OUTDIR"
OUTFILE="$OUTDIR/${SLUG}_${VERSION}.epub"

echo "⚙️  Building EPUB $VERSION..."

PANDOC_ARGS=(
  "${INPUTS[@]}"
  --resource-path="manuscript:images"
  --epub-cover-image="$COVER"
  --epub-metadata="$META"
  --toc
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
