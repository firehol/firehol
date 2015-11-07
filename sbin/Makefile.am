# Process this file with automake to produce Makefile.in

sbin_SCRIPTS = firehol fireqos link-balancer update-ipsets vnetbuild

if ENABLE_IPRANGE

sbin_PROGRAMS = iprange
iprange_SOURCES = iprange.c

iprange_CFLAGS = $(PTHREAD_CFLAGS)
iprange_LDADD = $(PTHREAD_LIBS)

endif
