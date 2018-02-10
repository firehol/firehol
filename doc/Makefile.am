# Process this file with automake to produce Makefile.in

SUBDIRS = . firehol fireqos vnetbuild

dochtmldir = $(htmldir)/html

MANUAL_LINKS = \
	links-internal-firehol \
	links-internal-fireqos \
	links-internal-vnetbuild \
	links-keywords-firehol \
	links-keywords-fireqos \
	links-keywords-vnetbuild \
	links-website-firehol \
	links-website-fireqos  \
	links-website-vnetbuild

if ENABLE_DOC

MANUAL_CSS = \
        firehol-manual.css

endif

MANUAL_TOOLS = \
	tools/check-links \
	tools/combine-pandoc \
	tools/man-synos \
	tools/mkservicelinks \
	tools/mkserviceman \
	tools/pandoc-post \
	tools/servicedb.pm \
	tools/format-table \
	tools/run-linkchecker

dochtml_DATA = \
	$(MANUAL_CSS)

if MAINTAINER_MODE

all-local: service-links

MKSERVICELINKS = ${top_srcdir}/doc/tools/mkservicelinks

service-links: services-db.data $(top_srcdir)/sbin/firehol \
		$(top_srcdir)/sbin/services.common \
		$(top_srcdir)/sbin/services.firehol
	$(MKSERVICELINKS) service-links $+

endif

EXTRA_DIST = \
	README.md \
	service-links \
	services-db.data \
	$(MANUAL_CSS) \
	$(MANUAL_LINKS) \
	$(MANUAL_TOOLS)

CLEANFILES =

DISTCLEANFILES =

MAINTAINERCLEANFILES = \
	service-links
