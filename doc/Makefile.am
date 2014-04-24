# Process this file with automake to produce Makefile.in

DIST_SUBDIRS = tools

dochtmldir = $(htmldir)/html

FIREHOLMANUALHTML_GENERATED = \
	firehol-manual.html

FIREHOLMANUALPDF_GENERATED = \
	firehol-manual.pdf

FIREHOLMANUAL_LINKS = \
	service-links \
	links-internal \
	links-keywords-firehol \
	links-keywords-fireqos

FIREHOLMANUAL_CSS = \
	firehol-manual.css

# Generate using:
# (echo firehol-services.5.md; ls fire*.md) | sed -ne 's;\(.*\).\([0-9]\).md;\tman/man\2/\1.\2 \\;p' |sort -u
FIREHOLMANUALMAN_GENERATED = \
	man/man1/firehol.1 \
	man/man1/fireqos.1 \
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
	man/man5/firehol-version.5 \
	man/man5/fireqos-class.5 \
	man/man5/fireqos-conf.5 \
	man/man5/fireqos-interface.5 \
	man/man5/fireqos-match.5 \
	man/man5/fireqos-params.5 \
	man/man5/fireqos-params-class.5 \
	man/man5/fireqos-params-match.5

# Generate using:
# sed -ne 's;extra-manpage: \(.*\)\([0-9]\);\tman/man\2/\1\2 \\;p' *.md|sort -u
FIREHOLMANUALMAN_GENERATED_INDIRECT = \
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
	man/man5/firehol-uid.5 \
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

FIREHOLMANUALMARKDOWN_GENERATED = \
	firehol-services.5.md

dochtml_DATA = \
	$(FIREHOLMANUAL_CSS) \
	$(FIREHOLMANUALHTML_GENERATED)

pdf_DATA = \
	$(FIREHOLMANUALPDF_GENERATED)

man_MANS = \
	$(FIREHOLMANUALMAN_GENERATED) \
	$(FIREHOLMANUALMAN_GENERATED_INDIRECT)

if MAINTAINER_MODE

MKSERVICELINKS = ${top_srcdir}/doc/tools/mkservicelinks
MKSERVICEMAN = ${top_srcdir}/doc/tools/mkserviceman
MANSYNOS = ${top_srcdir}/doc/tools/man-synos
COMBINEPANDOC = ${top_srcdir}/doc/tools/combine-pandoc
CHECKLINKS = ${top_srcdir}/doc/tools/check-links

FIREHOLIN = $(top_srcdir)/sbin/firehol.in

firehol-services.5.md: ../sbin/firehol.in services-db.data service-links
	$(MKSERVICEMAN) firehol-services.5.md $+

service-links: ../sbin/firehol.in services-db.data
	$(MKSERVICELINKS) service-links $+

man/man1/%.1: %.1.md
	$(MKDIR_P) tmp
	$(MKDIR_P) man/man1
	$(SED) -e '/^%/s/DATE/@PACKAGE_BUILT_DATE@/' -e '/^%/s/VERSION/@PACKAGE_VERSION@/' $< > tmp/manproc
	$(SED) -e 's/: .*#/: #/' $(FIREHOLMANUAL_LINKS) > tmp/anchor-links
	pandoc $(PANDOC_MAN_FLAGS) -o $@ tmp/manproc tmp/anchor-links
# Disable groff hyphenation (wrecks URLs) and supress any internal links,
# since pandoc 1.9.4.2 just leaves them verbatim in manpage output.
	$(SED) -i -e '1a.nh' -e 's/ (#[a-z.0-9_-]*)//g' $@
	$(MANSYNOS) $< $@ man/

man/man5/%.5: %.5.md
	$(MKDIR_P) tmp
	$(MKDIR_P) man/man5
	$(SED) -e '/^%/s/DATE/@PACKAGE_BUILT_DATE@/' -e '/^%/s/VERSION/@PACKAGE_VERSION@/' $< > tmp/manproc
	$(SED) -e 's/: .*#/: #/' $(FIREHOLMANUAL_LINKS) > tmp/anchor-links
	pandoc $(PANDOC_MAN_FLAGS) -o $@ tmp/manproc tmp/anchor-links
# Disable groff hyphenation (wrecks URLs) and supress any internal links,
# since pandoc 1.9.4.2 just leaves them verbatim in manpage output.
	$(SED) -i -e '1a.nh' -e 's/ (#[a-z.0-9_-]*)//g' $@
	$(MANSYNOS) $< $@ man/

$(FIREHOLMANUALMAN_GENERATED): $(FIREHOLMANUAL_LINKS)

firehol-manual.pdf: *.md $(FIREHOLMANUALMARKDOWN_GENERATED) $(FIREHOLMANUAL_LINKS)
	$(MKDIR_P) tmp
	$(SED) -e 's/: .*#/: #/' $(FIREHOLMANUAL_LINKS) > tmp/anchor-links
	$(COMBINEPANDOC) pdf tmp/pdf-combined.md contents.md tmp/anchor-links
	$(SED) -i -e '/^%/s/DATE/@PACKAGE_BUILT_DATE@/' -e '/^%/s/VERSION/@PACKAGE_VERSION@/' tmp/pdf-combined.md
	$(PANDOC) $(PANDOC_PDF_FLAGS) -o $@ tmp/pdf-combined.md

firehol-manual.html: *.md $(FIREHOLMANUALMARKDOWN_GENERATED) $(FIREHOLMANUAL_LINKS)
	$(MKDIR_P) tmp
	$(SED) -e 's/: .*#/: #/' $(FIREHOLMANUAL_LINKS) > tmp/anchor-links
	$(COMBINEPANDOC) html tmp/html-combined.md contents.md tmp/anchor-links
	$(SED) -i -e '/^%/s/DATE/@PACKAGE_BUILT_DATE@/' -e '/^%/s/VERSION/@PACKAGE_VERSION@/' tmp/html-combined.md
	$(PANDOC) $(PANDOC_HTML_FLAGS) -o tmp/unform.html tmp/html-combined.md
	$(XMLLINT) $(XMLLINT_FLAGS) --format tmp/unform.html > tmp/format.html
	$(CHECKLINKS) tmp/format.html $(FIREHOLMANUAL_LINKS)
# Remove manpage internal sections from HTML
	$(SED) -e '/^                  <ul>/,/^                  <\/ul>/d' tmp/format.html > $@

endif

EXTRA_DIST = \
	*.md \
	services-db.data \
	$(FIREHOLMANUAL_LINKS) \
	$(FIREHOLMANUAL_CSS) \
	$(FIREHOLMANUALHTML_GENERATED) \
	$(FIREHOLMANUALPDF_GENERATED) \
	$(FIREHOLMANUALMAN_GENERATED) \
	$(FIREHOLMANUALMAN_GENERATED_INDIRECT)

CLEANFILES =

DISTCLEANFILES =

MAINTAINERCLEANFILES = \
	services-links \
	$(FIREHOLMANUALMARKDOWN_GENERATED) \
	$(FIREHOLMANUALHTML_GENERATED) \
	$(FIREHOLMANUALPDF_GENERATED) \
	$(FIREHOLMANUALMAN_GENERATED) \
	$(FIREHOLMANUALMAN_GENERATED_INDIRECT)

uninstall-local:
	@-rmdir --ignore-fail-on-non-empty $(DESTDIR)$(dochtmldir)
	@-rmdir --ignore-fail-on-non-empty $(DESTDIR)$(pdfdir)
