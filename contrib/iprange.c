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
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>


static int  Cflg = 0; /* = 1 if "-C" specified */
static int	Jflg = 0;	/* = 1 if "-J" specified */
static char	*PROG;


/*---------------------------------------------------------------------*/
/* network address type: one field for the net address, one for prefix */
/*---------------------------------------------------------------------*/
typedef struct network_addr {
  in_addr_t addr;
  int pfx;
  in_addr_t broadcast;
} network_addr_t;


/*------------------------------------------------------------------*/
/* Set a bit to a given value (0 or 1); MSB is bit 1, LSB is bit 32 */
/*------------------------------------------------------------------*/
static inline in_addr_t set_bit( in_addr_t addr, int bitno, int val ) {

  if ( val )
    return( addr | (1 << (32 - bitno)) );
  else
    return( addr & ~(1 << (32 - bitno)) );

} /* set_bit() */


/*--------------------------------------*/
/* Compute netmask address given prefix */
/*--------------------------------------*/
static inline in_addr_t netmask( int prefix ) {

  if ( prefix == 0 )
    return( ~((in_addr_t) -1) );
  else
    return( ~((1 << (32 - prefix)) - 1) );

} /* netmask() */


/*----------------------------------------------------*/
/* Compute broadcast address given address and prefix */
/*----------------------------------------------------*/
static inline in_addr_t broadcast( in_addr_t addr, int prefix ) {

  return( addr | ~netmask(prefix) );

} /* broadcast() */


/*--------------------------------------------------*/
/* Compute network address given address and prefix */
/*--------------------------------------------------*/
static inline in_addr_t network( in_addr_t addr, int prefix ) {

  return( addr & netmask(prefix) );

} /* network() */


/*------------------------------------------------*/
/* Print out a 32-bit address in A.B.C.D/M format */
/*------------------------------------------------*/
void print_addr( in_addr_t addr, int prefix ) {

  struct in_addr in;

  in.s_addr = htonl( addr );
  if ( prefix < 32 )
    printf( "%s/%d\n", inet_ntoa(in), prefix );
  else
    printf( "%s/32\n", inet_ntoa(in));

} /* print_addr() */


/*------------------------------------------------------------*/
/* Recursively compute network addresses to cover range lo-hi */
/*------------------------------------------------------------*/
/* Note: Worst case scenario is when lo=0.0.0.1 and hi=255.255.255.254
 *       We then have 62 CIDR bloks to cover this interval, and 125
 *       calls to split_range();
 *       The maximum possible recursion depth is 32.
 */
void split_range( in_addr_t addr, int prefix, in_addr_t lo, in_addr_t hi ) {

  in_addr_t bc, lower_half, upper_half;

  if ( (prefix < 0) || (prefix > 32) ) {
    fprintf( stderr, "%s: Invalid mask size %d!\n", PROG,  prefix );
    exit( 1 );
  }

  bc = broadcast(addr, prefix);

  if ( (lo < addr) || (hi > bc) ) {
    fprintf( stderr, "%s: Out of range limits: %x, %x for "
                     "network %x/%d, broadcast: %x!\n",
             PROG, lo, hi, addr, prefix, bc );
    exit( 1 );
  }

  if ( (lo == addr) && (hi == bc) ) {
    print_addr( addr, prefix );
    return;
  }

  prefix++;
  lower_half = addr;
  upper_half = set_bit( addr, prefix, 1 );
  
  if ( hi < upper_half ) {
    split_range( lower_half, prefix, lo, hi );
  } else if ( lo >= upper_half ) {
    split_range( upper_half, prefix, lo, hi );
  } else {
    split_range( lower_half, prefix, lo, broadcast(lower_half, prefix) );
    split_range( upper_half, prefix, upper_half, hi );
  }

} /* split_range() */


/*-----------------------------------------------------------*/
/* Convert an A.B.C.D address into a 32-bit host-order value */
/*-----------------------------------------------------------*/
static inline in_addr_t a_to_hl( char *ipstr ) {

  struct in_addr in;

  if ( !inet_aton(ipstr, &in) ) {
    fprintf( stderr, "%s: Invalid address %s!\n", PROG, ipstr );
    exit( 1 );
  }

  return( ntohl(in.s_addr) );

} /* a_to_hl() */


/*-----------------------------------------------------------------*/
/* convert a network address char string into a host-order network */
/* address and an integer prefix value                             */
/*-----------------------------------------------------------------*/
static inline network_addr_t str_to_netaddr( char *ipstr ) {

  long int prefix = 32;
  char *prefixstr;
  network_addr_t netaddr;

  if ( (prefixstr = strchr(ipstr, '/')) ) {
    *prefixstr = '\0';
    prefixstr++;
    prefix = strtol( prefixstr, (char **) NULL, 10 );
    if ( errno || (*prefixstr == '\0') || (prefix < 0) || (prefix > 32) ) {
      fprintf( stderr, "%s: Invalid prefix /%s...!\n", PROG, prefixstr );
      exit( 1 );
    }
  }

  netaddr.pfx = (int) prefix;
  netaddr.addr = network( a_to_hl(ipstr), prefix );
  netaddr.broadcast = broadcast(netaddr.addr, netaddr.pfx);

  return( netaddr );

} /* str_to_netaddr() */


/*----------------------------------------------------------*/
/* compare two network_addr_t structures; used with qsort() */
/* sort in increasing order by address, then by prefix.     */
/*----------------------------------------------------------*/
int compar_netaddr( const void *p1, const void *p2 ) {

  network_addr_t *na1 = (network_addr_t *) p1, *na2 = (network_addr_t *) p2;

  if ( na1->addr < na2->addr )
    return( -1 );
  if ( na1->addr > na2->addr )
    return( 1 );
  if ( na1->pfx < na2->pfx )
    return( -1 );
  if ( na1->pfx > na2->pfx )
    return( 1 );
  return( 0 );

} /* compar_netaddr() */


/*------------------------------------------------------*/
/* Print out an address range in a.b.c.d-A.B.C.D format */
/*------------------------------------------------------*/
void print_addr_range( in_addr_t lo, in_addr_t hi ) {

  struct in_addr in;

  if ( lo != hi ) {
    in.s_addr = htonl( lo );
    printf( "%s-", inet_ntoa(in) );
  }

  in.s_addr = htonl( hi );
  printf( "%s\n", inet_ntoa(in) );

} /* print_addr_range() */


/*-------------------------------------------------------------------------*/
/* Convert a list of A.B.C.D/M network addresses from stdin into a list of */
/* ranges on stdout                                                        */
/*-------------------------------------------------------------------------*/
void netaddr_to_range( char *file ) {

  #define NETADDR_INC (65536 * 2)
  #define MAX_LINE 1024
  network_addr_t *netaddrs = NULL;
  int nmax = 0;
  char ipstr[MAX_LINE + 1];
  in_addr_t lo, hi;
  int i, n;
  FILE *fp = stdin;

  if ( file && *file ) {
    if ( !(fp = fopen(file, "r")) ) {
      fprintf( stderr, "%s: %s - %s\n", PROG, file, strerror(errno) );
      exit( 1 );
    }
  }

  for ( n = 0; fgets(ipstr, MAX_LINE, fp) ; n++ ) {
    if ( n >= nmax ) {
      nmax += NETADDR_INC;
      netaddrs = realloc( netaddrs, nmax * sizeof(network_addr_t) );
    }
    netaddrs[n] = str_to_netaddr( ipstr );
  }

  if ( n == 0 )
    return;

  qsort( (void *) netaddrs, n, sizeof(network_addr_t), compar_netaddr );

  // exit(0);

  /* we're guaranteed to have at least one network address at this point */
  lo = netaddrs[0].addr;
  hi = netaddrs[0].broadcast;

  int total = 0;

  for ( i = 1; i < n; i++ ) {

    if ( netaddrs[i].broadcast <= hi ) {
      continue;
    }

    if ( netaddrs[i].addr == hi + 1 ) {
      hi = netaddrs[i].broadcast;
      continue;
    }

    if ( Cflg )
      total += hi - lo + 1;
    else if ( Jflg )
      split_range(0, 0, lo, hi);
    else
      print_addr_range( lo, hi );

    lo = netaddrs[i].addr;
    hi = netaddrs[i].broadcast;
  }

  if ( Cflg ) {
    total += hi - lo + 1;
    printf("%d\n", total);
  }
  else if ( Jflg )
    split_range(0, 0, lo, hi);
  else
    print_addr_range( lo, hi );

} /* netaddr_to_range() */


/*----------------------------------------------------------------------------*/
/*----------------------------------------------------------------------------*/
int main( int argc, char **argv ) {

  in_addr_t lo, hi;
  network_addr_t netaddr;

  if ( (PROG = strrchr(argv[0], '/')) )
    PROG++;
  else
    PROG = argv[0];

  /* -j or -J, with optional input file name */
  if ( (argc == 2 || argc == 3) &&
       ((Jflg = (strcmp(argv[1], "-J") == 0)) || (strcmp(argv[1], "-j") == 0) || (Cflg = (strcmp(argv[1], "-C") == 0)))
     ) {
    netaddr_to_range( argv[2] );
    return( 0 );
  }

  /* -s lo hi */
  if ( (argc == 4) && (strcmp(argv[1], "-s") == 0) ) {
    netaddr = str_to_netaddr( argv[2] );
    lo = network( netaddr.addr, netaddr.pfx );
    netaddr = str_to_netaddr( argv[3] );
    hi = broadcast( netaddr.addr, netaddr.pfx );
    split_range( 0, 0, lo, hi );
    return( 0 );
  }

  printf( "\n Usage: %s -j | -J | -s <start-addr> <end-addr>\n\n"
          " Where: \"-j\", \"-J\" and \"-s\" are mutually exclusive.\n\n"
          "   -j [file]\n"
          "       Join the network addresses given as A.B.C.D[/M] in \"file\"\n"
          "       and print out ranges to stdout. Unless \"file\" is given,\n"
          "       file=stdin will be used.\n"
          "\n"
          "   -J [file]\n"
          "       Same as \"-j\", except that joined results are printed as\n"
          "       the minimum required number of CIDR network address blocks.\n"
          "\n"
          "   -C [file]\n"
          "       Print only the count of unique IPs present.\n"
          "\n"
          "   -s <start-addr> <end-addr>\n"
          "       Split the range from \"start-addr\" to \"end-addr\" into\n"
          "       the minimum number of CIDR network address blocks required\n"
          "       to cover it. \"start-addr\" and \"end-addr\" may be of the\n"
          "       form A.B.C.D[/M].\n"
          "\n"
          "   \"A.B.C.D\" is an IPv4 network address ( 0 <= A/B/C/D <= 255 ).\n"
          "   \"M\" is the CIDR representation of a netmask value ( 1 <= M <= 32 ).\n"
          "\n"
          , PROG);
  return( 1 );

}
