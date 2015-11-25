# Process this file with automake to produce Makefile.in

ipsetsdir = $(datarootdir)/update-ipsets
ipsetswebdir = $(ipsetsdir)/webdir

if ENABLE_UPDATE_IPSETS

ipsetsweb_DATA = \
	bogons.html \
	botscout.html \
	cta_cryptowall.html \
	dshield.html \
	firehol_level1.html \
	fullbogons.html \
	index.html \
	packetmail.html \
	spamhaus_drop.html \
	spamhaus_edrop.html \
	typeahead.css

endif

EXTRA_DIST = \
	$(ipsetsweb_DATA)

uninstall-local:
	@-rmdir --ignore-fail-on-non-empty $(DESTDIR)$(ipsetswebdir)
	@-rmdir --ignore-fail-on-non-empty $(DESTDIR)$(ipsetsdir)
