# Process this file with automake to produce Makefile.in

examplesdir = $(docdir)/examples

conffiles =

if ENABLE_FIREHOL

examples_SCRIPTS = \
	adblock.sh

conffiles += \
	server-dmz.conf \
	client-all.conf \
	lan-gateway.conf \
	office.conf \
	icmpv6.conf

endif

if ENABLE_FIREQOS

conffiles += \
	fireqos.conf \
	fireqos-multiple-organizations.conf

endif

if ENABLE_VNETBUILD

conffiles += \
	vnetbuild.conf \
	vnetbuild-simple.conf

endif

examples_DATA = $(conffiles)

EXTRA_DIST = \
	$(examples_DATA) \
	$(examples_SCRIPTS)

uninstall-local:
	@-rmdir --ignore-fail-on-non-empty $(DESTDIR)$(examplesdir)
