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

requires: kernel >= 2.4
requires: gawk >= 3.0
requires: iptables >= 1.2.4
requires: bash >= 2.04

%description
FireHOL uses an extremely simple but powerfull way to define
firewall rules which it turns into complete stateful iptables
firewalls.
FireHOL is a generic firewall generator, meaning that you can
design any kind of local or routing stateful packet filtering
firewalls with ease.

Install FireHOL if you want an easy way to configure stateful
packet filtering firewalls on Linux hosts and routers.

The default configuration file will allow only client traffic
on PPP and ethernet interfaces.

%prep
%setup

%build

%install
install -c -m 750 firehol.sh /etc/init.d/firehol
install -c -m 640 examples/client-all.conf /etc/firehol.conf

%pre

%post
/sbin/chkconfig --del firehol
/sbin/chkconfig --add firehol

%preun
/sbin/chkconfig --del firehol

%postun

%clean
rm -rf ${RPM_BUILD_DIR}/%{name}-%{version}

%files
%defattr(-,root,root)
%doc README TODO COPYING ChangeLog

/etc/init.d/firehol
%config(noreplace) /etc/firehol.conf

%doc examples/home-adsl.conf
%doc examples/home-dialup.conf
%doc examples/office.conf
%doc examples/server-dmz.conf
%doc examples/client-all.conf

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

%changelog
