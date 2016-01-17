#!/usr/bin/perl -w

#
# Find FireHOL program lines that are using program names direct rather
# than via detected environments
#

use strict;
use Data::Dumper;
use File::Basename;

if (@ARGV == 0) {
  print "Usage: ./packaging/firehol/detect-cmd.pl configure.ac sbin/file.in ...\n";
  print "\n";
  print "Finds usages of commands which should be converted to \$COMMAND_CMD format\n";
  exit 0;
}

my %commands = ();
foreach my $undetectable (qw/grep egrep sed/) {
  $commands{$undetectable} = 1;
}

my $acfile = shift @ARGV;
open C, "<$acfile" or die "Unable to open $acfile";
while (<C>) {
  if (/AX_CHECK_PROG/ or /AX_NEED_PROG/) {
    my @fields = split /[][]/;
    $commands{$fields[3]} = 1;
  }
}

my $status = 0;
my @commands = sort(keys(%commands));

#print join(",", @commands), "\n";
#exit 0;

sub printit {
  $status = 1;
  my $message = join('', @_);

  print basename($ARGV), ":", $., ": ", $message;
}

my $case = 0;
my $case_start = 0;
while (<>) {
  next if (/^\t*[YN]\|/); # Skip command tables
  next if (/^[[:space:]]*$/); # Skip blank lines
  next if (/^[[:space:]]#/); # Skip pure comments for efficiency
  next if (/`which .*head/); # Skip special case - initial command detection

  if (/^[[:space:]]*case\b/) {
    $case++;
    $case_start = 1;
    next;
  }
  if ($case > 0) {
    if (/^[[:space:]]*;;/) {
      $case_start = 1;
      next;
    }
    $case-- if (/^[[:space:]]*esac\b/);
  } else {
    $case_start = 0;
  }

  my @present=();
  foreach my $command (@commands) {
    push @present, $command if /\b$command\b/;
  }

  foreach my $present (@present) {
    if (/#.*\b$present\b/) {
      #printit "$present in a comment: $_";
    } elsif (/\${?$present}?/) {
      #printit "$present as a variable: $_";
    } elsif (/`[^`]*\b$present\b/ and /[|&;`][[:space:]]*$present/) {
      printit "$present in backtick substitution: $_";
    } elsif (/(\$\(|\`)[^)]*\b$present\b/ and /[(|&;`][[:space:]]*$present/) {
      printit "$present in substitution: $_";
    } elsif ($case_start == 0 and
             (/^[[:space:]]*$present$/ or /^[[:space:]]*$present\b[^=]/
                                       or /[|&;][[:space:]]*$present\b/)) {
      if (/^$present\(\)/) {
        delete $commands{$present}; # Redefined as a function
        @commands = sort(keys(%commands));
      } else {
        printit "$present used as a command: $_";
      }
    }
  }
  $case_start = 0 if ($case_start);
}

exit $status;
