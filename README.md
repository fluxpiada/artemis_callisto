# book_bake

Write a book in Markdown, keep it in Git, and let pandoc build it.

Two outputs, from the same chapters:

* an **EPUB** people can read
* a **PDF in [Shunn manuscript format](https://www.shunn.net/format/story/)**,
  the layout agents and editors expect for submissions

Push a version tag and GitHub Actions builds both and attaches them to a
Release. There is also a small download page, served straight from your repo.

## using a Github template
Use this template is a copy with no link back, so GitHub never updates it. But you can make each future update a single command.
Once per book, tell Git where the template lives:


```cd ~/<<YOUR REPO>>
git remote add template https://github.com/fluxpiada/book_bake.git
```
Each time the template changes:
```
git fetch template
git checkout template/main -- lib epub pdf .github wiki .gitignore
```
## Start

Click **Use this template**, clone your new repo, then:

```bash
./setup.sh
```

> No **Use this template** button? Then this repo's *Template repository* box
> is unticked — Settings → General, for whoever owns it. Meanwhile you can just
> clone it and run `rm -rf .git && git init`, which gets you the same thing.

It asks for your title, your name and your GitHub details, writes them into
`book.yaml`, generates a unique EPUB identifier, and removes itself.

Then write. Your chapters go in `manuscript/`, one file per chapter:

```text
manuscript/front/     title page, dedication — EPUB only
manuscript/01_*.md    your chapters, in number order
manuscript/back/      acknowledgments, appendix
manuscript/draft/     never built
```

Sample files are included so the build works before you have written anything.
Delete them as you go.

## Build

```bash
epub/bake_book_epub.sh --version=v0.1.0
pdf/bake_book_pdf.sh   --version=v0.1.0
```

Run both from the repo root. They write to `versions/`, which is gitignored —
build output belongs on Releases, not in the repo.

The PDF takes `--a4`, `--classic`, `--title-page`, `--with-extras` and
`--font=`. Run it with `--help`, or see
[`wiki/shunn_pdf_format.md`](wiki/shunn_pdf_format.md).

**You need:** pandoc, XeLaTeX (for the PDF), and Node 20 (the EPUB pulls your
release history from GitHub).

## Publish

Tag it. That is the whole process.

```bash
git tag -a v0.1.0 -m "First release"
git push origin v0.1.0
```

Both workflows build, and attach the EPUB and PDF to the Release. To get a
build without tagging, run either workflow from the Actions tab and download
the artifact.

To put the download page online, turn on GitHub Pages in Settings and point it
at the `main` branch, folder `/`. There is no site build step — `index.html` is
served as-is, so edit it and push.

## Everything is in `book.yaml`

Title, author, contact block, cover path, GitHub details, and two switches for
how the PDF filter treats ambiguous markdown. The build scripts read it every
time, so there is one place to change and nothing to keep in sync.

`index.html` is the exception: Pages serves it as a static file, so it cannot
read config. `setup.sh` fills it in once.

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
with a report you can diff between drafts. It points at `manuscript/` directly:

```bash
./run.sh 8 /path/to/your-book/manuscript
```

It has an English and a Dutch implementation.

## Licence

The tooling here is GPL-3 — see [LICENSE](LICENSE). Use it for anything.

**What you write is yours.** This licence makes no claim on your manuscript,
your cover, or the files you build from them.
