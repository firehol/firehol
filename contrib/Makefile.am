# Process this file with automake to produce Makefile.in

contribdir = $(docdir)/contrib

contrib_SCRIPTS = \
	dnsbl-ipset.sh \
	ipv4_range_to_cidr.awk \
	update-ipsets.sh

contrib_DATA = \
	contrib.mak \
	iprange.md

EXTRA_DIST = \
	$(contrib_DATA) \
	$(contrib_SCRIPTS)

uninstall-local:
	@-rmdir --ignore-fail-on-non-empty $(DESTDIR)$(contribdir)
