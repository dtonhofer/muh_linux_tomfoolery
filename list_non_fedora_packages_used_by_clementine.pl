#!/usr/bin/perl -w

# We want to know what packages not by vendor "Fedora Project" are being used by
# a currently running "Clementine" as it streams an AAC music stream over the Internet.
#
# Sample output:
#
# /usr/lib64/libfaad.so.2.0.0 --0--> Vendor = rpms.kwizart.net, Name = faad2-libs
# /usr/lib64/gstreamer-0.10/libgstfaad.so --0--> Vendor = RPM Fusion, Name = gstreamer-plugins-bad
# /usr/lib64/gstreamer-0.10/libgstffmpeg.so --0--> Vendor = Koji, Name = gstreamer-ffmpeg

# Step 1: Get all processes

open(my $PS,"ps -A |") or die "Could not open pipe from ps -A: $!";
my @pslines = <$PS>;
close($PS);

# Step 2: Get those processes that have $CLEM in their name and generate comme-separated list of their PIDs

my $CLEM = "clementine";
my @pids = ();

for my $line (@pslines) {
   if ($line =~ /^(\d+)\s+(\S+)\s+(\S+)\s+$CLEM/ ) {
     push(@pids,$1)
   }
}

my $pidlist = join(',',@pids);

# Step 3: Get the open files held by the processes listed in "$pidlist"

open(my $LSOF,"lsof -p '$pidlist'|") or die "Could not open pipe from lsof: $!";
my @lsoflines = <$LSOF>;
close($LSOF);

# Step 4: Check which one of the open files are indeed files that belong to packages not from "Fedora Project"

for my $line (@lsoflines) {
   chomp $line;
   if ($line =~ /\d+\s+\d+\s+(\S+)$/) {
      my $file = $1;
      if ( -f $file ) {
         # VENDOR is one of the fields of the RPM database, see "rpm --querytags" to list all the tags
         open(my $RPM,"rpm --query --queryformat='Vendor = %{VENDOR}, Name = %{NAME}' --file '$file' |") or die "Could not open pipe from rpm: $!";
         my @rpmdata = <$RPM>;
         close($RPM);
         $res = $?;
         if ($res == 0) {
            my $line1 = $rpmdata[0]; chomp $line1;
            if (! ($line1 =~ /^Vendor = Fedora Project/)) {
               print "$file --$res--> $line1\n";
            }
         }
      }
   }
}


