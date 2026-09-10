<?xml version="1.0" encoding="UTF-8"?>
$-- Rendered into the build tmpdir by epub/bake_book_epub.sh, from book.yaml.
$-- Do not edit the generated file; edit book.yaml.
$-- Rendered with -t html so that &, < and > in your title or blurb come out
$-- as valid XML instead of breaking the EPUB.
<dc:title>$title$</dc:title>
<dc:creator opf:role="aut"$if(author-sort)$ opf:file-as="$author-sort$"$endif$>$byline$</dc:creator>
<dc:identifier id="book-id">$identifier$</dc:identifier>
<dc:language>$lang$</dc:language>
$if(description)$
<dc:description>$description$</dc:description>
$endif$
$if(rights)$
<dc:rights>$rights$</dc:rights>
$endif$
<dc:date>$build-date$</dc:date>
$if(publisher)$
<dc:publisher>$publisher$</dc:publisher>
$endif$
