#!/bin/bash

set -o nounset
# set -x # Debugging switch on

# =============================================================================
# Author:   David Tonhofer
# Rights:   Public Domain
#
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
# --cfg=<path-to-file>  to explicity give the config file for the remote
# --ip=<ipaddr>         to set/override IP address from config file
# --dns=<hostname>      to set/override hostname from config file
# --port=<int>          to set/override TCP port from config file
# --x11                 to switch on X11 forwarding
# --verbose|-v          to make SSH client be verbose
# --ssh|ssh             to explicitly use SSH client (this is the default)
# --sftp|--ftp|sftp|ftp to explicitly use SSH client in SFTP mode
# --http|http           to use Firefox to access an http:// URL
# --https|https         to use Firefox to access an https:// URL
# --keydir=<dir>        to override the private-SSH-key directory
# --cmd=<string>        to execute a command on the remote
# --touch               to run simple information dumping shell commands on 
#                       the remote
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
#    HARDCODED_DNS = %THIS%.example.com
#    # HARDCODED_IP  = XX.XX.XX.XX
#    USER          = fedora
#    PRIVKEY       = %USER%@(%THIS%.example.com).privkey
#    # PORT        = 22
#    # TUNNEL      = ....
#    # USE_NOSTRICT = YES
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
#    - PRIVKEY gives the name of the private key file in ~/.ssh
#      ...%THIS works similar to DNS. Additionally %USER% takes the value of 
#      USER. 
#    - TUNNEL takes an argument that is passed to ssh "-L" option (see the
#      manpage of ssh)
#    - USE_NOSTRICT switches off strict host key checking
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
# TODO: Option to dump the config file for convenience
#       Option to switch user to another user (the private key file
#       will then be found according to the overriding username)
#       If connection does not work, try to reconnect after a suitable delay
#       Stylishly lowercase variables!
# =============================================================================

DIR=~qq  # ~qq is actually /usr/local/toolbox

if [[ ! -d $DIR ]]; then
   echo "There is no directory '$DIR'. Fix the script! Exiting!" >&2
   exit 1
fi

# ---
# Some variables set by option processing
# ---

USE_X11_FWD=          # Set via "--x11" flag
USE_VERBOSE=          # Set via "-v" or "--verbose" flag
CMDLINE_KEYDIR=       # Set via "--keydir=..."
CMDLINE_IP=           # Set via "--ip=..."
CMDLINE_DNS=          # Set via "--dns=..."
CMDLINE_PORT=         # Set via "--port=..."
CMD=                  # By default "ssh" otherwise set via "--ssh"/"--sftp"/"--http"/"--touch" flags
SCRIPT_TO_RUN=        # Set via "--cmd=..." (to run a script on the remote)
TOUCH_REMOTE=         # Set via "--touch" flag
CMDLINE_CFG=          # Set via "--cfg=..." (to set the config file instead of getting it from the $0 symlink name)

# ===
# Write (colored) line to stderr
# For coloring, see: 
# http://stackoverflow.com/questions/5947742/how-to-change-the-output-color-of-echo-in-linux
# ===

writeColored() {

   local TEXT1
   TEXT1=$(echo ${1:-''}) # get rid of whitespace

   local TEXT2
   TEXT2=$(echo ${2:-''}) # get rid of whitespace

   local MIS
   (( MIS=40-${#TEXT1} ))

   tput setaf 3

   echo -n "$TEXT1" >&2
   while [[ $MIS -gt 0 ]]; do
      echo -n " " >&2
      (( MIS-- ))
   done
   echo -n ": " >&2

   tput sgr 0

   if [[ $TEXT1 == "Target description" ]]; then
      tput setaf 6
      echo "$TEXT2" >&2
      tput sgr 0
   else
      echo "$TEXT2" >&2
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
# Option processing
# ===

processOptions() {

   # We use bash regular expressions, which are "grep" regular expressions; see "man grep"
   # or "man 7 regex"
   # In that case, the string on the right MUST NOT be enclosed in single or double quotes,
   # otherwise it becomes a literal string

   local USE_IP=
   local USE_DNS=
   local USE_CMDLINE_KEYDIR=
   local USE_CMDLINE_CFG=
   local USE_SCRIPT_TO_RUN=
   local USE_PORT=
   local PARAM=
   local UNKNOWN=
   local PRINT_HELP=

   for PARAM in "$@"; do   

      # Process arguments that are separate from their option
      # Note that an argument that demands a followup argument does nto generate an error if it 
      # is the las in the line
     
      if [[ -n $USE_CMDLINE_KEYDIR ]]; then
         CMDLINE_KEYDIR=$PARAM
         USE_CMDLINE_KEYDIR=""
         continue
      fi

      if [[ -n $USE_IP ]]; then
         CMDLINE_IP=$PARAM
         USE_IP=""
         continue
      fi

      if [[ -n $USE_DNS ]]; then
         CMDLINE_DNS=$PARAM
         USE_DNS=""
         continue
      fi

      if [[ -n $USE_SCRIPT_TO_RUN ]]; then
         SCRIPT_TO_RUN=$PARAM
         USE_SCRIPT_TO_RUN=""
         continue
      fi

      if [[ -n $USE_CMDLINE_CFG ]]; then
         CMDLINE_CFG=$PARAM
         USE_CMDLINE_CFG=""
         continue
      fi

      if [[ -n $USE_PORT ]]; then
         CMDLINE_PORT=$PARAM
         USE_PORT=""
         continue
      fi

      # Process option

      if [[ $PARAM == '--ssh' ]]; then
         if [[ -n $CMD ]]; then
            echo "Command was already set to '$CMD' but encountered option '$PARAM' -- setting again!" >&2
         fi
         CMD=ssh
         continue
      fi

      if [[ $PARAM == '--sftp' || $PARAM == '--ftp' || $PARAM == 'sftp' || $PARAM == 'ftp' ]]; then
         if [[ -n $CMD ]]; then
            echo "Command was already set to '$CMD' but encountered option '$PARAM' -- setting again!" >&2
         fi
         CMD=sftp
         continue
      fi

      if [[ $PARAM == '--http' || $PARAM == 'http' ]]; then
         if [[ -n $CMD ]]; then
            echo "Command was already set to '$CMD' but encountered option '$PARAM' -- setting again!" >&2
         fi
         CMD=http
         continue
      fi

      if [[ $PARAM == '--https' || $PARAM == 'https' ]]; then
         if [[ -n $CMD ]]; then
            echo "Command was already set to '$CMD' but encountered option '$PARAM' -- setting again!" >&2
         fi
         CMD=https
         continue
      fi

      if [[ $PARAM == '--touch' ]]; then
         if [[ -n $CMD ]]; then
            echo "Command was already set to '$CMD' but encountered option '$PARAM' --setting again!" >&2
         fi
         CMD=ssh # implies SSH connection
         TOUCH_REMOTE=Y
         continue
      fi

      if [[ $PARAM =~ --ip(=.+)? ]]; then
         if [[ $PARAM =~ --ip=(.+)? ]]; then
            CMDLINE_IP=$(echo "$PARAM" | cut --delimiter="=" --fields=2)
         else 
            USE_IP=1
         fi
         continue
      fi

      if [[ $PARAM =~ --port(=.+)? ]]; then
         if [[ $PARAM =~ --port=(.+)? ]]; then
            CMDLINE_PORT=$(echo "$PARAM" | cut --delimiter="=" --fields=2)
         else 
            USE_PORT=1
         fi
         continue
      fi

      if [[ $PARAM =~ --dns(=.+)? ]]; then
         if [[ $PARAM =~ --dns=(.+)? ]]; then
            CMDLINE_DNS=$(echo "$PARAM" | cut --delimiter="=" --fields=2)
         else
            USE_DNS=1
         fi
         continue
      fi

      if [[ $PARAM =~ --cmd(=.+)? ]]; then
         if [[ -n $CMD ]]; then
            echo "Command was already set to '$CMD' but encountered option '$PARAM' --setting again!" >&2
         fi
         CMD=ssh # implies SSH connection
         if [[ $PARAM =~ --cmd=(.+)? ]]; then
            SCRIPT_TO_RUN=$(echo "$PARAM" | cut --delimiter="=" --fields=2)
         else
            USE_SCRIPT_TO_RUN=1
         fi
         continue
      fi

      if [[ $PARAM =~ --cfg(=.+)? ]]; then
         if [[ $PARAM =~ --cfg=(.+)? ]]; then
            CMDLINE_CFG=$(echo "$PARAM" | cut --delimiter="=" --fields=2)
         else
            USE_CMDLINE_CFG=1
         fi
         continue
      fi

      if [[ $PARAM =~ --keydir(=.+)? ]]; then
         if [[ $PARAM =~ --keydir=(.+)? ]]; then
            CMDLINE_KEYDIR=$(echo "$PARAM" | cut --delimiter="=" --fields=2)
         else
            USE_CMDLINE_KEYDIR=1
         fi
         continue
      fi

      if [[ $PARAM == '--x11' ]]; then
         USE_X11_FWD=1
         continue
      fi

      if [[ $PARAM == '--help' || $PARAM == '-h' ]]; then
         PRINT_HELP=1
         break
      fi

      if [[ $PARAM == '--verbose' || $PARAM == '-v' ]]; then
         USE_VERBOSE=1
         continue
      fi

      # if we are here, we encountered something unknown in PARAM
      # if UNKNOWN is already set, add a comma for separation

      if [[ -n $UNKNOWN ]]; then
         UNKNOWN="$UNKNOWN,"
      fi

      UNKNOWN="${UNKNOWN}${PARAM}"

   done

   if [[ -n $UNKNOWN ]]; then
      echo "Unknown parameters '$UNKNOWN'" >&2
      PRINT_HELP=1
   fi

   if [[ -n $PRINT_HELP ]]; then
      echo "--cfg=<path-to-file>  to explicity give the config file for the remote" >&2
      echo "--ip=<ipaddr>         to set/override IP address from config file" >&2
      echo "--dns=<hostname>      to set/override hostname from config file" >&2
      echo "--port=<int>          to set/override TCP port from config file" >&2
      echo "--x11                 to switch on X11 forwarding" >&2
      echo "--verbose|-v          to make SSH client be verbose" >&2
      echo "--ssh|ssh             to explicitly use SSH client (this is the default)" >&2
      echo "--sftp|--ftp|sftp|ftp to explicitly use SSH client in SFTP mode" >&2
      echo "--http|http           to use Firefox to access an http:// URL" >&2
      echo "--https|https         to use Firefox to access an https:// URL" >&2
      echo "--keydir=<dir>        to override the private-SSH-key directory $HOME/.ssh" >&2
      echo "--cmd=<string>        to execute a command on the remote" >&2
      echo "--touch               to run simple information dumping shell commands on the remote" >&2
      exit 1
   fi
 
   if [[ -n $USE_IP && -n $USE_DNS ]]; then
      echo "Both '--ip=...' and '--dns=...' specified: use only one of those" >&2
      exit 1
   fi
}

# ===
# We are getting configuration from a configuration file
# It may have been given on the command line
# ===

lookForConfigFile() {
   local C1_LOGIND_DIR=$1
   local C2_LOGIND_DIR=$2
   local REQUEST1=$3
   local REQUEST2=$4
   local CANDIDATE=
   local COUNT=
   local CONFIG_FILE=
   for CANDIDATE in "$C1_LOGIND_DIR" "$C2_LOGIND_DIR"; do
      if [[ -d $CANDIDATE ]]; then
         # Recursively search underneath $CANDIDATE so that the user may organize this at will
         COUNT=$(find "$CANDIDATE" '(' -name "$REQUEST1" -o -name "$REQUEST2" ')' -type f | wc -l)
         if [[ $COUNT -gt 1 ]]; then
            echo "The directory '$CANDIDATE' contains $COUNT config files named '$REQUEST1' or '$REQUEST2'" >&2
            echo "Unsure how to connect -- exiting" >&2
            # TODO: Take the longest one first
            # TODO: This exit doesn't work as the function is executed in a subshell
            exit 1
         fi
         if [[ $COUNT -eq 1 ]]; then
            CONFIG_FILE=$(find "$CANDIDATE" '(' -name "$REQUEST1" -o -name "$REQUEST2" ')' -type f)
            break
         fi
      fi
   done
   echo "$CONFIG_FILE"
}

# ===
# Decide which config file to use
# ===

whichConfigFile() {
   if [[ -n $CMDLINE_CFG ]]; then
      if [[ ! -f "$CMDLINE_CFG" ]]; then
         echo "Cannot find configuration file given on the command line '$CMDLINE_CFG' (give full path!)" >&2
         echo "" # returned config file
      else
         echo "$CMDLINE_CFG" # returned config file
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
      local REQUEST1=$(basename "$0")   # possibly the name of the script
      local REQUEST2="${REQUEST1%%_*}"  # possibly with everyting after "_" removed
      #
      # Primary directory with login configuration files (searched first)
      #   
      local LOGIND="login.d"
      #
      # First choice is underneath user's .ssh directory
      #
      local C1_LOGIND_DIR="$HOMEDIR/.ssh/$LOGIND"
      #
      # Second choice is underneath the KEYDIR (given on the command line or the default one)
      # (it may well the same as above)
      #
      local C2_LOGIND_DIR="$KEYDIR/$LOGIND"  
      if [[ $C2_LOGIND_DIR == $C1_LOGIND_DIR ]]; then
         C2_LOGIND_DIR=
      fi
      #
      # Determine how to connect by name of command ---
      #
      if [[ ! -d "$C1_LOGIND_DIR" && ! -d "$C2_LOGIND_DIR" ]]; then
         echo "None of the directories" >&2
         echo "   $C1_LOGIND_DIR" >&2
         [[ -n $C2_LOGIND_DIR ]] && echo "   $C2_LOGIND_DIR" >&2
         echo "exists." >&2
         return 1
      fi
      local CONFIG_FILE=$(lookForConfigFile "$C1_LOGIND_DIR" "$C2_LOGIND_DIR" "$REQUEST1" "$REQUEST2")
      if [[ -z $CONFIG_FILE ]]; then
         echo "None of the directories" >&2
         echo "   $C1_LOGIND_DIR" >&2
         [[ -n $C2_LOGIND_DIR ]] && echo "   $C2_LOGIND_DIR" >&2
         echo -n "contains a file named '$REQUEST1'" >&2
         if [[ $REQUEST1 != $REQUEST2 ]]; then
             echo "or '$REQUEST2'." >&2
         fi
         echo >&2        
         return 1
      fi
      echo "$CONFIG_FILE" # successfully returned config file
      return 0
   fi
}

# ===
# DNS reverse resolution
# ===

reverseResolve() {
   local X=$1
   REVERSE=$(dig +short -x "$X")
   # spacing and parentheses are included here for convenience
   if [[ -z $REVERSE ]]; then
      REVERSE=" (could not be reverse-resolved)"
   else
      REVERSE=" (reverse-resolves to '$REVERSE')"
   fi
   echo "$REVERSE"
}

# ===
# DNS forward resoluion
# ===

forwardResolve() {
   local X=$1
   FORWARD=$(dig +short "$X")
   # spacing and parentheses are included here for convenience
   if [[ -z $FORWARD ]]; then
      FORWARD=" (could not be resolved)"
   else
      FORWARD=" (resolves to $FORWARD)"
   fi
   echo "$FORWARD"
}

# ===
# Fix Key File permissions
# The permission of the PRIVKEY should be "rw by owner only". If this is not
# the case, ssh will complain and exit when invoked. Let's fix it here!
# ===

fixKeyFilePermissions() {
   local KEY=$1
   local STAT=$(stat --format="%a" "$KEY")
   if [[ $? != 0 ]]; then
      echo "Could not stat private key file '$KEY' -- exiting" >&2
      exit 1
   fi
   if [[ $STAT != '600' ]]; then
      echo "Fixing permissions on private key file '$KEY'. Currently they are $STAT" >&2
      chmod 600 "$KEY"
      if [[ $? != 0 ]]; then
         echo "Could not chmod private key file '$KEY' -- exiting" >&2
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
# If CMD not set, default to "ssh"
# ---

if [[ -z $CMD ]]; then
   CMD=ssh
fi

# ---
# User home directory
# ---

USER=$(whoami)
HOMEDIR=$(getent passwd "$USER" | cut -d: -f6)

if [[ ! -d $HOMEDIR ]]; then 
   echo "The home directory '$HOMEDIR' of user '$USER' does not exist -- exiting" >&2
   exit 1
fi

# --- 
# Directory which contains the private keys, possibly overriden on cmdline
# The KEYDIR may not exist ... check later when it is needed
# --- 

if [[ -n $CMDLINE_KEYDIR ]]; then
   KEYDIR=$CMDLINE_KEYDIR
else
   KEYDIR=$HOMEDIR/.ssh
fi

CONFIG_FILE=$(whichConfigFile)

if [[ $? != 0 ]]; then
   echo "Cannot find out how to connect to anything due to missing config file -- exiting" >&2
   exit 1
else
   echo "Using configuration file '$CONFIG_FILE'" >&2
fi

# Reconstruct the "request" which will be used as %THIS% when reading the CONFIG_FILE

THIS=$(basename "$CONFIG_FILE")
THIS=${THIS%%_*}  # everyting after "_" removed

# --- Extract information from CONFIG_FILE using Perl script

EE="$DIR/login/bin/hidden/extract.pl"

# This shall be filled (or not)
# If the called script exits with error, we exit too and assume a message has been printed.
# Values may be missing. That is not a problem as they may be on the command line.
# Same value cannot be found at the same time, even (case of HARDCODED_DNS and HARDCODED_IP)
# A missing value may mean NO in case of booleans (case of USE_NOSTRICT)

HARDCODED_DNS=$($EE "$CONFIG_FILE" "HARDCODED_DNS") || exit 1
HARDCODED_IP=$($EE "$CONFIG_FILE" "HARDCODED_IP")   || exit 1
USER=$($EE "$CONFIG_FILE" "USER")                   || exit 1
PRIVKEY=$($EE "$CONFIG_FILE" "PRIVKEY")             || exit 1
HARDCODED_PORT=$($EE "$CONFIG_FILE" "PORT")         || exit 1
USE_NOSTRICT=$($EE "$CONFIG_FILE" "USE_NOSTRICT")   || exit 1
DESC=$($EE "$CONFIG_FILE" "DESC")                   || exit 1
TUNNEL=$($EE "$CONFIG_FILE" "TUNNEL")               || exit 1

# --- A description which may or may not exist
# Print colored, see: http://stackoverflow.com/questions/5947742/how-to-change-the-output-color-of-echo-in-linux

if [[ -n $DESC ]]; then
   writeColored "Target description" "$DESC"
fi

# --- If USER is unset or the string %ACTUAL% then replace by the result of "whoami"

if [[ -z $USER || $USER == "%ACTUAL%" ]]; then
   USER=$(whoami)
   SELUSER="Current user '$USER'"
else
   SELUSER="Specified user '$USER'"
fi

writeColored "Selected user" "$SELUSER"

# --- Set the 'PORT' by checking available values

if [[ -n $CMDLINE_PORT ]]; then
   PORT=$CMDLINE_PORT
   SELPORT="command line port $PORT"
elif [[ -n $HARDCODED_PORT ]]; then
   PORT=$HARDCODED_PORT
   SELPORT="hardcoded port $PORT"
else
   PORT=
   SELPORT="no port specified (using default value 22)"
fi

writeColored "Selected port" "$SELPORT"

# --- Set the 'TARGET' by checking available values; take the first that applies

if [[ -n $HARDCODED_DNS && -n $HARDCODED_IP ]]; then
   echo "Both hardcoded DNS ($HARDCODED_DNS) and hardcoded IP ($HARDCODED_IP) are set. What do? -- exiting" >&2
   exit 1
fi

TARGET=
SELECTED=
REVERSE1=
REVERSE2=
FORWARD1=
FORWARD2=

if [[ -n $CMDLINE_IP ]]; then
   TARGET=$CMDLINE_IP
   SELECTED="command line host IP"
   REVERSE1=$(reverseResolve "$TARGET")
fi

if [[ -z $TARGET && -n $CMDLINE_DNS ]]; then
   TARGET=$CMDLINE_DNS
   SELECTED="command line host name"
   FORWARD1=$(forwardResolve "$TARGET")
fi

if [[ -z $TARGET && -n $HARDCODED_IP ]]; then
   TARGET=$HARDCODED_IP
   SELECTED="hardcoded IP"
   REVERSE2=$(reverseResolve "$TARGET")
fi

if [[ -z $TARGET && -n $HARDCODED_DNS ]]; then
   # If a %THIS% is in the HARDCODED_DNS, replace by name of the request, i.e. the name of the config file itself: REQUEST 
   # TARGET=$(echo "$HARDCODED_DNS" | sed "s/%THIS%/$THIS/g")
   TARGET=${HARDCODED_DNS//%THIS%/$THIS}
   SELECTED="hardcoded host name"
   if [[ $TARGET != "$HARDCODED_DNS" ]]; then
      MORETEXT1=" (modified to '$TARGET')"
   else
      MORETEXT1=""
   fi
   MORETEXT2=$(forwardResolve "$TARGET")
   FORWARD2="$MORETEXT1 $MORETEXT2"
fi

if [[ -z $TARGET ]]; then
   echo "Could not determine to which host to connect; nothing on the command line or in the script" >&2
fi

# do not include spacing or markup in the second string so that it stays empty if the values are empty!

writeColored "Command line host IP"   "${CMDLINE_IP}${REVERSE1}"
writeColored "Command line host name" "${CMDLINE_DNS}${FORWARD1}"
writeColored "Hardcoded host IP"      "${HARDCODED_IP}${REVERSE2}"
writeColored "Hardcoded host name"    "${HARDCODED_DNS}${FORWARD2}"

if [[ -n $SELECTED ]]; then
   writeColored "Selected target" "$SELECTED '$TARGET'"
fi

if [[ -z $TARGET ]]; then
   echo "Exiting" >&2
   exit 1
fi

# --- Build the command array for "exec" to run SSH, SFTP or firefox

declare -a CMDARR
CMDARR[0]=$CMD
I=1

if [[ $CMD == http || $CMD == https ]]; then

   CMDARR[0]="firefox"
   if [[ $CMD == http ]]; then   
      CMDARR[1]="http://${TARGET}"
   else 
      CMDARR[1]="https://${TARGET}"
   fi

else

   CMDARR[$I]="-oConnectTimeout=2"
   (( I++ ))
 
   if [[ -n $USE_X11_FWD ]]; then
      CMDARR[$I]="-oForwardX11=yes"
      (( I++ ))
   fi

   if [[ -n $USE_VERBOSE ]]; then
      CMDARR[$I]="-vvv" # Really verbose!
      (( I++ ))
   fi

   if [[ -n $PORT ]]; then
      CMDARR[$I]="-oPort=${PORT}" 
      (( I++ ))
   fi

   if [[ -n $USE_NOSTRICT ]]; then
      CMDARR[$I]="-oStrictHostKeyChecking=no"
      (( I++ ))
   fi 

   if [[ -n $TUNNEL ]]; then
      CMDARR[$I]="-L${TUNNEL}"
      (( I++ ))
   fi 

   if [[ -n $PRIVKEY ]]; then

      # Replace certain strings in the PRIVKEY string:
      # %USER% --> login user: USER
      # %THIS% --> $THIS (basically the name of the config file with everything after the first _ removed)

      NEWPRIVKEY=$(echo "$PRIVKEY" | sed "s/%USER%/$USER/g" | sed "s/%THIS%/$THIS/g")

      if [[ "$NEWPRIVKEY" != "$PRIVKEY" ]]; then
         # echo "Private key patched from '$PRIVKEY' to '$NEWPRIVKEY'" >&2
         PRIVKEY="$NEWPRIVKEY"
      fi

      # echo "Private key to use is '$PRIVKEY'" >&2

      if [[ $PRIVKEY == /* ]]; then
         # absolute
         KEY=$PRIVKEY
      else
         # find the key under KEYDIR
         if [[ ! -d $KEYDIR ]]; then 
            echo "The keydirectory '$KEYDIR' does not exist or is not accessible -- exiting" >&2
            exit 1
         fi
         COUNT=$(find "$KEYDIR" -name "$PRIVKEY" -type f | wc -l)
         if [[ $COUNT -eq 0 ]]; then
            echo "The private key directory '$KEYDIR' contains no file named '$PRIVKEY' -- exiting" >&2
            exit 1
         fi
         if [[ $COUNT -gt 1 ]]; then
            echo "The private key directory '$KEYDIR' contains $COUNT files named '$PRIVKEY'. Unsure which to use -- exiting" >&2
            exit 1
         fi
         KEY=$(find "$KEYDIR" -name "$PRIVKEY" -type f)
      fi

      if [[ ! -f $KEY ]]; then
         echo "Key '$KEY' needed, but it does not exist" >&2
         exit 1
      fi

      fixKeyFilePermissions "$KEY"

      CMDARR[$I]="-i$KEY" 
      (( I++ ))

  fi

   CMDARR[$I]="${USER}@${TARGET}"
   (( I++ ))

   if [[ -n $SCRIPT_TO_RUN ]]; then
      CMDARR[$I]=$SCRIPT_TO_RUN
   fi
 
fi

# --- Connect ---

echo "Will run this command: ${CMDARR[*]}" >&2

if [[ -z $TOUCH_REMOTE ]]; then
   # Run the SSH command. 
   # Should we replace the current process using "exec" or run in subshell? Both work fine!
   # But if we run in subshell (and wait), we can do something on return, which is better.
   # exec "${CMDARR[@]}"
   # To compute duration, use "SECONDS", a built-in variable
   # https://stackoverflow.com/questions/8903239/how-to-calculate-time-difference-in-bash-script
   SECONDS=0 
   "${CMDARR[@]}"
   RES=$?
   duration=$SECONDS
   if [[ $RES != 0 ]]; then
      writeError "*** Some problem occurred. Return value is $RES. ***"
      if [[ $duration -gt 100 ]]; then
         writeError "It is now $(date)"
      fi
   fi
   txt="Connected for $(textifyDuration $duration)"
   if [[ $RES != 0 ]]; then
      writeError "$txt"
   else
      echo "$txt" >&2
   fi
else
   "${CMDARR[@]}" << HERE
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

