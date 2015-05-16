#!/bin/awk -f
# from: http://www.unix.com/shell-programming-and-scripting/233825-convert-ip-ranges-cidr-netblocks.html

# example usage:
#
# echo "1.2.3.4-1.2.5.2" | ipv4_range_to_cidr.awk
#

# Bitwise OR of var1 and var2
function bit_or(a, b, r, i, c) {
    for (r=i=0;i<32;i++) {
        c = 2 ^ i
        if ((int(a/c) % 2) || (int(b/c) % 2)) r += c
    }
    return r
}

# Rotate bytevalue left x times
function bit_lshift(var, x) {
  while(x--) var*=2;
  return var;
}

# Rotate bytevalue right x times
function bit_rshift(var, x) {
  while(x--) var=int(var/2);
  return var;
}

# convert ip ranges to CIDR notation
# str range2cidr(ip2dec("192.168.0.15"), ip2dec("192.168.5.115"))
#
# Credit to Chubler_XL for this brilliant function. (see his post below for non GNU awk)
#
function range2cidr(ipStart, ipEnd,  bits, mask, newip) {
    bits = 1
    mask = 1
    while (bits < 32) {
        newip = bit_or(ipStart, mask)
        if ((newip>ipEnd) || ((bit_lshift(bit_rshift(ipStart,bits),bits)) != ipStart)) {
           bits--
           mask = bit_rshift(mask,1)
           break
        }
        bits++
        mask = bit_lshift(mask,1)+1
    }
    newip = bit_or(ipStart, mask)
    bits = 32 - bits
    result = dec2ip(ipStart) "/" bits
    if (newip < ipEnd) result = result "\n" range2cidr(newip + 1, ipEnd)
    return result
}

# convert dotted quads to long decimal ip
#	int ip2dec("192.168.0.15")
#
function ip2dec(ip,   slice) {
	split(ip, slice, ".")
	return (slice[1] * 2^24) + (slice[2] * 2^16) + (slice[3] * 2^8) + slice[4]
}

# convert decimal long ip to dotted quads
#	str dec2ip(1171259392)
#
function dec2ip(dec,    ip, quad) {
	for (i=3; i>=1; i--) {
		quad = 256^i
		ip = ip int(dec/quad) "."
		dec = dec%quad
	}
	return ip dec
}

# convert decimal ip to binary
#	str dec2binary(1171259392)
#
function dec2binary(dec,    bin) {
	while (dec>0) {
		bin = dec%2 bin
		dec = int(dec/2)
	}
	return bin
}

# Convert binary ip to decimal
#	int binary2dec("1000101110100000000010011001000")
#
function binary2dec(bin,   slice, l, dec) {
	split(bin, slice, "")
	l = length(bin)
	for (i=l; i>0; i--) {
		dec += slice[i] * 2^(l-i)
	}
	return dec
}

# convert dotted quad ip to binary
#	str ip2binary("192.168.0.15")
#
function ip2binary(ip) {
	return dec2binary(ip2dec(ip))
}


# count the number of ip's in a dotted quad ip range
#	int countIp ("192.168.0.0" ,"192.168.1.255") + 1
#
function countQuadIp(ipStart, ipEnd) {
	return (ip2dec(ipEnd) - ip2dec(ipStart))
}

# count the number of ip's in a CIDR block
#	int countCidrIp ("192.168.0.0/12")
#
function countCidrIp (cidr) {
	sub(/.+\//, "", cidr)
	return 2^(32-cidr)
}

function sanitize(ip) {
	split(ip, slice, ".")
	return slice[1]/1 "." slice[2]/1 "." slice[3]/1 "." slice[4]/1
}

BEGIN{
	FS=",|-"
	#print "-N cidr nethash --maxelem 260000\n-N single iphash --maxelem 60000\n"
}

# sanitize ip's
{$1 = sanitize($1); $2 = sanitize($2)}

# range with a single IP
#$1==$2 {printf "-A single %s\n", $1} 
$1==$2 {printf $1 "\n"} 

# ranges with multiple IP's
$1!=$2{print range2cidr(ip2dec($1), ip2dec($2))}

# footer
END {
#	print "COMMIT\n"
}
