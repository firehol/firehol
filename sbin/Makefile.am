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

inclib_DATA = \
	functions.common \
	install.config \
	$(NULL)

inclib_SCRIPTS = $(scripts)

EXTRA_DIST = \
	functions.common \
	install.config.in \
	firehol.sh \
	fireqos.sh \
	simple_services.sh \
	$(scripts) \
	$(NULL)

AWK_STRIP_SH_HEADER = 'BEGIN {strip=1} {if (strip==1 && (/^\#/)) {next} else {strip=0; print $$0}}'

firehol: simple_services.sh firehol.sh
	($(CAT) firehol_header.sh >$@ && \
	(echo "#---------------------------------------------" && \
	 echo "#--- Start excerpt from simple_services.sh ---" && \
	 echo "#---------------------------------------------") >>$@ && \
	$(GAWK) $(AWK_STRIP_SH_HEADER) simple_services.sh >>$@  && \
	(echo "#-------------------------------------------" && \
	 echo "#--- End excerpt from simple_services.sh ---" && \
	 echo "#-------------------------------------------") >>$@ && \
	$(GAWK) $(AWK_STRIP_SH_HEADER) firehol.sh >>$@ && \
	$(CHMOD) +x $@) || (rm -f $@; false)

fireqos: simple_services.sh fireqos.sh
	($(CAT) fireqos_header.sh >$@ && \
	(echo "#---------------------------------------------" && \
	 echo "#--- Start excerpt from simple_services.sh ---" && \
	 echo "#---------------------------------------------") >>$@ && \
	$(EGREP) "^server_.*_ports=" simple_services.sh >>$@ && \
	(echo "#-------------------------------------------" && \
	 echo "#--- End excerpt from simple_services.sh ---" && \
	 echo "#-------------------------------------------") >>$@ && \
	$(GAWK) $(AWK_STRIP_SH_HEADER) fireqos.sh >>$@ && \
	$(CHMOD) +x $@) || (rm -f $@; false)

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

clean:
	$(RM) -f firehol fireqos
