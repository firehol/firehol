# iprange

The `aggregate` command installed on most systems is very slow.
If you have large netsets, this command is useless.

On Gentoo you can install `aggregate-flim`.

On any system you can download iprange from [here](http://www.cs.colostate.edu/~somlo/iprange.c), compile it with this:

```bash
gcc -Wall -O3 -o iprange iprange.c && cp iprange /usr/bin
```

`update-ipsets.sh` will search for an IP range aggregator in this order:

1. `iprange` in `/etc/firehol/ipsets`
2. `aggregate-flim` in the system path (e.g. `/usr/bin`)
3. `iprange` in the system path
4. `aggregate` (the slow one) in the system path

If none is found, `update-ipsets.sh` will not be able to aggregate ip ranges and a warning will be printed.
