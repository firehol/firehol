package servicedb;

use strict;
use Data::Dumper;
use Text::ParseWords;

#
# Simple line-oriented parser helper routines
#

my $filename;
my $fh;
my $line;
my $lineno;

sub getpos {
  return "$filename:$lineno";
}

sub set {
  $filename = shift;
  $fh = shift;
  $lineno = shift;
  $line = undef;
}

sub curr_line {
  return $line;
}

sub next_line_int {
  $line = <$fh>;
  $lineno++;
  unless (defined($line)) {
    close $fh;
    return;
  }

  while ($line =~ /^[[:space:]]*#/) {
    $line = <$fh>;
    $lineno++;
    return unless defined($line);
  }

  chomp $line;
  $line =~ s/^[[:space:]]*#.*//;
  $line =~ s/[[:space:]]+$//;
}

sub next_line {
  next_line_int();
  while (defined($line) and $line =~ /^$/) {
    next_line_int();
  }
}

sub err {
  my $message = shift;
  die getpos() . ": $message\n";
}

sub e_exp {
  my $expected = shift;
  my $actual = shift;
  $actual = "<EOF>" unless defined($actual);
  err("expected '$expected', got '$actual'");
}

sub open_file {
  my $name = shift;
  die "No name given\n" unless $name;

  open $fh, "<$name" or die "$name: Unable to open\n";
  return $fh;
}

# Extract service information from script
sub read_script {
  my $firehol_script = shift;
  open_file($firehol_script);

  my %services = ();
  my %all_run = ();

  while (<$fh>) {
    if (/^(server|client)_([[:alnum:]_]+)_ports="?([^"]*)"?/) {
      $services{$2}{$1} = $3;
    }
    if (/^(helper)_([[:alnum:]_]+)="?([^"]*)"?/) {
      my $field = $1;
      my $name = $2;
      my $val = $3;
      $services{$name}{$field} = $val;
      $services{$name}{"mod"} = $val;
      $services{$name}{"mod"} =~ s/([^[:space:]]+)/nf_conntrack_$1/g;
      $services{$name}{"mod"} =~ s/[[:space:]]+/,/g;
      $services{$name}{"modnat"} = $val;
      $services{$name}{"modnat"} =~ s/([^[:space:]]+)/nf_nat_$1/g;
      $services{$name}{"modnat"} =~ s/[[:space:]]+/,/g;
    }
    if (/^rules_([[:alnum:]_]+)\(\) +{/) {
      $services{$1}{type} = "complex";
    }
    $services{custom}{type} = "custom";
    if (/^ALL_SHOULD_ALSO_RUN="/) {
      s/^[^ ]* //;
      s/"$//;
      for my $s (split(/[[:space:]]+/, $_)) {
        $all_run{$s} = 1;
      }
    }
  }
  close $fh;
  return \%services, \%all_run;
}

# Extract service information from database
sub read_db {
  my $services_db = shift;
  open_file($services_db);

  my %single_cmd = (
                    'CPORT' => 'client',
                    'SPORT' => 'server',
                    'MOD' => 'mod',
                    'MODNAT' => 'modnat',
                    'NAME' => 'name',
                    'ALIAS' => 'alias',
                    'WIKI' => 'wiki',
                    'HOME' => 'home',
                   );

  my %multi_cmd = (
                    'EXAMPLE' => 'example',
                    'NOTES' => 'notes',
                   );

  my %db = ();
  my %dbalias = ();
  next_line;
  while (curr_line()) {
    my $name;
    if ($line =~ /^SERVICE (.*)/) {
      my $name = $1;
      next_line;
      last unless $line;
      while ($line =~ /^\t([[:alnum:]]+)/) {
        my $cmd = $1;
        $line =~ s/^[[:space:]]+[[:alnum:]]+[[:space:]]+//;
        if ($single_cmd{$cmd}) {
          my $n = $single_cmd{$cmd};
          $db{$name}{$n} = $line;
          if ($n eq "alias") {
            $dbalias{$line} = $name;
          }
          next_line;
          last unless $line;
        } elsif ($multi_cmd{$cmd}) {
          my $n = $multi_cmd{$cmd};
          my $val;
          next_line;
          last unless $line;
          while ($line =~ /^\t\t/) {
            $line =~ s/^[[:space:]]+//;
            $line =~ s/^-$//;
            if (defined($val)) { $val .= "\n" . $line } else { $val = $line; }
            next_line;
            last unless $line;
          }
          $db{$name}{$n} = $val if (defined($val));
        } else {
          err "Unknown command $cmd\n";
        }
        last unless $line;
      }
    } else {
      err "Unknown line $line\n";
    }
  }
  close $fh;
  return \%db, \%dbalias;
}

sub validate {
  my $services = shift;
  my $db = shift;
  my $dbalias = shift;

  my $err;
  my %servs = ();

  foreach my $s (sort(keys(%{$services}))) {
    unless ($$db{$s} or $$dbalias{$s}) {
      print STDERR "Service $s in firehol but not in services-db.data\n";
      $err = 1;
    }
    $servs{$s} = 1;
  }

  foreach my $d (sort(keys(%{$db}))) {
    unless ($$services{$d}) {
      print STDERR "Service $d services-db.data but not in firehol\n";
      $err = 1;
    }
    $servs{$d} = 1;
  }

  foreach my $k (sort(keys(%servs))) {
    my $name = $$db{$k}{"name"};
    if (!defined($name) and !defined($$dbalias{$k})) {
      print STDERR "Service $k has no NAME or ALIAS in services-db.txt\n";
      $err = 1;
    }
    if (defined($$db{$k}{"mod"}) and !defined($$services{$k}{"mod"})) {
      print STDERR "Service $k has services-db.txt MOD but no helper in script!\n";
      $err = 1;
    }
    if (defined($$db{$k}{"modnat"}) and !defined($$services{$k}{"modnat"})) {
      print STDERR "Service $k has services-db.txt MODNAT but no helper in script!\n";
      $err = 1;
    }
    if (defined($$db{$k}{"mod"}) and defined($$services{$k}{"mod"})) {
      if ($$db{$k}{"mod"} eq $$services{$k}{"mod"}) {
        print STDERR "Service $k MOD in services-db.txt is redundant\n";
        $err = 1;
      } elsif ($$db{$k}{"mod"} ne "N/A" and $$db{$k}{"mod"} !~ /^See/) {
        print STDERR "Service $k services-db.txt MOD, different to helper in script and not N/A!\n";
        $err = 1;
      }
    }
    if (defined($$db{$k}{"modnat"}) and defined($$services{$k}{"modnat"})) {
      if ($$db{$k}{"modnat"} eq $$services{$k}{"modnat"}) {
        print STDERR "Service $k MODNAT in services-db.txt is redundant\n";
        $err = 1;
      } elsif ($$db{$k}{"modnat"} ne "N/A" and $$db{$k}{"modnat"} !~ /^See/) {
        print STDERR "Service $k services-db.txt MODNAT, different to helper in script and not N/A!\n";
        $err = 1;
      }
    }
  }
  die "Validation errors" if ($err);

  # Sort case-insensitive unless identical e.g. ICMP vs icmp
  return sort { return $a cmp $b if (uc($a) eq uc($b));
                return uc($a) cmp uc($b) } keys(%servs);
}

1;
