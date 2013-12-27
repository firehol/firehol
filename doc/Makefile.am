# Process this file with automake to produce Makefile.in

DIST_SUBDIRS = xsl latex tools firehol-reference fireqos-reference

dochtmldir = $(htmldir)/html

FIREHOLMANUALXML_CSS=\
	firehol-manual.css

FIREHOLMANUALXML_MASTER=\
	firehol-manual.xml

FIREHOLMANUALXML_CHAPTERS=\
	chapter-intro.xml \
	firehol/appendix-rfc4890.xml \
	firehol/chapter-configuration.xml \
	firehol/chapter-security.xml \
	firehol/chapter-troubleshooting.xml \
	fireqos/chapter-configuration.xml

FIREHOLMANUALXML_REFERENCES=\
	firehol-reference/actions.xml \
	firehol-reference/cmd-client.xml \
	firehol-reference/cmd-group.xml \
	firehol-reference/cmd-policy.xml \
	firehol-reference/cmd-protection.xml \
	firehol-reference/cmd-server.xml \
	firehol-reference/def-interface.xml \
	firehol-reference/def-router.xml \
	firehol-reference/firehol-conf.xml \
	firehol-reference/firehol-variables.xml \
	firehol-reference/firehol.xml \
	firehol-reference/helpcmd-iptables.xml \
	firehol-reference/helpcmd-masquerade.xml \
	firehol-reference/helpcmd-tcpmss.xml \
	firehol-reference/helpconf-action.xml \
	firehol-reference/helpconf-blacklist.xml \
	firehol-reference/helpconf-classify.xml \
	firehol-reference/helpconf-connmark.xml \
	firehol-reference/helpconf-dscp.xml \
	firehol-reference/helpconf-mac.xml \
	firehol-reference/helpconf-mark.xml \
	firehol-reference/helpconf-nat.xml \
	firehol-reference/helpconf-proxy.xml \
	firehol-reference/helpconf-tosfix.xml \
	firehol-reference/helpconf-tos.xml \
	firehol-reference/helpconf-version.xml \
	firehol-reference/rule-params.xml \
	firehol-reference/services-a.xml \
	firehol-reference/services-b.xml \
	firehol-reference/services-c.xml \
	firehol-reference/services-d.xml \
	firehol-reference/services-e.xml \
	firehol-reference/services-f.xml \
	firehol-reference/services-g.xml \
	firehol-reference/services-h.xml \
	firehol-reference/services-i.xml \
	firehol-reference/services-j.xml \
	firehol-reference/services-k.xml \
	firehol-reference/services-l.xml \
	firehol-reference/services-m.xml \
	firehol-reference/services-n.xml \
	firehol-reference/services-o.xml \
	firehol-reference/services-p.xml \
	firehol-reference/services-q.xml \
	firehol-reference/services-r.xml \
	firehol-reference/services-s.xml \
	firehol-reference/services-t.xml \
	firehol-reference/services-u.xml \
	firehol-reference/services-v.xml \
	firehol-reference/services-w.xml \
	firehol-reference/services.xml \
	firehol-reference/services-x.xml \
	firehol-reference/services-y.xml \
	firehol-reference/services-z.xml \
	fireqos-reference/fireqos-conf.xml \
	fireqos-reference/fireqos.xml

FIREHOLMANUALXML_GENERATED = \
	services-a.xml \
	services-b.xml \
	services-c.xml \
	services-d.xml \
	services-e.xml \
	services-f.xml \
	services-g.xml \
	services-h.xml \
	services-i.xml \
	services-j.xml \
	services-k.xml \
	services-l.xml \
	services-m.xml \
	services-n.xml \
	services-o.xml \
	services-p.xml \
	services-q.xml \
	services-r.xml \
	services-s.xml \
	services-t.xml \
	services-u.xml \
	services-v.xml \
	services-w.xml \
	services-x.xml \
	services-y.xml \
	services-z.xml

FIREHOLMANUALMAN_GENERATED=\
	man/man1/firehol.1 \
	man/man1/fireqos.1 \
	man/man5/firehol-accept.5 \
	man/man5/firehol-action.5 \
	man/man5/firehol-actions.5 \
	man/man5/firehol-blacklist.5 \
	man/man5/firehol-classify.5 \
	man/man5/firehol-client4.5 \
	man/man5/firehol-client46.5 \
	man/man5/firehol-client.5 \
	man/man5/firehol-client6.5 \
	man/man5/firehol.conf.5 \
	man/man5/firehol-connmark.5 \
	man/man5/firehol-custom.5 \
	man/man5/firehol-deny.5 \
	man/man5/firehol-dnat.5 \
	man/man5/firehol-drop.5 \
	man/man5/firehol-dscp.5 \
	man/man5/firehol-dscp-param.5 \
	man/man5/firehol-dst4.5 \
	man/man5/firehol-dst.5 \
	man/man5/firehol-dst6.5 \
	man/man5/firehol-dsttype.5 \
	man/man5/firehol-gid.5 \
	man/man5/firehol-group.5 \
	man/man5/firehol-inface.5 \
	man/man5/firehol-interface4.5 \
	man/man5/firehol-interface46.5 \
	man/man5/firehol-interface.5 \
	man/man5/firehol-interface6.5 \
	man/man5/firehol-iptables.5 \
	man/man5/firehol-log.5 \
	man/man5/firehol-loglimit.5 \
	man/man5/firehol-mac.5 \
	man/man5/firehol-mac-param.5 \
	man/man5/firehol-mark.5 \
	man/man5/firehol-mark-param.5 \
	man/man5/firehol-masquerade.5 \
	man/man5/firehol-nat.5 \
	man/man5/firehol-outface.5 \
	man/man5/firehol-physin.5 \
	man/man5/firehol-physout.5 \
	man/man5/firehol-policy.5 \
	man/man5/firehol-protection.5 \
	man/man5/firehol-proto.5 \
	man/man5/firehol-redirect.5 \
	man/man5/firehol-reject.5 \
	man/man5/firehol-return.5 \
	man/man5/firehol-route4.5 \
	man/man5/firehol-route46.5 \
	man/man5/firehol-route.5 \
	man/man5/firehol-route6.5 \
	man/man5/firehol-router4.5 \
	man/man5/firehol-router46.5 \
	man/man5/firehol-router.5 \
	man/man5/firehol-router6.5 \
	man/man5/firehol-rule-params.5 \
	man/man5/firehol-server4.5 \
	man/man5/firehol-server46.5 \
	man/man5/firehol-server.5 \
	man/man5/firehol-server6.5 \
	man/man5/firehol-services.5 \
	man/man5/firehol-services-a.5 \
	man/man5/firehol-services-b.5 \
	man/man5/firehol-services-c.5 \
	man/man5/firehol-services-d.5 \
	man/man5/firehol-services-e.5 \
	man/man5/firehol-services-f.5 \
	man/man5/firehol-services-g.5 \
	man/man5/firehol-services-h.5 \
	man/man5/firehol-services-i.5 \
	man/man5/firehol-services-j.5 \
	man/man5/firehol-services-k.5 \
	man/man5/firehol-services-l.5 \
	man/man5/firehol-services-m.5 \
	man/man5/firehol-services-n.5 \
	man/man5/firehol-services-o.5 \
	man/man5/firehol-services-p.5 \
	man/man5/firehol-services-q.5 \
	man/man5/firehol-services-r.5 \
	man/man5/firehol-services-s.5 \
	man/man5/firehol-services-t.5 \
	man/man5/firehol-services-u.5 \
	man/man5/firehol-services-v.5 \
	man/man5/firehol-services-w.5 \
	man/man5/firehol-services-x.5 \
	man/man5/firehol-services-y.5 \
	man/man5/firehol-services-z.5 \
	man/man5/firehol-snat.5 \
	man/man5/firehol-src4.5 \
	man/man5/firehol-src.5 \
	man/man5/firehol-src5.5 \
	man/man5/firehol-srctype.5 \
	man/man5/firehol-tarpit.5 \
	man/man5/firehol-tcpmss.5 \
	man/man5/firehol-tos.5 \
	man/man5/firehol-tosfix.5 \
	man/man5/firehol-tos-param.5 \
	man/man5/firehol-transparent_proxy.5 \
	man/man5/firehol-transparent_squid.5 \
	man/man5/firehol-uid.5 \
	man/man5/firehol-variables.5 \
	man/man5/firehol-version.5 \
	man/man5/fireqos.conf.5

FIREHOLMANUALHTML_GENERATED = \
	firehol-manual.html \
	firehol-services.html

FIREHOLMANUALPDF_GENERATED = \
	firehol-manual.pdf

export FIREHOLMANUALXML_MASTER

dochtml_DATA = \
	$(FIREHOLMANUALXML_CSS) \
	$(FIREHOLMANUALHTML_GENERATED)

pdf_DATA = \
	$(FIREHOLMANUALPDF_GENERATED)

man_MANS = \
	$(FIREHOLMANUALMAN_GENERATED)

if MAINTAINER_MODE

PAPERTYPE = a4paper

MKSERVICELIST = ${top_srcdir}/doc/tools/mkservicelist
MKHTMLINDEX = ${top_srcdir}/doc/tools/mkhtmlindex

FIREHOLIN = $(top_srcdir)/sbin/firehol.in

XMLLINT_FLAGS += \
	--path ${abs_top_builddir}/doc:${abs_top_srcdir}/doc \
	--xinclude

XSLTPROC_FLAGS += \
	--path ${abs_top_builddir}/doc:${abs_top_srcdir}/doc:${abs_top_srcdir}/doc/xsl \
	--xinclude

##DBLATEX_FLAGS += \
##	--xslt=xsltproc \
##	--xslt-opts "--path ${abs_top_builddir}/doc:${abs_top_srcdir}/doc:${abs_top_srcdir}/doc/xsl"

export manpages_XSLTPROC_FLAGS = \
	$(XSLTPROC_FLAGS) \
	--param man.output.base.dir man

$(FIREHOLMANUALXML_GENERATED): services-generated

services-generated: $(FIREHOLIN) services-db.data
	$(MKSERVICELIST) services-a.xml $+
	touch services-generated

# Create index for services in the chunked HTML
html/index-services.html: html/index.html
	$(MKHTMLINDEX) $@ $(FIREHOLIN) html/rn*.html

# Create index for services in the single-page HTML
firehol-services.html: firehol-manual.html
	$(MKHTMLINDEX) $@ $(FIREHOLIN) firehol-manual.html

db-valid: \
		$(FIREHOLMANUALXML_MASTER) \
		$(FIREHOLMANUALXML_CHAPTERS) \
		$(FIREHOLMANUALXML_REFERENCES) \
		$(FIREHOLMANUALXML_GENERATED) \
		firehol.ent
	$(XMLLINT) $(XMLLINT_FLAGS) --noout --postvalid $<
	touch db-valid

# Create a chunked version for the website
html/index.html: db-valid xsl/chunk.xsl $(FIREHOLMANUALXML_CSS)
	mkdir -p html
	(cd html && $(XSLTPROC) $(XSLTPROC_FLAGS) chunk.xsl $(FIREHOLMANUALXML_MASTER))
	cp $(FIREHOLMANUALXML_CSS) html/.

# Create a single-page version to be included in tar
firehol-manual.html: db-valid xsl/html.xsl $(FIREHOLMANUALXML_CSS) html/index.html
	$(XSLTPROC) $(XSLTPROC_FLAGS) -o $@ html.xsl $(FIREHOLMANUALXML_MASTER)

firehol-manual.pdf: db-valid xsl/dblatex.xsl latex/dbfirehol.sty firehol-services.html html/index-services.html
	$(DBLATEX) $(DBLATEX_FLAGS) \
			-t pdf \
			-P paper.type=$(PAPERTYPE) \
			-p xsl/dblatex.xsl \
			-s latex/dbfirehol.sty \
			-o $@ \
		$(FIREHOLMANUALXML_MASTER)

$(FIREHOLMANUALMAN_GENERATED): db-valid xsl/manpages.xsl firehol-manual.pdf
	mkdir -p man
	(cd man && $(XSLTPROC) $(manpages_XSLTPROC_FLAGS) manpages.xsl $(FIREHOLMANUALXML_MASTER))

endif

EXTRA_DIST = \
	services-db.data \
	firehol.ent \
	$(FIREHOLMANUALXML_GENERATED) \
	db-valid \
	$(FIREHOLMANUALXML_CSS) \
	$(FIREHOLMANUALXML_MASTER) \
	$(FIREHOLMANUALHTML_GENERATED) \
	$(FIREHOLMANUALPDF_GENERATED) \
	$(FIREHOLMANUALMAN_GENERATED)

CLEANFILES =

DISTCLEANFILES =

MAINTAINERCLEANFILES = \
	firehol.ent \
	$(FIREHOLMANUALXML_GENERATED) \
	db-valid \
	services-generated \
	$(FIREHOLMANUALHTML_GENERATED) \
	$(FIREHOLMANUALPDF_GENERATED) \
	$(FIREHOLMANUALMAN_GENERATED)

uninstall-local:
	@-rmdir --ignore-fail-on-non-empty $(DESTDIR)$(dochtmldir)
	@-rmdir --ignore-fail-on-non-empty $(DESTDIR)$(pdfdir)
#	@-rmdir --ignore-fail-on-non-empty $(DESTDIR)$(docdir)

.NOTPARALLEL: $(FIREHOLMANUALMAN_GENERATED)
