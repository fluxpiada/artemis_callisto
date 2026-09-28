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

Without `--lang`, both scripts build the language set by `lang:` in the root
`book.yaml`. Pass `--lang=` to build another one:

```bash
epub/bake_book_epub.sh --version=v0.1.0 --lang=fr
pdf/bake_book_pdf.sh   --version=v0.1.0 --lang=fr
```

The code is the folder name under `manuscript/`. Ask for one that doesn't exist
and the script lists the ones that do.

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

Both workflows build every language, and attach the EPUBs and PDFs to the
Release. To get a build without tagging, run either workflow from the Actions
tab and download the artifact.

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
description:    "Une romance mythique entre la déesse Artémis et la nymphe Callisto."
rights:         "© 2026 F. J. S. Remmelzwaal"
identifier:     "urn:uuid:a8c22ec5-9d93-4cd8-9c54-82cf537d6020"
wordcount-text: "environ %s mots"
edition-text:   "Édition actuelle"
```

This file only holds what differs. Anything it leaves out — author, contact
block, cover, font — comes from the root `book.yaml`. Add `cover:` if the
French edition has its own cover. You don't write `lang:` here: the folder
name sets it.

Build it with `--lang=fr`. On a tag, CI builds every language on its own.

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
| `## ~ * ~` | a scene break, centred |
| `*emphasis*` | italic, or underlined with `--classic` |
| `<!-- a note -->` | nothing — pandoc drops comments from every format |

Chapter files sort by filename, so keep the numbers padded: `01_`, `02_`, …
`10_`. That order *is* the order of your book.

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
