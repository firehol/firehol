# Process this file with automake to produce Makefile.in

contribdir = $(docdir)/contrib

contrib_SCRIPTS = \
	dnsbl-ipset.sh

contrib_DATA = \
	firehol.service \
	fireqos.service

EXTRA_DIST = \
	$(contrib_SCRIPTS) \
	$(contrib_DATA)

uninstall-local:
	@-rmdir --ignore-fail-on-non-empty $(DESTDIR)$(contribdir)
