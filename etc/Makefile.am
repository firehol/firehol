# Process this file with automake to produce Makefile.in

fireholconfdir = $(sysconfdir)/firehol
servicesconfdir = $(sysconfdir)/firehol/services

conffiles=

if ENABLE_FIREHOL

servicesconf_DATA = \
	bittorrent.conf.example

conffiles += firehol.conf.example

endif

if ENABLE_FIREQOS
conffiles += fireqos.conf.example
endif

fireholconf_DATA = $(conffiles)

EXTRA_DIST = \
	firehol.conf.example \
	bittorrent.conf.example \
	fireqos.conf.example
