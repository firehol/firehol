# Process this file with automake to produce Makefile.in

testargs =

if ENABLE_FIREHOL
testargs += $(srcdir)/firehol
endif

if ENABLE_FIREQOS
testargs += $(srcdir)/fireqos
endif

if ENABLE_LINK_BALANCER
testargs += $(srcdir)/link-balancer
endif

if ENABLE_UPDATE_IPSETS
testargs += $(srcdir)/update-ipsets
endif

if ENABLE_VNETBUILD
testargs += $(srcdir)/vnetbuild
endif

if USERNS_ENABLED
check-local: unittest
	$(srcdir)/unittest $(testargs)
endif

TOOLS = \
  README.md \
  tools/clean-class \
  tools/clean-iptables \
  tools/newns \
  unittest \
  update-audit

# Generated with:
#  find firehol fireqos link-balancer update-ipsets -type f | sed -e 's:.*:  & \\:' | sort
TESTFILES = \
  firehol/basics/empty.aud4 \
  firehol/basics/empty.aud6 \
  firehol/basics/empty.conf \
  firehol/basics/interface46.aud4 \
  firehol/basics/interface46.aud6 \
  firehol/basics/interface46.conf \
  firehol/basics/interface.aud4 \
  firehol/basics/interface.aud6 \
  firehol/basics/interface.conf \
  firehol/basics/router46.aud4 \
  firehol/basics/router46.aud6 \
  firehol/basics/router46.conf \
  firehol/basics/router.aud4 \
  firehol/basics/router.aud6 \
  firehol/basics/router.conf \
  firehol/cmdline/panic-test.aud4 \
  firehol/cmdline/panic-test.aud6 \
  firehol/cmdline/panic-test.conf \
  firehol/cmdline/panic-test.run.sh \
  firehol/cmdline/stop-test.aud4 \
  firehol/cmdline/stop-test.aud6 \
  firehol/cmdline/stop-test.conf \
  firehol/cmdline/stop-test.post.sh \
  firehol/cmdline/stop-test.pre.sh \
  firehol/cmdline/stop-test.run.sh \
  firehol/cmdline/try-test.aud4 \
  firehol/cmdline/try-test.aud6 \
  firehol/cmdline/try-test.conf \
  firehol/cmdline/try-test.post.sh \
  firehol/cmdline/try-test.pre.sh \
  firehol/cmdline/try-test.run.sh \
  firehol/not-both/ipv4-disable-conf.aud4 \
  firehol/not-both/ipv4-disable-conf.aud6 \
  firehol/not-both/ipv4-disable-conf.conf \
  firehol/not-both/ipv4-disable-defaults.aud4 \
  firehol/not-both/ipv4-disable-defaults.aud6 \
  firehol/not-both/ipv4-disable-defaults.conf \
  firehol/not-both/ipv4-disable-defaults.pre.sh \
  firehol/not-both/ipv6-disable-conf.aud4 \
  firehol/not-both/ipv6-disable-conf.aud6 \
  firehol/not-both/ipv6-disable-conf.conf \
  firehol/not-both/ipv6-disable-defaults.aud4 \
  firehol/not-both/ipv6-disable-defaults.aud6 \
  firehol/not-both/ipv6-disable-defaults.conf \
  firehol/not-both/ipv6-disable-defaults.pre.sh \
  fireqos/basic/minimal-qos.class.aud \
  fireqos/basic/minimal-qos.conf \
  fireqos/basic/minimal-qos.filter.aud \
  fireqos/basic/minimal-qos.qdisc.aud \
  fireqos/cmdline/clear-all.class.aud \
  fireqos/cmdline/clear-all.conf \
  fireqos/cmdline/clear-all.filter.aud \
  fireqos/cmdline/clear-all.post.sh \
  fireqos/cmdline/clear-all.pre.sh \
  fireqos/cmdline/clear-all.qdisc.aud \
  fireqos/cmdline/clear-all.run.sh \
  fireqos/cmdline/no-args.class.aud \
  fireqos/cmdline/no-args.conf \
  fireqos/cmdline/no-args.filter.aud \
  fireqos/cmdline/no-args.qdisc.aud \
  fireqos/cmdline/no-args.run.sh \
  link-balancer/basics/simple.conf \
  link-balancer/basics/simple.pre.sh \
  link-balancer/basics/simple.rules.aud \
  link-balancer/basics/simple.table.aud \
  update-ipsets/basic/no-setup.conf \
  update-ipsets/basic/no-setup.run.sh \
  vnetbuild/basic/no-setup.conf \
  vnetbuild/basic/no-setup.ns.aud \
  vnetbuild/basic/no-setup.run.sh

EXTRA_DIST = $(TOOLS) $(TESTFILES)
