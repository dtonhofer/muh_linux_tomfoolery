#!/bin/bash

# install the symlinks for logins in user's home directory

DIR=~qq  # ~qq is actually /usr/local/toolbox

if [[ ! -d $DIR ]]; then
   echo "There is no directory '$DIR'. Fix the script! Exiting!" >&2
   exit 1
fi

if [[ $UID == 0 ]]; then
   echo "You are root -- exiting!" >&2
   exit 1
fi

# Does the target exist?

TARGET=$DIR/login/bin/loggy.sh

if [[ ! -x $TARGET ]]; then
   echo "The common symlink target, i.e. the executable '$TARGET' does not exist or is not executable -- exiting!" >&2
   exit 1
fi

# WHERE is the directory into which we add symlinks. This
# directory is put on the PATH by the script
# "/etc/profile.d/toolbox.sh"

WHERE="$HOME/bin/login"

if [[ ! -d "$WHERE" ]]; then
   echo "Directory '$WHERE' (the directory holding the correctly named symlinks to '$TARGET') does not exist -- creating it!" >&2
   mkdir -p "$WHERE" 
   if [[ $? != 0 ]]; then
      echo "Could not create directory '$WHERE' -- exiting!" >&2
      exit 1
   fi
fi

cd "$WHERE" || exit 1

# FROM is the directory holding the login configuration files

FROM="$HOME/.ssh/login.d"

if [[ ! -d "$FROM" ]]; then
   echo "Directory '$FROM' (holding the login configuration files) does not exist -- exiting!" >&2
   exit 1
fi

# Get all the machines, one per configuration files

MACHINES=()

while IFS= read -d $'\0' -r MACHINE; do
   MACHINE=$(basename $MACHINE)
   MACHINES+=("$MACHINE")
done < <(find "$FROM" -maxdepth 1 -type f -print0)

# Loop over the configuration files

for MACHINE in "${MACHINES[@]}"; do
   echo "Handling machine '$MACHINE'..."
   CONFIGFILE="$FROM/$MACHINE"
   if [[ ! -f $CONFIGFILE ]]; then
      echo "The configuration file '$CONFIGFILE' does not exist -- skipping creation of symlink '$MACHINE'" >&2
      FOUND=$(find "$DIR/login/config" -name "$MACHINE")
      if [[ -n $FOUND ]]; then
         echo "There are configuration files in $DIR: $FOUND -- you may want to copy them!" >&2
      fi
   else
      if [[ -s "$MACHINE" ]]; then
         echo "Symlink '$MACHINE' exists -- skipping!" >&2
      else
         ln -s "$TARGET" "$MACHINE"
         if [[ $? != 0 ]]; then
            echo "Could not create symlink '$MACHINE' --> '$TARGET'" >&2
         fi
      fi
   fi
done

