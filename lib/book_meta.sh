#!/usr/bin/env bash
# shellcheck shell=bash
#
# Shared by epub/bake_book_epub.sh and pdf/bake_book_pdf.sh.
# Source it, don't run it.
#
# Gives you:
#   $BOOK_CONFIG       path to book.yaml
#   $TMPDIR_BUILD      scratch dir, removed on exit
#   read_meta KEY      one value out of book.yaml (nested: read_meta github.owner)
#   use_language CODE  pick manuscript/CODE/; sets $BOOK_LANG, $MS_DIR, $META_ARGS
#   "${META_ARGS[@]}"  the pandoc arguments that feed the config to a build

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

# Until use_language runs, config is just the root book.yaml.
META_ARGS=(--metadata-file="$BOOK_CONFIG")
BOOK_LANG=""
MS_DIR=""
DEFAULT_LANG=""
ROOT_IDENTIFIER=""

# Read one scalar out of the config by handing it to pandoc's own template
# engine. Doing it this way means quoting, unicode and nesting behave exactly
# as they will when pandoc reads the same files during the real build — rather
# than however a hand-rolled grep would have guessed.
#
# An absent key renders empty, which is what the callers expect.
# --wrap=none matters: without it pandoc folds long values across lines, and
# the `head -1` below would then silently return only the first half.
read_meta() {
  printf '$%s$' "$1" > "$TMPDIR_BUILD/meta.tpl"
  pandoc /dev/null --from=markdown "${META_ARGS[@]}" \
    --template="$TMPDIR_BUILD/meta.tpl" --wrap=none -t plain 2>/dev/null | head -1
}

# Each language is a folder, manuscript/<code>/, and the folder name is the
# language code. Its optional book.yaml overrides the root one key by key:
# pandoc prefers the later --metadata-file, and -M beats both, so nobody has to
# write lang: by hand.
use_language() {
  local code=${1:-} d have=""

  DEFAULT_LANG=$(read_meta lang)
  ROOT_IDENTIFIER=$(read_meta identifier)
  [[ -z "$code" ]] && code="$DEFAULT_LANG"

  if [[ -z "$code" || ! -d "manuscript/$code" ]]; then
    for d in manuscript/*/; do
      [[ -d "$d" ]] && { d=${d%/}; have+="${d##*/} "; }
    done
    echo "❌ No manuscript/${code:-<language>}/ folder." >&2
    echo "   Languages in this repo: ${have:-none}" >&2
    exit 1
  fi

  BOOK_LANG=$code
  MS_DIR="manuscript/$code"
  META_ARGS=(--metadata-file="$BOOK_CONFIG")
  [[ -f "$MS_DIR/book.yaml" ]] && META_ARGS+=(--metadata-file="$MS_DIR/book.yaml")
  META_ARGS+=(--metadata=lang:"$code")
}

# Guard against publishing every book in the world under one EPUB id — or a
# translation under the same id as the original, which makes e-readers treat
# the two as one book.
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
  if [[ -n "$BOOK_LANG" && "$BOOK_LANG" != "$DEFAULT_LANG" && "$id" == "$ROOT_IDENTIFIER" ]]; then
    echo "❌ $MS_DIR/ has no identifier of its own." >&2
    echo "   A translation is a separate EPUB. Add this line to $MS_DIR/book.yaml:" >&2
    echo "     identifier: \"urn:uuid:\$(uuidgen | tr 'A-Z' 'a-z')\"" >&2
    exit 1
  fi
}
