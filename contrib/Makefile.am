# Process this file with automake to produce Makefile.in

contribdir = $(docdir)/contrib

contrib_SCRIPTS = \
	dnsbl-ipset.sh

EXTRA_DIST = \
	$(contrib_SCRIPTS)

uninstall-local:
	@-rmdir --ignore-fail-on-non-empty $(DESTDIR)$(contribdir)
