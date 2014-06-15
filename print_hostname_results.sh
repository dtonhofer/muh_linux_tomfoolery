#!/bin/bash

# ----
# Extract and print the various "hostnames" that can be elicited from the system
# ----

PAD=50

function checkEtcHostname {
   local ETCH="/etc/hostname"
   if [[ -f $ETCH ]]; then   
      CONTENTS=`cat $ETCH`
      # echo "File '$ETCH' contains: '$CONTENTS'"
      printf "%-${PAD}s: %s\n" "File '$ETCH'" "contains '$CONTENTS'"
   else
      # echo "File '$ETCH' does not exist"
      printf "%-${PAD}s: does not exist\n" "File '$ETCH'"
   fi
}

function checkSysconfigNetwork {
   local SYSN="/etc/sysconfig/network"
   if [[ -f $SYSN ]]; then
      LINE=`grep -e "^HOSTNAME=" $SYSN`
      if [[ -n $LINE ]]; then
          # echo "File '$SYSN' contains: '$LINE'"
          printf "%-${PAD}s: %s\n" "File '$SYSN' contains" "'$LINE'"
      else 
          # echo "File '$SYSN' exists but does not contain a line for 'HOSTNAME'"
         printf "%-${PAD}s: %s\n" "File '$SYSN'" "exists but has no 'HOSTNAME' line" 
      fi
   else
      # echo "File '$SYSN' does not exist"
      printf "%-${PAD}s: does not exist\n" "File '$SYSN'"
   fi
}

# -----------------
# Kernel via sysctl
# -----------------

KERNEL_H=`/sbin/sysctl -n kernel.hostname`
KERNEL_D=`/sbin/sysctl -n kernel.domainname`

# ----------------
# "nodename"; on Linux, this is the hostname
# ----------------

UNAME=`uname --nodename`

# ----------------
# Hostname command
# ----------------

THE_HOSTNAME=`hostname 2>&1`
if [[ $? != 0 ]]; then
   THE_HOSTNAME="['hostname' failed: '$THE_HOSTNAME']"
fi

SHORT_NAME=`hostname --short 2>&1`
if [[ $? != 0 ]]; then
   SHORT_NAME="['hostname --short' failed: '$SHORT_NAME']"
fi

NIS_DNAME=`domainname 2>&1`
if [[ $? != 0 ]]; then
   NIS_DAME="['domainname' failed: '$NIS_DNAME']"
fi

YP_DNAME=`hostname --yp 2>&1` # Same as `nisdomainname`
if [[ $? != 0 ]]; then
   YP_DNAME="['hostname --yp' failed: '$YP_DNAME']"
fi

DNS_DNAME=`hostname --domain 2>&1`  # Same as `dnsdomainname`'
if [[ $? != 0 ]]; then
   DNS_DNAME="['hostname --domain' failed: '$DNS_DNAME']"
fi

FQDN_NAME=`hostname --fqdn 2>&1`
if [[ $? != 0 ]]; then
   FQDN_DNAME="['hostname --fqdn' failed: '$FQDN_NAME']"
fi

ALIAS_NAME=`hostname --alias 2>&1`
if [[ $? != 0 ]]; then
   ALIAS_NAME="['hostname --alias' failed: '$ALIAS_NAME']"
fi

BY_IP_ADDR=`hostname --ip-address 2>&1`
if [[ $? != 0 ]]; then
   BY_IP_ADDR="['hostname --ip-address' failed: '$BY_IP_ADDR']"
fi

ALL_IP_ADDR=`hostname --all-ip-addresses 2>&1`
if [[ $? != 0 ]]; then
   ALL_IP_ADDR="['hostname --all-ip-addresses' failed: '$ALL_IP_ADDR']"
fi

ALL_FQDN_NAMES=`hostname --all-fqdn 2>&1`
if [[ $? != 0 ]]; then
   ALL_FQDN_NAMES="['hostname --all-fqdn' failed: '$ALL_FQDN_NAMES']"
fi

# ----------------
# hostnamectl command (may not exist on this system)
# ----------------

HNCTL=/bin/hostnamectl

if [[ -x $HNCTL ]]; then
   HNCTL_STATIC=`hostnamectl --static status 2>&1`
   if [[ $? != 0 ]]; then
      HNCTL_STATIC="[hostnamectl status failed: '$HNCTL_STATUS']"
   fi
   HNCTL_TRANSIENT=`hostnamectl --transient status 2>&1`
   if [[ $? != 0 ]]; then
      HNCTL_TRANSIENT="[hostnamectl status failed: '$HNCTL_TRANSIENT']"
   fi
   HNCTL_PRETTY=`hostnamectl --pretty status 2>&1`
   if [[ $? != 0 ]]; then
      HNCTL_PRETTY="[hostnamectl status failed: '$HNCTL_PRETTY']"
   fi
fi

printf "%-${PAD}s: %s\n" "Kernel hostname via 'sysctl'"                       "$KERNEL_H"
printf "%-${PAD}s: %s\n" "Kernel domainname via 'sysctl'"                     "$KERNEL_D"
checkEtcHostname
checkSysconfigNetwork
printf "%-${PAD}s: %s\n" "According to the shell"                             "HOSTNAME = $HOSTNAME"
printf "%-${PAD}s: %s\n" "Nodename given by 'uname --nodename'"               "$UNAME"
printf "%-${PAD}s: %s\n" "Hostname ('hostname')"                              "$THE_HOSTNAME"
printf "%-${PAD}s: %s\n" "Short hostname ('hostname --short')"                "$SHORT_NAME"
printf "%-${PAD}s: %s\n" "NIS domain name ('domainname')"                     "$NIS_DNAME"
printf "%-${PAD}s: %s\n" "YP default domain ('hostname --yp')"                "$YP_DNAME"
printf "%-${PAD}s: %s\n" "DNS domain name ('hostname --domain')"              "$DNS_DNAME"
printf "%-${PAD}s: %s\n" "Fully qualified hostname ('hostname --fqdn')"       "$FQDN_NAME"
printf "%-${PAD}s: %s\n" "Hostname alias ('hostname --alias')"                "$ALIAS_NAME"
printf "%-${PAD}s: %s\n" "By IP address ('hostname --ip-address')"            "$BY_IP_ADDR"
printf "%-${PAD}s: %s\n" "All IPs ('hostname --all-ip-addresses')"            "$ALL_IP_ADDR"
printf "%-${PAD}s: %s\n" "All FQHNs via IPs ('hostname --all-ip-addresses')"  "$ALL_FQDN_NAMES"

if [[ -x $HNCTL ]]; then
   printf "%-${PAD}s: %s\n" "Static hostname via 'hostnamectl'"                  "$HNCTL_STATIC"
   printf "%-${PAD}s: %s\n" "Transient hostname via 'hostnamectl'"               "$HNCTL_TRANSIENT"
   printf "%-${PAD}s: %s\n" "Pretty hostname via 'hostnamectl'"                  "$HNCTL_PRETTY"
fi

# ----------
# Notes
# ----------

# The result of gethostname() ...obtained by running 'hostname'
# The part before the first '.' of the value returned by gethostname(); ...obtained by running 'hostname --short'"
# The result of getdomainname(); the code of 'hostname' seems to call this the 'NIS domain name' ...on Linux, this is the kernel-configured domainname ...obtained by running 'domainname'"
# The result of yp_get_default_domain(), which may fail ...obtained by running 'ĥostname --yp'"
# 'hostname' values obtained via DNS
# The part after the first '.' of the 'canonical name' value returned by getaddrinfo(gethostname()) ...obtained by running 'hostname --domain'
# The 'canonical name' value returned by getaddrinfo(gethostname()) ...obtained by running 'hostname --fqdn'"
# Alias obtained by gethostbyname(gethostname()) ...obtained by running 'hostname --alias'"
# 'hostname' values obtained by collecting configured network addresses
# Collect the IP addresses from getaddrinfo(gethostname()), apply getnameinfo(ip) to all those addresses ...obtained by running 'hostname --ip-address'"
# Call getnameinfo(NI_NUMERICHOST) on all addresses snarfed from active interfaces ...obtained by running 'hostname --all-ip-addresses'"
# Call getnameinfo(NI_NAMEREQD) on all addresses snarfed from active interfaces (involves lookup in /etc/hosts) ...obtained by running 'hostname --all-fqdn'"


