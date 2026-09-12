# Chapter I - The First One

Chapters are the numbered files directly in `manuscript/`. The number sets the
order, so `01_`, `02_`, `03_` is all the structure you need. Delete this file
and write your own; nothing anywhere refers to it by name.

Start the file with a level-one heading in this shape. The PDF turns it into a
proper Shunn chapter opening — a third of the way down a fresh page, centred —
and the EPUB turns it into a table-of-contents entry.

## ~ * ~

That was a scene break. Write it as `## ~ * ~` on its own line, and the PDF
renders it as a centred `#` the way the format asks. A run of asterisks or
tildes works too; `## ~ *** ~` is the same thing.

A scene break is the only divider you need. Do not try to force a page break —
manuscript format does not use them inside a chapter.

Emphasis with *asterisks* comes out italic, or underlined if you build with
`--classic`, which is what Shunn Classic asks for.

```text
Fenced blocks are code by default.

If your book has no code in it and you want blocks like this to render as
centred screen text instead — a terminal, a sign, a readout — set
shunn.machinetext to true in book.yaml. Leave it off if you write about
software, or your indentation will vanish.
```

Keep writing. The word count on the PDF cover sheet is computed from the
chapter files only, and rounded the way the format expects.
