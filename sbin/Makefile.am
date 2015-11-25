# Process this file with automake to produce Makefile.in

scriptsin = \
	firehol.in \
	fireqos.in \
	link-balancer.in \
	update-ipsets.in \
	vnetbuild.in

inclibdir = $(libdir)/firehol

SUFFIXES = .in
.in:
	if [ "$@" = "commands.sed.in" ]; then \
		true; \
	elif sed \
		-e '/^# Start defaults before configure/,/^# End/d' \
		-e 's#[$$]prefix_POST#$(prefix)#g' \
		-e 's#[$$]bindir_POST#$(bindir)#g' \
		-e 's#[$$]libdir_POST#$(libdir)/firehol#g' \
		-e 's#[$$]localstatedir_POST#$(localstatedir)#g' \
		-e 's#[$$]sysconfdir_POST#$(sysconfdir)#g' \
		-f commands.sed \
		$< > $@.tmp; then \
		mv "$@.tmp" "$@"; \
		chmod 755 "$@"; \
        else \
		rm -f "$@.tmp"; \
		false; \
	fi

inclib_DATA = \
	functions.common.sh

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

EXTRA_DIST = \
	commands.sed.in \
	$(scriptsin) \
	$(inclib_DATA)

uninstall-local:
	@-rmdir --ignore-fail-on-non-empty $(DESTDIR)$(inclibdir)
