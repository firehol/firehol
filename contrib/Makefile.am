# Process this file with automake to produce Makefile.in

contribdir = $(docdir)/contrib

servicefiles =

if ENABLE_FIREHOL

contrib_SCRIPTS = \
	dnsbl-ipset.sh

servicefiles += firehol.service

endif

if ENABLE_FIREQOS
servicefiles += fireqos.service
endif

contrib_DATA = README $(servicefiles)

EXTRA_DIST = \
	$(contrib_SCRIPTS) \
	$(contrib_DATA)

uninstall-local:
	@-rmdir --ignore-fail-on-non-empty $(DESTDIR)$(contribdir)
