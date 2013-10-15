# Process this file with automake to produce Makefile.in

DIST_SUBDIRS = xsl latex tools reference man

dochtmldir = $(htmldir)/html

FIREHOLMANUALXML_CSS = \
	firehol-manual.css

FIREHOLMANUALXML_MASTER = \
	firehol-manual.xml

FIREHOLMANUALXML_CHAPTERS= \
	chapter-intro.xml \
	chapter-language.xml \
	chapter-security.xml \
	chapter-troubleshooting.xml

FIREHOLMANUALXML_REFERENCES = \
	reference/firehol.xml \
	reference/firehol-conf.xml \
	reference/firehol-variables.xml \
	reference/def-interface.xml \
	reference/def-router.xml \
	reference/cmd-policy.xml \
	reference/cmd-protection.xml \
	reference/cmd-server.xml \
	reference/cmd-client.xml \
	reference/cmd-group.xml \
	reference/helpconf-version.xml \
	reference/helpconf-action.xml \
	reference/helpconf-blacklist.xml \
	reference/helpconf-classify.xml \
	reference/helpconf-connmark.xml \
	reference/helpconf-dscp.xml \
	reference/helpconf-mac.xml \
	reference/helpconf-mark.xml \
	reference/helpconf-nat.xml \
	reference/helpconf-proxy.xml \
	reference/helpconf-tos.xml \
	reference/helpconf-tosfix.xml \
	reference/helpcmd-iptables.xml \
	reference/helpcmd-masquerade.xml \
	reference/helpcmd-tcpmss.xml \
	reference/rule-params.xml \
	reference/actions.xml \
	reference/services.xml

FIREHOLMANUALXML_GENERATED = \
	services-list.xml

FIREHOLMANUALMAN_GENERATED = \
	man/man1/firehol.1 \
	man/man5/firehol-accept.5 \
	man/man5/firehol-action.5 \
	man/man5/firehol-actions.5 \
	man/man5/firehol-blacklist.5 \
	man/man5/firehol-classify.5 \
	man/man5/firehol-client.5 \
	man/man5/firehol.conf.5 \
	man/man5/firehol-connmark.5 \
	man/man5/firehol-custom.5 \
	man/man5/firehol-deny.5 \
	man/man5/firehol-dnat.5 \
	man/man5/firehol-drop.5 \
	man/man5/firehol-dscp.5 \
	man/man5/firehol-dscp-param.5 \
	man/man5/firehol-dst.5 \
	man/man5/firehol-dsttype.5 \
	man/man5/firehol-gid.5 \
	man/man5/firehol-group.5 \
	man/man5/firehol-inface.5 \
	man/man5/firehol-interface.5 \
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
	man/man5/firehol-route.5 \
	man/man5/firehol-router.5 \
	man/man5/firehol-rule-params.5 \
	man/man5/firehol-server.5 \
	man/man5/firehol-services.5 \
	man/man5/firehol-snat.5 \
	man/man5/firehol-src.5 \
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
	man/man5/firehol-version.5

FIREHOLMANUALHTML_GENERATED = \
	firehol-services.html \
	firehol-manual.html

FIREHOLMANUALPDF_GENERATED = \
	firehol-manual.pdf

export FIREHOLMANUALXML_MASTER

man_MANS = \
	$(FIREHOLMANUALMAN_GENERATED)

dochtml_DATA = \
	$(FIREHOLMANUALXML_CSS) \
	$(FIREHOLMANUALHTML_GENERATED)

pdf_DATA = \
	$(FIREHOLMANUALPDF_GENERATED)

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

services-list.xml: $(FIREHOLIN) services-db.data
	$(MKSERVICELIST) $@ $+

firehol-services.html:
	$(MKHTMLINDEX) $@ $(FIREHOLIN)

db-valid: \
		$(FIREHOLMANUALXML_MASTER) \
		$(FIREHOLMANUALXML_CHAPTERS) \
		$(FIREHOLMANUALXML_REFERENCES) \
		$(FIREHOLMANUALXML_GENERATED) \
		firehol.ent
	$(XMLLINT) $(XMLLINT_FLAGS) --noout --postvalid $<
	touch db-valid

$(FIREHOLMANUALMAN_GENERATED): db-valid xsl/manpages.xsl
	$(MAKE) -C man manpages

firehol-manual.html: db-valid xsl/html.xsl $(FIREHOLMANUALXML_CSS)
	$(XSLTPROC) $(XSLTPROC_FLAGS) -o $@ html.xsl $(FIREHOLMANUALXML_MASTER)

firehol-manual.pdf: db-valid xsl/dblatex.xsl latex/dbfirehol.sty
	$(DBLATEX) $(DBLATEX_FLAGS) \
			-t pdf \
			-P paper.type=$(PAPERTYPE) \
			-p xsl/dblatex.xsl \
			-s latex/dbfirehol.sty \
			-o $@ \
		$(FIREHOLMANUALXML_MASTER)

endif

EXTRA_DIST = \
	services-db.data \
	firehol.ent \
	$(FIREHOLMANUALXML_GENERATED) \
	db-valid \
	$(FIREHOLMANUALXML_CSS) \
	$(FIREHOLMANUALXML_CHAPTERS) \
	$(FIREHOLMANUALXML_MASTER) \
	$(FIREHOLMANUALMAN_GENERATED) \
	$(FIREHOLMANUALHTML_GENERATED) \
	$(FIREHOLMANUALPDF_GENERATED)

CLEANFILES =

DISTCLEANFILES =

MAINTAINERCLEANFILES = \
	firehol.ent \
	$(FIREHOLMANUALXML_GENERATED) \
	db-valid \
	$(FIREHOLMANUALMAN_GENERATED) \
	$(FIREHOLMANUALHTML_GENERATED) \
	$(FIREHOLMANUALPDF_GENERATED)

uninstall-local:
	@-rmdir --ignore-fail-on-non-empty $(DESTDIR)$(dochtmldir)
	@-rmdir --ignore-fail-on-non-empty $(DESTDIR)$(pdfdir)
#	@-rmdir --ignore-fail-on-non-empty $(DESTDIR)$(docdir)

.NOTPARALLEL: $(FIREHOLMANUALMAN_GENERATED)
