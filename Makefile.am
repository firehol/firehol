# Process this file with automake to produce Makefile.in

ACLOCAL_AMFLAGS = -I m4

AUTOMAKE_OPTIONS = \
	gnu \
	check-news \
	dist-xz \
	dist-bzip2 \
	std-options

AM_DISTCHECK_CONFIGURE_FLAGS = \
	--disable-maintainer-mode

SUBDIRS = sbin etc examples doc

DIST_SUBDIRS = $(SUBDIRS) m4

EXTRA_DIST = \
	autogen.sh

uninstall-local:
	@-rmdir --ignore-fail-on-non-empty $(DESTDIR)$(docdir)
