# Process this file with automake to produce Makefile.in


inclibdir = @firehollibexecdir@

include $(top_srcdir)/build/subst.inc

SUFFIXES = .in

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

CLEANFILES = install.config

helper_scripts =
if ENABLE_FIREHOL_OR_FIREQOS
helper_scripts += simple_services.sh
endif

inclib_DATA = \
	functions.common \
	install.config \
	$(helper_scripts) \
	$(NULL)

inclib_SCRIPTS = $(scripts)

EXTRA_DIST = \
	functions.common \
	install.config.in \
	$(helper_scripts) \
	$(scripts) \
	$(NULL)

install-exec-hook:
	$(MKDIR_P) "$(DESTDIR)$(sbindir)"
	$(CHMOD) 755 "$(DESTDIR)$(sbindir)"
	for i in $(scripts); do \
		$(RM) -f "$(DESTDIR)$(sbindir)/$$i"; \
		$(LN_S_R) "$(DESTDIR)$(inclibdir)/$$i" "$(DESTDIR)$(sbindir)"; done

uninstall-hook:
	for i in $(scripts); do \
		$(RM) -f "$(DESTDIR)$(sbindir)/$$i"; done
	@-rmdir --ignore-fail-on-non-empty $(DESTDIR)$(inclibdir)
