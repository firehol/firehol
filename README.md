FireHOL
=======

http://firehol.org/

    FireHOL, an iptables stateful packet filtering firewall for humans!
    FireQOS, a TC based bandwidth shaper for humans!

Git
===
These instructions are for people who are working with the git repository.
There are more general instructions starting with
[Upgrade Notes](#upgrade-notes).

Cloning Git Repository
----------------------

The [github firehol repository page](https://github.com/firehol/firehol)
lists URLs which can be used to clone the repository.

After cloning you should copy the git hooks, for style checking and more:

~~~~
cp hooks/* .git/hooks
~~~~

Building Git Repository
-----------------------
You need [GNU autoconf](http://www.gnu.org/software/autoconf/) and
[GNU automake](http://www.gnu.org/software/automake/) to be able to
run:

~~~~
./autogen.sh
./configure --enable-maintainer-mode
make
make install
~~~~

If you don't want to have to install pandoc you can instead choose
to build without documentation or manpages:

~~~~
./autogen.sh
./configure --disable-doc --disable-man
make
make install
~~~~

Re-run `autogen.sh` whenever you change `configure.ac` or a `Makefile.am`

You can run the `sbin/*.in` scripts in-situ but they will produce internal
git versions e.g. `FireQOS $Id: def55bbc9c2a78aef580e88ad6d3f9ba689a6004 $`.

The "compiled" scripts must be installed, along with their function
libraries in order to work correctly.


Upgrade Notes
=============
From version 2.0.0-pre6, FireHOL adds combined IPv4/IPv6 support within
a single configuration.

If you are upgrading FireHOL from a version earlier than 2.0.0-pre6,
please read the [upgrade notes](http://firehol.org/upgrade/).


Installation
============
If you are installing the package from a tar-files release, FireHOL uses
the GNU Autotools so you can just do:
  ./configure && make && make install

You can get help on the options available (including disabling unwanted
components) by running:
  ./configure --help

From version 3.0.0 it is no longer recommended to install firehol by
copying files, since a function library is now used, in addition to
the scripts.


Getting Started
===============
Configuration for FireHOL goes in `/etc/firehol/firehol.conf`
Configuration for FireQOS goes in `/etc/firehol/fireqos.conf`

In the examples directory, you can find examples for both programs.

To start the programs:

~~~~
firehol start
fireqos start
~~~~

For more details on the command-line options, see the man-pages:

~~~~
man firehol
man fireqos
~~~~

Read the [tutorials](http://firehol.org/tutorial/) on the website for
more information and to learn how to configure the programs.

For detailed information on the configuration files, read the manual
online, or start with these the man-pages:

~~~~
man firehol.conf
man fireqos.conf
~~~~

You may want to ensure that FireHOL and FireQOS run at boot-time. If you
installed from an distribution package this will be configured in the
usual way.

For a tar-file installation, the binaries can often be linked directly
into `/etc/init.d`, since their options are SysVInit compatible. Some
example systemd service files can be found in the contrib folder.


Support and documentation
=========================
The main website is [http://firehol.org/](http://firehol.org/).

To ask questions please sign up to the
[mailing list](http://lists.firehol.org/mailman/listinfo/firehol-support)

Man pages, PDF and HTML documentation are provided as part of the package
and can be found in the tarball or in your distribution's standard locations
(e.g. `/usr/share/doc`). The [latest manual](http://firehol.org/manual/)
is also online.

The site has a [list of all services](http://firehol.org/services/) supported
by FireHOL "out of the box" as well as information on adding new services.


License
=======

    Copyright (C) 2012-2015 Phil Whineray <phil@firehol.org>
    Copyright (C) 2003-2015 Costa Tsaousis <costa@tsaousis.gr>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
