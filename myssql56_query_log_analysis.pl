#!/usr/bin/perl

use strict;
use warnings;
use Switch;   # dnf install perl-Switch

# ############################################################################
# Last update: 2018-01-27
# License: MIT license, see https://opensource.org/licenses/MIT
# Script written in the context of:
# https://serverfault.com/questions/894074/mysql-general-query-log-analysis
# Available at:
# https://github.com/dtonhofer/muh_linux_tomfoolery
#
# If you are doing system/software archeology and have a MySQL 5.6 query log
# and want to get some statistics out of it to see who connects, and how many
# queries they issue and what they queries they issue, then this script may
# help. It read a MySQL 5.6 query log on stdin and builds a statistic over the
# queries. 
#
# There are two statistics, chosen by the `my $coarse = 1/0;` line:
# 
# * Coarse-grained statistics resulting in a list if users and query counts 
#   only.
# * Fine-grained statistics also grouping the SQL queries into "bins" and print
#   the "representative" query and the bin sizes too. Queries are put into the
#   same "bin" when their Levenshtein distance (editing distance) to the query
#   that initiated bin creation (the template) is "small enough" (in this case,
#   within 10% of the mean of the query lengths). A better program would parse
#   the SQL and compare the parse trees to see whether these only differ by 
#   constants. Still, this heuristic approach seems to work somewhat. 
# 
# For this script, one needs the "LevenshteinXS" library, which is backed by C
# code. The "Levensthein" library is too slow.
# 
# Processing speed: With LevenstheinXS, we process 35959949 log lines in 640 minutes:
# *936 lines/s* on a Intel(R) Core(TM) i3-6100 CPU @ 3.70GHz with an SSD.
#
# Evidently, if you have the general query log, you are aware of data 
# protection issues.
# ############################################################################

# -------
# Processing speed: With LevenstheinXS, we process 35959949 log lines in
# 640 minutes: 936 lines/s on a Intel(R) Core(TM) i3-6100 CPU @ 3.70GHz
# with an SSD.
# -------

# ---
# We need a module to compute the edit distance between two SQL queries.
# http://search.cpan.org/~jgoldberg/Text-LevenshteinXS-0.03/LevenshteinXS.pm
# http://search.cpan.org/dist/Text-Levenshtein/lib/Text/Levenshtein.pm
# One really needs the XS version of the Levensthein algorithm, otherwise the
# program runs too slow.
# ---

use Text::LevenshteinXS qw(distance);  # dnf install perl-Text-LevenshteinXS

# Additional logging?

my $verbose = 0;

# Just count queries instead of grouping them.

my $coarse = 1;

# ---
# As we read through the file, we will encounter "current timestamps".
# The latest will be stored in "when" (todo: transform into real datetime)
# ---

my $when = '1970-01-01 00:00:00'; # at the beginning, "when" is unknown

# ---
# Types of queries. We have a counter for each
# ---

my @qtypes = qw(select update insert alter delete drop call other);

# ---
# To track connections that are live at the current location of the general query log
# ---

# liveconns
# key: the connection id ("connid"), an integer which seems to be a monotonously increasing value
# val: a hashref generally called "$thisliveconn" with:
#        "connid" => connection id
#        "when"   => a string representing the datetime of the connection
#        "user"   => a string representing the user login (someone@somewhere)
#        "db"     => the name of the database in the connection reequest (may be missing)
# 
# There always seems to be a liveconnection with id "1", so create it at once

my $liveconns = { 1 => { 'connid' => 1,
                         'when'   => $when,
                         'user'   => "root" } };

# ---
# To collect statistics about SQL usage
# ---

# stats
# key: a string representing the user login (someone@somewhere)
# val: a hashref generally called "$thisstats" with:
#        "user"        => a string representing the user login (someone@somewhere)
#        "conncount"   => number of connections seen for this user
#        "querycount"  => number of queries run for this user
#        "selectcount" => number of select queries 
#        "updatecount" => number of update queries
#        "insertcount" => number of insert queries
#        "altercount"  => number of alter queries
#        "deletecount" => number of delete queries
#        "dropcount"   => number of drop queries
#        "callcount"   => number of call queries
#        "othercount"  => number of other queries
#        "queries"     => a hashref generally called "$queries" with:
#                         key: an SQL query (suitably mangled, basically a template)
#                         val: the number of times this query was submitted

my $stats = { };

# --- 
# A function to sort key of a hashref by their descending value of the hashref (which is an occurrence count)
# ---

sub sorterofqueries {
   my($queries) = @_; # hashref
   my @foo = (keys %$queries);
   # Sort in place by descending occurrence count (this is apparently optimized by Perl)
   @foo = sort { my $ca = $$queries{$a}; my $cb = $$queries{$b}; $cb <=> $ca } @foo; 
   return \@foo; # arrayref
}

# ---
# When an SQL query has been captured, this is called to update stats
# ---

sub terminateSql {
   my($sql,$user,$isprepare) = @_;
   print "Captured SQL: $sql\n" if $verbose;
   #
   # We don't have a good parser for MySQL SQL statements handy
   # (SQL-Statement is not the solution ... http://search.cpan.org/~rehsack/SQL-Statement-1.412/lib/SQL/Parser.pm)
   # 
   # So we use a hack: compute Levenshtein editing distance to already seen statements.
   # If it is small, assume the statements are the same!
   #
   # Unfortunately this algorithm is slow.
   # (There should be a way to break off the edit distance computation at some max value...)
   #
   # Clean up SQL statement
   # 1) Uppercase: Some queries are lowercase
   # 2) Multispace to monospace
   # 3) Trim whitespace at start and end
   #
   my $mangled = uc($sql);
   $mangled =~ s/\s+/ /g;
   $mangled =~ /^\s*(.*)\s*$/; $mangled = $1;
   if (!$mangled) {
      # nothing left (can this really happen?)
      return
   }
   #
   # Uninteresting crap!
   #
   if ($mangled =~ /^SET (NAMES|AUTOCOMMIT|CHARACTER|SESSION|OPTIMIZER|CHARACTER_SET_RESULTS|SQL_|@\@TX_ISOLATION|@\@SQL_SELECT_LIMIT)/ ||
       $mangled =~ /^SELECT (DATABASE|@\@TX_ISOLATION|CURRENT_USER) / ||
       $mangled =~ /^SHOW / ||
       $mangled =~ /^COMMIT/ ||
       $mangled =~ /^USE / ||
       $mangled =~ /^EXPLAIN / ||
       $mangled =~ /^DESCRIBE / ||
       $mangled =~ /^(UN)?LOCK TABLES/ ||
       $mangled =~ /^\/\*.*\*\//) {
      return
   }
   #
   # We also ignore the prepare statement (I am always happy to see these but they 
   # may be rare!) as there will be an execute statement later too.
   #
   if ($isprepare) {
      print STDERR "Honest-to-God 'prepare' statement by $user: $sql\n";
      return
   }
   #
   # Update stats. We have 1 additional query
   #
   die unless exists $$stats{$user};
   my $thisstats = $$stats{$user};
   die unless $$thisstats{user} eq $user;
   $$thisstats{querycount}++;
   switch ($mangled) {
   case /^SELECT/ { $$thisstats{selectcount}++ }
   case /^UPDATE/ { $$thisstats{updatecount}++ }
   case /^INSERT/ { $$thisstats{insertcount}++ }
   case /^ALTER/  { $$thisstats{altercount}++  } 
   case /^DELETE/ { $$thisstats{deletecount}++ }
   case /^DROP/   { $$thisstats{dropcount}++   }
   case /^CALL/   { $$thisstats{callcount}++   }
   else { $$thisstats{othercount}++; print STDERR "Unknown query operation: $mangled\n"; }
   }
   # 
   # Retrieve queries previously (approximatively) seen to match against them. 
   #
   die unless $$thisstats{queries};
   my $queries = $$thisstats{queries};
   #
   # If we just count, we stop here
   #
   return if ($coarse);
   #
   # To improve speed, do this with "test against query most frequently seen first" approach.
   #
   my $queryarray = sorterofqueries($queries);
   #
   # Now search over queryarray
   #
   my $foundq = undef;
   my $lenm = length($mangled);
   for my $q (@$queryarray) {
      my $lenq = length($q);
      my $lenmid = ($lenm + $lenq)/2;
      if (distance($mangled,$q)/$lenmid < 0.15) {  # MAGIC VALUE 15%!!!
          #print "Pretty similar\n";
          #print "  $mangled\n";
          #print "  $q\n";
         $foundq = $q;
         last
      }
   } 
   if ($foundq) { 
      # another occurrence
      $$queries{$foundq}++;
      print "User $user: $$queries{$foundq} instances of $foundq\n" if $verbose;
   }
   else {
      # first occurrence
      $$queries{$mangled} = 1;
      print "User $user: Fresh $$queries{$mangled}\n" if $verbose;
   }
}

# ---
# Loop over lines in query log
#
# The file we want to read is an MySQL "general query log" for MySQL 5.6
# https://dev.mysql.com/doc/refman/5.6/en/query-log.html
#
# We get the lines from the diamond
# ---

# An SQL statement may spread over several lines. "mlsql" is the accumulator
# of those lines. If it is "undefined", we are not capturing lines right now,
# otherwise we are capturing lines (if "mlsql" is the empty string we are
# capturing lines indeed!)

my $mlsql     = undef;
my $connid    = undef; # "connid" unknown at first
my $user      = undef; # "user" unknown at first
my $prevtime  = 0;     # system clock (just for logging)
my $isprepare = 0;     # set if we are currently working on a "prepare" statement

while(my $origLine = <>)  {   
    chomp($origLine);
    my $rest = $origLine;

    # last if ($when =~ /^2017-12-16/); # short breakoff hack

    #   
    # Immediately discard known crap!
    #

    next if ($rest =~ /^\/usr\/sbin\/mysqld, Version:/);
    next if ($rest =~ /^Tcp port: 3306  Unix socket:/);
    next if ($rest =~ /^Time\s+Id\s+Command\s+Argument/);

    #
    # There are tabs in the output, and these seem to assume 1 tab = 8 spaces.
    # So replace!
    #

    $rest =~ s/\t/        /g;

    # 
    # What we will encounter in the general query log:
    #
    # CASE 1:
    #  A line may have a timestamp composed of date and time at the beginning,
    #  followed by a connection id (this format is also column oriented as the
    #  connection id starts at character 16):
    #
    #  |012345678901234567890123456789--charcounting
    #  |171215  4:17:03 124090 Query
    #
    # CASE 2: 
    #  A line may have 2 tabs (should yield 16 spaces) followed by a connection id:
    #
    #  |012345678901234567890123456789--charcounting
    #  |(TAB)   (TAB)   123753 Query    SELECT
    #
    # CASE 3:
    #  A line may contain a fragment of a multine SQL statement:
    #
    #  | WHERE n.id NOT IN (SELECT
    # 
 
    if ($rest =~ /^(\d\d)(\d\d)(\d\d)\s+(\d{1,2})\:(\d{1,2})\:(\d{1,2})\s+(\d+)\s+(.*)$/) {
       #### CASE 1 ####
       my $year   = 2000 + $1 * 1;
       my $month  = $2 * 1;
       my $day    = $3 * 1;
       my $hour   = $4 * 1;
       my $min    = $5 * 1;
       my $sec    = $6 * 1;
       $connid    = $7 * 1; # does the connection id fit the int?
       $rest      = $8;
       #
       # Terminate a (possibly multiline) SQL in progress as this line is no longer
       # part of an SQL statement
       #
       if (defined $mlsql) {
          die unless defined $user;
          terminateSql($mlsql,$user,$isprepare);
          $mlsql = undef
       }
       #
       # Update "when". TODO: Check that it is later than previous "when".
       #
       $when = sprintf("%04d-%02d-%02d %02d:%02d:%02d",$year,$month,$day,$hour,$min,$sec);
       # 
       # Tell the user where we are et every 5 seconds
       # 
       if ((time - $prevtime) > 5) {
          print STDERR "Now at: $when\n";
          $prevtime = time
       }
    } elsif ($rest =~ /^\s+(\d+)\s+((Query|Quit|Connect|Init|Refresh|Prepare|Execute|Close stmt)(.*?))\s*$/) {
       #### CASE 2 ####
       #       
       # The datetime may be missing and the next element would then be a connection id.
       # This may be difficult to properly distinguish from SQL statement fragments!
       # For example the line may contain "   1 AS QUOTA" which looks like a line starting
       # with a connection id but is actually part of a multiline SQL statement.
       # We could pretend to know there are 16 spaces after TAB replacement (which is a bit
       # more precise), but this is actually not true as lines with connection id 1 
       # are actually misaligned. 
       # In the end, we just make sure one of the action keywords is in there, too.
       #
       if (defined $mlsql) {
          die unless defined $user;
          terminateSql($mlsql,$user,$isprepare);
          $mlsql = undef;
       }
       $connid = $1 * 1; # does the connection id fit the int?
       $rest   = $2;
    } else {
       #### CASE 3 ####
       if (defined $mlsql) {
          $mlsql .= " $rest"; # capture this SQL fragment
       }
       else {
          print STDERR "Could not process this line (at line start): '$origLine'\n";
       }       
       next # Process next line w/o further ado
    }

    # 
    # Assert: not in multiline SQL capture mode at the present time
    #

    die if defined $mlsql;

    # 
    # The line may indicate a new connection, possibly with the database name. Like:
    # |171214 23:16:01 123752 Connect  foo@localhost on bardatabase
    #

    if ($rest =~ /^\s*Connect\s+(\S+)\s*on\s*(\S*)\s*$/) {
       $user = $1;
       my $db   = $2;
       if ($verbose) {
          print "New connection by user '$user' at $when with connid $connid";
          print " on database '$db'" if $db;
          print "\n" 
       }
       # Assert: there is not currently a live connection with id $connid 
       die "Connection $connid already in map!" if exists $$liveconns{$connid};
       $$liveconns{$connid} = { when => $when, user => $user, db => $db, connid => $connid };
       if (!exists $$stats{$user}) {
          my $thisstats = { user => $user, conncount => 0, querycount => 0, queries => {} };
          for my $key (@qtypes) {
             my $val = $$thisstats{$key . "count"} = 0
          }
          $$stats{$user} = $thisstats;
       }
       my $thisstats = $$stats{$user};
       die unless $$thisstats{user} = $user;
       $$thisstats{conncount}++;
       next
    }

    #
    # Some users don't manage to connect. This is just printed to STDERR
    #

    if ($rest =~ /^\s*Connect\s+Access denied for user (\S+)\s/) {
       my $user = $1;
       print STDERR "Failed connection attempt by $user at $when\n";
       next
    } 

    # 
    # The "connection id" should be found in the liveconns hash, either
    # just added or already added earlier. If not, just drop the line
    #
    
    if (! exists $$liveconns{$connid}) {
       print STDERR "Unknown connection id $connid at $when - dropping line '$origLine'\n";
       next
    }

    # 
    # The line may indicate a disconnection. Like this:
    # |123751 Quit
    #

    if ($rest =~ /^\s*Quit\s*$/) {
       if (exists $$liveconns{$connid}) {
          my $thisliveconn = $$liveconns{$connid};
          delete $$liveconns{$connid};
          print "Connection $connid removed from liveconnections map\n" if $verbose;
       }
       else {
          print STDERR "Connection $connid disconnected but it's not in the liveconnections map\n";
       }
       next
    }

    # 
    # The line may indicate a DB change. Like this:
    # |123798 Init DB foodatabase
    #

    if ($rest =~ /^\s*Init DB\s+(\S*)\s*$/) {
       my $db = $1;
       print "Connection $connid connects to database $db\n" if $verbose;
       next
    }

    #
    # Not sure what to do with these; ignore them.
    # 

    if ($rest =~ /^\s*(Refresh|Close stmt)\s*$/) {
       next
    }

    # 
    # The line may be a query. In any other case, we give up!
    #

    if ($rest =~ /^\s*(Query|Execute|Prepare)\s+(.*)$/) {
       # Capture the possibly multiline SQL statement (which may be empty)
       $mlsql = $2;
       $isprepare = ($rest =~ /^\s*Prepare/)
    }
    else {
       print STDERR "Unknown: '$origLine'\n"
    }
}

# ---
# Result!
# ---

sub sorterofusers {
   my($stats) = @_; # hashref
   my @foo = (keys %$stats);
   # Sort in place by descending occurrence count (this is apparently optimized by Perl)
   @foo = sort { my $ca = $$stats{$a}; my $cb = $$stats{$b}; $$cb{querycount} <=> $$ca{querycount} } @foo; 
   return \@foo; # arrayref
}

my $sortedusers = sorterofusers($stats);

my $addsep = 0;

foreach my $user (@$sortedusers) {
   my $ts = $$stats{$user};
   if ($addsep && !$coarse) {
      print "\n\n\n";
   }
   $addsep = 1;
   if ($coarse) {
      printf "User %-60s (%10d queries, %7d connections)", $user, $$ts{querycount}, $$ts{conncount};
      my $addsep2 = 0;
      for my $key (@qtypes) {
         my $val = $$ts{$key . "count"};
         if ($val) {
            if ($addsep2) { 
               print ", "
            } else {
               print " "
            }
            $addsep2 = 1;
            printf("%d %ss", $val, $key);
         }
      }
      print "\n";
   }
   else {
      printf "User %s (%d queries, %d connections)\n", $user, $$ts{querycount}, $$ts{conncount};
      my $queries = $$ts{queries};
      my $queryarray = sorterofqueries($queries);
      for my $q (@$queryarray) {
         printf "%d occurrences:\n", $$queries{$q};
         printf "   %s\n", $q;
      } 
   }
}

