#!/bin/bash
#
# Service definitions for FireHOL and FireQOS.
#
#   Copyright
#
#       Copyright (C) 2002-2017 Costa Tsaousis <costa@tsaousis.gr>
#       Copyright (C) 2012-2017 Phil Whineray <phil@sanewall.org>
#
#   License
#
#       This program is free software; you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation; either version 2 of the License, or
#       (at your option) any later version.
#
#       This program is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with this program. If not, see <http://www.gnu.org/licenses/>.
#
#       See the file COPYING for details.
#

# Services API version
FIREHOL_SERVICES_API="1"

# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
#
# SIMPLE SERVICES DEFINITIONS
#
# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
# The following are definitions for simple services.
# We define as "simple" the services that are implemented using a single socket,
# initiated by the client and used by the server.
#
# The following list is sorted by service name.

server_all_ports="any/any"
client_all_ports="any"
helper_all="ftp irc sip pptp proto_gre"

# any is the same with all, without helpers
server_any_ports="${server_all_ports}"
client_any_ports="${client_all_ports}"
helper_any=

server_AH_ports="51/any"
client_AH_ports="any"

server_amanda_ports="udp/10080"
client_amanda_ports="default"
helper_amanda="amanda"

server_aptproxy_ports="tcp/9999"
client_aptproxy_ports="default"

server_apcupsd_ports="tcp/6544"
client_apcupsd_ports="default"

server_apcupsdnis_ports="tcp/3551"
client_apcupsdnis_ports="default"

server_asterisk_ports="tcp/5038"
client_asterisk_ports="default"

server_cups_ports="tcp/631 udp/631"
client_cups_ports="any"

server_cvspserver_ports="tcp/2401"
client_cvspserver_ports="default"

server_darkstat_ports="tcp/666"
client_darkstat_ports="default"

server_daytime_ports="tcp/13"
client_daytime_ports="default"

server_dcc_ports="udp/6277"
client_dcc_ports="default"

server_dcpp_ports="tcp/1412 udp/1412"
client_dcpp_ports="default"

server_dns_ports="udp/53 tcp/53"
client_dns_ports="any"

server_dhcprelay_ports="udp/67"
client_dhcprelay_ports="67"

server_dict_ports="tcp/2628"
client_dict_ports="default"

server_distcc_ports="tcp/3632"
client_distcc_ports="default"

server_eserver_ports="tcp/4661 udp/4661 udp/4665"
client_eserver_ports="any"

server_ESP_ports="50/any"
client_ESP_ports="any"

server_echo_ports="tcp/7"
client_echo_ports="default"

server_finger_ports="tcp/79"
client_finger_ports="default"

server_ftp_ports="tcp/21"
client_ftp_ports="default"
helper_ftp="ftp"

server_gift_ports="tcp/4302 tcp/1214 tcp/2182 tcp/2472"
client_gift_ports="any"

server_giftui_ports="tcp/1213"
client_giftui_ports="default"

server_gkrellmd_ports="tcp/19150"
client_gkrellmd_ports="default"

server_GRE_ports="47/any"
client_GRE_ports="any"
helper_GRE="proto_gre"

server_h323_ports="udp/1720 tcp/1720"
client_h323_ports="default"
helper_h323="h323"

server_heartbeat_ports="udp/690:699"
client_heartbeat_ports="default"

server_http_ports="tcp/80"
client_http_ports="default"

server_https_ports="tcp/443"
client_https_ports="default"

server_httpalt_ports="tcp/8080"
client_httpalt_ports="default"

server_iax_ports="udp/5036"
client_iax_ports="default"

server_iax2_ports="udp/5469 udp/4569"
client_iax2_ports="default"

server_ICMP_ports="icmp/any"
client_ICMP_ports="any"

server_icmp_ports="${server_ICMP_ports}"
client_icmp_ports="${client_ICMP_ports}"

server_ICMPV6_ports="icmpv6/any"
client_ICMPV6_ports="any"

server_icmpv6_ports="${server_ICMPV6_ports}"
client_icmpv6_ports="${client_ICMPV6_ports}"

server_icp_ports="udp/3130"
client_icp_ports="3130"

server_ident_ports="tcp/113"
client_ident_ports="default"

server_imap_ports="tcp/143"
client_imap_ports="default"

server_imaps_ports="tcp/993"
client_imaps_ports="default"

server_irc_ports="tcp/6667"
client_irc_ports="default"
helper_irc="irc"

server_isakmp_ports="udp/500"
client_isakmp_ports="any"

server_ipsecnatt_ports="udp/4500"
client_ipsecnatt_ports="any"

server_jabber_ports="tcp/5222 tcp/5223"
client_jabber_ports="default"

server_jabberd_ports="tcp/5222 tcp/5223 tcp/5269"
client_jabberd_ports="default"

server_l2tp_ports="udp/1701"
client_l2tp_ports="any"

server_ldap_ports="tcp/389"
client_ldap_ports="default"

server_ldaps_ports="tcp/636"
client_ldaps_ports="default"

server_lpd_ports="tcp/515"
client_lpd_ports="any"

server_microsoft_ds_ports="tcp/445"
client_microsoft_ds_ports="default"

server_mms_ports="tcp/1755 udp/1755"
client_mms_ports="default"
helper_mms="mms"

server_ms_ds_ports="${server_microsoft_ds_ports}"
client_ms_ds_ports="${client_microsoft_ds_ports}"

server_msnp_ports="tcp/6891"
client_msnp_ports="default"

server_msn_ports="tcp/1863 udp/1863"
client_msn_ports="default"

server_mysql_ports="tcp/3306"
client_mysql_ports="default"

server_netbackup_ports="tcp/13701 tcp/13711 tcp/13720 tcp/13721 tcp/13724 tcp/13782 tcp/13783"
client_netbackup_ports="any"

server_netbios_ns_ports="udp/137"
client_netbios_ns_ports="any"

server_netbios_dgm_ports="udp/138"
client_netbios_dgm_ports="any"

server_netbios_ssn_ports="tcp/139"
client_netbios_ssn_ports="default"

server_nntp_ports="tcp/119"
client_nntp_ports="default"

server_nntps_ports="tcp/563"
client_nntps_ports="default"

server_ntp_ports="udp/123 tcp/123"
client_ntp_ports="any"

server_nut_ports="tcp/3493 udp/3493"
client_nut_ports="default"

server_nxserver_ports="tcp/5000:5200"
client_nxserver_ports="default"

server_openvpn_ports="tcp/1194 udp/1194"
client_openvpn_ports="default"

server_oracle_ports="tcp/1521"
client_oracle_ports="default"

server_OSPF_ports="89/any"
client_OSPF_ports="any"

server_pop3_ports="tcp/110"
client_pop3_ports="default"

server_pop3s_ports="tcp/995"
client_pop3s_ports="default"

server_portmap_ports="udp/111 tcp/111"
client_portmap_ports="any" # Portmap clients appear to use ports below 1024

server_postgres_ports="tcp/5432"
client_postgres_ports="default"

server_pptp_ports="tcp/1723"
client_pptp_ports="default"
helper_pptp="pptp proto_gre"

server_privoxy_ports="tcp/8118"
client_privoxy_ports="default"

server_radius_ports="udp/1812 udp/1813"
client_radius_ports="default"

server_radiusproxy_ports="udp/1814"
client_radiusproxy_ports="default"

server_radiusold_ports="udp/1645 udp/1646"
client_radiusold_ports="default"

server_radiusoldproxy_ports="udp/1647"
client_radiusoldproxy_ports="default"

server_rdp_ports="tcp/3389"
client_rdp_ports="default"

server_rndc_ports="tcp/953"
client_rndc_ports="default"

server_rsync_ports="tcp/873 udp/873"
client_rsync_ports="default"

server_rtp_ports="udp/10000:20000"
client_rtp_ports="any"

server_sane_ports="tcp/6566"
client_sane_ports="default"
helper_sane="sane"

server_sip_ports="tcp/5060 udp/5060"
client_sip_ports="5060 default"
helper_sip="sip"

server_socks_ports="tcp/1080 udp/1080"
client_socks_ports="default"

server_squid_ports="tcp/3128"
client_squid_ports="default"

server_smtp_ports="tcp/25"
client_smtp_ports="default"

server_smtps_ports="tcp/465"
client_smtps_ports="default"

server_snmp_ports="udp/161"
client_snmp_ports="default"

server_snmptrap_ports="udp/162"
client_snmptrap_ports="any"

server_nrpe_ports="tcp/5666"
client_nrpe_ports="default"

server_ssh_ports="tcp/22"
client_ssh_ports="default"

server_stun_ports="udp/3478 udp/3479"
client_stun_ports="any"

server_submission_ports="tcp/587"
client_submission_ports="default"

server_sunrpc_ports="${server_portmap_ports}"
client_sunrpc_ports="${client_portmap_ports}"

server_swat_ports="tcp/901"
client_swat_ports="default"

server_syslog_ports="udp/514"
client_syslog_ports="514 default"

server_telnet_ports="tcp/23"
client_telnet_ports="default"

server_tftp_ports="udp/69"
client_tftp_ports="default"
helper_tftp="tftp"

server_tomcat_ports="${server_httpalt_ports}"
client_tomcat_ports="${client_httpalt_ports}"

server_time_ports="tcp/37 udp/37"
client_time_ports="default"

server_upnp_ports="udp/1900 tcp/2869"
client_upnp_ports="default"

server_uucp_ports="tcp/540"
client_uucp_ports="default"

server_whois_ports="tcp/43"
client_whois_ports="default"

server_vmware_ports="tcp/902"
client_vmware_ports="default"

server_vmwareauth_ports="tcp/903"
client_vmwareauth_ports="default"

server_vmwareweb_ports="tcp/8222 tcp/8333"
client_vmwareweb_ports="default"

server_vnc_ports="tcp/5900:5903"
client_vnc_ports="default"

server_webcache_ports="${server_httpalt_ports}"
client_webcache_ports="${client_httpalt_ports}"

server_webmin_ports="tcp/10000"
client_webmin_ports="default"

server_xdmcp_ports="udp/177"
client_xdmcp_ports="default"
