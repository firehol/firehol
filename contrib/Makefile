all: iprange

iprange: iprange.c
	$(CC) -Wall -Wextra -O3 -o iprange iprange.c

clean:
	-rm iprange

install: iprange
	install --owner root --mode 0755 --preserve-timestamps --strip iprange /usr/bin/iprange

.PHONY: all clean install
