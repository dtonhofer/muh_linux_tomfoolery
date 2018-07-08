#!/bin/bash

# =====================
# Install the symlinks for logins in user's home directory
# =====================

DIR=~qq  # ~qq is actually /usr/local/toolbox

if [[ ! -d $DIR ]]; then
   echo "There is no directory '$DIR'. Fix the script! Exiting!" >&2
   exit 1
fi

if [[ $UID == 0 ]]; then
   echo "You are root -- exiting!" >&2
   exit 1
fi

# ---
# Does the target script (i.e. "loggy.sh" to which all the symlinks will point) exist?
# ---

TARGET=$DIR/login/bin/loggy.sh

if [[ ! -x $TARGET ]]; then
   echo "The common symlink target, i.e. the executable '$TARGET' does not exist or is not executable -- exiting!" >&2
   exit 1
fi

# ---
# WHERE is the directory into which we add symlinks. This
# directory is put on the PATH by the script
# "/etc/profile.d/toolbox.sh"
# ---

# Candidates:

WHERE_C1="$HOME/bin/login"
WHERE_C2="$HOME/.bin/login" # Preferred because not shown by default.

if [[ -d "$WHERE_C2" ]]; then
   WHERE="$WHERE_C2"
elif [[ -d "$WHERE_C1" ]]; then
   WHERE="$WHERE_C1"
else
   echo "Neither directory '$WHERE_C1' nor directory '$WHERE_C2' (the directory" >&2
   echo "holding the correctly named symlinks to '$TARGET') exist -- please" >&2
   echo "create either one and put it on the PATH!" >&2
   echo "Exiting!" >&2
   exit 1
fi

cd "$WHERE" || exit 1

# ---
# LOGIND is the directory holding the user-local login configuration files which have
# been copied at some time from ~qq/login/config/$(hostname)
# ---

LOGIND="$HOME/.ssh/login.d"

if [[ ! -d "$LOGIND" ]]; then
   echo "Directory '$LOGIND' (holding the login configuration files) does not exist -- exiting!" >&2
   exit 1
fi

# ---
# The user may have asked for refresh
# ---

if [[ -n $REFRESH ]]; then
   LOGIND_SRC=~qq/login/config/$(hostname)
   if [[ ! -d $LOGIND_SRC ]]; then
      echo "Cannot refresh as the source directory '$LOGIND_SRC' does not exist -- exiting!" >&2
      exit 1
   fi
fi

# ---
# TODO: Handle an option --refresh, which creates this directory and fills it with the
# config files found in ~qq/login/config/$(hostname) and deletes any superfluous files
# ---

# ---
# Get all the "machines" in an array - one per configuration file in $LOGIND
# ---

MACHINES=()

while IFS= read -d $'\0' -r MACHINE; do
   MACHINE=$(basename $MACHINE)
   MACHINES+=("$MACHINE")
done < <(find "$LOGIND" -maxdepth 1 -type f -print0)

# ---
# For each configuration file, create a symlink!
# ---

for MACHINE in "${MACHINES[@]}"; do
   if [[ -s "$MACHINE" ]]; then
      echo "Symlink '$MACHINE' exists -- skipping!" >&2
   else
      echo "*** Symlink '$MACHINE' does not exist -- creating! ***" >&2
      ln -s "$TARGET" "$MACHINE"
      if [[ $? != 0 ]]; then
         echo "Could not create symlink '$MACHINE' --> '$TARGET'" >&2
      fi
   fi
done

