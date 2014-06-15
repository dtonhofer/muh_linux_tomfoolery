muh_linux_tomfoolery
====================

Scripts that I edit on muh linux machine

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

Like pages from the Necronomicon, studying `hostname` leads down a rabbit hole. 

* Kernel settings are set via `/etc/sysctl.conf` (see `man sysctl.conf`)
* `systemd` additionally sets from `/etc/sysctl.d/*.conf` (see `man sysctl.d`)
* Additional settings may be in `/usr/lib/sysctl.d/*.conf`, in particular `/usr/lib/sysctl.d/00-system.conf`
* The man page for `systcl` (configure kernel parameters at runtime) gives the `--system` option to load settings from a raft of possible system configuration files.
* Hostname may also be set from `/etc/sysconfig/network`
* For Fedora 19/20 the hostname seems to be set from: `/etc/hostname` if the kernel values have not been set explicitely.
* See also: http://jblevins.org/log/hostname
* But things may have changed with the introduction of "systemd", see http://www.freedesktop.org/wiki/Software/systemd/hostnamed and http://www.freedesktop.org/software/systemd/man/hostnamectl.html

