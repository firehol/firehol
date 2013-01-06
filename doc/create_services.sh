#!/bin/bash


if [ ! -f ../firehol.sh -o ! -f services.html ]
then
	echo "Please step into the 'doc' directory of firehol"
	exit 1
fi

title_AH="IPSec Authentication Header (AH)"
wikipedia_AH="http://en.wikipedia.org/wiki/IPsec#Authentication_Header"
service_AH_notes="
For more information see the <a href=\"http://www.freeswan.org/freeswan_trees/freeswan-1.99/doc/ipsec.html#AH.ipsec\">FreeS/WAN documentation</a>
and <a href=\"http://www.ietf.org/rfc/rfc2402.txt?number=2402\">RFC 2402</a>.
"

home_amanda="http://www.amanda.org/"
title_amanda="Advanced Maryland Automatic Network Disk Archiver"
wikipedia_amanda="http://en.wikipedia.org/wiki/Advanced_Maryland_Automatic_Network_Disk_Archiver"

title_aptproxy="Advanced Packaging Tool"
wikipedia_aptproxy="http://en.wikipedia.org/wiki/Apt-proxy"

title_apcupsd="APC UPS Daemon"
home_apcupsd="http://www.apcupsd.com"
wikipedia_apcupsd="http://en.wikipedia.org/wiki/Apcupsd"
service_apcupsd_notes="This service must be defined as <b>server apcupsd accept</b> on all machines not directly connected to the UPS (i.e. slaves).
<p>
Note that the port defined here is not the default port (6666) used if you download and compile
APCUPSD, since the default is conflicting with IRC and many distributions (like Debian) have
changed this to 6544.
<p>
You can define port 6544 in APCUPSD, by changing the value of NETPORT in its configuration file,
or overwrite this FireHOL service definition using the procedures described in
<a href=\"adding.html\">Adding Services</a>.
"

title_apcupsdnis="APC UPS Daemon"
home_apcupsdnis="http://www.apcupsd.com"
wikipedia_apcupsdnis="http://en.wikipedia.org/wiki/Apcupsd"
service_apcupsdnis_notes="APC UPS Network Information Server. This service allows the remote WEB interfaces
<a href=\"http://www.apcupsd.com/\">APCUPSD</a> has, to connect and get information from the server directly connected to the UPS device.
"

server_all_ports="all"
client_all_ports="all"
service_all_type="complex"
service_all_notes="
Matches all traffic (all protocols, ports, etc) while ensuring that required kernel modules are loaded.
<br>This service may indirectly setup a set of other services, if they are required by the kernel modules to be loaded.
Currently it activates also <a href=\"#ftp\">ftp</a>, <a href=\"#irc\">irc</a> and <a href=\"#icmp\">icmp</a>.
"

server_any_ports="all"
client_any_ports="all"
service_any_type="complex"
service_any_notes="
Matches all traffic (all protocols, ports, etc), but does not care about kernel modules and does not activate any other service indirectly.
In combination with the <a href=\"commands.html#parameters\">Optional Rule Parameters</a> this service can match unusual traffic (e.g. GRE - protocol 47).
"
service_any_example="server any <u>myname</u> accept proto 47"

server_anystateless_ports="all"
client_anystateless_ports="all"
service_anystateless_type="complex"
service_anystateless_notes="
Matches all traffic (all protocols, ports, etc), but does not care about kernel modules and does not activate any other service indirectly.
In combination with the <a href=\"commands.html#parameters\">Optional Rule Parameters</a> this service can match unusual traffic (e.g. GRE - protocol 47).
<p>
Also, this service is exactly the same with service <a href=\"#any\">any</a>, but does not care about the state of traffic.
"
service_anystateless_example="server anystateless <u>myname</u> accept proto 47"

wikipedia_asterisk="http://en.wikipedia.org/wiki/Asterisk_PBX"
home_asterisk="http://www.asterisk.org"
service_asterisk_notes="
This service refers only to the <b>manager</b> interface of asterisk.
You should normally need to enable <a href=\"#sip\">sip</a>, <a href=\"#h323\">h323</a>,
<a href=\"#rtp\">rtp</a>, etc at the firewall level, if you enable the relative channel drivers
of asterisk."

title_cups="Common UNIX Printing System"
home_cups="http://www.cups.org"
wikipedia_cups="http://en.wikipedia.org/wiki/Common_Unix_Printing_System"

title_cvspserver="Concurrent Versions System"
home_cvspserver="http://www.nongnu.org/cvs/"
wikipedia_cvspserver="http://en.wikipedia.org/wiki/Concurrent_Versions_System"

server_custom_ports="defined&nbsp;in&nbsp;the&nbsp;command"
client_custom_ports="defined&nbsp;in&nbsp;the&nbsp;command"
service_custom_type="complex"
service_custom_notes="
This service is used by FireHOL to allow you define services it currently does not support.<br>
To find more about this service please check the <a href=\"adding.html\">Adding Services</a> section.
"
service_custom_example="server custom <u>myimap</u> <u>tcp/143</u> <u>default</u> accept"

home_darkstat="http://dmr.ath.cx/net/darkstat/"
service_darkstat_notes="
Darkstat is a network traffic analyzer.
It's basically a packet sniffer which runs as a background process on a cable/DSL router
and gathers all sorts of useless but interesting statistics.
"

title_daytime="Daytime Protocol"
wikipedia_daytime="http://en.wikipedia.org/wiki/Daytime_Protocol"

home_distcc="http://distcc.samba.org/"
wikipedia_distcc="http://en.wikipedia.org/wiki/Distcc"
service_distcc_notes="
For distcc security, please check the <a href=\"http://distcc.samba.org/security.html\">distcc security design</a>.
"

title_dcc="Distributed Checksum Clearinghouses"
wikipedia_dcc="http://en.wikipedia.org/wiki/Distributed_Checksum_Clearinghouse"
service_dcc_notes="
See <a href=\"http://www.rhyolite.com/anti-spam/dcc/FAQ.html#firewall-ports\">http://www.rhyolite.com/anti-spam/dcc/FAQ.html#firewall-ports</a>.
"

title_dcpp="Direct Connect++"
home_dcpp="http://dcplusplus.sourceforge.net"

title_dhcp="Dynamic Host Configuration Protocol"
wikipedia_dhcp="http://en.wikipedia.org/wiki/Dhcp"
server_dhcp_ports="udp/67"
client_dhcp_ports="68"
service_dhcp_notes="
The DHCP service has been changed in v1.211 of FireHOL and now it is implemented as stateless.
This has been done because DHCP clients broadcast the network (src 0.0.0.0 dst 255.255.255.255) to find a DHCP server.
If the DHCP service was stateful the iptables connection tracker would not match the packets and deny to send the reply.
Note that this change does not affect the security of either DHCP servers or clients, since only the specific ports are
allowed (there is no random port at either the server or the client side).
<p>
Also, keep in mind that the <b>server dhcp accept</b> or <b>client dhcp accept</b> commands should placed within
interfaces that either do not have <b>src</b> and / or <b>dst</b> defined (because of the initial broadcast).
<p>
You can overcome this problem by placing the DHCP service on a separate
interface, without an <b>src</b> or <b>dst</b> but with a <b>policy return</b>.
Place this interface before the one that defines the rest of the services.
<p>
For example:
<table border=0 cellpadding=0 cellspacing=0>
<tr><td><pre>
<br>&nbsp;&nbsp;&nbsp;&nbsp;interface eth0 dhcp
<br>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;policy return
<br>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;server dhcp accept
<br>
<br>&nbsp;&nbsp;&nbsp;&nbsp;interface eth0 lan src \"\$mylan\" dst \"\$myip\"
<br>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;...
<br>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;client all accept
</td></tr></table>
"

service_dhcprelay_notes="DHCP Relay.
<p><small><b><font color=\"gray\">From RFC 1812 section 9.1.2</font></b></small><br>
   In many cases, BOOTP clients and their associated BOOTP server(s) do
   not reside on the same IP (sub)network.  In such cases, a third-party
   agent is required to transfer BOOTP messages between clients and
   servers.  Such an agent was originally referred to as a BOOTP
   forwarding agent.  However, to avoid confusion with the IP forwarding
   function of a router, the name BOOTP relay agent has been adopted
   instead.
<p>
For more information about DHCP Relay see section 9.1.2 of
<a href=\"http://www.ietf.org/rfc/rfc1812.txt?number=1812\">RFC 1812</a>
and section 4 of 
<a href=\"http://www.ietf.org/rfc/rfc1542.txt?number=1542\">RFC 1542</a>
"

title_dict="Dictionary Server Protocol"
wikipedia_dict="http://en.wikipedia.org/wiki/DICT"
service_dict_notes="
See <a href=\"http://www.ietf.org/rfc/rfc2229.txt?number=2229\">RFC2229</a>.
"

title_dns="Domain Name System"
wikipedia_dns="http://en.wikipedia.org/wiki/Domain_Name_System"
service_dns_notes="
On very busy DNS servers you may see a few dropped DNS packets in your logs.
This is normal. The iptables connection tracker will timeout the session and leave unmatched DNS packets that arrive too late to be any usefull.
"

title_echo="Echo Protocol"
wikipedia_echo="http://en.wikipedia.org/wiki/Echo_Protocol"


service_ESP_notes="IPSec Encapsulated Security Payload (ESP).
<p>
For more information see the <a href=\"http://www.freeswan.org/freeswan_trees/freeswan-1.99/doc/ipsec.html#ESP.ipsec\">FreeS/WAN documentation</a>
and RFC <a href=\"http://www.ietf.org/rfc/rfc2406.txt?number=2406\">RFC 2406</a>.
"

title_emule="eMule (Donkey network client)"
home_emule="http://www.emule-project.com"
server_emule_ports="many"
client_emule_ports="many"
service_emule_example="client emule accept src 1.1.1.1"
service_emule_type="complex"
service_emule_notes="
FireHOL defines:
<ul>
	<li>Connection from any client port to the server at tcp/4661<br>&nbsp;</li>
	<li>Connection from any client port to the server at tcp/4662<br>&nbsp;</li>
	<li>Connection from any client port to the server at udp/4665<br>&nbsp;</li>
	<li>Connection from any client port to the server at udp/4672<br>&nbsp;</li>
	<li>Connection from any server port to the client at tcp/4662<br>&nbsp;</li>
	<li>Connection from any server port to the client at udp/4672<br>&nbsp;</li>
</ul>
Use the FireHOL <a href=\"commands.html#client\">client</a> command to match the eMule client.
<p>
Please note that the eMule client is an HTTP client also.
"

title_eserver="eDonkey network server"
wikipedia_eserver="http://en.wikipedia.org/wiki/Eserver"

title_finger="Finger Protocol"
wikipedia_finger="http://en.wikipedia.org/wiki/Finger_protocol"

title_ftp="File Transfer Protocol"
wikipedia_ftp="http://en.wikipedia.org/wiki/Ftp"
service_ftp_notes="FireHOL uses the netfilter module to match both active and passive ftp connections."

title_gift="giFT Internet File Transfer"
home_gift="http://gift.sourceforge.net"
wikipedia_gift="http://en.wikipedia.org/wiki/GiFT"
service_gift_notes="
The <b>gift</b> FireHOL service supports:<br>
<ul>
<li>Gnutella listening at tcp/4302</li>
<li>FastTrack listening at tcp/1214</li>
<li>OpenFT listening at tcp/2182 and tcp/2472</li>
</ul>

The above ports are the defaults given for the coresponding GiFT modules.<p>
To allow access to the user interface ports of GiFT, use the <a href=\"#giftui\">giftui</a> FireHOL service.
"

title_giftui="giFT Internet File Transfer"
home_giftui="http://gift.sourceforge.net"
wikipedia_giftui="http://en.wikipedia.org/wiki/GiFT"
service_giftui_notes="
This service refers only to the user interface ports offered by GiFT.
To allow gift accept P2P requests, use the <a href=\"#gift\">gift</a> FireHOL service.
"

home_gkrellmd="http://members.dslextreme.com/users/billw/gkrellm/gkrellm.html"
wikipedia_gkrellmd="http://en.wikipedia.org/wiki/Gkrellm"

title_GRE="Generic Routing Encapsulation"
wikipedia_GRE="http://en.wikipedia.org/wiki/Generic_Routing_Encapsulation"
service_GRE_notes="
This service matches just the protocol. For full VPN functionality additional services may be needed (such as <a href=\"#pptp\">pptp</a>)"

home_heartbeat="http://www.linux-ha.org/"
service_heartbeat_notes="
This FireHOL service has been designed such a way that it will allow multiple heartbeat clusters on the same LAN.
"

wikipedia_h323="http://en.wikipedia.org/wiki/H323"

title_http="Hypertext Transfer Protocol"
wikipedia_http="http://en.wikipedia.org/wiki/Http"

title_https="Secure Hypertext Transfer Protocol"
wikipedia_https="http://en.wikipedia.org/wiki/Https"

home_hylafax="http://www.hylafax.org"
wikipedia_hylafax="http://en.wikipedia.org/wiki/Hylafax"
server_hylafax_ports="many"
client_hylafax_ports="many"
service_hylafax_type="complex"
service_hylafax_notes="
This complex service allows incomming requests to server port tcp/4559 and outgoing <b>from</b> server port tcp/4558.
<p>
<b>The correct operation of this service has not been verified.</b>
<p>
<b>USE THIS WITH CARE. A HYLAFAX CLIENT MAY OPEN ALL TCP UNPRIVILEGED PORTS TO ANYONE</b> (from port tcp/4558).
"

title_iax="Inter-Asterisk eXchange"
wikipedia_iax="http://en.wikipedia.org/wiki/Iax"
home_iax="http://www.asterisk.org"
service_iax_notes="
This service refers to IAX version 1. There is also the <a href=\"#iax2\">iax2</a> service.<p>
"

title_iax2="Inter-Asterisk eXchange"
wikipedia_iax2="http://en.wikipedia.org/wiki/Iax"
home_iax2="http://www.asterisk.org"
service_iax2_notes="
This service refers to IAX version 2. There is also the <a href=\"#iax\">iax</a> service.<p>
"

title_ICMP="Internet Control Message Protocol"
wikipedia_ICMP="http://en.wikipedia.org/wiki/Internet_Control_Message_Protocol"

title_icmp="${title_ICMP}"
wikipedia_icmp="${wikipedia_ICMP}"

title_icp="Internet Cache Protocol"
wikipedia_icp="http://en.wikipedia.org/wiki/Internet_Cache_Protocol"

wikipedia_ident="http://en.wikipedia.org/wiki/Ident"
service_ident_example="server ident reject with tcp-reset"

title_imap="Internet Message Access Protocol"
wikipedia_imap="http://en.wikipedia.org/wiki/Imap"

title_imaps="Secure Internet Message Access Protocol"
wikipedia_imaps="http://en.wikipedia.org/wiki/Imap"

title_ipsecnatt="NAT traversal and IPsec"
wikipedia_ipsecnatt="http://en.wikipedia.org/wiki/NAT_traversal#NAT_traversal_and_IPsec"

title_irc="Internet Relay Chat"
wikipedia_irc="http://en.wikipedia.org/wiki/Internet_Relay_Chat"

title_isakmp="Internet Security Association and Key Management Protocol"
wikipedia_isakmp="http://en.wikipedia.org/wiki/ISAKMP"
service_isakmp_notes="IPSec key negotiation (IKE on UDP port 500).
<p>
For more information see the <a href=\"http://www.freeswan.org/freeswan_trees/freeswan-1.99/doc/quickstart-firewall.html#quick_firewall\">FreeS/WAN documentation</a>.
"

title_jabber="Extensible Messaging and Presence Protocol"
wikipedia_jabber="http://en.wikipedia.org/wiki/Jabber"
service_jabber_notes="
Clear and SSL client-to-server connections.
"

title_jabberd="Extensible Messaging and Presence Protocol"
wikipedia_jabberd="http://en.wikipedia.org/wiki/Jabber"
service_jabberd_notes="
Clear and SSL jabber client-to-server and server-to-server connections.
<p>
Use this service for a jabberd server. In all other cases, use the <a href=\"#jabber\">jabber</a> service.
"

title_l2tp="Layer 2 Tunneling Protocol"
wikipedia_l2tp="http://en.wikipedia.org/wiki/L2tp"

title_ldap="Lightweight Directory Access Protocol"
wikipedia_ldap="http://en.wikipedia.org/wiki/Ldap"

title_ldaps="Lightweight Directory Access Protocol"
wikipedia_ldaps="http://en.wikipedia.org/wiki/Ldap"

title_lpd="Line Printer Daemon protocol"
wikipedia_lpd="http://en.wikipedia.org/wiki/Line_Printer_Daemon_protocol"
service_lpd_notes="
LPD is documented in <a href=\"http://www.ietf.org/rfc/rfc1179.txt?number=1179\">RFC 1179</a>.
<p>
Since many operating systems are incorrectly using non-default client ports for LPD access, this
definition allows any client port to access the service (additionally to the RFC defined 721 to 731 inclusive)."


service_microsoft_ds_notes="
Direct Hosted (i.e. NETBIOS-less SMB)
<p>
This is another NETBIOS Session Service with minor differences with <a href=\"#netbios_ssn\">netbios_ssn</a>.
It is supported only by Windows 2000 and Windows XP and it offers the advantage of being indepedent of WINS
for name resolution.
<p>
It seems that samba supports transparently this protocol on the <a href=\"#netbios_ssn\">netbios_ssn</a> ports,
so that either direct hosted or traditional SMB can be served simultaneously.
<p>
Please refer to the <a href=\"#netbios_ssn\">netbios_ssn</a> service for more information.
"

title_mms="Microsoft Media Server"
wikipedia_mms="http://en.wikipedia.org/wiki/Microsoft_Media_Server"
service_mms_notes="
Microsoft's proprietary network streaming protocol used to transfer unicast data in Windows Media Services (previously called NetShow Services). MMS can be transported via UDP or TCP. The MMS default port is UDP/TCP 1755.
"

service_ms_ds_notes="
Direct Hosted (i.e. NETBIOS-less SMB)
<p>
This is another NETBIOS Session Service with minor differences with <a href=\"#netbios_ssn\">netbios_ssn</a>.
It is supported only by Windows 2000 and Windows XP and it offers the advantage of being indepedent of WINS
for name resolution.
<p>
It seems that samba supports transparently this protocol on the <a href=\"#netbios_ssn\">netbios_ssn</a> ports,
so that either direct hosted or traditional SMB can be served simultaneously.
<p>
Please refer to the <a href=\"#netbios_ssn\">netbios_ssn</a> service for more information.
"

service_msn_notes="
Microsoft MSN Messenger Service<p>
For a discussion about what works and what is not, please take a look at
<A HREF=\"http://www.microsoft.com/technet/treeview/default.asp?url=/technet/prodtechnol/winxppro/evaluate/worki01.asp\">this technet note</A>.
"

wikipedia_multicast="http://en.wikipedia.org/wiki/Multicast"
server_multicast_ports="N/A"
client_multicast_ports="N/A"
service_multicast_type="complex"
service_multicast_notes="
The multicast service matches all packets send to 224.0.0.0/4 using IGMP or UDP.
"
service_multicast_example="server multicast reject with proto-unreach"

home_mysql="http://www.mysql.com/"
wikipedia_mysql="http://en.wikipedia.org/wiki/Mysql"

wikipedia_netbackup="http://en.wikipedia.org/wiki/Netbackup"
service_netbackup_notes="
This is the Veritas NetBackup service. To use this service you must define it
as both client and server in NetBackup clients and NetBackup servers."
service_netbackup_example="server netbackup accept<br>client netbackup accept"

title_netbios_ns="NETBIOS Name Service"
wikipedia_netbios_ns="http://en.wikipedia.org/wiki/Netbios#Name_service"
service_netbios_ns_notes="
See also the <a href=\"#samba\">samba</a> service.
"

title_netbios_dgm="NETBIOS Datagram Distribution Service"
wikipedia_netbios_dgm="http://en.wikipedia.org/wiki/Netbios#Datagram_distribution_service"
service_netbios_dgm_notes="
See also the <a href=\"#samba\">samba</a> service.
<p>
Keep in mind that this service broadcasts (to the broadcast address of your LAN) UDP packets.
If you place this service within an interface that has a <b>dst</b> parameter, remember to
include (in the <b>dst</b> parameter) the broadcast address of your LAN too.
"

title_netbios_ssn="NETBIOS Session Service"
wikipedia_netbios_ssn="http://en.wikipedia.org/wiki/Netbios#Session_service"
service_netbios_ssn_notes="
See also the <a href=\"#samba\">samba</a> service.
<p>
Please keep in mind that newer NETBIOS clients prefer to use port 445 (<a href=\"#microsoft_ds\">microsoft_ds</a>)
for the NETBIOS session service, and when this is not available they fall back to port 139 (netbios_ssn).
Versions of samba above 3.x bind automatically to ports 139 and 445.
<p>
If you have an older samba version and your policy on an interface or router is <b>DROP</b>, clients trying to
access port 445 will have to timeout before falling back to port 139. This timeout can be up to several minutes.
<p>
To overcome this problem either explicitly <b>REJECT</b> the <a href=\"#microsoft_ds\">microsoft_ds</a> service
with a tcp-reset message (<b>server microsoft_ds reject with tcp-reset</b>),
or redirect port 445 to port 139 using the following rule (put it all-in-one-line at the top of your FireHOL config):
<p>
<b>
iptables -t nat -A PREROUTING -i eth0 -p tcp -s 1.1.1.1/24 --dport 445 -d 2.2.2.2 -j REDIRECT --to-port 139
<p>
</b>or<b>
<p>
redirect to 139 inface eth0 src 1.1.1.1/24 proto tcp dst 2.2.2.2 dport 445
</b><p>
where:
<ul>
	<li><b>eth0</b> is the network interface your NETBIOS server uses
	<br>&nbsp;
	</li>
	<li><b>1.1.1.1/24</b> is the subnet matching all the clients IP addresses
	<br>&nbsp;
	</li>
	<li><b>2.2.2.2</b> is the IP of your linux server on eth0 (or whatever you set the first one above)
	</li>
</ul>
"

title_nfs="Network File System"
wikipedia_nfs="http://en.wikipedia.org/wiki/Network_File_System_%28protocol%29"
server_nfs_ports="many"
client_nfs_ports="500:65535"
service_nfs_type="complex"
service_nfs_notes="
The NFS service queries the RPC service on the NFS server host to find out the ports <b>nfsd</b>, <b>mountd</b>, <b>lockd</b> and <b>rquotad</b> are listening.
Then, according to these ports it sets up rules on all the supported protocols (as reported by RPC) in order the
clients to be able to reach the server.
<p>
For this reason, the NFS service requires that:
<ul>
	<li>the firewall is restarted if the NFS server is restarted</li>
	<li>the NFS server must be specified on all nfs statements (only if it is not the localhost)</li>
</ul>
Since NFS queries the remote RPC server, it is required to also be allowed to do so, by allowing the
<a href=\"#portmap\">portmap</a> service too. Take care, that this is allowed by the <b>running firewall</b>
when FireHOL tries to query the RPC server. So you might have to setup NFS in two steps: First add the portmap
service and activate the firewall, then add the NFS service and restart the firewall.
<p>
To avoid this you can setup your NFS server to listen on pre-defined ports, as it is well documented in
<a href=\"http://nfs.sourceforge.net/nfs-howto/ar01s06.html#srv_security_nfsd_mountd\">http://nfs.sourceforge.net/nfs-howto/ar01s06.html#srv_security_nfsd_mountd</a>.
If you do this then you will have to define the the ports using the procedure described in <a href=\"adding.html\">Adding Services</a>.
"
service_nfs_example="client nfs accept <u>dst</u> <u>1.2.3.4</u>"

title_nis="Network Information Service"
wikipedia_nis="http://en.wikipedia.org/wiki/Network_Information_Service"
server_nis_ports="many"
client_nis_ports="500:65535"
service_nis_type="complex"
service_nis_notes="
The nis service queries the RPC service on the nis server host to find out the ports <b>ypserv</b> and <b>yppasswdd</b> are listening.
Then, according to these ports it sets up rules on all the supported protocols (as reported by RPC) in order the
clients to be able to reach the server.
<p>
For this reason, the nis service requires that:
<ul>
	<li>the firewall is restarted if the nis server is restarted</li>
	<li>the nis server must be specified on all nis statements (only if it is not the localhost)</li>
</ul>
Since nis queries the remote RPC server, it is required to also be allowed to do so, by allowing the
<a href=\"#portmap\">portmap</a> service too. Take care, that this is allowed by the <b>running firewall</b>
when FireHOL tries to query the RPC server. So you might have to setup nis in two steps: First add the portmap
service and activate the firewall, then add the nis service and restart the firewall.
<p>
This service has been created by <a href=\"https://sourceforge.net/tracker/?func=detail&atid=487695&aid=1050951&group_id=58425\">Carlos Rodrigues</a>.
His comments regarding this implementation, are:
<p>
<b>These rules work for client access only!</b>
<p>
Pushing changes to slave servers won't work if these rules are active
somewhere between the master and its slaves, because it is impossible to
predict the ports where <b>yppush</b> will be listening on each push.
<p>
Pulling changes directly on the slaves will work, and could be improved
performance-wise if these rules are modified to open <b>fypxfrd</b>. This wasn't
done because it doesn't make that much sense since pushing changes on the
master server is the most common, and recommended, way to replicate maps.
"
service_nis_example="client nis accept <u>dst</u> <u>1.2.3.4</u>"

title_nntp="Network News Transfer Protocol"
wikipedia_nntp="http://en.wikipedia.org/wiki/Nntp"

title_nntps="Secure Network News Transfer Protocol"
wikipedia_nntps="http://en.wikipedia.org/wiki/Nntp"

title_ntp="Network Time Protocol"
wikipedia_ntp="http://en.wikipedia.org/wiki/Network_Time_Protocol"

title_nut="Network UPS Tools"
home_nut="http://networkupstools.org/"

wikipedia_nxserver="http://en.wikipedia.org/wiki/NX_Server"
service_nxserver_notes="
Default ports used by NX server for connections without encryption.<br>
Note that nxserver also needs the <a href=\"#ssh\">ssh</a> service to be enabled.<p>
The TCP ports used by nxserver is 4000 + DISPLAY_BASE to 4000 + DISPLAY_BASE + DISPLAY_LIMIT.
DISPLAY_BASE and DISPLAY_LIMIT are set in /usr/NX/etc/node.conf and the defaults are DISPLAY_BASE=1000
and DISPLAY_LIMIT=200.<p>
For encrypted nxserver sessions, only <a href=\"#ssh\">ssh</a> is needed.
"

title_oracle="Oracle Database"
wikipedia_oracle="http://en.wikipedia.org/wiki/Oracle_db"

title_ospf="Open Shortest Path First"
wikipedia_ospf="http://en.wikipedia.org/wiki/Ospf"

wikipedia_ping="http://en.wikipedia.org/wiki/Ping"
server_ping_ports="N/A"
client_ping_ports="N/A"
service_ping_type="complex"
service_ping_notes="
This services matches requests of protocol <b>ICMP</b> and type <b>echo-request</b> (TYPE=8)
and their replies of type <b>echo-reply</b> (TYPE=0).
<p>
The <b>ping</b> service is stateful.
"

title_pop3="Post Office Protocol"
wikipedia_pop3="http://en.wikipedia.org/wiki/Pop3"

title_pop3s="Secure Post Office Protocol"
wikipedia_pop3s="http://en.wikipedia.org/wiki/Pop3"

title_portmap="Open Network Computing Remote Procedure Call - Port Mapper"
wikipedia_portmap="http://en.wikipedia.org/wiki/Portmap"

title_postgres="PostgreSQL"
wikipedia_postgres="http://en.wikipedia.org/wiki/Postgres"

title_pptp="Point-to-Point Tunneling Protocol"
wikipedia_pptp="http://en.wikipedia.org/wiki/Pptp"

home_privoxy="http://www.privoxy.org/"

title_radius="Remote Authentication Dial In User Service (RADIUS)"
wikipedia_radius="http://en.wikipedia.org/wiki/RADIUS"

title_radiusold="Remote Authentication Dial In User Service (RADIUS)"
wikipedia_radiusold="http://en.wikipedia.org/wiki/RADIUS"

title_radiusoldproxy="Remote Authentication Dial In User Service (RADIUS)"
wikipedia_radiusoldproxy="http://en.wikipedia.org/wiki/RADIUS"

title_radiusproxy="Remote Authentication Dial In User Service (RADIUS)"
wikipedia_radiusproxy="http://en.wikipedia.org/wiki/RADIUS"

title_rdp="Remote Desktop Protocol (also known as Terminal Services)"
wikipedia_rdp="http://en.wikipedia.org/wiki/Remote_Desktop_Protocol"

title_rndc="Remote Name Daemon Control"
wikipedia_rndc="http://en.wikipedia.org/wiki/Rndc"

home_rsync="http://rsync.samba.org/"
wikipedia_rsync="http://en.wikipedia.org/wiki/Rsync"

title_rtp="Real-time Transport Protocol"
wikipedia_rtp="http://en.wikipedia.org/wiki/Real-time_Transport_Protocol"
service_rtp_notes="
RTP ports are generally all the UDP ports. This definition narrows down RTP ports to UDP 10000 to 20000.
"

server_samba_ports="many"
client_samba_ports="default"
service_samba_type="complex"
service_samba_notes="
The samba service automatically sets all the rules for <a href=\"#netbios_ns\">netbios_ns</a>, <a href=\"#netbios_dgm\">netbios_dgm</a>, <a href=\"#netbios_ssn\">netbios_ssn</a> and <a href=\"#microsoft_ds\">microsoft_ds</a>.
<p>
Please refer to the notes of the above services for more information.
<p>
NETBIOS initiates based on the broadcast address of an interface (request goes to broadcast address) but the server responds from
its own IP address. This makes the <b>server samba accept</b> statement drop the server reply, because of the way the iptables connection tracker works.
<p>
This service definition includes a hack, that allows a linux samba server to respond correctly in such situations, by allowing new outgoing connections
from the well known <a href=\"#netbios_ns\">netbios_ns</a> port to the clients high ports.
<p>
<b>However, for clients and routers this hack is not applied because it would open all unpriviliged ports to the samba server.</b>
The only solution to overcome the problem in such cases (routers or clients) is to build a trust relationship between the samba servers and clients.
"

service_sip_notes="
<a href=\"http://www.voip-info.org/wiki-SIP\">SIP</a> is the Session Initiation Protocol,
an IETF standard protocol (RFC 2543) for initiating interactive user sessions involving
multimedia elements such as video, voice, chat, gaming, etc.
SIP works in the application layer of the OSI communications model.
"

service_stun_notes="
<a href=\"http://www.voip-info.org/wiki-STUN\">STUN</a> is a protocol for assisting devices behind a NAT firewall or router with their packet routing.
"

server_timestamp_ports="N/A"
client_timestamp_ports="N/A"
service_timestamp_type="complex"
service_timestamp_notes="
This services matches requests of protocol <b>ICMP</b> and type <b>timestamp-request</b> (TYPE=13)
and their replies of type <b>timestamp-reply</b> (TYPE=14).
<p>
The <b>timestamp</b> service is stateful.
"

service_upnp_notes="
<a href=\"http://upnp.sourceforge.net/\">UPNP</a> is Univeral Plug and Play.<p>
For a linux implementation check: <a href=\"http://linux-igd.sourceforge.net/\">Linux IGD</a>.
"

service_whois_notes="See: <a href=\"http://www.busan.edu/~nic/networking/firewall/ch08_08.htm\">O'Reilly's Building Internet Firewalls book</a> about whois and firewalls."

service_webmin_notes="<a href=\"http://www.webmin.com\">Webmin</a> is a web-based interface for system administration for Unix."

service_xdmcp_notes="
<b>X Display Manager Control Protocol</b><br>
See <a href=\"http://www.jirka.org/gdm-documentation/x70.html\">http://www.jirka.org/gdm-documentation/x70.html</a> for a discussion about XDMCP and firewalls
(this is about Gnome Display Manager, a replacement of XDM).
"

# ---------------------------------------------------------------------------------------------------------------

scount=0
print_service() {
	scount=$[scount + 1]
	
	if [ $scount -gt 1 ]
	then
		color=' bgcolor="#F0F0F0"'
		scount=0
	else
		color=""
	fi
	
	local service="${1}";	shift
	local type="${1}";	shift
	local sports="${1}";	shift
	local dports="${1}";	shift
	local mods="${1}";	shift
	local title="${1}";	shift
	local home="${1}";	shift
	local wiki="${1}";	shift
	local example="${1}";	shift
	local notes="${*}"
	
cat <<EOF
<tr ${color}>
	<td align="center" valign="top"><a name="${service}"><b>${service}</b></a></td>
	<td align="center" valign="top">${type}</td>
	<td>
		<table cellspacing=0 cellpadding=5 border=0>
		<tr>
EOF
	echo "<td align=right valign=middle nowrap width=150><small><font color="gray">Server Ports</td><td>"
	c=0
	for x in ${sports}
	do
		if [ $c -ne 0 ]
		then
			echo ", "
		fi
		
		echo "<b>${x}</b>"
		c=$[c + 1]
	done
	
	echo "</td></tr><tr><td align=right valign=middle nowrap><small><font color="gray">Client Ports</td><td>"
	c=0
	for x in ${dports}
	do
		if [ $c -ne 0 ]
		then
			echo ", "
		fi
		
		echo "<b>${x}</b>"
		c=$[c + 1]
	done
	
	if [ ! -z "${mods}" ]
	then
	
		echo "</td></tr><tr><td align=right valign=middle nowrap><small><font color="gray">Netfilter Modules</td><td>"
		c=0
		for x in ${mods}
		do
			if [ $c -ne 0 ]
			then
				echo ",<br> "
			fi
		
			local kv="NF_CONNTRACK_`echo ${x} | tr [a-z] [A-Z]`"
			test "${kv}" = "NF_CONNTRACK_PROTO_GRE" && local kv="NF_CT_PROTO_GRE"
			
			echo "<font color=red><b>${x}</b></font> (<a href=\"http://cateee.net/lkddb/web-lkddb/${kv}.html\">CONFIG_${kv}</a>)"
			c=$[c + 1]
		done
	
		echo "</td></tr><tr><td align=right valign=middle nowrap><small><font color="gray">Netfilter NAT Modules</td><td>"
		c=0
		for x in ${mods}
		do
			case "${x}" in
				netbios_ns|netlink|sane)
					# these do not exist in nat
					continue
					;;
			esac
			
			if [ $c -ne 0 ]
			then
				echo ",<br>"
			fi
		
			local kv="NF_NAT_`echo ${x} | tr [a-z] [A-Z]`"
			echo "<font color=red><b>${x}</b></font> (<a href=\"http://cateee.net/lkddb/web-lkddb/${kv}.html\">CONFIG_${kv}</a>)"
			c=$[c + 1]
		done
	
		echo "</td></tr>"
	fi
	
	if [ ! -z "${home}" ]
	then
		echo "<tr><td align=right valign=middle nowrap><small><font color=\"gray\">Official Site</td><td><a href=\"${home}\">${title} Home</a></td></tr>"
	fi
	
	if [ ! -z "${wiki}" ]
	then
		echo "<tr><td align=right valign=middle nowrap><small><font color=\"gray\">Wikipedia</td><td><a href=\"${wiki}\">${title} in Wikipedia</a></td></tr>"
	fi
	
	# echo "<tr><td align=right valign=middle nowrap><small><font color=\"gray\">Google Search</td><td><a href=\"http://www.google.com/search?q=${service}+iptables+firewall+ports&hl=en&num=10&lr=&ft=i&tbs=qdr:y&cr=&safe=off\">${title} in Google</a></td></tr>"
	
cat <<EOF
	<tr><td align=right valign=top nowrap><small><font color="gray">Notes</td><td>${notes}<br>&nbsp;</td></tr>
	<tr><td align=right valign=top nowrap><small><font color="gray">Example</td><td><b>${example}</b></td></tr>
	</table>
	</td>
	</tr>
EOF
}

smart_print_service() {
	local server="${1}"
	
	local server_varname="server_${server}_ports"
	local server_ports="`eval echo \\\$${server_varname}`"
	
	local client_varname="client_${server}_ports"
	local client_ports="`eval echo \\\$${client_varname}`"
	
	local mods_varname="helper_${server}"
	local require_modules="`eval echo \\\$${mods_varname}`"
	
	local notes_varname="service_${server}_notes"
	local notes="`eval echo \\\$${notes_varname}`"
	
	local type_varname="service_${server}_type"
	local type="`eval echo \\\$${type_varname}`"
	
	local title_varname="title_${server}"
	local title="`eval echo \\\$${title_varname}`"
	
	local wiki_varname="wikipedia_${server}"
	local wiki="`eval echo \\\$${wiki_varname}`"
	
	local home_varname="home_${server}"
	local home="`eval echo \\\$${home_varname}`"
	
	if [ -z "${title}" ]
	then
		title="${server}"
	fi
	
	if [ -z "${type}" ]
	then
		local type="simple"
	fi
	
	local example_varname="service_${server}_example"
	local example="`eval echo \\\$${example_varname}`"
	
	if [ -z "${example}" ]
	then
		local example="server ${server} accept"
	fi
	
	print_service "${server}" "${type}" "${server_ports}" "${client_ports}" "${require_modules}" "${title}" "${home}" "${wiki}" "${example}" "${notes}"
}



tmp="/tmp/services.$$"

# The simple services
cat "../firehol.sh"			|\
	grep -e "^server_.*_ports=" >"${tmp}"

cat "../firehol.sh"			|\
	grep -e "^client_.*_ports=" >>"${tmp}"

cat "../firehol.sh"			|\
	grep -e "^service_.*_notes=" >>"${tmp}"

cat "../firehol.sh"			|\
	grep -e "^helper_.*=" >>"${tmp}"

. "${tmp}"
rm -f "${tmp}"

all_services() {
	(
		cat "../firehol.sh"			|\
			grep -e "^server_.*_ports="	|\
			cut -d '=' -f 1			|\
			sed "s/^server_//"		|\
			sed "s/_ports\$//"
			
		cat "../firehol.sh"			|\
			grep -e "^rules_.*()"		|\
			cut -d '(' -f 1			|\
			sed "s/^rules_//"
	) | sort -f | uniq
}



# header
cat <<"EOF"
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN">
<HTML>
<HEAD>
<link rel="stylesheet" type="text/css" href="css.css">
<TITLE>FireHOL, Pre-defined service definitions.</TITLE>
<meta name="author" content="Costa Tsaousis">
<meta name="description" content="

Home for FireHOL, an iptables stateful packet filtering firewall builder for Linux (kernel 2.4),
supporting NAT, SNAT, DNAT, REDIRECT, MASQUERADE, DMZ, dual-homed, multi-homed and router setups,
protecting and securing hosts and LANs in all kinds of topologies. Configuration is done using
simple client and server statements while it can detect (and produce) its configuration
automatically. FireHOL is extremely easy to understand, configure and audit.

">

<meta name="keywords" content="iptables, netfilter, filter, firewall, stateful, port, secure, security, NAT, DMZ, DNAT, DSL, SNAT, redirect, router, rule, rules, automated, bash, block, builder, cable, complex, configuration, dual-homed, easy, easy configuration, example, fast, features, flexible, forward, free, gpl, helpme mode, human, intuitive, language, linux, masquerade, modem, multi-homed, open source, packet, panic mode, protect, script, service, system administration, wizard">
<meta http-equiv="Expires" content="Wed, 19 Mar 2003 00:00:01 GMT">
</HEAD>

<BODY bgcolor="#FFFFFF">

<center>
<script type="text/javascript"><!--
google_ad_client = "pub-4254040714325099";
google_ad_width = 728;
google_ad_height = 90;
google_ad_format = "728x90_as";
google_ad_channel ="";
google_page_url = document.location;
google_color_border = "336699";
google_color_bg = "FFFFFF";
google_color_link = "0000FF";
google_color_url = "008000";
google_color_text = "000000";
//--></script>
<script type="text/javascript"
  src="http://pagead2.googlesyndication.com/pagead/show_ads.js">
</script>
</center>
<p>

Bellow is the list of FireHOL supported services. You can overwrite all the services (including those marked as complex) with the
procedures defined in <a href="adding.html">Adding Services</a>.
<p>
In case you have problems with some service because it is defined by its port names instead of its port numbers, you can find the
required port numbers at <a href="http://www.graffiti.com/services">http://www.graffiti.com/services</a>.
<p>
Please report problems related to port names usage. I will replace the faulty names with the relative numbers to eliminate this problem.
All the services defined by name in FireHOL are known to resolve in <a href="http://www.redhat.com">RedHat</a> systems 7.x and 8.
<p>
<center>
<hr noshade size=1>
<table border=0 cellspacing=3 cellpadding=5 width="80%">
<tr>
EOF

lc=0
last_letter=
do_letter() {
	if [ ! -z "${last_letter}" ]
	then
		echo "</td></tr></table></td>"
		echo >&2 "Closing ${last_letter}"
		last_letter=
	fi
	
	if [ ! -z "${1}" ]
	then
		lc=$[lc + 1]
		if [ $lc -eq 5 ]
		then
			echo "</tr><tr>"
			echo >&2 "--- break ---"
			lc=1
		fi
		
		printf >&2 "Openning ${1}... "
		last_letter=${1}
		
		echo "
<td width=\"25%\" align=left valign=top>
	<table border=0 cellpadding=10 cellspacing=5 width=\"100%\">
	<tr><td align=left valign=top><font color=\"gray\" size=+1><b>${last_letter}</td></tr>
	<tr><td align=left valign=top><small>
"
	fi
}

all_services |\
	(
		last=
		t=0
		while read
		do
			first=`echo ${REPLY:0:1} | tr "[a-z]" "[A-Z]"`
			
			while [ ! "$first" = "$last" ]
			do
				# echo >&2 "F:$first L:$last"
				
				t=0
				case "$last" in
					A)	last=B
						test "$first" = "$last" && do_letter $last
						;;
					B)	last=C
						test "$first" = "$last" && do_letter $last
						;;
					C)	last=D
						test "$first" = "$last" && do_letter $last
						;;
					D)	last=E
						test "$first" = "$last" && do_letter $last
						;;
					E)	last=F
						test "$first" = "$last" && do_letter $last
						;;
					F)	last=G
						test "$first" = "$last" && do_letter $last
						;;
					G)	last=H
						test "$first" = "$last" && do_letter $last
						;;
					H)	last=I
						test "$first" = "$last" && do_letter $last
						;;
					I)	last=J
						test "$first" = "$last" && do_letter $last
						;;
					J)	last=K
						test "$first" = "$last" && do_letter $last
						;;
					K)	last=L
						test "$first" = "$last" && do_letter $last
						;;
					L)	last=M
						test "$first" = "$last" && do_letter $last
						;;
					M)	last=N
						test "$first" = "$last" && do_letter $last
						;;
					N)	last=O
						test "$first" = "$last" && do_letter $last
						;;
					O)	last=P
						test "$first" = "$last" && do_letter $last
						;;
					P)	last=Q
						test "$first" = "$last" && do_letter $last
						;;
					Q)	last=R
						test "$first" = "$last" && do_letter $last
						;;
					R)	last=S
						test "$first" = "$last" && do_letter $last
						;;
					S)	last=T
						test "$first" = "$last" && do_letter $last
						;;
					T)	last=U
						test "$first" = "$last" && do_letter $last
						;;
					U)	last=V
						test "$first" = "$last" && do_letter $last
						;;
					V)	last=W
						test "$first" = "$last" && do_letter $last
						;;
					W)	last=X
						test "$first" = "$last" && do_letter $last
						;;
					X)	last=Y
						test "$first" = "$last" && do_letter $last
						;;
					Y)	last=Z
						test "$first" = "$last" && do_letter $last
						;;
					Z)	echo >&2 "internal error"
						exit 1
						;;
					*)	last=A
						test "$first" = "$last" && do_letter $last
						;;
				esac
			done
			
			t=$[t + 1]
			test $t -gt 1 && printf ", "
			printf "<a href=\"#$REPLY\">$REPLY</a>"
		done
		do_letter ""
	)


cat <<"EOF"
</tr></table>
<hr noshade size=1>
<p>
<table border=0 cellspacing=5 cellpadding=10 width="80%">
<tr bgcolor="#EEEEEE"><th>Service</th><th>Type</th><th>Description</th></tr>
EOF


all_services |\
	(
		while read
		do
			smart_print_service $REPLY
		done
	)


cat <<"EOF"
</table>
</center>
<p>
<hr noshade size=1>
<table border=0 width="100%">
<tr><td align=center valign=middle>
	<A href="http://sourceforge.net"><IMG src="http://sourceforge.net/sflogo.php?group_id=58425&amp;type=5" width="210" height="62" border="0" alt="SourceForge Logo"></A>
</td><td align=center valign=middle>
	<small>$Id: create_services.sh,v 1.58 2013/01/06 23:49:08 ktsaou Exp $</small>
	<p>
	<b>FireHOL</b>, a firewall for humans...<br>
	&copy; Copyright 2004
	Costa Tsaousis <a href="mailto: costa@tsaousis.gr">&lt;costa@tsaousis.gr&gt</a>
</body>
</html>
EOF
