#!/usr/bin/perl -w

use strict; 

# ==========
# Author:   David Tonhofer
# Rights:   Public Domain
#
# Description:
#
# Extract a value from a file of "=" separated key-value pairs.
# The key and filename are passed as arguments.
# ==========

# Pass the name of a file and a key

my $file = $ARGV[0];
my $key  = $ARGV[1];

if (!$file) {
   die "No name of file to open given"
}

if (! -f $file) {
   die "The indicated file '$file' does not exist"
}

if (!$key) {
   die "No key given"
}

if (! $key =~ /^\w+$/) {
   die "The given key '$key' does not consist only of 'word characters'"
}

open(my $fh, $file) or die "Could not open file '$file': $!";
my @lines = <$fh>;
close $fh;

for my $line (@lines) {
   chomp $line;
   if ($line =~ /^\s*$/ || $line =~ /^\s*#/) {
      next
   }
   if ($line =~ /^\s*(\w+?)\s*=\s*(.*?)\s*(#.*)?$/) {
      my $line_key   = $1;
      my $line_value = $2;
      if ($line_key eq $key) {
         print "$line_value\n";
         exit 0
      }
   }
   else {
      print STDERR "Could not match line '$line'\n"
   }
}

# print STDERR "Did not find a line matching '$key' in file '$file'\n";
# OK, but no result!

exit 0

