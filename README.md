# book_bake

Write a book in Markdown, keep it in Git, and let pandoc build it.

Two outputs, from the same chapters:

* an **EPUB** people can read
* a **PDF in [Shunn manuscript format](https://www.shunn.net/format/story/)**,
  the layout agents and editors expect for submissions

Push a version tag and GitHub Actions builds both and attaches them to a
Release. There is also a small download page, served straight from your repo.

The same book can live here in more than one language — see
[Another language](#another-language).

## Start

Click **Use this template**, clone your new repo, then:

```bash
./setup.sh
```

> No **Use this template** button? Then this repo's *Template repository* box
> is unticked — Settings → General, for whoever owns it. Meanwhile you can just
> clone it and run `rm -rf .git && git init`, which gets you the same thing.

It asks for your title, your name, the language you write in and your GitHub
details, writes them into `book.yaml`, generates a unique EPUB identifier, and
removes itself.

Then write. Your chapters go in `manuscript/<language>/`, one file per chapter —
`manuscript/nl/` for Dutch:

```text
manuscript/nl/book.yaml  title, blurb and identifier for this language
manuscript/nl/front/     title page, dedication — EPUB only
manuscript/nl/01_*.md    your chapters, in number order
manuscript/nl/back/      acknowledgments, appendix
manuscript/nl/draft/     never built
```

Every folder directly in `manuscript/` is treated as a language, by the build
and by CI. Don't leave anything else there.

## Build

```bash
epub/bake_book_epub.sh --version=v0.1.0
pdf/bake_book_pdf.sh   --version=v0.1.0
```

Run both from the repo root. They write to `versions/`, which is gitignored —
build output belongs on Releases, not in the repo. File names end in the
language code: `Artemis_en_Callisto_v0.1.0_nl.epub`.

### Choosing the language

Without `--lang`, both scripts build **every language** — one EPUB or PDF per
folder in `manuscript/`. To build fewer, pass `--lang=`:

```bash
epub/bake_book_epub.sh --version=v0.1.0 --lang=nl        # just this one
pdf/bake_book_pdf.sh   --version=v0.1.0 --lang=nl,fr     # these two
epub/bake_book_epub.sh --version=v0.1.0 --lang=all       # every folder, whatever book.yaml says
```

To fix which languages a release publishes, list them in the root `book.yaml`:

```yaml
publish: [nl]
```

A build without `--lang` then builds only those: locally, on a tag, and on a
manual Actions run with the *languages* box left empty. Leave `publish:` out
and every language is built. `--lang=` always wins.

The code is the folder name under `manuscript/`. Ask for one that doesn't exist
and the script lists the ones that do; the other languages still build, and the
run ends with an error naming the one that failed.

### How the EPUB opens

1. **The cover** — the `cover:` image from `book.yaml`. See [The cover](#the-cover).
2. **Title and copyright page** — `front/10_title.md`, with the release
   history and build stamp the build adds underneath.
3. **Contents** — generated on every build, headed by `contents-text:`
   (*Inhoud*, *Table des matières*). It lists your chapters and nothing marked
   `{.unlisted}`.
4. **Chapter one.**

The e-reader's own contents menu lists the same chapters.

The PDF also takes `--a4`, `--classic`, `--title-page`, `--with-extras` and
`--font=`. Run it with `--help`, or see
[`wiki/shunn_pdf_format.md`](wiki/shunn_pdf_format.md).

**You need:** pandoc, XeLaTeX (for the PDF), and Node 20 (the EPUB pulls your
release history from GitHub).

> The build scripts are bash. On Windows, run them from Git Bash or WSL — they
> have not been tested in PowerShell.

## Publish

Tag it. That is the whole process.

```bash
git tag -a v0.1.0 -m "First release"
git push origin v0.1.0
```

Both workflows build every language — or the ones in `publish:`, see
[Choosing the language](#choosing-the-language) — and attach the EPUBs and PDFs to the
Release. To get a build without tagging, run either workflow from the Actions
tab and download the artifact. Its *languages* box takes `nl` or `nl,fr`;
left empty, it builds what a tag would.

To put the download page online, turn on GitHub Pages in Settings and point it
at the `main` branch, folder `/`. There is no site build step — `index.html` is
served as-is, so edit it and push.

## Everything is in `book.yaml`

Title, author, contact block, cover path, GitHub details, and two switches for
how the PDF filter treats ambiguous markdown. The build scripts read it every
time, so there is one place to change and nothing to keep in sync.

`index.html` is the exception: Pages serves it as a static file, so it cannot
read config. `setup.sh` fills it in once.

### The metadata that goes into the EPUB

| `book.yaml` key | EPUB field | Example |
| --- | --- | --- |
| `title` | `dc:title` | `"De Romance van Artemis en Callisto"` |
| `byline` | `dc:creator` | `"F. J. S. Remmelzwaal"` |
| `author-sort` | `dc:creator` `file-as` | `"Remmelzwaal, Floortje J. S."` |
| `identifier` | `dc:identifier` | `"urn:uuid:ad861c7d-…"` — see below |
| `lang` | `dc:language` | set from the folder name |
| `description` | `dc:description` | one sentence about the book |
| `rights` | `dc:rights` | `"© 2026 F. J. S. Remmelzwaal"` |
| `publisher` | `dc:publisher` | `"self-published"` |
| — | `dc:date` | filled in with the build date |

`author-sort` is how libraries and e-readers file the book: surname first.
`description` is the blurb a reader sees in their library, so write it in the
language of that edition.

## The cover

E-readers show the cover as a picture — in the library, the store, the file
list — so the title and author have to be *in* the image. `epub/make_cover.py`
does that: it takes `cover-art:` from `book.yaml`, puts the title above it and
the author below, and writes a portrait 1600 × 2560 JPEG per language.

```bash
# macOS / Linux / Windows (PowerShell), with uv
uv run --with pillow epub/make_cover.py --lang=nl
uv run --with pillow epub/make_cover.py --lang=fr
```

Without uv, install Pillow once (`pip install pillow`) and run
`python3 epub/make_cover.py --lang=nl` — on Windows `py epub/make_cover.py --lang=nl`.

That writes `images/cover_nl.jpg` and `images/cover_fr.jpg`. Point `cover:` at
them — the root `book.yaml` for the default language, `manuscript/fr/book.yaml`
for French — and commit the images. Run it again whenever a title changes; the
build itself never runs it, so CI needs no Python.

It uses the first serif it finds (Didot, Palatino, Georgia on a Mac). Pick
another with `--font=/path/to/Font.ttf`.

> Written and tested on macOS. The Windows font paths are in the script but
> have not been tried on a Windows machine.

## The identifier

Every EPUB carries an `identifier`: a unique, permanent ID. E-readers and
stores use it to tell books apart — two EPUBs with the same identifier are
treated as the same book, so one can replace the other in a reader's library,
or mix up their reading progress and highlights.

It is `urn:uuid:` followed by a random UUID:

```yaml
identifier: "urn:uuid:ad861c7d-dbc6-4086-b04e-80b3228d7fd1"
```

`./setup.sh` makes the first one for you. To make one by hand:

```bash
# macOS / Linux
uuidgen | tr 'A-Z' 'a-z'
```

```powershell
# Windows (PowerShell)
[guid]::NewGuid().ToString()
```

Paste the output after `urn:uuid:` — no space between them.

The rules:

* **One per edition.** Each language gets its own, in
  `manuscript/<code>/book.yaml`. The default language uses the one in the root
  `book.yaml`.
* **Never change it.** A new version of the same edition keeps the same
  identifier — the version number is what changes between releases.
* **Never copy one.** Not from another book, not from this book's other
  language. The build refuses a placeholder identifier, and refuses a
  translation that has none of its own.

## Another language

Every folder in `manuscript/` is a language, and **the folder name is the
language code**: `en`, `nl`, `fr`, `de`. To add French next to Dutch:

```bash
cp -r manuscript/nl manuscript/fr
```

Then generate a new identifier ([see above](#the-identifier)), put it in
`manuscript/fr/book.yaml`, and translate the chapters:

```yaml
title:          "La Romanze d'Artémis et de Callisto"
shorttitle:     "Artémis"
slug:           "Artemis_et_Callisto"
cover:          "images/cover_fr.jpg"
description:    "Une romance mythique entre la déesse Artémis et la nymphe Callisto."
rights:         "© 2026 F. J. S. Remmelzwaal"
identifier:     "urn:uuid:a8c22ec5-9d93-4cd8-9c54-82cf537d6020"
wordcount-text: "environ %s mots"
edition-text:   "Édition actuelle"
contents-text:  "Table des matières"
```

This file only holds what differs. Anything it leaves out — author, contact
block, cover art, font — comes from the root `book.yaml`. The cover has the
title on it, so each language gets its own: run `epub/make_cover.py --lang=fr`
([The cover](#the-cover)). You don't write `lang:` here: the folder name sets
it.

Build just this language with `--lang=fr`; without it, French is built along
with the rest.

## Getting template updates

A repo made with **Use this template** is a copy with no link back, so GitHub
never updates it for you. Two commands do.

Once per book, tell Git where the template lives:

```bash
cd path/to/your-book
git remote add template https://github.com/fluxpiada/book_bake.git
```

Each time the template changes:

```bash
git fetch template
git checkout template/main -- lib epub pdf .github wiki .gitignore
```

That replaces only the tooling. Your chapters, `book.yaml`, `index.html` and
this README are never touched. Build once to check, then commit.

## Writing conventions

| You write | You get |
| --- | --- |
| `# Chapter I - The Fjord` | a chapter opening, and a table-of-contents entry |
| `# Dankwoord {.unlisted}` | a page with that heading, left out of the contents — use it for the title page and acknowledgments |
| `## ~ * ~` | a scene break, centred |
| `*emphasis*` | italic, or underlined with `--classic` |
| `<!-- a note -->` | nothing — pandoc drops comments from every format |

Chapter files sort by filename, so keep the numbers padded: `01_`, `02_`, …
`10_`. That order *is* the order of your book.

Start every file with its `#` heading, on the first line. Anything above it —
even an HTML comment — becomes an empty page of its own.

## Checking your prose

[readability-stats](https://github.com/fluxpiada/readability-stats) reads a
folder of Markdown chapters and reports readability, pacing and vocabulary,
with a report you can diff between drafts. Point it at one language folder:

```bash
./run.sh 8 /path/to/your-book/manuscript/nl
```

It has an English and a Dutch implementation.

## Licence

The tooling here is GPL-3 — see [LICENSE](LICENSE). Use it for anything.

**What you write is yours.** This licence makes no claim on your manuscript,
your cover, or the files you build from them.
