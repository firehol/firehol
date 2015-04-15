% firehol-synproxy(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-synproxy - configure synproxy

<!--
contents-table:helper:synproxy:keyword-firehol-synproxy:Y:-:Configure synproxy.
extra-manpage: firehol-synproxy4.5
extra-manpage: firehol-synproxy6.5
-->

# SYNOPSIS 

synproxy *type* *rules-to-match-request* *action* [*action options*]


# DESCRIPTION

- **type** defines where the SYNPROXY will be attached. It can be `input` (or `in`), `forward` (or `pass`):
    - use `input` (or `in`) when the IP of the real server is an IP assigned to a physical interface of the machine (i.e. the IP is at the firewall itself)
    - use `forward` (or `pass`) when the IP of the real server is routed by the machine (i.e. SYNPROXY should look at the FORWARD chain for this traffic).

- `rules to match request` are FireHOL optional rule parameters and should match the original client REQUEST, before any destination NAT. `inface` and `dst` are required:

    - `inface` is one or more interfaces the REQUEST should be received from
    - `dst` is the IP of the real server, as seen by the client (before any destination NAT)

- **action** defines how SYNPROXY will reach the real server and can be:

    - `accept` to just allow the REQUEST reach the real server without any destination NAT

    - `dnat to IP:PORT` or `dnat to IP1-IP2:PORT1-PORT2` or `dnat to IP` or `dnat to :PORT` to have SYNPROXY reach a server on another machine in a DMZ (different IP and/or PORT compared to the original request). The synproxy statement supports everything supported by the dnat helper (see [firehol-nat(5)][]).
 
    - `redirect to PORT` to divert the request to a port on the firewall itself. The synproxy statement supports everything supported by the redirect helper (see [firehol-nat(5)][]).
 
    - `action CUSTOM_ACTION` to have any other FireHOL action performed on the NEW socket. Use the `action` helper to define custom actions (see [firehol-action(5)][]).

    - `action options` are everything supported by FireHOL optional rule parameters that should be applied only on the final action of SYN packet from SYNPROXY to the real server. For example this can be used to append `loglimit "TEXT"`  to have something logged by iptables, or limit the concurrent sockets with `connlimit`. Generally, everything you can write on the same line after `server http accept` is also accepted here.


# BACKGROUND

SYNPROXY is a TCP SYN packets proxy. It can be used to protect any TCP server (like a web server) from SYN floods and similar DDos attacks.

SYNPROXY is a netfilter module, in the Linux kernel. It is optimized to handle millions of packets per second utilizing all CPUs available without any concurrency locking between the connections.

The net effect of this, is that the real servers will not notice any change during the attack. The valid TCP connections will pass through and served, while the attack will be stopped at the firewall.

For more information on why you should use a SYNPROXY, check these articles:

- http://rhelblog.redhat.com/2014/04/11/mitigate-tcp-syn-flood-attacks-with-red-hat-enterprise-linux-7-beta/
- https://r00t-services.net/knowledgebase/14/Homemade-DDoS-Protection-Using-IPTables-SYNPROXY.html

SYNPROXY is included in the Linux kernels since version 3.12.


# HOW IT WORKS

* When a SYNPROXY is used, clients transparently get connected to the SYNPROXY. So the 3-way TCP handshake  happens first between the client and the SYNPROXY:

    * Clients send TCP SYN to server A
    * At the firewall, when this packet arrives it is marked as UNTRACKED
    * The UNTRACKED TCP SYN packet is then given to SYNPROXY
    * SYNPROXY gets this and responds (as server A) with TCP SYN+ACK (UNTRACKED)
    * Client responds with TCP ACK (marked as INVALID or UNTRACKED in iptables) which is also given to SYNPROXY

* Once a client has been connected to the SYNPROXY, SYNPROXY automatically initiates a 3-way TCP handshake with the real server, spoofing the SYN packet so that the real server will see that the original client is attempting to connect:

    * SYNPROXY sends TCP SYN to real server A. This is a NEW connection in iptables and happens on the OUTPUT chain. The source IP of the packet is the IP of the client
    * The real server A responds with SYN+ACK to the client
    * SYNPROXY receives this and responds back to the server with ACK. The connection is now marked as ESTABLISHED

* Once the connection has been established, SYNPROXY leaves the traffic flow between the client and the server

So, SYNPROXY can be used for any kind of TCP traffic. It can be used for both unencrypted and encrypted traffic, since it does not interfere with the content itself.


# USE CASES

In FireHOL SYNPROXY support is implemented as a helper. The `synproxy` command can be used to set up any number of SYNPROXYs.

FireHOL can set up SYNPROXY for any of these cases:

1. **real server on the firewall itself, on the same port**
 (e.g. SYNPROXY on port 80, real server on port 80 too).
 
2. **real server on the firewall itself, on a different port**
 (e.g. SYNPROXY on port 2200, real server on port 22).
 
3. **real server on a different machine, without NAT**
 (e.g. SYNPROXY on a router catching traffic towards IP A, port 80 and real server is at IP A port 80 too).
 
4. **real server on a different machine, with NAT**
 (e.g. SYNPROXY on a router catching traffic towards IP A, port 80 and real server is at IP 10.1.1.1 port 90).
 
5. **screening incoming traffic that should never be sent to a real server**
 so that traps and dynamic blacklists can be created using traffic that has been screened by SYNPROXY (eliminate "internet noise" and spoofed packets).

So, generally, all cases are covered.


# DESIGN

The general guidelines for using `synproxy` in FireHOL, are:

1. **Design your firewall as you would normally do without SYNPROXY**
2. Test that it works without SYNPROXY. Test especially the servers you want to protect. They should be working too
3. Add `synproxy` statements for the servers you want to protect.

To achieve these requirements:

1. The helper will automatically do everything needed for SYNPROXY to:

	* receive the initial SYN packet from the client
	* respond back to the client with SYN+ACK
	* receive the first ACK packet from the client
	* send the initial SYN packet to the server

 There are cases where the above are very tricky to achieve. You don't need to match these in your `firehol.conf`. The `synproxy` helper will automatically take care of them.
 However:
 
   > You do need the allow the flow of traffic between the real server and the real client
   > (as you normally do without a `synproxy`, with a `client`, `server`, or `route` statement in an `interface` or `router` section).

2. The helper will prevent the 3-way TCP handshake between SYNPROXY and the real server interact with other **destination NAT** rules you may have. However for this to happen, make sure you place the `synproxy` statements above any destination NAT rules (`redirect`, `dnat`, `transparent_squid`, `transparent_proxy`, `tproxy`, etc).
 So:
 
   > SYNPROXY will interact with destination NAT you have in `firehol.conf` **only** if the `synproxy` statements are place below the destination NAT ones.
   > 
   > You normally do not need to have `synproxy` interact with other destination NAT rules. The `synproxy` helper will handle the destination NAT (`dnat` or `redirect`) it needs by itself.
   > 
   > So **place `synproxy` statements above all destination NAT statements, unless you know what you are doing**.

3. The helper will allow the 3-way TCP handshake between SYNPROXY and the real server interact with **source NAT** rules you may have (`snat`, `masquerade`), since these may be needed to reach the real server.


# LIMITATIONS

1. Internally there are matches that are made without taking into account the original `inface`. So, in case different actions have to be taken depending on the interface the request is received, `src` should be added to differentiate the traffic between the two flows.

2. SYNPROXY does not inherit MARKs from the original request packets. It should and it would make matching a lot easier, but it does not. This means that for all packets generated by SYNPROXY, `inface` is lost.

3. FireHOL internally uses a MARK to tag packets send from SYNPROXY to the target server. This is used for 3 reasons:

	- isolate these packets from other destination NAT rules. If they were not isolated from the destination NAT rules, then packets from the SYNPROXY could be matched by a transparent proxy and enter your web proxy. They could be matched by a transparent proxy because they actually originate from the local machine.

	- isolate the same packets from the rest of the packet filtering rules. Without this isolation, most probably the packets will have been dropped since they come from lo.

	- report if orphan synproxy packets are encountered. So packets the FireHOL engine failed to match properly, should appear with a iptables log saying "ORPHAN SYNPROXY->SERVER". If you don't have such logs, everything works as expected.


# OTHER OPTIONS

You can change the TCP options used by `synproxy` by setting the variable `FIREHOL_SYNPROXY_OPTIONS`. The default is this:

~~~
FIREHOL_SYNPROXY_OPTIONS="--sack-perm --timestamp --wscale 7 --mss 1460"
~~~

If you want to see it in action in the iptables log, then enable logging:

~~~
FIREHOL_SYNPROXY_LOG=1
~~~

The  default is disabled (0). If you enable it, every step of the 3-way setup between the client and SYNPROXY and the SYN packet of SYNPROXY towards the real server will be logged by iptables.

Using the variable `FIREHOL_CONNTRACK_LOOSE_MATCHING` you can set `net.netfilter.nf_conntrack_tcp_loose`. FireHOL will automatically set this to 0 when a synproxy is set up.

Using the variable `FIREHOL_TCP_TIMESTAMPS` you can set `net.ipv4.tcp_timestamps`.  FireHOL will automatically set this to 1 when a synproxy is set up.

Using the variable `FIREHOL_TCP_SYN_COOKIES` you can set `net.ipv4.tcp_syncookies`.  FireHOL will automatically set this to 1 when a synproxy is set up.

On a busy server, you are advised to increase the maximum connection tracker entries and its hash table size.

- Using the variable `FIREHOL_CONNTRACK_HASHSIZE` you can set `/sys/module/nf_conntrack/parameters/hashsize`.

- Using the variable `FIREHOL_CONNTRACK_MAX` you can set `net.netfilter.nf_conntrack_max`.

FireHOL will not alter these variables by itself.


# SYNPROXY AND DYNAMIC IP

By default the `synproxy` helper requires from you to define a `dst IP` of the server that is to be protected. This is required because the destination IP will be used to match the SYN packet the synproxy sends to the server.

There is however another way that allows the use of synproxy in environments where the IP of the server is unknown (like a dynamic IP DSL):

1. First you need to set `FIREHOL_SYNPROXY_EXCLUDE_OWNER=1`. This will make synproxy not match packets that are  generated by the local machine, even if the process that generates them uses your public IP (the packets in order to be matched they will need not have a UID or GID).

2. Next you will need to exclude you lan IPs by adding `src not "${UNROUTABLE_IPS}"` (or any other network you know you use) to the synproxy statement.



# EXAMPLES

Protect a web server running on the firewall with IP 1.2.3.4, from clients on eth0:

~~~
ipv4 synproxy input inface eth0 dst 1.2.3.4 dport 80 accept

interface eth0 wan
    server http accept
~~~

Protect a web server running on port 90 on the firewall with IP 1.2.3.4, from clients on eth0 that believe the web server is running on port 80:

~~~
server_myhttp_ports="tcp/90"
client_myhttp_ports="default"

ipv4 synproxy input inface eth0 dst 1.2.3.4 dport 80 redirect to 90

interface eth0 wan
    server myhttp accept # packet filtering works with the real ports
~~~

Protect a web server running on another machine (5.6.7.8), while the firewall is the router (without NAT):

~~~
ipv4 synproxy forward inface eth0 dst 5.6.7.8 dport 80 accept

router wan2lan inface eth0 outface eth1
    server http accept dst 5.6.7.8
~~~

Protect a web server running on another machine in a DMZ (public IP is 1.2.3.4 on eth0, web server IP is 10.1.1.1 on eth1):

~~~
ipv4 synproxy input inface eth0 \
    dst 1.2.3.4 dport 80 dnat to 10.1.1.1

router wan2lan inface eth0 outface eth1
    server http accept dst 10.1.1.1
~~~

Note that we used `input` not `forward`, because the firewall has the IP 1.2.3.4 on its eth0 interface. The client request is expected on input.

Protect an array of 10 web servers running on 10 other machines in a DMZ (public IP is 1.2.3.4 on eth0, web servers IPs are 10.1.1.1 to 10.1.1.10 on eth1):

~~~
ipv4 synproxy input inface eth0 \
    dst 1.2.3.4 dport 80 dnat to 10.1.1.1-10.1.1.10 persistent

router wan2lan inface eth0 outface eth1
    server http accept dst 10.1.1.1-10.1.1.10
~~~

The above configuration is a load balancer. Requests towards 1.2.3.4 port 80 will be distributed to the 10 web servers with persistence (each client will always see one of them).

Catch all traffic towards SSH port tcp/22 and send it to `TRAP_AND_DROP` as explained in [Working With Traps](Working-with-traps). At the same time, allow SSH on port tcp/2200 (without altering the ssh server):

~~~
 # definition of action TRAP_AND_DROP
 ipv4 action TRAP_AND_DROP sockets_suspects_trap 3600 86400 1 src not "${UNROUTABLE_IPS}" next action DROP

 # send ssh traffic to TRAP_AND_DROP
 ipv4 synproxy input inface eth0 dst 1.2.3.4 dport 22 action TRAP_AND_DROP

 # accept ssh traffic on tcp/2200
 ipv4 synproxy input inface eth0 dst 1.2.3.4 dport 2200 redirect to 22

 interface eth0 wan
    server ssh accept
~~~


# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [firehol-interface(5)][keyword-firehol-interface] - interface definition
* [firehol-router(5)][keyword-firehol-router] - router definition
* [firehol-params(5)][] - optional rule parameters
* [firehol-masquerade(5)][keyword-firehol-masquerade] - masquerade helper
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online Documentation](http://firehol.org/documentation/)
* [NAT HOWTO](http://www.netfilter.org/documentation/HOWTO/NAT-HOWTO-6.html)
* [netfilter flow diagram][netfilter flow diagram]

[netfilter flow diagram]: http://upload.wikimedia.org/wikipedia/commons/3/37/Netfilter-packet-flow.svg
