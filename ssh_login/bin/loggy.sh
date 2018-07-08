#!/bin/bash

set -o nounset
# set -x # Debugging switch on

# =============================================================================
# Author:   David Tonhofer
# Rights:   Public Domain
# -----------------------------------------------------------------------------
# Connect to a remote machine running SSH by typing the name of the machine 
# on the command line. Because I can't be bothered to remember the command
# line options or (login,hostname) tuples.
#
# This is just a simple tool to enable easier login to a given set of machines
# from a vanilla Linux workstation; no special SSH key management occurs;
# we do not even use an SSH agent (https://en.wikipedia.org/wiki/Ssh-agent))#  
# -----------------------------------------------------------------------------
#
# Options:
# 
# --cfg=[path-to-file]  to explicity give the config file for the remote machine
#
# --ip=[ipaddr]         to set/override IP address from the config file
# --dns=[hostname]      to set/override hostname from the config file
#                      (both can be given, but IP overrides DNS)
#
# --port=[int]          to set/override TCP port from the config file
# --keydir=[dir]        to override the private-SSH-key directory /root/.ssh
#
# --ssh                 to explicitly use SSH client (this is the default)
# --sftp|--ftp          to explicitly use SSH client in SFTP mode instead
# --http                to use Firefox to access an http:// URL instead
# --https               to use Firefox to access an https:// URL instead
#
# --x11                 to switch on X11 forwarding of the SSH protocol
# --verbose|-v          to make SSH client be verbose
#
# --proxyport=[port]    to set up a SOCKS proxy locally on the given port (implies --ssh)
# --proxybind=[any|...] to bind the SOCKS proxy to an address (by default, localhost) (implies --ssh)
#
# --cmd=[string]        to execute a command on the remote machine (implies --ssh)
# --touch               to run infodump shell commands on the remote machine (implies --ssh)
#
# How to set it up:
# 
# 1) Store this script in secure place, e.g. 
#    /usr/local/toolbox/login/bin/loggy.sh
#
# 2) For each remote machine, create a public/private SSH keypair using 
#    "ssh-keygen".
# 
#    The script assumes a default naming convention for the private key, which
#    is: 
#
#    REMOTE_USER@(REMOTE_MACHINE).privkey            for unencrypted priv key
#    REMOTE_USER@(REMOTE_MACHINE).privkey.crypted    for encrypted priv key
# 
#    Suppose we want to connect to "foobar.example.com" as user "fedora", then:
#
#    $ ssh-keygen -t rsa -b 2048 -f 'fedora@(foobar.example.com).privkey'
#
#    will create
#
#    'fedora@(foobar.example.com).privkey'      - private key, correctly named
#    'fedora@(foobar.example.com).privkey.pub'  - public key, awkwardly named
#
#    The private key file goes to $HOME/.ssh on the local machine.
#    The public key file *contents* go:
#      - into the file ".ssh/authorized_keys" on 
#      - the remote machine (here, "foobar.example.com")
#      - of the user as whom we will connect (here, "fedora")
#      - and make sure the permissions on ".ssh/authorized_keys" are 
#        restrictive: chmod 600 ~/.ssh/authorized_keys
#    The public key file can be deleted after that.
#    
# 3) Create a configuration file describing the remote machine. The script
#    assumes the configuration file directory is "~/.ssh/logins.d".
#
#    The configuration file must be named as you would name the command by 
#    which you want to connect.
#
#    If you want the command to be "foobar.example.com", name the config file
#    "foobar.example.com". If you want the command to be 
#    "fedora_at_foobar.example.com" name it "fedora_at_foobar.example.com".
#
#    The confguration file just gives information to the script on how to 
#    connect. Contents example:
#
#    ------
#    DESC          = Cloud machine AWS Ireland (RHEL 7)
#    hardcoded_dns = %THIS%.example.com
#    # hardcoded_ip  = XX.XX.XX.XX
#    USER          = fedora
#    privkey       = %USER%@(%THIS%.example.com).privkey
#    # PORT        = 22
#    # TUNNEL      = ....
#    # use_nostrict = YES
#    ------
#    
#    - A line starting with "#" is a comment
#    - There can be space around "=" as this is not bash assignment syntax
#    - You can give the DNS entry or the IP of the remote machine (but not 
#      both).
#    - For the DNS entry, "%THIS%" is replaced by the name of the config file.
#      ...useful if you copy the same config to several others that only 
#      differ by name, PORT may be specified if SSH server runs on nonstandard
#      port.
#    - privkey gives the name of the private key file in ~/.ssh
#      ...%THIS works similar to DNS. Additionally %USER% takes the value of 
#      USER. 
#    - TUNNEL takes an argument that is passed to ssh "-L" option (see the
#      manpage of ssh)
#    - use_nostrict switches off strict host key checking
#
# 4) In a directory that is on your search path (e.g. "~/bin/login"), create a
#    symlink using "ln -s"
#    - That has the same name as the configuration file above
#    - That points to this script.
#
#    For example, in ~/bin/login, the symlink would be:
#
#       foobar.example.com -> /usr/local/toolbox/login/bin/loggy.sh
#
#    The script sbin/install_all_symlinks_in_home_directory.sh does that for you.
#    
# 5) You can now connect using SSH by executing
#
#    $ foobar.example.com 
#
#    on the command line. The options allow you to override fields from the config
#    file or do other acrobatics.
#
# -----------------------------------------------------------------------------
# Notes
#
# 1) There is a minimal similar functionality built into SSH client directly.
#    The file ~/.ssh/config allows to define the identity files on a per-host
#    basis.
#
# 2) For X11 forwarding, install "xorg-x11-xauth" on the remote machine and
#    pass "--x11" to this script.
#    See also: https://wiki.archlinux.org/index.php/SSH#X11_forwarding
#
# TODO: - Option to dump the config file for convenience
#       - Option to switch user to another user (the private key file
#         will then be found according to the overriding username)
#       - If connection does not work, try to reconnect after a suitable delay
#       - ConnectTimeout should be overridable
#       - Be able to configure a proxy on the remote
# =============================================================================

dir=~qq  # ~qq is actually /usr/local/toolbox

if [[ ! -d $dir ]]; then
   echo "There is no directory '$dir'. Fix the script! Exiting!" >&2
   exit 1
fi

# ---
# Some variables set by option processing
# ---

use_x11_fwd=          # Set via "--x11" flag
use_verbose=          # Set via "-v" or "--verbose" flag
cmdline_keydir=       # Set via "--keydir=..."
cmdline_ip=           # Set via "--ip=..."
cmdline_dns=          # Set via "--dns=..."
cmdline_port=         # Set via "--port=..."
cmdline_proxybind=    # Set via "--proxybind=..."
cmdline_proxyport=    # Set via "--proxyport=..."
mode=ssh              # By default "ssh" otherwise set via "--ssh"/"--sftp"/"--http"/"--touch" flags
mode_lock=            # Once set, "mode" cannot be changed anymore; if it is "FAIL", then there is mode confusion
script_to_run=        # Set via "--cmd=..." (to run a script on the remote)
touch_remote=         # Set via "--touch" flag
cmdline_cfg=          # Set via "--cfg=..." (to set the config file instead of getting it from the $0 symlink name)

# ===
# Write (colored) line to stderr
# For coloring, see: 
# http://stackoverflow.com/questions/5947742/how-to-change-the-output-color-of-echo-in-linux
# ===

writeColored() {

   local text1
   text1=$(echo ${1:-''}) # get rid of whitespace

   local text2
   text2=$(echo ${2:-''}) # get rid of whitespace

   local mis
   (( mis=40-${#text1} ))

   tput setaf 3

   echo -n "$text1" >&2
   while [[ $mis -gt 0 ]]; do
      echo -n " " >&2
      (( mis-- ))
   done
   echo -n ": " >&2

   tput sgr 0

   if [[ $text1 == "Target description" ]]; then
      tput setaf 6
      echo "$text2" >&2
      tput sgr 0
   else
      echo "$text2" >&2
   fi
}

# ===
# Write (red) line to stderr
# ===

writeError() {
   tput setaf 1
   echo "$1" >&2
   tput sgr 0
}

# ===
# Change the mode. Sets returnvalue to 1 on problem.
# ===

changeMode() {
   local from_mode=$1
   local to_mode=$2
   local param=$3
   if [[ $from_mode != "$to_mode" ]]; then
      if [[ -n $mode_lock ]]; then
         echo "Mode was already immutably set to '$from_mode' but encountered option '$param' -- can't do that!" >&2
         mode_lock=FAIL
      else
         mode="$to_mode"
         mode_lock=Y
      fi   
   fi
}

# ===
# Option processing
# ===

processOptions() {

   # We use bash regular expressions, which are "grep" regular expressions; see "man grep"
   # or "man 7 regex"
   # In that case, the string on the right MUST NOT be enclosed in single or double quotes,
   # otherwise it becomes a literal string

   local use_ip=
   local use_dns=
   local use_cmdline_keydir=
   local use_cmdline_cfg=
   local use_script_to_run=
   local use_port=
   local use_proxyport=
   local use_proxybind=

   local param=
   local unknown=
   local print_help=
   local old_mode=

   for param in "$@"; do   

      # Process args that are separate from their option.
      # i.e. "--target X" instead of "--target=X"
      # Note that an option that demands an arg does not generate an error if it 
      # is the last one on the command line; this should maybe be fixed...
     
      if [[ -n $use_cmdline_keydir ]]; then
         cmdline_keydir=$param
         use_cmdline_keydir=""
         continue
      fi

      if [[ -n $use_ip ]]; then
         cmdline_ip=$param
         use_ip=""
         continue
      fi

      if [[ -n $use_dns ]]; then
         cmdline_dns=$param
         use_dns=""
         continue
      fi

      if [[ -n $use_script_to_run ]]; then
         script_to_run=$param
         use_script_to_run=""
         continue
      fi

      if [[ -n $use_cmdline_cfg ]]; then
         cmdline_cfg=$param
         use_cmdline_cfg=""
         continue
      fi

      if [[ -n $use_port ]]; then
         cmdline_port=$param
         use_port=""
         continue
      fi

      if [[ -n $use_proxyport ]]; then
         cmdline_proxyport=$param
         use_proxyport=""
         continue
      fi

      if [[ -n $use_proxybind ]]; then
         cmdline_proxybind=$param
         use_proxybind=""
         continue
      fi

      # Process flags, i.e. "--option" elements

      if [[ $param == '--ssh' ]]; then
         old_mode="$mode"; mode=ssh; changeMode "$old_mode" "$mode" "$param"
         continue
      fi

      if [[ $param =~ ^--s?ftp$ ]]; then
         old_mode="$mode"; mode=sftp; changeMode "$old_mode" "$mode" "$param"
         continue
      fi

      if [[ $param == '--http' ]]; then
         old_mode="$mode"; mode=http; changeMode "$old_mode" "$mode" "$param"
         continue
      fi

      if [[ $param == '--https' ]]; then
         old_mode="$mode"; mode=https; changeMode "$old_mode" "$mode" "$param"
         continue
      fi

      if [[ $param == '--touch' ]]; then
         old_mode="$mode"; mode=ssh; changeMode "$old_mode" "$mode" "$param"
         touch_remote=Y
         continue
      fi

      if [[ $param == '--x11' ]]; then
         use_x11_fwd=1
         continue
      fi

      if [[ $param == '--verbose' || $param == '-v' ]]; then
         use_verbose=1
         continue
      fi

      # Process "--option=arg" elements, but also cater for "--option arg" style

      if [[ $param =~ ^--ip(=.+)? ]]; then
         if [[ $param =~ ^--ip=(.+)? ]]; then
            cmdline_ip=$(echo "$param" | cut --delimiter="=" --fields=2)
         else 
            use_ip=1
         fi
         continue
      fi

      if [[ $param =~ ^--port(=.+)? ]]; then
         if [[ $param =~ ^--port=(.+)? ]]; then
            cmdline_port=$(echo "$param" | cut --delimiter="=" --fields=2)
         else 
            use_port=1
         fi
         continue
      fi

      if [[ $param =~ ^--proxyport(=.+)? ]]; then
         if [[ $param =~ ^--proxyport=(.+)? ]]; then
            cmdline_proxyport=$(echo "$param" | cut --delimiter="=" --fields=2)
         else 
            use_proxyport=1
         fi
         old_mode="$mode"; mode=ssh; changeMode "$old_mode" "$mode" "$param"
         continue
      fi

      if [[ $param =~ ^--proxybind(=.+)? ]]; then
         if [[ $param =~ ^--proxybind=(.+)? ]]; then
            cmdline_proxybind=$(echo "$param" | cut --delimiter="=" --fields=2)
         else 
            use_proxybind=1
         fi
         old_mode="$mode"; mode=ssh; changeMode "$old_mode" "$mode" "$param"
         continue
      fi

      if [[ $param =~ ^--dns(=.+)? ]]; then
         if [[ $param =~ ^--dns=(.+)? ]]; then
            cmdline_dns=$(echo "$param" | cut --delimiter="=" --fields=2)
         else
            use_dns=1
         fi
         continue
      fi

      if [[ $param =~ ^--cmd(=.+)? ]]; then
         if [[ $param =~ --cmd=(.+)? ]]; then
            script_to_run=$(echo "$param" | cut --delimiter="=" --fields=2)
         else
            use_script_to_run=1
         fi
         old_mode="$mode"; mode=ssh; changeMode "$old_mode" "$mode" "$param"
         continue
      fi

      if [[ $param =~ ^--cfg(=.+)? ]]; then
         if [[ $param =~ ^--cfg=(.+)? ]]; then
            cmdline_cfg=$(echo "$param" | cut --delimiter="=" --fields=2)
         else
            use_cmdline_cfg=1
         fi
         continue
      fi

      if [[ $param =~ ^--keydir(=.+)? ]]; then
         if [[ $param =~ ^--keydir=(.+)? ]]; then
            cmdline_keydir=$(echo "$param" | cut --delimiter="=" --fields=2)
         else
            use_cmdline_keydir=1
         fi
         continue
      fi

      # Special case: "--help" or "-h"

      if [[ $param == '--help' || $param == '-h' ]]; then
         print_help=1
         break
      fi

      # if we are here, we encountered something unknown in "param";
      # if "unknown" is already set, add a comma for separation

      if [[ -n $unknown ]]; then
         unknown="$unknown,"
      fi

      unknown="${unknown}${param}"

   done

   if [[ -n $unknown ]]; then
      echo "Unknown parameters '$unknown'" >&2
      print_help=1
   fi

   if [[ -n $print_help ]]; then
cat >&2 <<HERE
--cfg=[path-to-file]  to explicity give the config file for the remote machine

--ip=[ipaddr]         to set/override IP address from the config file
--dns=[hostname]      to set/override hostname from the config file
                      (both can be given, but IP overrides DNS)

--port=[int]          to set/override TCP port from the config file
--keydir=[dir]        to override the private-SSH-key directory $HOME/.ssh

--ssh                 to explicitly use SSH client (this is the default)
--sftp|--ftp          to explicitly use SSH client in SFTP mode instead
--http                to use Firefox to access an http:// URL instead
--https               to use Firefox to access an https:// URL instead

--x11                 to switch on X11 forwarding of the SSH protocol
--verbose|-v          to make SSH client be verbose

--proxyport=[port]    to set up a SOCKS proxy locally on the given port (implies --ssh)
--proxybind=[any|...] to bind the SOCKS proxy to an address (by default, localhost) (implies --ssh)

--cmd=[string]        to execute a command on the remote machine (implies --ssh)
--touch               to run infodump shell commands on the remote machine (implies --ssh)
HERE
      exit 1
   fi
 
   if [[ -n $use_ip && -n $use_dns ]]; then
      echo "Both '--ip=...' and '--dns=...' specified: use only one of those -- exiting" >&2
      exit 1
   fi

   if [[ -n $cmdline_proxybind && -z $cmdline_proxyport ]]; then
      echo "Proxy bind is '$cmdline_proxybind' but proxy port is unset -- this makes no sense -- exiting" >&2
      exit 1
   fi


   if [[ $mode_lock == FAIL ]]; then
      echo "Unclear what mode to use -- exiting" >&2
      exit 1
   fi
}

# ===
# We are getting configuration from a configuration file
# It may have been given on the command line
# ===

lookForConfigFile() {
   local c1_logind_dir=$1
   local c2_logind_dir=$2
   local request1=$3
   local request2=$4
   local candidate=
   local count=
   local config_file=
   for candidate in "$c1_logind_dir" "$c2_logind_dir"; do
      if [[ -d $candidate ]]; then
         # Recursively search underneath $candidate so that the user may organize this at will
         count=$(find "$candidate" '(' -name "$request1" -o -name "$request2" ')' -type f | wc -l)
         if [[ $count -gt 1 ]]; then
            echo "The directory '$candidate' contains $count config files named '$request1' or '$request2'" >&2
            echo "Unsure how to connect -- exiting" >&2
            # TODO: Take the longest one first
            # TODO: This exit doesn't work as the function is executed in a subshell
            exit 1
         fi
         if [[ $count -eq 1 ]]; then
            config_file=$(find "$candidate" '(' -name "$request1" -o -name "$request2" ')' -type f)
            break
         fi
      fi
   done
   echo "$config_file"
}

# ===
# Decide which config file to use
# ===

whichConfigFile() {
   if [[ -n $cmdline_cfg ]]; then
      if [[ ! -f "$cmdline_cfg" ]]; then
         echo "Cannot find configuration file given on the command line '$cmdline_cfg' (give full path!)" >&2
         echo "" # returned config file
      else
         echo "$cmdline_cfg" # returned config file
      fi
   else
      #
      # Default behaviour: Need to search for the config file based on the
      # name of this executable (i.e. '$0'), which should be a symlink
      # that is named like the configuration file that shall be read.
      #
      # E.g. $0 is "foobar.example.com_best" and there is this symlink:
      #
      # foobar.example.com_best -> /usr/local/toolbox/login/bin/loggy.sh
      #
      # Then we will be looking for config file
      #
      # 1) foobar.example.com_best
      # 2) foobar.example.com
      #
      local request1; request1=$(basename "$0")   # possibly the name of the script
      local request2="${request1%%_*}"  # possibly with everyting after "_" removed
      #
      # Primary directory with login configuration files (searched first)
      #   
      local logind="login.d"
      #
      # First choice is underneath user's .ssh directory
      #
      local c1_logind_dir="$homedir/.ssh/$logind"
      #
      # Second choice is underneath the keydir (given on the command line or the default one)
      # (it may well the same as above)
      #
      local c2_logind_dir="$keydir/$logind"  
      if [[ $c2_logind_dir == "$c1_logind_dir" ]]; then
         c2_logind_dir=
      fi
      #
      # Determine how to connect by name of command ---
      #
      if [[ ! -d "$c1_logind_dir" && ! -d "$c2_logind_dir" ]]; then
         echo "None of the directories" >&2
         echo "   $c1_logind_dir" >&2
         [[ -n $c2_logind_dir ]] && echo "   $c2_logind_dir" >&2
         echo "exists." >&2
         return 1
      fi
      local config_file; config_file=$(lookForConfigFile "$c1_logind_dir" "$c2_logind_dir" "$request1" "$request2")
      if [[ -z $config_file ]]; then
         echo "None of the directories" >&2
         echo "   $c1_logind_dir" >&2
         [[ -n $c2_logind_dir ]] && echo "   $c2_logind_dir" >&2
         echo -n "contains a file named '$request1'" >&2
         if [[ $request1 != "$request2" ]]; then
             echo "or '$request2'." >&2
         fi
         echo >&2        
         return 1
      fi
      echo "$config_file" # successfully returned config file
      return 0
   fi
}

# ===
# DNS reverse resolution
# ===

reverseResolve() {
   local ipaddr=$1
   rev=$(dig +short -x "$ipaddr")
   # spacing and parentheses are included here for convenience
   if [[ -z $rev ]]; then
      rev=" (could not be reverse-resolved)"
   else
      rev=" (reverse-resolves to '$rev')"
   fi
   echo "$rev"
}

# ===
# DNS forward resoluion
# ===

forwardResolve() {
   local name=$1
   fwd=$(dig +short "$name")
   # spacing and parentheses are included here for convenience
   if [[ -z $fwd ]]; then
      fwd=" (could not be resolved)"
   else
      fwd=" (resolves to $fwd)"
   fi
   echo "$fwd"
}

# ===
# Fix Key File permissions
# The permission of the privkey should be "rw by owner only". If this is not
# the case, ssh will complain and exit when invoked. Let's fix it here!
# ===

fixKeyFilePermissions() {
   local key=$1
   local stat;
   if ! stat=$(stat --format="%a" "$key") ; then
      echo "Could not stat private key file '$key' -- exiting" >&2
      exit 1
   fi
   if [[ $stat != '600' ]]; then
      echo "Fixing permissions on private key file '$key'. Currently they are $stat" >&2
      if ! chmod 600 "$key" ; then
         echo "Could not chmod private key file '$key' -- exiting" >&2
         exit 1
      fi
   fi
} 

# ===
# Just textify a duration
# ===

textifyDuration() {
   local duration=$1
   local shiff=$duration
   local secs=$((shiff % 60));  shiff=$((shiff / 60));
   local mins=$((shiff % 60));  shiff=$((shiff / 60));
   local hours=$shiff
   local splur; if [ $secs  -eq 1 ]; then splur=''; else splur='s'; fi
   local mplur; if [ $mins  -eq 1 ]; then mplur=''; else mplur='s'; fi
   local hplur; if [ $hours -eq 1 ]; then hplur=''; else hplur='s'; fi
   if [[ $hours -gt 0 ]]; then
      txt="$hours hour$hplur, $mins minute$mplur, $secs second$splur"
   elif [[ $mins -gt 0 ]]; then
      txt="$mins minute$mplur, $secs second$splur"
   else
      txt="$secs second$splur"
   fi
   echo "$txt"
}

# ===
# MAIN
# ===

processOptions "$@"

# ---
# User home directory
# ---

user=$(whoami)
homedir=$(getent passwd "$user" | cut -d: -f6)

if [[ ! -d $homedir ]]; then 
   echo "The home directory '$homedir' of user '$user' does not exist -- exiting" >&2
   exit 1
fi

# --- 
# Directory which contains the private keys, possibly overriden on cmdline
# The keydir may not exist ... check later when it is needed
# --- 

if [[ -n $cmdline_keydir ]]; then
   keydir=$cmdline_keydir
else
   keydir=$homedir/.ssh
fi

if ! config_file=$(whichConfigFile) ; then
   echo "Cannot find out how to connect to anything due to missing config file -- exiting" >&2
   exit 1
else
   echo "Using configuration file '$config_file'" >&2
fi

# Reconstruct the "request" which will be used as %THIS% when reading the config_file

this=$(basename "$config_file")
this=${this%%_*}  # everyting after "_" removed

# --- Extract information from config_file using Perl script

eex="$dir/login/bin/hidden/extract.pl"

# This shall be filled (or not)
# If the called script exits with error, we exit too and assume a message has been printed.
# Values may be missing. That is not a problem as they may be on the command line.
# Same value cannot be found at the same time, even (case of hardcoded_dns and hardcoded_ip)
# A missing value may mean NO in case of booleans (case of use_nostrict)

hardcoded_dns=$($eex "$config_file" "HARDCODED_DNS") || exit 1
hardcoded_ip=$($eex "$config_file" "HARDCODED_IP")   || exit 1
user=$($eex "$config_file" "USER")                   || exit 1
privkey=$($eex "$config_file" "PRIVKEY")             || exit 1
hardcoded_port=$($eex "$config_file" "PORT")         || exit 1
use_nostrict=$($eex "$config_file" "USE_NOSTRICT")   || exit 1   # Not in the command line...
desc=$($eex "$config_file" "DESC")                   || exit 1
tunnel=$($eex "$config_file" "TUNNEL")               || exit 1   # Create a tunnel on the remote
socks_proxy_arg=                                                # Only on the command line

# --- A description which may or may not exist
# Print colored, see: http://stackoverflow.com/questions/5947742/how-to-change-the-output-color-of-echo-in-linux

if [[ -n $desc ]]; then
   writeColored "Target description" "$desc"
fi

# --- If $user is unset or the string %ACTUAL% then replace by the result of "whoami"

if [[ -z $user || $user == "%ACTUAL%" ]]; then
   user=$(whoami)
   seluser="Current user '$user'"
else
   seluser="Specified user '$user'"
fi

writeColored "Selected user" "$seluser"


# --- Set the port on the remote machine, if needed

if [[ -n $cmdline_port ]]; then
   port=$cmdline_port
   selport="command line port $port"
elif [[ -n $hardcoded_port ]]; then
   port=$hardcoded_port
   selport="hardcoded port $port"
else
   port=
   selport="no port specified (using default value 22)"
fi

writeColored "Selected port" "$selport"


# --- Set the local SOCKS proxy endpoint, if needed

if [[ -n $cmdline_proxyport ]]; then
   if [[ -z $cmdline_proxybind ]]; then
      socks_proxy_arg="127.0.0.1:$cmdline_proxyport"
   elif [[ ${cmdline_proxybind,,} == any ]]; then
      # note: lowercased in the comparison, so "ANY" or "aNY" are good, too
      socks_proxy_arg="*:$cmdline_proxyport"
   else 
      socks_proxy_arg="$cmdline_proxybind:$cmdline_proxyport"
   fi 

   writeColored "Socks proxy on $socks_proxy_arg"
fi


# --- Set the 'target' by checking available values; take the first that applies

if [[ -n $hardcoded_dns && -n $hardcoded_ip ]]; then
   echo "Both hardcoded DNS ($hardcoded_dns) and hardcoded IP ($hardcoded_ip) are set. What do? -- exiting" >&2
   exit 1
fi

target=
selected=
reverse1=
reverse2=
forward1=
forward2=

if [[ -n $cmdline_ip ]]; then
   target=$cmdline_ip
   selected="command line host IP"
   reverse1=$(reverseResolve "$target")
fi

if [[ -z $target && -n $cmdline_dns ]]; then
   target=$cmdline_dns
   selected="command line host name"
   forward1=$(forwardResolve "$target")
fi

if [[ -z $target && -n $hardcoded_ip ]]; then
   target=$hardcoded_ip
   selected="hardcoded IP"
   reverse2=$(reverseResolve "$target")
fi

if [[ -z $target && -n $hardcoded_dns ]]; then
   # If a %THIS% is in the hardcoded_dns, replace by name of the request, i.e. the name of the config file itself: REQUEST 
   # target=$(echo "$hardcoded_dns" | sed "s/%THIS%/$this/g")
   target=${hardcoded_dns//%THIS%/$this}
   selected="hardcoded host name"
   if [[ $target != "$hardcoded_dns" ]]; then
      moretext1=" (modified to '$target')"
   else
      moretext1=""
   fi
   moretext2=$(forwardResolve "$target")
   forward2="$moretext1 $moretext2"
fi

if [[ -z $target ]]; then
   echo "Could not determine to which host to connect; nothing on the command line or in the script" >&2
fi

# do not include spacing or markup in the second string so that it stays empty if the values are empty!

writeColored "Command line host IP"   "${cmdline_ip}${reverse1}"
writeColored "Command line host name" "${cmdline_dns}${forward1}"
writeColored "Hardcoded host IP"      "${hardcoded_ip}${reverse2}"
writeColored "Hardcoded host name"    "${hardcoded_dns}${forward2}"

if [[ -n $selected ]]; then
   writeColored "Selected target" "$selected '$target'"
fi

if [[ -z $target ]]; then
   echo "Exiting" >&2
   exit 1
fi

# --- Build the command array for "exec" to run SSH, SFTP or firefox

declare -a cmdarr

if [[ $mode =~ ^https?$ ]]; then

   cmdarr[0]="firefox"
   if [[ $mode == http ]]; then   
      cmdarr[1]="http://${target}"
   else 
      cmdarr[1]="https://${target}"
   fi

else

   cmdarr[0]=$mode

   I=1
   cmdarr[$I]="-oConnectTimeout=15"
   (( I++ ))
 
   if [[ -n $use_x11_fwd ]]; then
      cmdarr[$I]="-oForwardX11=yes"
      (( I++ ))
   fi

   if [[ -n $use_verbose ]]; then
      cmdarr[$I]="-vvv" # Really verbose!
      (( I++ ))
   fi

   if [[ -n $port ]]; then
      cmdarr[$I]="-oPort=${port}" 
      (( I++ ))
   fi

   if [[ -n $use_nostrict ]]; then
      cmdarr[$I]="-oStrictHostKeyChecking=no"
      (( I++ ))
   fi 

   if [[ -n $socks_proxy_arg ]]; then
      cmdarr[$I]="-D${socks_proxy_arg}"
      (( I++ ))
   fi

   if [[ -n $tunnel ]]; then
      cmdarr[$I]="-L${tunnel}"
      (( I++ ))
   fi 

   if [[ -n $privkey ]]; then

      # Replace certain strings in the privkey string:
      # %USER% --> login user: $user
      # %THIS% --> $this (basically the name of the config file with everything after the first _ removed)

      newprivkey=$(echo "$privkey" | sed "s/%USER%/${user}/g" | sed "s/%THIS%/${this}/g")

      if [[ "$newprivkey" != "$privkey" ]]; then
         # echo "Private key patched from '$privkey' to '$newprivkey'" >&2
         privkey="$newprivkey"
      fi

      # echo "Private key to use is '$privkey'" >&2

      if [[ $privkey == /* ]]; then
         # absolute
         KEY=$privkey
      else
         # find the key under keydir
         if [[ ! -d $keydir ]]; then 
            echo "The keydirectory '$keydir' does not exist or is not accessible -- exiting" >&2
            exit 1
         fi
         count=$(find "$keydir" -name "$privkey" -type f | wc -l)
         if [[ $count -eq 0 ]]; then
            echo "The private key directory '$keydir' contains no file named '$privkey' -- exiting" >&2
            exit 1
         fi
         if [[ $count -gt 1 ]]; then
            echo "The private key directory '$keydir' contains $count files named '$privkey'. Unsure which to use -- exiting" >&2
            exit 1
         fi
         KEY=$(find "$keydir" -name "$privkey" -type f)
      fi

      if [[ ! -f $KEY ]]; then
         echo "Key '$KEY' needed, but it does not exist" >&2
         exit 1
      fi

      fixKeyFilePermissions "$KEY"

      cmdarr[$I]="-i$KEY" 
      (( I++ ))

  fi

   cmdarr[$I]="${user}@${target}"
   (( I++ ))

   if [[ -n $script_to_run ]]; then
      cmdarr[$I]=$script_to_run
   fi
 
fi

# --- Connect ---

echo "Will run this command: ${cmdarr[*]}" >&2

if [[ -z $touch_remote ]]; then
   # Run the SSH command. 
   # Should we replace the current process using "exec" or run in subshell? Both work fine!
   # But if we run in subshell (and wait), we can do something on return, which is better.
   # exec "${cmdarr[@]}"
   # To compute duration, use "SECONDS", a built-in variable
   # https://stackoverflow.com/questions/8903239/how-to-calculate-time-difference-in-bash-script
   SECONDS=0 
   "${cmdarr[@]}"
   res=$?
   duration=$SECONDS
   if [[ $res != 0 ]]; then
      writeError "*** Some problem occurred. Return value is $res. ***"
      if [[ $duration -gt 100 ]]; then
         writeError "It is now $(date)"
      fi
   fi
   txt="Connected for $(textifyDuration $duration)"
   if [[ $res != 0 ]]; then
      writeError "$txt"
   else
      echo "$txt" >&2
   fi
else
   "${cmdarr[@]}" << HERE
echo "------"
echo -n "Hostname: "; hostname
echo -n "System  : "
if [[ -f /etc/system-release ]]; then
   cat /etc/system-release
else 
   echo "?"
fi
echo -n "Date    : "; date
echo -n "Uname   : "; uname -srv
echo -n "Uptime  : "; uptime
if [[ -x \$(which selinuxenabled) ]]; then
   echo -n "SELinux : "
   if \$(selinuxenabled); then
      echo "enabled"
   else
      echo '** DISABLED **'
   fi
else 
   echo "No selinux command found!"
fi
echo
if [[ -x \$(which java 2>/dev/null) ]]; then
  java -version 2>&1 | sed ':a;N;\$!ba;s/\\n/; /g' 
else 
  echo 'No java command found!'
fi
echo
echo "NTP information:"
if [[ -x \$(which ntpq) ]]; then
   ntpq -c peers
else 
   echo "No ntpq command found!"
fi
echo "------"
HERE
fi

