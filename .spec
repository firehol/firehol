Summary: An easy to use but powerfull iptables stateful firewall
Name: firehol
Version: MYVERSION
Release: MYRELEASE
Copyright: GPL
Group: Applications/Internet
Source: %{name}-%{version}.tar.bz2
URL: http://firehol.sourceforge.net
Vendor: Costa Tsaousis
Packager: Costa Tsaousis
BuildArchitectures: noarch
BuildRoot: %{_tmppath}/%{name}-buildroot

requires: bash >= 2.04
requires: fileutils >= 4.0.36
requires: gawk >= 3.0
requires: grep >= 2.4.2
requires: iproute >= 2.2.4
requires: iptables >= 1.2.4
requires: kernel >= 2.4
requires: less
requires: modutils >= 2.4.13
requires: net-tools >= 1.57
requires: sed >= 3.02
requires: sh-utils >= 2.0
requires: textutils >= 2.0.11
requires: util-linux >= 2.11

%description
FireHOL uses an extremely simple but powerfull way to define
firewall rules which it turns into complete stateful iptables
firewalls.
FireHOL is a generic firewall generator, meaning that you can
design any kind of local or routing stateful packet filtering
firewalls with ease.

Install FireHOL if you want an easy way to configure stateful
packet filtering firewalls on Linux hosts and routers.

You can run FireHOL with the 'helpme' argument, to get a
configuration file for the system run, which you can modify
according to your needs.

The default configuration file will allow only client traffic
on all interfaces.

%prep
%{__rm} -rf %{buildroot}
%setup

%build

%install
mkdir -p %{buildroot}/etc/firehol/examples
test -f /etc/firehol.conf -a ! -f /etc/firehol/firehol.conf && mv -f /etc/firehol.conf /etc/firehol/firehol.conf
mkdir -p %{buildroot}/etc/init.d
install -m 750 firehol.sh %{buildroot}/etc/init.d/firehol
install -m 640 examples/client-all.conf %{buildroot}/etc/firehol/firehol.conf
mkdir -p %{buildroot}/%{_mandir}/man1
mkdir -p %{buildroot}/%{_mandir}/man5
gzip -9 man/firehol.1
gzip -9 man/firehol.conf.5
install -m 644 man/firehol.1.gz %{buildroot}/%{_mandir}/man1/firehol.1.gz
install -m 644 man/firehol.conf.5.gz %{buildroot}/%{_mandir}/man5/firehol.conf.5.gz
install -m 644 examples/home-adsl.conf %{buildroot}/etc/firehol/examples/home-adsl.conf
install -m 644 examples/home-dialup.conf %{buildroot}/etc/firehol/examples/home-dialup.conf
install -m 644 examples/office.conf %{buildroot}/etc/firehol/examples/office.conf
install -m 644 examples/server-dmz.conf %{buildroot}/etc/firehol/examples/server-dmz.conf
install -m 644 examples/client-all.conf %{buildroot}/etc/firehol/examples/client-all.conf
install -m 644 examples/lan-gateway.conf %{buildroot}/etc/firehol/examples/lan-gateway.conf

%pre

%post
if [ -f /etc/firehol.conf -a ! -f /etc/firehol/firehol.conf ]
then
	mv -f /etc/firehol.conf /etc/firehol/firehol.conf
	echo
	echo
	echo "FireHOL has now its configuration in /etc/firehol/firehol.conf"
	echo "Your existing configuration has been moved to its new place."
	echo
fi
/sbin/chkconfig --del firehol

%preun
/sbin/chkconfig --del firehol

%postun

%clean
rm -rf ${RPM_BUILD_DIR}/%{name}-%{version}

%files
%defattr(-,root,root)
%doc README TODO COPYING ChangeLog WhatIsNew

%dir /etc/firehol
%dir /etc/firehol/examples

/etc/init.d/firehol
%{_mandir}/man1/firehol.1.gz
%{_mandir}/man5/firehol.conf.5.gz

%config(noreplace) /etc/firehol/firehol.conf

/etc/firehol/examples/home-adsl.conf
/etc/firehol/examples/home-dialup.conf
/etc/firehol/examples/office.conf
/etc/firehol/examples/server-dmz.conf
/etc/firehol/examples/client-all.conf
/etc/firehol/examples/lan-gateway.conf

%doc adblock.sh get-iana.sh
%doc doc/adding.html
%doc doc/css.css
%doc doc/fwtest.html
%doc doc/index.html
%doc doc/language.html
%doc doc/services.html
%doc doc/tutorial.html
%doc doc/commands.html
%doc doc/header.html
%doc doc/invoking.html
%doc doc/overview.html
%doc doc/trouble.html
%doc doc/faq.html

%changelog
