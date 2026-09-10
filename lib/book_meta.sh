#!/usr/bin/env bash
# shellcheck shell=bash
#
# Shared by epub/bake_book_epub.sh and pdf/bake_book_pdf.sh.
# Source it, don't run it.
#
# Gives you:
#   $BOOK_CONFIG   path to book.yaml
#   $TMPDIR_BUILD  scratch dir, removed on exit
#   read_meta KEY  one value out of book.yaml (nested: read_meta github.owner)

BOOK_CONFIG="${BOOK_CONFIG:-book.yaml}"

# Every path in both bake scripts is relative to the repo root. Running from
# anywhere else used to create a stray versions/ beside the caller; fail loudly
# instead.
if [[ ! -f "$BOOK_CONFIG" ]]; then
  echo "❌ Missing $BOOK_CONFIG — run this from the repo root." >&2
  exit 1
fi

command -v pandoc >/dev/null 2>&1 || {
  echo "❌ pandoc is not installed. See https://pandoc.org/installing.html" >&2
  exit 1
}

TMPDIR_BUILD=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BUILD"' EXIT

# Read one scalar out of book.yaml by handing it to pandoc's own template
# engine. Doing it this way means quoting, unicode and nesting behave exactly
# as they will when pandoc reads the same file during the real build — rather
# than however a hand-rolled grep would have guessed.
#
# An absent key renders empty, which is what the callers expect.
# --wrap=none matters: without it pandoc folds long values across lines, and
# the `head -1` below would then silently return only the first half.
read_meta() {
  printf '$%s$' "$1" > "$TMPDIR_BUILD/meta.tpl"
  pandoc /dev/null --from=markdown --metadata-file="$BOOK_CONFIG" \
    --template="$TMPDIR_BUILD/meta.tpl" --wrap=none -t plain 2>/dev/null | head -1
}

# Guard against publishing every book in the world under one EPUB id.
require_real_identifier() {
  local id
  id=$(read_meta identifier)
  case "$id" in
    ""|*__UUID__*|*123e4567*)
      echo "❌ book.yaml still has a placeholder 'identifier'." >&2
      echo "   Run ./setup.sh, or set it by hand to: urn:uuid:\$(uuidgen | tr 'A-Z' 'a-z')" >&2
      exit 1
      ;;
  esac
}
