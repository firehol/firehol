/* iprange
 * Copyright (C) 2003 Gabriel L. Somlo
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2,
 * as published by the Free Software Foundation
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 * To compile:
 *  on Linux:
 *   gcc -o iprange iprange.c -O2 -Wall
 *  on Solaris 8, Studio 8 CC:
 *   cc -xO5 -xarch=v8plusa -xdepend iprange.c -o iprange -lnsl -lresolv
 *
 * CHANGELOG:
 *  2004-10-16 Paul Townsend (alpha alpha beta at purdue dot edu)
 *   - more general input/output formatting
 *  2015-05-31 Costa Tsaousis (costa@tsaousis.gr)
 *   - added -C option to report count of unique IPs
 *   - some optimizations to speed it up by 10% - 20%
 *  2015-06-06 Costa Tsaousis (costa@tsaousis.gr)
 *   - added support for loading multiple sets
 *   - added support for merging multiple files
 *   - added support for comparing ipsets (all-to-all, one-to-all)
 *   - added support for parsing IP ranges from the input file
 *     (much like -s did for a single range)
 *   - added support for parsing netmasks
 *   - added support for min prefix generated
 *   - added support for reducing the prefixes for iptables ipsets
 *   - the output is now always optimized (reduced / merged)
 *   - removed option -s (convert a single IP range to CIDR)
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#ifdef __GNUC__
// gcc branch optimization
// #warning "Using GCC branch optimizations"
#define likely(x)       __builtin_expect(!!(x), 1)
#define unlikely(x)     __builtin_expect(!!(x), 0)
#else
#define likely(x)       (x)
#define unlikely(x)     (x)
#endif

static char *PROG;
int debug = 0;
int cidr_use_network = 1;
int default_prefix = 32;

char *print_prefix_ips  = "";
char *print_prefix_nets = "";
char *print_suffix_ips  = "";
char *print_suffix_nets = "";

/*---------------------------------------------------------------------*/
/* network address type: one field for the net address, one for prefix */
/*---------------------------------------------------------------------*/
typedef struct network_addr {
	in_addr_t addr;
	in_addr_t broadcast;
} network_addr_t;

/*------------------------------------------------------------------*/
/* Set a bit to a given value (0 or 1); MSB is bit 1, LSB is bit 32 */
/*------------------------------------------------------------------*/
static inline in_addr_t set_bit(in_addr_t addr, int bitno, int val)
{

	if (val)
		return (addr | (1 << (32 - bitno)));
	else
		return (addr & ~(1 << (32 - bitno)));

}				/* set_bit() */

/*--------------------------------------*/
/* Compute netmask address given prefix */
/*--------------------------------------*/
static inline in_addr_t netmask(int prefix)
{

	if (prefix == 0)
		return (~((in_addr_t) - 1));
	else
		return (~((1 << (32 - prefix)) - 1));

}				/* netmask() */

/*----------------------------------------------------*/
/* Compute broadcast address given address and prefix */
/*----------------------------------------------------*/
static inline in_addr_t broadcast(in_addr_t addr, int prefix)
{

	return (addr | ~netmask(prefix));

}				/* broadcast() */

/*--------------------------------------------------*/
/* Compute network address given address and prefix */
/*--------------------------------------------------*/
static inline in_addr_t network(in_addr_t addr, int prefix)
{

	return (addr & netmask(prefix));

}				/* network() */

/*------------------------------------------------*/
/* Print out a 32-bit address in A.B.C.D/M format */
/*------------------------------------------------*/

int prefix_counters[33] = { 0 };
int prefix_enabled[33] = { 1 };
int split_range_disable_printing = 0;

void print_addr(in_addr_t addr, int prefix)
{

	if(likely(prefix >= 0 && prefix <= 32))
		prefix_counters[prefix]++;

	if(unlikely(split_range_disable_printing)) return;

	struct in_addr in;

	in.s_addr = htonl(addr);

	if (prefix < 32)
		printf("%s%s/%d%s\n", print_prefix_nets, inet_ntoa(in), prefix, print_suffix_nets);
	else
		printf("%s%s%s\n", print_prefix_ips, inet_ntoa(in), print_suffix_ips);

}				/* print_addr() */

/*------------------------------------------------------------*/
/* Recursively compute network addresses to cover range lo-hi */
/*------------------------------------------------------------*/
/* Note: Worst case scenario is when lo=0.0.0.1 and hi=255.255.255.254
 *       We then have 62 CIDR bloks to cover this interval, and 125
 *       calls to split_range();
 *       The maximum possible recursion depth is 32.
 */

void split_range(in_addr_t addr, int prefix, in_addr_t lo, in_addr_t hi)
{

	in_addr_t bc, lower_half, upper_half;

	if (unlikely((prefix < 0) || (prefix > 32))) {
		fprintf(stderr, "%s: Invalid mask size %d!\n", PROG, prefix);
		exit(1);
	}

	bc = broadcast(addr, prefix);

	if (unlikely((lo < addr) || (hi > bc))) {
		fprintf(stderr, "%s: Out of range limits: %x, %x for "
			"network %x/%d, broadcast: %x!\n", PROG, lo, hi, addr, prefix, bc);
		exit(1);
	}

	if ((lo == addr) && (hi == bc) && prefix_enabled[prefix]) {
		print_addr(addr, prefix);
		return;
	}

	prefix++;
	lower_half = addr;
	upper_half = set_bit(addr, prefix, 1);

	if (hi < upper_half) {
		split_range(lower_half, prefix, lo, hi);
	} else if (lo >= upper_half) {
		split_range(upper_half, prefix, lo, hi);
	} else {
		split_range(lower_half, prefix, lo, broadcast(lower_half, prefix));
		split_range(upper_half, prefix, upper_half, hi);
	}

}				/* split_range() */

/*-----------------------------------------------------------*/
/* Convert an A.B.C.D address into a 32-bit host-order value */
/*-----------------------------------------------------------*/
static inline in_addr_t a_to_hl(char *ipstr) {
	struct in_addr in;

	if (unlikely(!inet_aton(ipstr, &in))) {
		fprintf(stderr, "%s: Invalid address %s. Reason: %s\n", PROG, ipstr, strerror(errno));
		exit(1);
	}

	return (ntohl(in.s_addr));

}				/* a_to_hl() */

/*-----------------------------------------------------------------*/
/* convert a network address char string into a host-order network */
/* address and an integer prefix value                             */
/*-----------------------------------------------------------------*/
static inline network_addr_t str_to_netaddr(char *ipstr) {

	long int prefix = default_prefix;
	char *prefixstr;
	network_addr_t netaddr;

	if ((prefixstr = strchr(ipstr, '/'))) {
		*prefixstr = '\0';
		prefixstr++;
		errno = 0;
		prefix = strtol(prefixstr, (char **)NULL, 10);
		if (unlikely(errno || (*prefixstr == '\0') || (prefix < 0) || (prefix > 32))) {
			// try the netmask format
			in_addr_t mask = ~a_to_hl(prefixstr);
			//fprintf(stderr, "mask is %u (0x%08x)\n", mask, mask);
			prefix = 32;
			while((likely(mask & 0x00000001))) {
				mask >>= 1;
				prefix--;
			}

			if(unlikely(mask)) {
				fprintf(stderr, "%s: Invalid netmask %s (calculated prefix = %ld, remaining = 0x%08x)\n", PROG, prefixstr, prefix, mask << (32 - prefix));
				exit(1);
			}
		}
	}

	if(likely(cidr_use_network))
		netaddr.addr = network(a_to_hl(ipstr), prefix);
	else
		netaddr.addr = a_to_hl(ipstr);

	netaddr.broadcast = broadcast(netaddr.addr, prefix);

	return (netaddr);

}				/* str_to_netaddr() */

/*----------------------------------------------------------*/
/* compare two network_addr_t structures; used with qsort() */
/* sort in increasing order by address, then by prefix.     */
/*----------------------------------------------------------*/
int compar_netaddr(const void *p1, const void *p2)
{

	network_addr_t *na1 = (network_addr_t *) p1, *na2 = (network_addr_t *) p2;

	if (na1->addr < na2->addr)
		return (-1);
	if (na1->addr > na2->addr)
		return (1);
	if (na1->broadcast > na2->broadcast)
		return (-1);
	if (na1->broadcast < na2->broadcast)
		return (1);
	return (0);

}				/* compar_netaddr() */

/*------------------------------------------------------*/
/* Print out an address range in a.b.c.d-A.B.C.D format */
/*------------------------------------------------------*/
void print_addr_range(in_addr_t lo, in_addr_t hi)
{

	struct in_addr in;

	if (likely(lo != hi)) {
		in.s_addr = htonl(lo);
		printf("%s%s-", print_prefix_nets, inet_ntoa(in));
		in.s_addr = htonl(hi);
		printf("%s%s\n", inet_ntoa(in), print_suffix_nets);
	}
	else {
		in.s_addr = htonl(hi);
		printf("%s%s%s\n", print_prefix_ips, inet_ntoa(in), print_suffix_ips);
	}
}				/* print_addr_range() */


// ----------------------------------------------------------------------------

#define NETADDR_INC 1024
#define MAX_LINE 1024

typedef struct ipset {
	char filename[FILENAME_MAX+1];
	unsigned long int lines;
	unsigned long int entries;
	unsigned long int entries_max;
	unsigned long int unique_ips;		// this is updated only after calling ipset_optimize()

	struct ipset *next;
	struct ipset *prev;

	network_addr_t *netaddrs;
} ipset;

ipset *ipset_create(const char *filename, int entries) {
	if(entries < NETADDR_INC) entries = NETADDR_INC;

	ipset *ips = malloc(sizeof(ipset));
	if(unlikely(!ips)) return NULL;

	ips->netaddrs = malloc(entries * sizeof(network_addr_t));
	if(unlikely(!ips->netaddrs)) {
		free(ips);
		return NULL;
	}

	ips->lines = 0;
	ips->entries = 0;
	ips->entries_max = entries;
	ips->unique_ips = 0;
	ips->next = NULL;
	ips->prev = NULL;
	strncpy(ips->filename, (filename && *filename)?filename:"stdin", FILENAME_MAX);
	ips->filename[FILENAME_MAX] = '\0';

	return ips;
}

void ipset_free(ipset *ips) {
	if(ips->next) ips->next->prev = ips->prev;
	if(ips->prev) ips->prev->next = ips->next;

	free(ips->netaddrs);
	free(ips);
}

void ipset_free_all(ipset *ips) {
	if(ips->prev) {
		ips->prev->next = NULL;
		ipset_free_all(ips->prev);
	}

	if(ips->next) {
		ips->next->prev = NULL;
		ipset_free_all(ips->next);
	}

	ipset_free(ips);
}

static inline void ipset_expand(ipset *ips, unsigned long int free_entries_needed) {
	if(unlikely(!free_entries_needed)) free_entries_needed = 1;

	if(unlikely(ips && (ips->entries_max - ips->entries) < free_entries_needed)) {
		ips->entries_max += (free_entries_needed < NETADDR_INC)?NETADDR_INC:free_entries_needed;

		network_addr_t *n = realloc(ips->netaddrs, ips->entries_max * sizeof(network_addr_t));
		if(unlikely(!n)) {
			fprintf(stderr, "%s: Cannot re-allocate memory (%ld bytes)\n", PROG, ips->entries_max * sizeof(network_addr_t));
			exit(1);
		}
		ips->netaddrs = n;
	}
}

static inline void ipset_add_ipstr(ipset *ips, char *ipstr) {
	ipset_expand(ips, 1);

	ips->netaddrs[ips->entries] = str_to_netaddr(ipstr);
	ips->unique_ips += ips->netaddrs[ips->entries].broadcast - ips->netaddrs[ips->entries].addr + 1;
	ips->entries++;
	ips->lines++;
}

static inline void ipset_add(ipset *ips, in_addr_t from, in_addr_t to) {
	ipset_expand(ips, 1);

	ips->netaddrs[ips->entries].addr = from;
	ips->netaddrs[ips->entries++].broadcast = to;
	ips->unique_ips += to - from + 1;
	ips->lines++;
}

static inline void ipset_optimize(ipset *ips) {
	if(unlikely(debug)) fprintf(stderr, "%s: Optimizing %s\n", PROG, ips->filename);

	// sort it
	qsort((void *)ips->netaddrs, ips->entries, sizeof(network_addr_t), compar_netaddr);

	// optimize it in a new space
	network_addr_t *naddrs = malloc(ips->entries * sizeof(network_addr_t));
	if(unlikely(!naddrs)) {
		ipset_free(ips);
		fprintf(stderr, "%s: Cannot allocate memory (%ld bytes)\n", PROG, ips->entries * sizeof(network_addr_t));
		exit(1);
	}

	int i, n = ips->entries, lines = ips->lines;

	network_addr_t *oaddrs = ips->netaddrs;
	ips->netaddrs = naddrs;
	ips->entries = 0;
	ips->unique_ips = 0;
	ips->lines = 0;

	in_addr_t lo = oaddrs[0].addr, hi = oaddrs[0].broadcast;
	for (i = 1; i < n; i++) {
		if (oaddrs[i].broadcast <= hi)
			continue;

		if (oaddrs[i].addr == hi + 1) {
			hi = oaddrs[i].broadcast;
			continue;
		}

		ipset_add(ips, lo, hi);

		lo = oaddrs[i].addr;
		hi = oaddrs[i].broadcast;
	}
	ipset_add(ips, lo, hi);
	ips->lines = lines;

	free(oaddrs);
}

static inline void ipset_optimize_all(ipset *root) {
	ipset *ips;

	for(ips = root; ips ;ips = ips->next)
		ipset_optimize(ips);
}


// returns
// -1 = cannot parse line
//  0 = skip line - nothing useful here
//  1 = parsed 1 ip address
//  2 = parsed 2 ip addresses
int parse_line(char *line, int lineid, char *ipstr, char *ipstr2, int len) {
	char *s = line;
	
	// skip all spaces
	while(unlikely(*s == ' ' || *s == '\t')) s++;

	// skip a line of comment
	if(unlikely(*s == '#' || *s == ';')) return 0;

	// if we reached the end of line
	if(unlikely(*s == '\r' || *s == '\n' || *s == '\0')) return 0;

	// get the ip address
	int i = 0;
	while(likely(i < len && ((*s >= '0' && *s <= '9') || *s == '.' || *s == '/')))
		ipstr[i++] = *s++;

	if(unlikely(!i)) return -1;

	// terminate ipstr
	ipstr[i] = '\0';

	// skip all spaces
	while(unlikely(*s == ' ' || *s == '\t')) s++;

	// the rest is comment
	if(unlikely(*s == '#' || *s == ';')) return 1;

	// if we reached the end of line
	if(likely(*s == '\r' || *s == '\n' || *s == '\0')) return 1;

	if(unlikely(*s != '-')) {
		fprintf(stderr, "%s: Ignoring text on line %d, expected a - after %s, but found '%s'\n", PROG, lineid, ipstr, s);
		return 1;
	}

	// skip the -
	s++;

	// skip all spaces
	while(unlikely(*s == ' ' || *s == '\t')) s++;

	// the rest is comment
	if(unlikely(*s == '#' || *s == ';')) {
		fprintf(stderr, "%s: Ignoring text on line %d, expected an ip address after -, but found '%s'\n", PROG, lineid, s);
		return 1;
	}

	// if we reached the end of line
	if(unlikely(*s == '\r' || *s == '\n' || *s == '\0')) {
		fprintf(stderr, "%s: Incomplete range on line %d, expected an ip address after -, but line ended\n", PROG, lineid);
		return 1;
	}

	// get the ip 2nd address
	i = 0;
	while(likely(i < len && ((*s >= '0' && *s <= '9') || *s == '.' || *s == '/')))
		ipstr2[i++] = *s++;

	if(unlikely(!i)) {
		fprintf(stderr, "%s: Incomplete range on line %d, expected an ip address after -, but line ended\n", PROG, lineid);
		return 1;
	}

	// terminate ipstr
	ipstr2[i] = '\0';

	// skip all spaces
	while(unlikely(*s == ' ' || *s == '\t')) s++;

	// the rest is comment
	if(unlikely(*s == '#' || *s == ';')) return 2;

	// if we reached the end of line
	if(likely(*s == '\r' || *s == '\n' || *s == '\0')) return 2;

	fprintf(stderr, "%s: Ignoring text on line %d, after the second ip address: '%s'\n", PROG, lineid, s);
	return 2;
}

ipset *ipset_load(const char *filename) {
	ipset *ips = ipset_create((filename && *filename)?filename:"stdin", 0);
	if(unlikely(!ips)) return NULL;

	FILE *fp = stdin;
	if (likely(filename && *filename)) {
		fp = fopen(filename, "r");
		if (unlikely(!fp)) {
			fprintf(stderr, "%s: %s - %s\n", PROG, filename, strerror(errno));
			return NULL;
		}
	}

	// load it
	if(unlikely(debug)) fprintf(stderr, "%s: Loading from %s\n", PROG, ips->filename);

	int lineid = 0;
	char line[MAX_LINE + 1], ipstr[101], ipstr2[101];
	while(likely(ips && fgets(line, MAX_LINE, fp))) {
		lineid++;

		switch(parse_line(line, lineid, ipstr, ipstr2, 100)) {
			case -1:
				// cannot read line
				fprintf(stderr, "%s: Cannot understand line No %d from %s: %s\n", PROG, lineid, ips->filename, line);
				break;

			case 0:
				// nothing on this line
				break;

			case 1:
				// 1 IP on this line
				ipset_add_ipstr(ips, ipstr);
				break;

			case 2:
				// 2 IPs in range on this line
				{
					in_addr_t lo, hi;
					network_addr_t netaddr1, netaddr2;
					netaddr1 = str_to_netaddr(ipstr);
					netaddr2 = str_to_netaddr(ipstr2);

					lo = (netaddr1.addr < netaddr2.addr)?netaddr1.addr:netaddr2.addr;
					hi = (netaddr1.broadcast > netaddr2.broadcast)?netaddr1.broadcast:netaddr2.broadcast;
					ipset_add(ips, lo, hi);
				}
				break;

			default:
				fprintf(stderr, "%s: Cannot understand result code.\n", PROG);
				exit(1);
				break;
		}
	}

	if(unlikely(!ips)) return NULL;

	//if(unlikely(!ips->entries)) {
	//	free(ips);
	//	return NULL;
	//}

	return ips;
}

void ipset_print_reduce(ipset *ips, int acceptable_increase, int min_accepted) {
	int i, n = ips->entries, total = 0, acceptable, iterations = 0, initial = 0, eliminated = 0;

	// reset the prefix counters
	for(i = 0; i <= 32; i++)
		prefix_counters[i] = 0;

	// disable printing
	split_range_disable_printing = 1;

	// enable all prefixes
	for(i = 0; i <= 32; i++)
		prefix_enabled[i] = 1;

	// find how many prefixes are there
	if(unlikely(debug)) fprintf(stderr, "\nCounting prefixes in %s\n", ips->filename);
	for(i = 0; i < n ;i++)
		split_range(0, 0, ips->netaddrs[i].addr, ips->netaddrs[i].broadcast);

	// count them
	if(unlikely(debug)) fprintf(stderr, "Break down by prefix:\n");
	total = 0;
	for(i = 0; i <= 32 ;i++) {
		if(prefix_counters[i]) {
			if(unlikely(debug)) fprintf(stderr, "	- prefix /%d counts %d entries\n", i, prefix_counters[i]);
			total += prefix_counters[i];
			initial++;
		}
		else prefix_enabled[i] = 0;
	}
	if(unlikely(debug)) fprintf(stderr, "Total %d entries generated\n", total);

	// find the upper limit
	acceptable = total * acceptable_increase / 100;
	if(acceptable < min_accepted) acceptable = min_accepted;
	if(unlikely(debug)) fprintf(stderr, "Acceptable is to reach %d entries by reducing prefixes\n", acceptable);

	// reduce the possible prefixes
	while(total < acceptable) {
		iterations++;

		// find the prefix with the least increase
		int min = -1, to = -1, min_increase = acceptable * 10, j, multiplier, increase;
		for(i = 0; i <= 31 ;i++) {
			if(!prefix_counters[i] || !prefix_enabled[i]) continue;

			for(j = i + 1, multiplier = 2; j <= 32 ; j++, multiplier *= 2) {
				if(!prefix_counters[j]) continue;

				increase = prefix_counters[i] * (multiplier - 1);
				if(unlikely(debug)) fprintf(stderr, "		> Examining merging prefix %d to %d (increase by %d)\n", i, j, increase);
				
				if(increase < min_increase) {
					min_increase = increase;
					min = i;
					to = j;
				}
				break;
			}
		}

		if(min == -1 || to == -1 || min == to) {
			if(unlikely(debug)) fprintf(stderr, "	Nothing more to reduce\n");
			break;
		}

	 	multiplier = 1;
		for(i = min; i < to; i++) multiplier *= 2;

		increase = prefix_counters[min] * multiplier - prefix_counters[min];
		if(unlikely(debug)) fprintf(stderr, "		> Selected prefix %d (%d entries) to be merged in %d (total increase by %d)\n", min, prefix_counters[min], to, increase);

		if(total + increase > acceptable) {
			if(unlikely(debug)) fprintf(stderr, "	Cannot proceed to increase total %d by %d, above acceptable %d.\n", total, increase, acceptable);
			break;
		}

		int old_to_counters = prefix_counters[to];

		total += increase;
		prefix_counters[to] += increase + prefix_counters[min];
		prefix_counters[min] = 0;
		prefix_enabled[min] = 0;
		eliminated++;
		if(unlikely(debug)) fprintf(stderr, "		Eliminating prefix %d in %d (had %d, now has %d entries), total is now %d (increased by %d)\n", min, to, old_to_counters, prefix_counters[to], total, increase);
	}

	if(unlikely(debug)) fprintf(stderr, "\nEliminated %d out of %d prefixes (%d remain in the final set).\n", eliminated, initial, initial - eliminated);

	// reset the prefix counters
	for(i = 0; i <= 32; i++)
		prefix_counters[i] = 0;

	// enable printing
	split_range_disable_printing = 0;

	// print it
	for(i = 0; i < n ;i++)
		split_range(0, 0, ips->netaddrs[i].addr, ips->netaddrs[i].broadcast);
}

#define PRINT_RANGE 1
#define PRINT_CIDR 2
#define PRINT_SINGLE_IPS 3
#define PRINT_REDUCED 4

int ipset_reduce_factor = 120;
int ipset_reduce_min_accepted = 16384;

void ipset_print(ipset *ips, int print) {
	int i, n = ips->entries;

	// reset the prefix counters
	for(i = 0; i <= 32; i++)
		prefix_counters[i] = 0;

	if(unlikely(debug)) fprintf(stderr, "%s: Printing %s\n", PROG, ips->filename);

	if(print == PRINT_REDUCED) {
		ipset_print_reduce(ips, ipset_reduce_factor, ipset_reduce_min_accepted);
	}
	else {
		for(i = 0; i < n ;i++)
			if(likely(print == PRINT_CIDR))
				split_range(0, 0, ips->netaddrs[i].addr, ips->netaddrs[i].broadcast);

			else if(likely(print == PRINT_SINGLE_IPS)) {
				in_addr_t x, broadcast = ips->netaddrs[i].broadcast;
				for(x = ips->netaddrs[i].addr; x <= broadcast ; x++)
					print_addr_range(x, x);
			}
			else
				print_addr_range(ips->netaddrs[i].addr, ips->netaddrs[i].broadcast);
	}

	// print prefix break down
	if(unlikely((print == PRINT_CIDR || print == PRINT_REDUCED) && debug)) {
		fprintf(stderr, "\nBreak down by prefix:\n");
		int total = 0;
		for(i = 0; i <= 32 ;i++) {
			if(prefix_counters[i]) {
				fprintf(stderr, "	- prefix /%d counts %d entries\n", i, prefix_counters[i]);
				total += prefix_counters[i];
			}
		}
		fprintf(stderr, "Total %d entries generated\n", total);
	}
}

static inline void ipset_merge(ipset *to, ipset *add) {
	if(unlikely(debug)) fprintf(stderr, "%s: Merging %s to %s\n", PROG, add->filename, to->filename);

	ipset_expand(to, add->entries);

	memcpy(&to->netaddrs[to->entries], &add->netaddrs[0], add->entries * sizeof(network_addr_t));

	to->entries = to->entries + add->entries;
	to->lines += add->lines;
}

ipset *ipset_copy(ipset *ips1) {
	if(unlikely(debug)) fprintf(stderr, "%s: Copying %s\n", PROG, ips1->filename);

	ipset *ips = ipset_create(ips1->filename, ips1->entries);
	if(unlikely(!ips)) return NULL;

	memcpy(&ips->netaddrs[0], &ips1->netaddrs[0], ips1->entries * sizeof(network_addr_t));

	ips->entries = ips1->entries;
	ips->unique_ips = ips1->unique_ips;
	ips->lines = ips1->lines;

	return ips;
}

ipset *ipset_combine(ipset *ips1, ipset *ips2) {
	if(unlikely(debug)) fprintf(stderr, "%s: Combining %s and %s\n", PROG, ips1->filename, ips2->filename);

	ipset *ips = ipset_create("combined", ips1->entries + ips2->entries);
	if(unlikely(!ips)) return NULL;

	memcpy(&ips->netaddrs[0], &ips1->netaddrs[0], ips1->entries * sizeof(network_addr_t));
	memcpy(&ips->netaddrs[ips1->entries], &ips2->netaddrs[0], ips2->entries * sizeof(network_addr_t));

	ips->entries = ips1->entries + ips2->entries;
	ips->lines = ips1->lines + ips2->lines;	

	return ips;
}

void usage(const char *me) {
	fprintf(stderr, "\n"
		"iprange\n"
		"manage IP ranges\n"
		"\n"
		"Original,   Copyright (C) 2003 Gabriel L. Somlo\n"
		"Adapted,    Copyright (C) 2004 Paul Townsend\n"
		"Refactored, Copyright (C) 2015 Costa Tsaousis for FireHOL\n"
		"License: GPL\n"
		"\n"
		"Usage: %s [options] file1 file2 file3 ...\n"
		"\n"
		"options:\n"
		"	--optimize or --combine or --merge or -J\n"
		"		> enables IPSET_COMBINE mode\n"
		"		merge all files and print the merged set\n"
		"		this is the default\n"
		"\n"
		"	--ipset-reduce PERCENT\n"
		"		> enables IPSET_REDUCE mode\n"
		"		merge all files and print the merged set\n"
		"		but try to reduce the number of prefixes (subnets)\n"
		"		found, while allowing some increase in entries\n"
		"		the PERCENT is how much percent to allow\n"
		"		increase of the entries in order to reduce the\n"
		"		prefixes (subnets)\n"
		"		(the internal default PERCENT is 20)\n"
		"		(use -v to see exactly what it does)\n"
		"\n"
		"	--ipset-reduce-entries ENTRIES\n"
		"		> enables IPSET_REDUCE mode\n"
		"		allow increasing the entries above PERCENT, if\n"
		"		they are below ENTRIES\n"
		"		(the internal default ENTRIES is 16384)\n"
		"\n"
		"	--compare\n"
		"		> enables IPSET_COMPARE mode\n"
		"		compare all files with all other files\n"
		"		the output is CSV formatted\n"
		"		add --header to get the CSV header too\n"
		"\n"
		"	--compare-first\n"
		"		> enables IPSET_COMPARE_FIRST mode\n"
		"		compare the first file with all other files\n"
		"		the output is CSV formatted\n"
		"		add --header to get the CSV header too\n"
		"\n"
		"	--count-unique or -C\n"
		"		> enables IPSET_COUNT_UNIQUE mode\n"
		"		merge all files and print its counts\n"
		"		the output is CSV formatted\n"
		"		add --header to get the CSV header too\n"
		"\n"
		"	--count-unique-all\n"
		"		> enables IPSET_COUNT_UNIQUE_ALL mode\n"
		"		print counts for each file\n"
		"		the output is CSV formatted\n"
		"		add --header to get the CSV header too\n"
		"\n"
		"	--print-ranges or -j\n"
		"		print IP ranges (A.A.A.A-B.B.B.B)\n"
		"		the default is to print CIDRs (A.A.A.A/B)\n"
		"		it only applies when the output is not CSV\n"
		"\n"
		"	--print-single-ips or -1\n"
		"		print single IPs\n"
		"		this can produce large output\n"
		"		the default is to print CIDRs (A.A.A.A/B)\n"
		"		it only applies when the output is not CSV\n"
		"\n"
		"	--print-prefix STRING\n"
		"		print STRING before each IP, range or CIDR\n"
		"		this sets both --print-prefix-ips and\n"
		"		--print-prefix-nets\n"
		"\n"
		"	--print-prefix-ips STRING\n"
		"		print STRING before each single IP\n"
		"		useful for entering single IPs to a different\n"
		"		ipset than the networks\n"
		"\n"
		"	--print-prefix-nets STRING\n"
		"		print STRING before each range or CIDR\n"
		"		useful for entering sunbets to a different\n"
		"		ipset than single IPs\n"
		"\n"
		"	--print-suffix STRING\n"
		"		print STRING after each IP, range or CIDR\n"
		"		this sets both --print-suffix-ips and\n"
		"		--print-suffix-nets\n"
		"\n"
		"	--print-suffix-ips STRING\n"
		"		print STRING after each single IP\n"
		"		useful for giving single IPs different\n"
		"		ipset options\n"
		"\n"
		"	--print-suffix-nets STRING\n"
		"		print STRING after each range or CIDR\n"
		"		useful for giving subnets different\n"
		"		ipset options\n"
		"\n"
		"	--header\n"
		"		when the output is CSV, print the header line\n"
		"		the default is to not print the header line\n"
		"\n"
		"	--dont-fix-network\n"
		"		by default, the network address of all CIDRs\n"
		"		is used (i.e. 1.1.1.17/24 is read as 1.1.1.0/24)\n"
		"		this option disables this feature\n"
		"		(i.e. 1.1.1.17/24 is read as 1.1.1.17-1.1.1.255)\n"
		"\n"
		"	--default-prefix PREFIX or -p PREFIX\n"
		"		Set the default prefix for all IPs without mask\n"
		"		the default is 32\n"
		"\n"
		"	--min-prefix N\n"
		"		do not generate prefixes larger than N\n"
		"		i.e. if N is 24 then /24 to /32 entries will be\n"
		"		     generated (a /16 network will be generated\n"
		"		     using multiple /24 networks)\n"
		"		this is useful to optimize netfilter/iptables\n"
		"		ipsets, where each different prefix increases the\n"
		"		lookup time for each packet, but the number of\n"
		"		entries in the ipset do not affect its performance\n"
		"		with this setting more entries will be produced\n"
		"		to accomplish the same match\n"
		"\n"
		"	--has-compare or --has-reduce\n"
		"		exits with 0\n"
		"		older versions of iprange will exit with 1\n"
		"		use this option in scripts to find if this\n"
		"		version of iprange is present in a system\n"
		"\n"
		"	-v\n"
		"		be verbose on stderr\n"
		"\n"
		"	--help or -h\n"
		"		print this message\n"
		"\n"
		"	fileN\n"
		"		a filename or - for stdin\n"
		"		each filename can be followed by [as NAME]\n"
		"		to change its name on the CSV output\n"
		"\n"
		"		if no filename is given, stdin is assumed\n"
		"\n"
		"		the files may contain:\n"
		"		 - comments starting with # or ;\n"
		"		 - one IP per line (without mask)\n"
		"		 - a CIDR per line (A.A.A.A/B)\n"
		"		 - an IP range per line (A.A.A.A - B.B.B.B)\n"
		"		 - a CIDR range per line (A.A.A.A/B - C.C.C.C/D)\n"
		"		   the range is calculated as the network address\n"
		"		   of A.A.A.A/B to the broadcast address of C.C.C.C/D\n"
		"		   (this is affected by --dont-fix-network)\n"
		"		 - CIDRs can be given in either prefix or netmask\n"
		"		   format in all cases (including ranges)\n"
		"		 - spaces and empty lines are ignored\n"
		"\n"
		"		any number of files can be given\n"
		"\n"
		, me);
	exit(1);	
}

#define MODE_COMBINE 1
#define MODE_COMPARE 2
#define MODE_COMPARE_FIRST 3
#define MODE_COMPARE_NEXT 4
#define MODE_COUNT_UNIQUE_MERGED 5
#define MODE_COUNT_UNIQUE_ALL 6

int main(int argc, char **argv) {
	if ((PROG = strrchr(argv[0], '/')))
		PROG++;
	else
		PROG = argv[0];

	ipset *root = NULL, *ips = NULL, *first = NULL, *compare = NULL;
	int i, mode = MODE_COMBINE, print = PRINT_CIDR, header = 0, read_compare = 0;

	// enable all prefixes
	for(i = 0; i <= 32; i++)
		prefix_enabled[i] = 1;
	
	for(i = 1; i < argc ; i++) {
		if(strcmp(argv[i], "as") == 0 && root && i+1 < argc) {
			strncpy(root->filename, argv[++i], FILENAME_MAX);
			root->filename[FILENAME_MAX] = '\0';
		}
		else if(strcmp(argv[i], "--min-prefix") == 0 && i+1 < argc) {
			int j, min_prefix = atoi(argv[++i]);
			for(j = 0; j < min_prefix; j++)
				prefix_enabled[j] = 0;
		}
		else if((strcmp(argv[i], "--default-prefix") == 0 || strcmp(argv[i], "-p") == 0) && i+1 < argc) {
			default_prefix = atoi(argv[++i]);
		}
		else if(strcmp(argv[i], "--ipset-reduce") == 0 && i+1 < argc) {
			ipset_reduce_factor = 100 + atoi(argv[++i]);
			print = PRINT_REDUCED;
		}
		else if(strcmp(argv[i], "--ipset-reduce-entries") == 0 && i+1 < argc) {
			ipset_reduce_min_accepted = atoi(argv[++i]);
			print = PRINT_REDUCED;
		}
		else if(strcmp(argv[i], "--optimize") == 0 || strcmp(argv[i], "--combine") == 0 || strcmp(argv[i], "-J") == 0 || strcmp(argv[i], "--merge") == 0) {
			mode = MODE_COMBINE;
		}
		else if(strcmp(argv[i], "--compare") == 0) {
			mode = MODE_COMPARE;
		}
		else if(strcmp(argv[i], "--compare-first") == 0) {
			mode = MODE_COMPARE_FIRST;
		}
		else if(strcmp(argv[i], "--compare-next") == 0) {
			mode = MODE_COMPARE_NEXT;
			read_compare = 1;
			compare = NULL;
		}
		else if(strcmp(argv[i], "--count-unique") == 0 || strcmp(argv[i], "-C") == 0) {
			mode = MODE_COUNT_UNIQUE_MERGED;
		}
		else if(strcmp(argv[i], "--count-unique-all") == 0) {
			mode = MODE_COUNT_UNIQUE_ALL;
		}
		else if(strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
			usage(argv[0]);
		}
		else if(strcmp(argv[i], "-v") == 0) {
			debug = 1;
		}
		else if(strcmp(argv[i], "--print-ranges") == 0 || strcmp(argv[i], "-j") == 0) {
			print = PRINT_RANGE;
		}
		else if(strcmp(argv[i], "--print-single-ips") == 0 || strcmp(argv[i], "-1") == 0) {
			print = PRINT_SINGLE_IPS;
		}
		else if(strcmp(argv[i], "--print-prefix") == 0 && i+1 < argc) {
			print_prefix_ips  = argv[++i];
			print_prefix_nets = print_prefix_ips;
		}
		else if(strcmp(argv[i], "--print-prefix-ips") == 0 && i+1 < argc) {
			print_prefix_ips = argv[++i];
		}
		else if(strcmp(argv[i], "--print-prefix-nets") == 0 && i+1 < argc) {
			print_prefix_nets = argv[++i];
		}
		else if(strcmp(argv[i], "--print-suffix") == 0 && i+1 < argc) {
			print_suffix_ips = argv[++i];
			print_suffix_nets = print_suffix_ips;
		}
		else if(strcmp(argv[i], "--print-suffix-ips") == 0 && i+1 < argc) {
			print_suffix_ips = argv[++i];
		}
		else if(strcmp(argv[i], "--print-suffix-nets") == 0 && i+1 < argc) {
			print_suffix_nets = argv[++i];
		}
		else if(strcmp(argv[i], "--header") == 0) {
			header = 1;
		}
		else if(strcmp(argv[i], "--dont-fix-network") == 0) {
			cidr_use_network = 0;
		}
		else if(strcmp(argv[i], "--has-compare") == 0 || strcmp(argv[i], "--has-reduce") == 0) {
			fprintf(stderr, "yes, compare and reduce is present.\n");
			exit(0);
		}
		else {
			if(strcmp(argv[i], "-") == 0)
				ips = ipset_load(NULL);
			else
				ips = ipset_load(argv[i]);

			if(!ips) {
				fprintf(stderr, "%s: Cannot load ipset: %s\n", PROG, argv[i]);
				exit(1);
			}

			if(read_compare) {
				ips->next = compare;
				compare = ips;
				if(ips->next) ips->next->prev = ips;
			}
			else {
				if(!first) first = ips;
				ips->next = root;
				root = ips;
				if(ips->next) ips->next->prev = ips;
			}
		}
	}

	if(mode == MODE_COMBINE || mode == MODE_COUNT_UNIQUE_MERGED) {
		// if no ipset was given on the command line
		// assume stdin
		if(!root) {
			root = ipset_load(NULL);
			if(!root) {
				fprintf(stderr, "%s: No ipsets to merge.\n", PROG);
				exit(1);
			}
		}

		// for debug mode to show something meaningful
		strcpy(root->filename, "combined ipset");

		for(ips = root->next; ips ;ips = ips->next)
			ipset_merge(root, ips);

		ipset_optimize(root);

		if(mode == MODE_COMBINE)
			ipset_print(root, print);

		else if(mode == MODE_COUNT_UNIQUE_MERGED) {
			if(unlikely(header)) printf("entries,unique_ips\n");
			printf("%lu,%lu\n", root->lines, root->unique_ips);
		}
	}
	else if(mode == MODE_COMPARE || mode == MODE_COMPARE_FIRST || mode == MODE_COMPARE_NEXT || mode == MODE_COUNT_UNIQUE_ALL) {
		ipset_optimize_all(root);

		if(mode == MODE_COMPARE) {
			if(!root || !root->next) {
				fprintf(stderr, "%s: two ipsets at least are needed to be compared.\n", PROG);
				exit(1);
			}

			if(unlikely(header)) printf("name1,name2,entries1,entries2,ips1,ips2,combined_ips,common_ips\n");
			
			ipset *ips2, *combined;
			for(ips = root; ips ;ips = ips->next) {
				for(ips2 = ips; ips2 ;ips2 = ips2->next) {
					if(ips == ips2) continue;

					combined = ipset_combine(ips, ips2);
					if(!combined) {
						fprintf(stderr, "%s: Cannot merge ipset %s and %s\n", PROG, ips->filename, ips2->filename);
						exit(1);
					}

					// for debug mode to show something meaningful
					strcpy(combined->filename, "combined ipset");

					ipset_optimize(combined);
					fprintf(stdout, "%s,%s,%lu,%lu,%lu,%lu,%lu,%lu\n", ips->filename, ips2->filename, ips->lines, ips2->lines, ips->unique_ips, ips2->unique_ips, combined->unique_ips, ips->unique_ips + ips2->unique_ips - combined->unique_ips);
					ipset_free(combined);
				}
			}
		}
		if(mode == MODE_COMPARE_NEXT) {
			if(!root) {
				fprintf(stderr, "%s: no files given before the --compare-next parameter.\n", PROG);
				exit(1);
			}
			if(!compare) {
				fprintf(stderr, "%s: no files given after the --compare-next parameter.\n", PROG);
				exit(1);
			}
			ipset_optimize_all(compare);

			if(unlikely(header)) printf("name1,name2,entries1,entries2,ips1,ips2,combined_ips,common_ips\n");

			ipset *ips2, *combined;
			for(ips = root; ips ;ips = ips->next) {
				for(ips2 = compare; ips2 ;ips2 = ips2->next) {
					combined = ipset_combine(ips, ips2);
					if(!combined) {
						fprintf(stderr, "%s: Cannot merge ipset %s and %s\n", PROG, ips->filename, ips2->filename);
						exit(1);
					}

					// for debug mode to show something meaningful
					strcpy(combined->filename, "combined ipset");

					ipset_optimize(combined);
					fprintf(stdout, "%s,%s,%lu,%lu,%lu,%lu,%lu,%lu\n", ips->filename, ips2->filename, ips->lines, ips2->lines, ips->unique_ips, ips2->unique_ips, combined->unique_ips, ips->unique_ips + ips2->unique_ips - combined->unique_ips);
					ipset_free(combined);
				}
			}
		}
		else if(mode == MODE_COMPARE_FIRST) {
			if(!first || !root || !root->next) {
				fprintf(stderr, "%s: two ipsets at least are needed to be compared.\n", PROG);
				exit(1);
			}
			
			if(unlikely(header)) printf("name,entries,unique_ips,common_ips\n");

			ipset *combined;
			for(ips = root; ips ;ips = ips->next) {
				if(ips == first) continue;

				combined = ipset_combine(ips, first);
				if(!combined) {
					fprintf(stderr, "%s: Cannot merge ipset %s and %s\n", PROG, ips->filename, first->filename);
					exit(1);
				}

				// for debug mode to show something meaningful
				strcpy(combined->filename, "combined ipset");

				ipset_optimize(combined);
				printf("%s,%lu,%lu,%lu\n", ips->filename, ips->lines, ips->unique_ips, ips->unique_ips + first->unique_ips - combined->unique_ips);
				ipset_free(combined);
			}
		}
		else if(mode == MODE_COUNT_UNIQUE_ALL) {
			if(unlikely(header)) printf("name,entries,unique_ips\n");

			for(ips = root; ips ;ips = ips->next) {
				printf("%s,%lu,%lu\n", ips->filename, ips->lines, ips->unique_ips);
			}
		}
	}
	else {
		fprintf(stderr, "%s: Unknown mode.\n", PROG);
		exit(1);
	}

	exit(0);
}
