# Process this file with automake to produce Makefile.in

if MAINTAINER_MODE
gensrcdir=../..
else
gensrcdir=${top_srcdir}
endif

MANUAL_LINKS = \
	${top_srcdir}/doc/links-internal-vnetbuild \
	${top_srcdir}/doc/links-keywords-vnetbuild \
	${top_srcdir}/doc/links-website-vnetbuild

dochtmldir = $(htmldir)/html

MANUALHTML_GENERATED = \
	vnetbuild-manual.html

MANUALPDF_GENERATED = \
	vnetbuild-manual.pdf

# Generate using:
# (ls vn*.md) | sed -ne 's;\(.*\).\([0-9]\).md;\tman/man\2/\1.\2 \\;p' |sort -u
MANUALMAN_GENERATED = \
	man/man1/vnetbuild.1 \
	man/man5/vnetbuild-conf.5

# Generate using:
# sed -ne 's;extra-manpage: \(.*\)\([0-9]\);\tman/man\2/\1\2 \\;p' *.md|sort -u
MANUALMAN_GENERATED_INDIRECT = \
	man/man5/vnetbuild-bridgedev.5 \
	man/man5/vnetbuild.conf.5 \
	man/man5/vnetbuild-dev.5 \
	man/man5/vnetbuild-exec.5 \
	man/man5/vnetbuild-host.5 \
	man/man5/vnetbuild-pre_up.5 \
	man/man5/vnetbuild-route.5 \
	man/man5/vnetbuild-switch.5

if ENABLE_VNETBUILD

if ENABLE_DOC

dochtml_DATA = \
	$(MANUALHTML_GENERATED)

pdf_DATA = \
	$(MANUALPDF_GENERATED)

endif

if ENABLE_MAN

man_MANS = \
	$(MANUALMAN_GENERATED) \
	$(MANUALMAN_GENERATED_INDIRECT)

$(MANUALMAN_GENERATED_INDIRECT): $(MANUALMAN_GENERATED)

endif

endif

if MAINTAINER_MODE

MKSERVICELINKS = ${top_srcdir}/doc/tools/mkservicelinks
MKSERVICEMAN = ${top_srcdir}/doc/tools/mkserviceman
MANSYNOS = ${top_srcdir}/doc/tools/man-synos
COMBINEPANDOC = ${top_srcdir}/doc/tools/combine-pandoc
PANDOCPOST = $(gensrcdir)/doc/tools/pandoc-post
CHECKLINKS = ${top_srcdir}/doc/tools/check-links

man/man1/%.1: %.1.md
	$(MKDIR_P) man/man1
	$(SED) -e '/^%/s/DATE/@PACKAGE_BUILT_DATE@/' -e '/^%/s/VERSION/@PACKAGE_VERSION@/' $< > tmp-manproc
	$(SED) -e 's/: .*#/: #/' $(MANUAL_LINKS) > tmp-anchor-links
	$(PANDOC) $(PANDOC_MAN_FLAGS) -o $@ tmp-manproc tmp-anchor-links
	$(PANDOCPOST) $(PANDOC_VERSION) man $@
	$(MANSYNOS) $< $@ man/

man/man5/%.5: %.5.md
	$(MKDIR_P) man/man5
	$(SED) -e '/^%/s/DATE/@PACKAGE_BUILT_DATE@/' -e '/^%/s/VERSION/@PACKAGE_VERSION@/' $< > tmp-manproc
	$(SED) -e 's/: .*#/: #/' $(MANUAL_LINKS) > tmp-anchor-links
	$(PANDOC) $(PANDOC_MAN_FLAGS) -o $@ tmp-manproc tmp-anchor-links
	$(PANDOCPOST) $(PANDOC_VERSION) man $@
	$(MANSYNOS) $< $@ man/

$(MANUALMAN_GENERATED): $(MANUAL_LINKS)

vnetbuild-manual.pdf: *.md $(MANUAL_LINKS)
	$(SED) -e 's/: .*#/: #/' $(MANUAL_LINKS) > tmp-anchor-links
	$(COMBINEPANDOC) pdf tmp-pdf-combined.md contents.md tmp-anchor-links
	$(SED) -i -e '/^%/s/DATE/@PACKAGE_BUILT_DATE@/' -e '/^%/s/VERSION/@PACKAGE_VERSION@/' tmp-pdf-combined.md
	$(PANDOC) $(PANDOC_PDF_FLAGS) -o $@ tmp-pdf-combined.md
	rm tmp-pdf-combined.md
	$(PANDOCPOST) $(PANDOC_VERSION) pdf $@

vnetbuild-manual.html: *.md $(MANUAL_LINKS)
	$(SED) -e 's/: .*#/: #/' $(MANUAL_LINKS) > tmp-anchor-links
	$(COMBINEPANDOC) html tmp-html-combined.md contents.md tmp-anchor-links
	$(SED) -i -e '/^%/s/DATE/@PACKAGE_BUILT_DATE@/' -e '/^%/s/VERSION/@PACKAGE_VERSION@/' tmp-html-combined.md
	$(PANDOC) $(PANDOC_HTML_FLAGS) -o tmp-manual.html tmp-html-combined.md
	rm tmp-html-combined.md
	$(CHECKLINKS) tmp-manual.html $(MANUAL_LINKS)
	$(PANDOCPOST) $(PANDOC_VERSION) html tmp-manual.html
	mv tmp-manual.html $@

endif

EXTRA_DIST = \
	*.md \
	$(MANUALHTML_GENERATED) \
	$(MANUALPDF_GENERATED) \
	$(MANUALMAN_GENERATED) \
	$(MANUALMAN_GENERATED_INDIRECT)

CLEANFILES = \
       tmp-anchor-links \
       tmp-html-combined.md \
       tmp-manproc \
       tmp-manual.html \
       tmp-pdf-combined.md

DISTCLEANFILES =

MAINTAINERCLEANFILES = \
	service-links \
	$(MANUALHTML_GENERATED) \
	$(MANUALPDF_GENERATED) \
	$(MANUALMAN_GENERATED) \
	$(MANUALMAN_GENERATED_INDIRECT)


if MAINTAINER_MODE

DISTCLEANFILES += $(MAINTAINERCLEANFILES)

endif


uninstall-local:
	@-rmdir --ignore-fail-on-non-empty $(DESTDIR)$(dochtmldir)
	@-rmdir --ignore-fail-on-non-empty $(DESTDIR)$(pdfdir)
