# Process this file with automake to produce Makefile.in

ACLOCAL_AMFLAGS = -I m4

AUTOMAKE_OPTIONS = \
	foreign \
	dist-xz \
	dist-bzip2 \
	std-options

AM_DISTCHECK_CONFIGURE_FLAGS = \
	--disable-maintainer-mode

SUBDIRS = sbin etc examples doc contrib html

DIST_SUBDIRS = $(SUBDIRS) m4

EXTRA_DIST = autogen.sh README

if GIT_TREE

all-local: README

README: README.md
	sed -e '/^Upgrade Notes$$/p' -e '/^Git$$/,/^Upgrade Notes$$/d' $< > $@

endif

uninstall-local:
	@-rmdir --ignore-fail-on-non-empty $(DESTDIR)$(docdir)
