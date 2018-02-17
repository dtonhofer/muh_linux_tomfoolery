muh_linux_tomfoolery
====================

Scripts that I edit on my linux machine.

The scripts under `ssh_login`
-----------------------------

Connect to a remote machine running SSH by typing the name of the machine on the command line. Because I can't be bothered to remember the command line options or the many (login,hostname) tuples.

This is just a simple tool to enable easier login to a given set of machines from a vanilla Linux workstation; no special SSH key management occurs; we do not even use an SSH agent.

`print_hostname_results.sh`
---------------------------

Shell script that applies various methods to obtain the hostname and prints the results. Writing this involved scouring various documentation, discovering new commands and encountering hair-raisingly wrong information on the Interwebs. I also checked through the sourcecode of the `hostname` command tyring to discover what it does. Not entirely fun!

A sample output:

    Kernel hostname via 'sysctl'                      : sigyn.homelinux.org
    Kernel domainname via 'sysctl'                    : (none)
    File '/etc/hostname'                              : contains 'sigyn.homelinux.org'
    File '/etc/sysconfig/network'                     : exists but has no 'HOSTNAME' line
    According to the shell                            : HOSTNAME = sigyn.homelinux.org
    Nodename given by 'uname --nodename'              : sigyn.homelinux.org
    Hostname ('hostname')                             : sigyn.homelinux.org
    Short hostname ('hostname --short')               : sigyn
    NIS domain name ('domainname')                    : (none)
    YP default domain ('hostname --yp')               : ['hostname --yp' failed: 'hostname: Local domain name not set']
    DNS domain name ('hostname --domain')             : homelinux.org
    Fully qualified hostname ('hostname --fqdn')      : sigyn.homelinux.org
    Hostname alias ('hostname --alias')               : 
    By IP address ('hostname --ip-address')           : 78.141....
    All IPs ('hostname --all-ip-addresses')           : 192.168.1.... 192.168.122.... 2001:..... 
    All FQHNs via IPs ('hostname --all-ip-addresses') : sigyn.fritz.box sigyn.homelinux.org sigyn-2.fritz.box 
    Static hostname via 'hostnamectl'                 : sigyn.homelinux.org
    Transient hostname via 'hostnamectl'              : sigyn.homelinux.org
    Pretty hostname via 'hostnamectl'                 : 

Studying `hostname` leads down a rabbit hole. 

* Kernel settings are set via `/etc/sysctl.conf` (see `man sysctl.conf`)
* `systemd` additionally sets from `/etc/sysctl.d/*.conf` (see `man sysctl.d`)
* Additional settings may be in `/usr/lib/sysctl.d/*.conf`, in particular `/usr/lib/sysctl.d/00-system.conf`
* The man page for `systcl` (configure kernel parameters at runtime) gives the `--system` option to load settings from a raft of possible system configuration files.
* Hostname may also be set from `/etc/sysconfig/network`
* For Fedora 19/20 the hostname seems to be set from: `/etc/hostname` if the kernel values have not been set explicitely.
* See also: http://jblevins.org/log/hostname
* But things may have changed with the introduction of "systemd", see http://www.freedesktop.org/wiki/Software/systemd/hostnamed and http://www.freedesktop.org/software/systemd/man/hostnamectl.html

`myssql56_query_log_analysis.pl`
--------------------------------

* Last update: 2018-01-27
* License: MIT license, see https://opensource.org/licenses/MIT
* Script written in the context of https://serverfault.com/questions/894074/mysql-general-query-log-analysis

If you are doing system/software archeology and have a MySQL 5.6 query log and want to get some statistics out of it to see who connects, and how many queries they issue and what they queries they issue, then this script may help. It read a MySQL 5.6 query log on stdin and builds a statistic over the queries. 

There are two statistics, chosen by the `my $coarse = 1/0;` line:

* Coarse-grained statistics resulting in a list if users and query counts only.
* Fine-grained statistics also grouping the SQL queries into "bins" and print the "representative" query and the bin sizes too. Queries are put into the same "bin" when their Levenshtein distance (editing distance) to the query that initiated bin creation (the template) is "small enough" (in this case, within 10% of the mean of the query lengths). A better program would parse the SQL and compare the parse trees to see whether these only differ by constants. Still, this heuristic approach seems to work somewhat. 

For this script, one needs the "LevenshteinXS" library, which is backed by C code. The "Levensthein" library is too slow.
 
Processing speed: With LevenstheinXS, we process 35959949 log lines in 640 minutes: *936 lines/s* on a Intel(R) Core(TM) i3-6100 CPU @ 3.70GHz with an SSD.

Evidently, if you have the general query log, you are aware of data protection issues.
