#!/usr/bin/perl -w

use strict;
use utf8;

# 234567890123456789012345678901234567890123456789012345678901234567890123456789
################################################################################
# Get information on the system's memory, organized as a tree
#
# Run with "KiB", "MiB", "GiB" to display valus in the corresponding unit.
# Or leave out to have values scaled to less than 1024 in any case.
#
# Run with "watch" for continuous output.
#
# This is based on old code written at M-PLIFY. Published under the
# MIT License.
#
# Next up: detect problems and inconsistencies in the representation (as
# I'm not sure the tree representation is actually correct, even though
# I have checked docs and books)
################################################################################

printMemoryUsage( getMeminfoData() , getProcessData(), $ARGV[0] );

################################################################################
# Generation of output
# --------------------
#
# Interpretation of the values is as follows (may not be fully correct):
#
# Page size is generally 4096 
#
# /proc/meminfo
#   active = 778256384 - Memory that has been used more recently and usually not reclaimed unless absolutely necessary (part of the cache or not?)
#   buffers = 108290048 - Memory in buffer cache, used for disk I/O, small size, contains disk blocks. Mostly useless as metric nowadays. Not swapped.
#   cached = 1128198144 - Memory in the pagecache (diskcache) minus SwapCache.
#   commitlimit = 2910482432
#   committed_as = 514187264 - Estimate of how much RAM (+swap?) you would need to make a 99.99% guarantee that there never is OOM for this workload. 
#   dirty = 438272 - Part of "cached" that needs to be written back.
#   highfree = 1048576 - See "hightotal".
#   hightotal = 671023104 - Is the total amount of free memory in the high region. Highmem is all memory above (approx) 860MB of physical RAM.
#   hugepages_free = 0
#   hugepages_total = 0
#   hugepagesize = 4194304
#   inactive = 749842432 - See "active" (maybe only relative to the cache)
#   lowfree = 19116032 - See "lowtotal"
#   lowtotal = 922103808 - The amount of free memory of the low memory region, which the kernel can address directly. All kernel datastructures go here.
#   mapped = 313671680 - Memory used for mmap operations of disk files
#   memfree = 20164608 - See "memtotal"
#   memtotal = 1593126912 - Total usable ram (i.e. physical ram minus a few reserved bits and the kernel binary code)
#   memused = 1572962304 - See "memtotal"
#   pagetables = 2072576 - Memory used by pagetables
#   slab = 31596544 - Kernel structures
#   swapcached = 0 - Memory that once was swapped out, is swapped back in but still also is in the swapfile. 
#   swapfree = 2113691648 - See "swaptotal"
#   swaptotal = 2113921024 - Total amount of physical swap memory.
#   swapused = 229376 - See "swaptotal"
#   vmallocchunk = 105082880
#   vmalloctotal = 109043712
#   vmallocused = 3461120
#   writeback = 0 - RAM being written back to disk
#
# /proc/stat
#   btime = 1196798258 - boot time
#   contextswitches = 1987070624 
#   cpu.idle = 379556414
#   cpu.iowait = 27921016
#   cpu.irq = 87293
#   cpu.nice = 29143965
#   cpu.softirq = 0
#   cpu.system = 14890252
#   cpu.system_sum = 14977545
#   cpu.user = 49281938
#   cpu.user_sum = 78425903
#   cpu0.idle = 379556414
#   cpu0.iowait = 27921016
#   cpu0.irq = 87293
#   cpu0.nice = 29143965
#   cpu0.softirq = 0
#   cpu0.system = 14890252
#   cpu0.system_sum = 14977545
#   cpu0.user = 49281938
#   cpu0.user_sum = 78425903
#   interrupts = 1192971253
#   processes = 12279957
#   procs_blocked = 0
#   procs_running = 1
#
# /proc/vmstat
#   allocstall = 47
#   kswapd_inodesteal = 5286299
#   kswapd_steal = 584758979
#   nr_dirty = 107 - pages that are dirty
#   nr_mapped = 76610 
#   nr_page_table_pages = 506
#   nr_slab = 7714 - pages in the slab
#   nr_unstable = 0 
#   nr_writeback = 0 - pages under writeback
#   pageoutrun = 15764388
#   pgactivate = 53420117
#   pgalloc_dma = 83710219
#   pgalloc_high = 370975849
#   pgalloc_normal = 2208625913
#   pgdeactivate = 43899209
#   pgfault = 1272896786 - minor page faults since last boot
#   pgfree = 2663317058
#   pginodesteal = 0
#   pgmajfault = 104134 - major page faults since last boot
#   pgpgin = 15464165 - pages moved in since last boot
#   pgpgout = 1788628193 - pages moved out since last boot
#   pgrefill_dma = 16473828
#   pgrefill_high = 55619898
#   pgrefill_normal = 160924490
#   pgrotated = 8637
#   pgscan_direct_dma = 99
#   pgscan_direct_high = 1221
#   pgscan_direct_normal = 1485
#   pgscan_kswapd_dma = 16912572
#   pgscan_kswapd_high = 91842630
#   pgscan_kswapd_normal = 494765601
#   pgsteal_dma = 16386355
#   pgsteal_high = 88715426
#   pgsteal_normal = 479659918
#   pswpin = 64 - pages swapped in since last boot
#   pswpout = 76 - pages swapped out since last boot
#   slabs_scanned = 60352512
################################################################################

################################################################################
# Convert a value in KiB some other unit. Return a ("value","unit") pair
# If "GiB" is passed as second parameter: Convert to GiB
# If "MiB" is passed as second parameter: Convert to MiB
# If "KiB" is passed as second parameter: Convert to KiB, i.e. do nothing
# otherwise
# Convert to the first unit that lets value drop below 1024
################################################################################

sub memConvert {
   my ($valIn,$convert) = @_;
   my ($value,$unit) = ($valIn,"KiB");
   # Only do something if we want conversion and conversion shall be beyond KiB
   if ($convert eq "GiB") {
      $value = ($value / 1024) / 1024;
      $unit = "GiB"
   }
   elsif ($convert eq "MiB") {
      $value = $value / 1024;
      $unit = "MiB"
   }
   elsif ($convert eq "KiB") {
      # Leave as is
   }
   else {
      # Flexible conversion
      if ($value>1024) {  
         $value = $value / 1024;  $unit = "MiB"; 
         if ($value>1024) { 
            $value = $value / 1024;  $unit = "GiB"
         }
      }
   }
   return ($value,$unit)
}

################################################################################
# Helper: build output string
################################################################################

sub stringBuild {
   my ($prefix,$value,$units) = @_;
   my $dotstring = '.....................................................';
   my $data = sprintf("%.2f", $value);
   return $prefix . substr($dotstring,0,length($dotstring) - length($prefix) - length($data)) . $data . ' ' . $units . "\n";
}

################################################################################
# Print result to stdout, based on the memory and processd data
################################################################################

sub printMemoryUsage {

  my($md,$pd,$convert)                  = @_; # hashrefs: meminfoData and processData, and conversion flag
  my($caching,$used,$copied,$nonkernel) = (0,0,0,0);

  my $output = "Total physical memory available\n";
  $output .= stringBuild("├──Swap"                          , memConvert($$md{swaptotal},$convert));
  $output .= stringBuild("│  ├──Free"                       , memConvert($$md{swapfree},$convert));
  $output .= stringBuild("│  └──Used"                       , memConvert($$md{swaptotal} - $$md{swapfree},$convert));
  $output .= stringBuild("└──RAM"                           , memConvert($$md{memtotal},$convert));
  $output .= stringBuild("   ││├──Free"                     , memConvert($$md{memfree},$convert));
  $output .= stringBuild("   ││└──Used"                     , memConvert($used = $$md{memtotal} - $$md{memfree},$convert));
  $output .= stringBuild("   ││   ├──Kernel slab"           , memConvert($$md{slab},$convert));
  $output .= stringBuild("   ││   │  └──Page tables"        , memConvert($$md{pagetables},$convert));
  $output .= stringBuild("   ││   └──Non-kernel"            , memConvert($nonkernel = $used - $$md{slab},$convert));
  $output .= stringBuild("   ││      ├──Caching"            , memConvert($caching = $$md{buffers} + $$md{cached} + $$md{swapcached},$convert));
  $output .= stringBuild("   ││      │  ├──Buffer cache"    , memConvert($$md{buffers},$convert));
  $output .= stringBuild("   ││      │  ├──Page cache"      , memConvert($$md{cached},$convert));
  $output .= stringBuild("   ││      │  │  ├──Mapped"       , memConvert($$md{mapped},$convert));
  $output .= stringBuild("   ││      │  │  │  ├──Dirty"     , memConvert($$md{dirty},$convert));
  $output .= stringBuild("   ││      │  │  │  ├──Writeback" , memConvert($$md{writeback},$convert));
  $output .= stringBuild("   ││      │  │  │  └──Clean"     , memConvert($$md{mapped} - $$md{dirty} - $$md{writeback},$convert));
  $output .= stringBuild("   ││      │  │  └──Copied"       , memConvert($copied = $$md{cached} - $$md{mapped},$convert));
  $output .= stringBuild("   ││      │  └──Swapcached"      , memConvert($$md{swapcached},$convert));
  $output .= stringBuild("   ││      └──User processes"     , memConvert($used - $caching - $$md{slab},$convert));
  $output .= stringBuild("   ││          └──Sum RSS"        , memConvert($$pd{sumrss},$convert));
  $output .= "   ││\n";
  $output .= stringBuild("   │├──Inactive pages"            , memConvert($$md{inactive},$convert));
  $output .= stringBuild("   │├──Active pages"              , memConvert($$md{active},$convert));
  $output .= stringBuild("   │└──Other pages"               , memConvert($$md{memtotal} - $$md{inactive} - $$md{active},$convert));
  $output .= "   │\n";
  if (exists $$md{lowtotal}) {
     $output .= stringBuild("   ├──Low memory"                 , memConvert($$md{lowtotal},$convert));
     $output .= stringBuild("   │  ├──Free"                    , memConvert($$md{lowfree},$convert));
     $output .= stringBuild("   │  └──Used"                    , memConvert($$md{lowtotal} - $$md{lowfree},$convert));
  }
  if (exists $$md{hightotal}) {
     $output .= stringBuild("   └──High memory"                , memConvert($$md{hightotal},$convert));
     $output .= stringBuild("      ├──Free"                    , memConvert($$md{highfree},$convert));
     $output .= stringBuild("      └──Used"                    , memConvert($$md{hightotal} - $$md{highfree},$convert));
  } 
  binmode STDOUT, ":utf8";
  print $output
}

################################################################################
# Get all lines from "/proc/meminfo" into a hash mapping "key" to "values"
#
# The keys are fully lowercased.
# The values are expressed in KiB (1024 byte)
# Function call exit with error code 1 if a problem occurs.
#
# If all goes well, the reference to the hash which contains the key->value 
# mappings is returned
################################################################################

sub getMeminfoData {
   my $md  = {};
   my $meminfoFile = "/proc/meminfo";
   open(my $cat,"< $meminfoFile") or die "Could not open '$meminfoFile': $!";
   my @cat = <$cat>;
   close $cat or die "Could not close '$meminfoFile': $!";
   for my $line (@cat) {
      chomp $line;
      if ($line =~ /^\s*(\S+)\s*:\s*(\d+)\s*(\S*)\s*$/) {
         my($key,$value,$unit) = (lc($1),$2 * 1,$3);
         my $multiplier;
         if (!exists $$md{$key}) {
            if ($unit eq "kB" || $unit eq '') {
               # Assume this means KiB (1024), not KB (1000)
               # Or else no unit, just a count
               $multiplier = 1
            }
            else {
               print STDERR "Unknown unit '$unit' in line '$line' of '$meminfoFile' -- exiting\n";
               exit 1
            }
            $$md{$key} = $value * $multiplier;
         }
         else {
            print STDERR "Duplicate key in '$meminfoFile', line '$line' -- exiting\n";
            exit 1
         }
      }
      else {
         print STDERR "Could not parse '$meminfoFile', line '$line' -- exiting\n";
         exit 1
      }
   }
   # Additional computations according to "proc/sysinfo.c" of package "procps-3.2.3"
   # $$md{"swapused"} = $$md{"swaptotal"} - $$md{"swapfree"};
   # $$md{"memused"}  = $$md{"memtotal"}  - $$md{"memfree"};
   if (exists $$md{lowtotal} && $$md{lowtotal} == 0) {
      # Consider the whole of the memory as "low" (architecture-dependent)
      $$md{lowtotal} = $$md{memtotal};
      $$md{lowfree}  = $$md{memfree}
   }
   return $md
}

################################################################################
# Get all lines from "/proc/stat" into a hash mapping "key" to "values"
#
# The keys are fully lowercased.
# The values for the CPU will be references to hashes themselves, with the 
# per-CPU information.
#
# If all goes well, the reference to the hash which contains the key->value 
# mappings is returned
################################################################################

sub getStatLines {
   my ($preflatten) = @_; # Set to true to flatten the per-CPU values in the result
   my  $statRef     = {};
   my  $statFile    = "/proc/stat";
   open(my $cat,"< $statFile") or die "Could not open '$statFile': $!";
   my @cat = <$cat>;
   close $cat or die "Could not close '$statFile': $!";
   for my $line (@cat) {
      chomp $line;
      if ($line =~ /^\s*(\S+)\s*(.*)$/) {
         my($cpuKey,$value) = (lc($1),$2);
         if (!exists($$statRef{$cpuKey})) {
            if ($cpuKey =~ /^cpu/) {
               my $cpuRef = separateStatCpuValues($cpuKey,$value); # returns hash ref
               if ($preflatten) {
                 flattenHash($cpuKey,$statRef,$cpuRef) # flattens the returned per-CPU hash into the toplevel hash
               }
               else {
                 $$statRef{$cpuKey} = $cpuRef # sets up the returned per-CPU hash as value
               }
            }
            elsif ($cpuKey =~ /^intr/) {
               $$statRef{"interrupts"} = extractInterruptsValue($value) # rename key and get unique value out
            }
            elsif ($cpuKey eq "ctxt") {
               $$statRef{"contextswitches"} = $value # rename key
            }
            else {
               $$statRef{$cpuKey} = $value
            }
         }
         else {
            print STDERR "Duplicate key in '$statFile', line '$line' -- exiting\n";
            exit 1
         }
      }
      else {
         print STDERR "Could not parse '$statFile', line '$line' -- exiting\n";
         exit 1
      }
   }
   return $statRef
}

################################################################################
# Helper: Separate out the per-CPU values into their own hash.
#
# Is passed the name of the key (for debugging) and the value string that has to 
# be taken apart.
#
# Returns the reference to the hash which contains the key->value mappings.
################################################################################

sub separateStatCpuValues {
  my ($cpuKey,$cpuValues) = @_;
  my $cpuRef = {};
  if ($cpuValues =~ /^(\d+) (\d+) (\d+) (\d+) (\d+) (\d+) (\d+)$/) {
     $$cpuRef{"user"} = $1;
     $$cpuRef{"nice"} = $2;
     $$cpuRef{"system"}  = $3;
     $$cpuRef{"idle"} = $4;
     $$cpuRef{"iowait"} = $5;
     $$cpuRef{"irq"} = $6;
     $$cpuRef{"softirq"} = $7;
     $$cpuRef{"system_sum"} = $3 + $6 + $7; 
     $$cpuRef{"user_sum"}   = $1 + $2;
     return $cpuRef;
  }
  else {
     print STDERR "Could not parse '/proc/stat' CPU value string '$cpuValues' for cpu '$cpuKey' -- exiting\n";
     exit 1;
  }
}

################################################################################
# Helper: Flatten a hash with "key" -> value mappings by copying the mappings
# into a destination hash as "superkey.key" -> value mappings.
################################################################################

sub flattenHash {
   my($superKey,$destHashRef,$opHashRef) = @_;
   for my $key (keys %$opHashRef) {
     my $value = $$opHashRef{$key};
     my $extendedKey = "$superKey.$key";
     if (!(exists $$destHashRef{$extendedKey})) {
        $$destHashRef{$extendedKey} = $value
     }
     else {
       print STDERR "The extended key '$extendedKey' already exists in the target hash -- exiting\n";
       exit 1
     }      
   }
}

################################################################################
# Helper: Separate out the first numeric value in a string of values.
# Is passed the name of the key (for debugging) and the value string that has to
# be taken apart.
################################################################################

sub extractInterruptsValue {
   my($values) = @_;
   if ($values =~ /^(\d+)/) {
      return $1
   }
   else {
      print STDERR "Could not parse '/proc/stat' interrupts value '$values' -- exiting\n";
      exit 1
   }
}

################################################################################
# Run the sum over RSS as given by 'ps' and also the number of processes
# Returns a result in KiB
################################################################################

sub getProcessData {
   my($sumRss,$procCount,$line) = (0,0,'');
   open(my $ps, "ps --no-headers -Ao 'rss' |") or die "Could not open pipe from 'ps': $!\n";
   my @ps = <$ps>;
   close($ps) or die "Could not close pipe from 'ps': $!\n";
   foreach my $line (@ps) {
     chomp $line ;
     $sumRss += $line*1; # in KiB
     $procCount++
   }
   return { "sumrss" => $sumRss, "processcount" => $procCount }
}

