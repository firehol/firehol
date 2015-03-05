# Process this file with automake to produce Makefile.in

SUBDIRS = . firehol fireqos

all-local: service-links

dochtmldir = $(htmldir)/html

MANUAL_LINKS = \
	links-internal-firehol \
	links-internal-fireqos \
	links-keywords-firehol \
	links-keywords-fireqos \
	links-website-firehol \
	links-website-fireqos

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
	tools/servicedb.pm

dochtml_DATA = \
	$(MANUAL_CSS)

if MAINTAINER_MODE

MKSERVICELINKS = ${top_srcdir}/doc/tools/mkservicelinks

FIREHOLIN = $(top_srcdir)/sbin/firehol.in

service-links: $(FIREHOLIN) services-db.data
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
