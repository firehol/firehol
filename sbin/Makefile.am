# Process this file with automake to produce Makefile.in

scripts =
if ENABLE_FIREHOL
scripts += firehol
endif

if ENABLE_FIREQOS
scripts += fireqos
endif

if ENABLE_LINK_BALANCER
scripts += link-balancer
endif

if ENABLE_UPDATE_IPSETS
scripts += update-ipsets
endif

if ENABLE_VNETBUILD
scripts += vnetbuild
endif

sbin_SCRIPTS = $(scripts)
