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
	ipsum.html \
	ipsum_2.html \
	ipsum_3.html \
	ipsum_4.html \
	ipsum_5.html \
	ipsum_6.html \
	ipsum_7.html \
	ipsum_8.html \
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
