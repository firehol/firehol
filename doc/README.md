FireHOL/FireQOS Manual Maintenance
==================================

The manuals are written in the pandoc version of Markdown. See the
[pandoc site](http://johnmacfarlane.net/pandoc/README.html) for tool
and syntax information:

The single-file manuals (PDF and HTML) are combined by a script which looks
at the file in the appropriate subdirectory:
    contents.md

To add a new file, just add it to contents.md and specify the output
manpages in Makefile.am under MANUALMAN_GENERATED.

If synonym manpages are needed, add them to Makefile.am under the variable
MANUALMAN_GENERATED_INDIRECT and create a comment block in the .md file:

~~~~
<!--
extra-manpage: firehol-accept.5
extra-manpage: firehol-reject.5
extra-manpage: firehol-drop.5
extra-manpage: firehol-deny.5
extra-manpage: firehol-return.5
extra-manpage: firehol-tarpit.5
-->
~~~~

See the pandoc website and manpage for details and options. To quickly
process this file, try:

    pandoc -f markdown -o README.pdf README.md
    pandoc -f markdown -o README.html README.md


Titles
======

Use #, ##, ### rather than underlining titles, since some of the scripts
rely on them when combining files. The exception is introduction.md which
should use ==== etc. These conventions are relied on whilst combining
files to ensure sections wind up at the correct hierarchy in the output.


Linking
=======

In order to make links across multiple formats as simple as possible,
follow these conventions:

Keywords + Services Links
:   Always write links to these as:

        [your text][keyword-product-name]

    Keyword link definitions should be included in `link-keywords-firehol`
    or `links-keywords-fireqos`, and should be of the form:
        `file.md#anchor-in-single-html`

    the build scripts will take care of excluding or replacing the file.md
    according to the output format.

    Services links are generated automatically as part of the build process
    and will be put in the `service-links` file.

Internal Links
:   Always write links to these as:

        [title name][] or [your text][title name]

    Internal link definitions should be included in `links-internal` and
    written in the form:
        `filename.md#markdown-anchor`

    these will be processed appropriately for each format.

External Links
:   External links can be written in-line as:

        [whatever](http://host/path/#id)

    they are not subject to special processing.


Uniqueness of anchors
---------------------
For the single-page HTML output, the anchors which are referenced must
be globally unique, not just within a file. This means whenever an
internal link is created, the section to which it refers must be
uniquely named.

The check-links script ensures this is the case whilst building the
HTML output.

Pandoc creates anchors automatically for most headers etc. but it is
possible to manually create an anchor with standard HTML syntax e.g.

    <a id="myid"></a>

This can be used as normal and should be included in `internal-links`
if it will be used from within the document or referred to from the
website.


Vim Syntax highlighting
=======================
Best will be to install specific pandoc highlighting, such as
that available in the [vim-pandoc](https://github.com/vim-pandoc/vim-pandoc)
plugin.

If you need a simple way to install the plugin, first install
[pathogen](https://github.com/tpope/vim-pathogen), which is simple and
makes adding the syntax highlighter simple too.

An alternative quick way to ensure .md files are recognised as markdowm,
not Modula2 by editing your
[.vimrc](https://github.com/tpope/vim-markdown/blob/master/ftdetect/markdown.vim)

Note that vim markdown syntax highlighting does not match pandoc perfectly,
so you may get some occasional artifacts.


Quirks
======

Pandoc output has a few quirks, depending on version. Versions earlier
than 1.9.4.2 are known to have problems, so FireHOL checks for that as
a minimum.

Some post-processing of output is performed by a script to tidy up some
artifacts.
