# Process this file with automake to produce Makefile.in

MANUAL_LINKS = \
	${top_srcdir}/doc/links-internal-fireqos \
	${top_srcdir}/doc/links-keywords-fireqos \
	${top_srcdir}/doc/links-website-fireqos

dochtmldir = $(htmldir)/html

MANUALHTML_GENERATED = \
	fireqos-manual.html

MANUALPDF_GENERATED = \
	fireqos-manual.pdf

# Generate using:
# (ls fire*.md) | sed -ne 's;\(.*\).\([0-9]\).md;\tman/man\2/\1.\2 \\;p' |sort -u
MANUALMAN_GENERATED = \
	man/man1/fireqos.1 \
	man/man5/fireqos-class.5 \
	man/man5/fireqos-conf.5 \
	man/man5/fireqos-interface.5 \
	man/man5/fireqos-match.5 \
	man/man5/fireqos-params.5 \
	man/man5/fireqos-params-class.5 \
	man/man5/fireqos-params-match.5

# Generate using:
# sed -ne 's;extra-manpage: \(.*\)\([0-9]\);\tman/man\2/\1\2 \\;p' *.md|sort -u
MANUALMAN_GENERATED_INDIRECT = \
	man/man5/fireqos-ack.5 \
	man/man5/fireqos-acks.5 \
	man/man5/fireqos-adsl.5 \
	man/man5/fireqos-at.5 \
	man/man5/fireqos-atm.5 \
	man/man5/fireqos-balanced.5 \
	man/man5/fireqos-bfifo.5 \
	man/man5/fireqos-burst.5 \
	man/man5/fireqos-cburst.5 \
	man/man5/fireqos-ceil.5 \
	man/man5/fireqos-class4.5 \
	man/man5/fireqos-class46.5 \
	man/man5/fireqos-class6.5 \
	man/man5/fireqos-class-params.5 \
	man/man5/fireqos-codel.5 \
	man/man5/fireqos-commit.5 \
	man/man5/fireqos.conf.5 \
	man/man5/fireqos-dport.5 \
	man/man5/fireqos-dports.5 \
	man/man5/fireqos-dst.5 \
	man/man5/fireqos-ethernet.5 \
	man/man5/fireqos-fq_codel.5 \
	man/man5/fireqos-gre.5 \
	man/man5/fireqos-host.5 \
	man/man5/fireqos-icmp.5 \
	man/man5/fireqos-interface4.5 \
	man/man5/fireqos-interface46.5 \
	man/man5/fireqos-interface6.5 \
	man/man5/fireqos-ip.5 \
	man/man5/fireqos-ipv6.5 \
	man/man5/fireqos-linklayer.5 \
	man/man5/fireqos-mark.5 \
	man/man5/fireqos-match4.5 \
	man/man5/fireqos-match46.5 \
	man/man5/fireqos-match6.5 \
	man/man5/fireqos-match-params.5 \
	man/man5/fireqos-max.5 \
	man/man5/fireqos-min.5 \
	man/man5/fireqos-minrate.5 \
	man/man5/fireqos-mpu.5 \
	man/man5/fireqos-mtu.5 \
	man/man5/fireqos-net.5 \
	man/man5/fireqos-none.5 \
	man/man5/fireqos-overhead.5 \
	man/man5/fireqos-pfifo.5 \
	man/man5/fireqos-port.5 \
	man/man5/fireqos-ports.5 \
	man/man5/fireqos-prio.5 \
	man/man5/fireqos-priority.5 \
	man/man5/fireqos-proto.5 \
	man/man5/fireqos-protocol.5 \
	man/man5/fireqos-qdisc.5 \
	man/man5/fireqos-quantum.5 \
	man/man5/fireqos-r2q.5 \
	man/man5/fireqos-rate.5 \
	man/man5/fireqos-sfq.5 \
	man/man5/fireqos-sport.5 \
	man/man5/fireqos-sports.5 \
	man/man5/fireqos-src.5 \
	man/man5/fireqos-syn.5 \
	man/man5/fireqos-syns.5 \
	man/man5/fireqos-tcp.5 \
	man/man5/fireqos-tos.5 \
	man/man5/fireqos-tsize.5 \
	man/man5/fireqos-udp.5

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

fireqos-manual.pdf: *.md $(MANUAL_LINKS)
	$(SED) -e 's/: .*#/: #/' $(MANUAL_LINKS) > tmp-anchor-links
	$(COMBINEPANDOC) pdf tmp-pdf-combined.md contents.md tmp-anchor-links
	$(SED) -i -e '/^%/s/DATE/@PACKAGE_BUILT_DATE@/' -e '/^%/s/VERSION/@PACKAGE_VERSION@/' tmp-pdf-combined.md
	$(PANDOC) $(PANDOC_PDF_FLAGS) -o $@ tmp-pdf-combined.md
	rm tmp-pdf-combined.md
	$(PANDOCPOST) $(PANDOC_VERSION) pdf $@

fireqos-manual.html: *.md $(MANUAL_LINKS)
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
