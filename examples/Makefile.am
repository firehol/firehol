# Process this file with automake to produce Makefile.in

examplesdir = $(docdir)/examples

examples_SCRIPTS = \
	adblock.sh

examples_DATA = \
	server-dmz.conf \
	client-all.conf \
	lan-gateway.conf \
	office.conf

EXTRA_DIST = \
	$(examples_DATA) \
	$(examples_SCRIPTS)

uninstall-local:
	@-rmdir --ignore-fail-on-non-empty $(DESTDIR)$(examplesdir)
