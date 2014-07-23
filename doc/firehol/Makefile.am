# Process this file with automake to produce Makefile.in

MANUAL_LINKS = \
	${top_srcdir}/doc/service-links \
	${top_srcdir}/doc/links-internal-firehol \
	${top_srcdir}/doc/links-keywords-firehol \
	${top_srcdir}/doc/links-website-firehol

dochtmldir = $(htmldir)/html

MANUALHTML_GENERATED = \
	firehol-manual.html

MANUALPDF_GENERATED = \
	firehol-manual.pdf

# Generate using:
# (echo firehol-services.5.md; ls fire*.md) | sed -ne 's;\(.*\).\([0-9]\).md;\tman/man\2/\1.\2 \\;p' |sort -u
MANUALMAN_GENERATED = \
	man/man1/firehol.1 \
	man/man5/firehol-action.5 \
	man/man5/firehol-actions.5 \
	man/man5/firehol-blacklist.5 \
	man/man5/firehol-classify.5 \
	man/man5/firehol-client.5 \
	man/man5/firehol-conf.5 \
	man/man5/firehol-connmark.5 \
	man/man5/firehol-dscp.5 \
	man/man5/firehol-group.5 \
	man/man5/firehol-interface.5 \
	man/man5/firehol-iptables.5 \
	man/man5/firehol-mac.5 \
	man/man5/firehol-mark.5 \
	man/man5/firehol-masquerade.5 \
	man/man5/firehol-modifiers.5 \
	man/man5/firehol-nat.5 \
	man/man5/firehol-params.5 \
	man/man5/firehol-policy.5 \
	man/man5/firehol-protection.5 \
	man/man5/firehol-proxy.5 \
	man/man5/firehol-router.5 \
	man/man5/firehol-server.5 \
	man/man5/firehol-services.5 \
	man/man5/firehol-tcpmss.5 \
	man/man5/firehol-tos.5 \
	man/man5/firehol-tosfix.5 \
	man/man5/firehol-variables.5 \
	man/man5/firehol-version.5

# Generate using:
# sed -ne 's;extra-manpage: \(.*\)\([0-9]\);\tman/man\2/\1\2 \\;p' *.md|sort -u
MANUALMAN_GENERATED_INDIRECT = \
	man/man5/firehol-accept.5 \
	man/man5/firehol-client4.5 \
	man/man5/firehol-client46.5 \
	man/man5/firehol-client6.5 \
	man/man5/firehol.conf.5 \
	man/man5/firehol-custom.5 \
	man/man5/firehol-deny.5 \
	man/man5/firehol-dnat.5 \
	man/man5/firehol-dport.5 \
	man/man5/firehol-drop.5 \
	man/man5/firehol-dscp-param.5 \
	man/man5/firehol-dst4.5 \
	man/man5/firehol-dst.5 \
	man/man5/firehol-dst6.5 \
	man/man5/firehol-dsttype.5 \
	man/man5/firehol-gid.5 \
	man/man5/firehol-inface.5 \
	man/man5/firehol-interface4.5 \
	man/man5/firehol-interface46.5 \
	man/man5/firehol-interface6.5 \
	man/man5/firehol-ip6tables.5 \
	man/man5/firehol-ipv4.5 \
	man/man5/firehol-ipv6.5 \
	man/man5/firehol-log.5 \
	man/man5/firehol-loglimit.5 \
	man/man5/firehol-mac-param.5 \
	man/man5/firehol-mark-param.5 \
	man/man5/firehol-outface.5 \
	man/man5/firehol-physin.5 \
	man/man5/firehol-physout.5 \
	man/man5/firehol-proto.5 \
	man/man5/firehol-redirect.5 \
	man/man5/firehol-reject.5 \
	man/man5/firehol-return.5 \
	man/man5/firehol-route4.5 \
	man/man5/firehol-route46.5 \
	man/man5/firehol-route6.5 \
	man/man5/firehol-router4.5 \
	man/man5/firehol-router46.5 \
	man/man5/firehol-router6.5 \
	man/man5/firehol-server4.5 \
	man/man5/firehol-server46.5 \
	man/man5/firehol-server6.5 \
	man/man5/firehol-snat.5 \
	man/man5/firehol-sport.5 \
	man/man5/firehol-src4.5 \
	man/man5/firehol-src.5 \
	man/man5/firehol-src6.5 \
	man/man5/firehol-srctype.5 \
	man/man5/firehol-tarpit.5 \
	man/man5/firehol-tos-param.5 \
	man/man5/firehol-transparent_proxy.5 \
	man/man5/firehol-transparent_squid.5 \
	man/man5/firehol-uid.5

MANUALMARKDOWN_GENERATED = \
	firehol-services.5.md

dochtml_DATA = \
	$(MANUALHTML_GENERATED)

pdf_DATA = \
	$(MANUALPDF_GENERATED)

man_MANS = \
	$(MANUALMAN_GENERATED) \
	$(MANUALMAN_GENERATED_INDIRECT)

if MAINTAINER_MODE

MKSERVICELINKS = ${top_srcdir}/doc/tools/mkservicelinks
MKSERVICEMAN = ${top_srcdir}/doc/tools/mkserviceman
MANSYNOS = ${top_srcdir}/doc/tools/man-synos
COMBINEPANDOC = ${top_srcdir}/doc/tools/combine-pandoc
PANDOCPOST = ${top_srcdir}/doc/tools/pandoc-post
CHECKLINKS = ${top_srcdir}/doc/tools/check-links

FIREHOLIN = $(top_srcdir)/sbin/firehol.in

firehol-services.5.md: $(FIREHOLIN) ../services-db.data ../service-links
	$(MKSERVICEMAN) firehol-services.5.md $+

man/man1/%.1: %.1.md
	$(MKDIR_P) tmp
	$(MKDIR_P) man/man1
	$(SED) -e '/^%/s/DATE/@PACKAGE_BUILT_DATE@/' -e '/^%/s/VERSION/@PACKAGE_VERSION@/' $< > tmp/manproc
	$(SED) -e 's/: .*#/: #/' $(MANUAL_LINKS) > tmp/anchor-links
	$(PANDOC) $(PANDOC_MAN_FLAGS) -o $@ tmp/manproc tmp/anchor-links
	$(PANDOCPOST) $(PANDOC_VERSION) man $@
	$(MANSYNOS) $< $@ man/

man/man5/%.5: %.5.md
	$(MKDIR_P) tmp
	$(MKDIR_P) man/man5
	$(SED) -e '/^%/s/DATE/@PACKAGE_BUILT_DATE@/' -e '/^%/s/VERSION/@PACKAGE_VERSION@/' $< > tmp/manproc
	$(SED) -e 's/: .*#/: #/' $(MANUAL_LINKS) > tmp/anchor-links
	$(PANDOC) $(PANDOC_MAN_FLAGS) -o $@ tmp/manproc tmp/anchor-links
	$(PANDOCPOST) $(PANDOC_VERSION) man $@
	$(MANSYNOS) $< $@ man/

$(MANUALMAN_GENERATED): $(MANUAL_LINKS)

firehol-manual.pdf: *.md $(MANUALMARKDOWN_GENERATED) $(MANUAL_LINKS)
	$(MKDIR_P) tmp
	$(SED) -e 's/: .*#/: #/' $(MANUAL_LINKS) > tmp/anchor-links
	$(COMBINEPANDOC) pdf tmp/pdf-combined.md contents.md tmp/anchor-links
	$(SED) -i -e '/^%/s/DATE/@PACKAGE_BUILT_DATE@/' -e '/^%/s/VERSION/@PACKAGE_VERSION@/' tmp/pdf-combined.md
	$(PANDOC) $(PANDOC_PDF_FLAGS) -o $@ tmp/pdf-combined.md
	$(PANDOCPOST) $(PANDOC_VERSION) pdf $@

firehol-manual.html: *.md $(MANUALMARKDOWN_GENERATED) $(MANUAL_LINKS)
	$(MKDIR_P) tmp
	$(SED) -e 's/: .*#/: #/' $(MANUAL_LINKS) > tmp/anchor-links
	$(COMBINEPANDOC) html tmp/html-combined.md contents.md tmp/anchor-links
	$(SED) -i -e '/^%/s/DATE/@PACKAGE_BUILT_DATE@/' -e '/^%/s/VERSION/@PACKAGE_VERSION@/' tmp/html-combined.md
	$(PANDOC) $(PANDOC_HTML_FLAGS) -o tmp/manual.html tmp/html-combined.md
	$(CHECKLINKS) tmp/manual.html $(MANUAL_LINKS)
	$(PANDOCPOST) $(PANDOC_VERSION) html tmp/manual.html
	cp tmp/manual.html $@

endif

EXTRA_DIST = \
	*.md \
	$(MANUALHTML_GENERATED) \
	$(MANUALPDF_GENERATED) \
	$(MANUALMAN_GENERATED) \
	$(MANUALMAN_GENERATED_INDIRECT)

CLEANFILES =

DISTCLEANFILES =

MAINTAINERCLEANFILES = \
	service-links \
	$(MANUALMARKDOWN_GENERATED) \
	$(MANUALHTML_GENERATED) \
	$(MANUALPDF_GENERATED) \
	$(MANUALMAN_GENERATED) \
	$(MANUALMAN_GENERATED_INDIRECT)

uninstall-local:
	@-rmdir --ignore-fail-on-non-empty $(DESTDIR)$(dochtmldir)
	@-rmdir --ignore-fail-on-non-empty $(DESTDIR)$(pdfdir)
