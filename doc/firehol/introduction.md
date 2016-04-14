Introduction
============

Who should read this manual
---------------------------

This is a reference guide with specific detailed information on
commands and configuration syntax for the FireHOL tool.
The reference is unlikely to be suitable for newcomers to the tools,
except as a means to look up more information on a particular command.

For tutorials and guides to using FireHOL and FireQOS, please visit
the [website](http://firehol.org/).

Where to get help
-----------------

The [FireHOL website](http://firehol.org/).

The [mailing lists and
archives](http://lists.firehol.org/mailman/listinfo).

The package comes with a complete set of manpages, a README and a brief
INSTALL guide.

Installation
------------

You can download tar-file releases by visiting the [FireHOL website
download area](http://firehol.org/download/).

Unpack and change directory with:

~~~~
tar xfz firehol-version.tar.gz
cd firehol-version
~~~~

From version 3.0.0 it is no longer recommended to install firehol by
copying files, since a function library is now used, in addition to
the scripts.

Options for the configure program can be seen in the INSTALL file and by
running:

~~~~
./configure --help
~~~~

To build and install taking the default options:

~~~~
./configure && make && sudo make install
~~~~

To not have files appear under /usr/local, try something like:

~~~~
./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var
make
make install
~~~~

If your O/S does not usually have a `/usr/libexec`, you may want
to add `--libexecdir=/usr/lib` to the `configure`.

All of the common SysVInit command line arguments are recognised which
makes it easy to deploy the script as a startup service.

Packages are available for most distributions and you can use your
distribution's standard commands (e.g. aptitude, yum, etc.) to install
these.

> **Note**
>
> Distributions do not always offer the latest version. You can see what
> the latest release is on the [FireHOL website](http://firehol.org/).

Licence
-------

This manual is licensed under the same terms as the FireHOL package, the
GNU GPL v2 or later.

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the
Free Software Foundation; either version 2 of the License, or (at your
option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
Public License for more details.

You should have received a copy of the GNU General Public License along
with this program; if not, write to the Free Software Foundation, Inc.,
59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
