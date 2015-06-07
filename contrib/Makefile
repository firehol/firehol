all: iprange

iprange: iprange.c
	$(CC) -Wall -Wextra -O3 -o iprange iprange.c

clean:
	-rm iprange

install: iprange
	install --owner root --mode 0755 --preserve-timestamps --strip iprange /usr/bin/iprange
	install --owner root --mode 0700 --preserve-timestamps --strip iprange /etc/firehol/ipsets/iprange
	install --owner root --mode 0700 --preserve-timestamps ipv4_range_to_cidr.awk /etc/firehol/ipsets/ipv4_range_to_cidr.awk
	install --owner root --mode 0700 --preserve-timestamps update-ipsets.sh /etc/firehol/ipsets/update-ipsets.sh

.PHONY: all clean install
