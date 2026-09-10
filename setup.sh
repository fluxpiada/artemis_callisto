#!/usr/bin/env bash
#
# Run this once, after creating your repo from the template.
#
# It asks four questions, writes the answers into book.yaml, generates a real
# EPUB identifier, and fills in index.html — the one file that cannot read
# book.yaml, because GitHub Pages serves it as a plain static file.
#
# Then it deletes itself. Everything after this is edited in book.yaml.

set -euo pipefail

cd "$(dirname "$0")"

[[ -f book.yaml ]] || { echo "❌ Run this from the repo root." >&2; exit 1; }

if ! grep -q '__GH_OWNER__' book.yaml; then
  echo "✅ Already set up — book.yaml has no placeholders left."
  echo "   Edit book.yaml directly from here on."
  exit 0
fi

echo
echo "Setting up your book. Press Enter to accept the [default]."
echo

ask() { # ask VAR "prompt" "default"
  local __var=$1 __prompt=$2 __default=$3 __answer
  read -r -p "$__prompt [$__default]: " __answer || true
  printf -v "$__var" '%s' "${__answer:-$__default}"
}

GUESS_OWNER=$(git config --get remote.origin.url 2>/dev/null | sed -n 's#.*[:/]\([^/]*\)/[^/]*$#\1#p')
GUESS_REPO=$(git config --get remote.origin.url 2>/dev/null | sed -n 's#.*/\([^/]*\)\.git$#\1#p')

ask TITLE  "Book title"          "Your Book Title"
ask AUTHOR "Author name"         "A. N. Author"
ask OWNER  "GitHub user or org"  "${GUESS_OWNER:-your-username}"
ask REPO   "GitHub repo name"    "${GUESS_REPO:-your-book}"

# A double quote in any of these would break the YAML written below.
for v in TITLE AUTHOR OWNER REPO; do
  printf -v "$v" '%s' "${!v//\"/}"
done

# Filesystem-safe name for build output: spaces to underscores, drop the rest.
SLUG=$(printf '%s' "$TITLE" | tr ' ' '_' | tr -cd '[:alnum:]_-')
[[ -n "$SLUG" ]] || SLUG="your_book"

# Surname for the running header: the last whitespace-separated word.
SURNAME="${AUTHOR##* }"

# Library sort order: "Author, A. N."
FIRST="${AUTHOR% *}"
SORTNAME="$SURNAME, $FIRST"

# A permanent, unique id for the EPUB. Every book needs its own.
if command -v uuidgen >/dev/null 2>&1; then
  UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
else
  UUID=$(python3 -c 'import uuid; print(uuid.uuid4())')
fi

DESC="Download the ePub of $TITLE."
RIGHTS="© $(date +%Y) $AUTHOR"

# Values reach perl through the environment rather than by being pasted into
# the script text. That way a quote or a backslash in someone's name cannot
# break the substitution, and nothing needs escaping on either side.
export TITLE AUTHOR OWNER REPO UUID SLUG SORTNAME SURNAME DESC RIGHTS

# perl -pi, not sed -i: sed wants a backup-suffix argument on macOS and refuses
# one on Linux, and this has to work on both.
perl -pi -e '
  s/__BOOK_TITLE__/$ENV{TITLE}/g;
  s/__BOOK_AUTHOR__/$ENV{AUTHOR}/g;
  s/__BOOK_DESCRIPTION__/$ENV{DESC}/g;
  s/__GH_OWNER__/$ENV{OWNER}/g;
  s/__GH_REPO__/$ENV{REPO}/g;
  s/__UUID__/$ENV{UUID}/g;
' index.html manuscript/front/10_title.md

perl -pi -e '
  s/^title:.*/title:       "$ENV{TITLE}"/;
  s/^byline:.*/byline:      "$ENV{AUTHOR}"/;
  s/^author-sort:.*/author-sort: "$ENV{SORTNAME}"/;
  s/^slug:.*/slug:        "$ENV{SLUG}"/;
  s/^surname:.*/surname:     "$ENV{SURNAME}"/;
  s/^description:.*/description: "$ENV{DESC}"/;
  s/^rights:.*/rights:      "$ENV{RIGHTS}"/;
  s/__UUID__/$ENV{UUID}/;
  s/__GH_OWNER__/$ENV{OWNER}/;
  s/__GH_REPO__/$ENV{REPO}/;
  # First line of the Shunn contact block is your legal name. The rest stay
  # bracketed placeholders, on purpose — fill them in before submitting.
  s/^  - "A\. N\. Author"$/  - "$ENV{AUTHOR}"/;
' book.yaml

# None of the files this script fills in may still hold a placeholder.
# (setup.sh and lib/book_meta.sh mention the placeholder names on purpose, so
# they are not in this list.)
if grep -n '__[A-Z_]\{3,\}__' book.yaml index.html manuscript/front/10_title.md; then
  echo
  echo "❌ Placeholders remain in the lines above. Fix them by hand." >&2
  exit 1
fi

cat <<EOF

✅ Set up "$TITLE" by $AUTHOR.

   Next:
     1. Replace images/cover.png with your own cover.
     2. Write your chapters in manuscript/ — delete the samples.
     3. Fill in the contact block in book.yaml before submitting anywhere.
     4. Build:  epub/bake_book_epub.sh --version=v0.1.0

   Everything else is in book.yaml and README.md.

EOF

rm -- "$0"
echo "   (setup.sh has removed itself. Commit when ready.)"
echo
