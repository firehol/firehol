# Process this file with automake to produce Makefile.in

ipsetsdir = $(datarootdir)/update-ipsets
ipsetswebdir = $(ipsetsdir)/webdir

if ENABLE_UPDATE_IPSETS

ipsetsweb_DATA = \
	abuseipdb_1d.html \
	abuseipdb_30d.html \
	bds_atif.html \
	bogons.html \
	botscout.html \
	c2_tracker.html \
	cta_cryptowall.html \
	cybercure.html \
	dshield.html \
	firehol_level1.html \
	firehol_level2.html \
	firehol_level3.html \
	firehol_level4.html \
	fullbogons.html \
	griffinguard.html \
	index.html \
	ipsum.html \
	ipsum_2.html \
	ipsum_3.html \
	ipsum_4.html \
	ipsum_5.html \
	ipsum_6.html \
	ipsum_7.html \
	ipsum_8.html \
	maltrail_scanners.html \
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
