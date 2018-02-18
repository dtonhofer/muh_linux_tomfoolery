#!/bin/bash

# =============================================================================
# Author:   David Tonhofer
# Rights:   Public Domain
#
# Make verifying a file's checksum easy! Constanly annoyed by not knowing 
# which checksum you have in front of you today and not ready to eyeball
# the result of md5sum? Use this!
#
# Check it:
#
# verify_checksum file.tgz [SHA1, SHA256, MD5 checksum]
#
# ...or you can exchange arguments:
#
# verify_checksum [SHA1, SHA256, MD5 checksum] file.tgz
#
# ...or you can compute the checksums of a file:
#
# verify_checksum file.tgz
#
# ...or you can compare two files:
#
# verify_checkusm file1.tgz file2.tgz
#
# (Program more or less passes "shellcheck")
# =============================================================================

set -o nounset

declare -A hasher
hasher[1]=md5sum
hasher[2]=sha1sum
hasher[3]=sha256sum
hasher[4]=sha512sum

# ---
# Two arguments given
# Returns 0 if none are a file.
#         1 if the first is a file.
#         2 if the second is a file.
#         3 if both are files.
# ---

function two_args_assess {
   local ARG1=$1
   local ARG2=$2
   local RES=0
   if [[ -f $ARG1 ]]; then
      ((RES+=1))
   fi
   if [[ -f $ARG2 ]]; then
      ((RES+=2))
   fi
   return $RES
}

# ---
# One argument given. It must be a file!
# If the argument is a file, prints the file's hashsums and returns 0.
# If the argument is not a file does nothing and, returns 1.
# ---

function one_arg_perform {
   local ARG=$1
   if [[ ! -f $ARG ]]; then
      return 1
   else
      local PROG
      for PROG in "${hasher[@]}"; do
         which "$PROG" >/dev/null 2>&1
         if [[ $? != 0 ]]; then
            echo "(Program '$PROG' not on path - skipping)" >&2
         else
            local RESULT=$($PROG "$ARG" | cut --field=1 --delimiter=' ')
            printf "%9s: %s\n" "$PROG" "$RESULT"
         fi
      done
      return 0
   fi
}

# ---
# Recognize hash
# Returns 0: unrecognized
#         1: md5sum
#         2: sha1
#         3: sha256
#         4: sha512
# ---

function recognize_hash {
   local UHASH=$1
   if [[ -n $(echo "$UHASH" | grep --perl-regex '^[0-9a-f]{32}$') ]]; then
      return 1 # md5
   elif [[ -n $(echo "$UHASH" | grep --perl-regex '^[0-9a-f]{40}$') ]]; then
      return 2 # sha1
   elif [[ -n $(echo "$UHASH" | grep --perl-regex '^[0-9a-f]{64}$') ]]; then
      return 3 # sha256
   elif [[ -n $(echo "$UHASH" | grep --perl-regex '^[0-9a-f]{128}$') ]]; then
      return 4 # sha512
   else
      return 0
   fi
}

# ---
# Verify hash
# Return 100: Error computing hash
#        101: Hash program not not on path
#          0: Hash matches
#          1: Hash does not match
# ---

function verify_hash_btm {
   local WHAT_HASH=$1
   local FILE=$2
   local UHASH=$3
   local PROG=${hasher[$WHAT_HASH]}
   which "$PROG" >/dev/null 2>&1
   if [[ $? != 0 ]]; then
      echo "Program '$PROG' not on path" >&2
      return 101
   else
      # >>> Compute!
      local RESULT=$("$PROG" "$FILE")
      # <<< 
      local RES=$?
      if [[ $? != 0 ]]; then
         echo "A problem occurred computing hashsum of '$FILE'" >&2
         return 100
      fi
      local CMPWITH=$(echo "$RESULT" | cut --fields=1 --delimiter=' ' | tr '[:upper:]' '[:lower:]')
      if [[ $CMPWITH == "$UHASH" ]]; then
         echo "OK: Hash MATCHES using $PROG on '$FILE'"
         return 0
      else 
         echo "BAD: Hash DOES NOT MATCH using $PROG on '$FILE'"
         echo "$UHASH -- should be"
         echo "$CMPWITH -- as is"
         return 1
      fi
   fi
}

# ---
# Given a file and a hash, verify! 
# It has already been checked that the file exists.
# Return: 99: unrecognized hash
#        100: Error computing hash
#        101: Hash program not not on path
#          0: Hash matches
#          1: Hash does not match
# ---

function verify_hash_top {
   local FILE=$1
   local HASH=$2
   local UHASH=$(echo "$HASH" | tr '[:upper:]' '[:lower:]')
   recognize_hash "$UHASH";
   local WHAT_HASH=$?
   case $WHAT_HASH in
   0) 
      echo "Could not recognize '$HASH' as either MD5 or SHA(1,256,512)" >&2
      return 99
      ;;
   *) 
      verify_hash_btm "$WHAT_HASH" "$FILE" "$UHASH"; 
      return $?
      ;;
   esac
}

# ---
# Comparing two files
# 0: All hashes match
# 1: At least one hash does not match
# ---

function compare_two_files {
   local FILE1=$1
   local FILE2=$2
   for PROG in "${hasher[@]}"; do
      which "$PROG" >/dev/null 2>&1
      if [[ $? != 0 ]]; then
         echo "(Program '$PROG' not on path - skipping)" >&2
      else
         local RESULT1=$($PROG "$FILE1" | cut --field=1 --delimiter=' ')
         local RESULT2=$($PROG "$FILE2" | cut --field=1 --delimiter=' ')
         if [[ $RESULT1 == "$RESULT2" ]]; then
            echo "OK: Hash MATCHES using $PROG ($RESULT1)"
         else 
            echo "BAD: Hash DOES NOT MATCH using $PROG"
            echo "$RESULT1 -- for '$FILE1'"
            echo "$RESULT2 -- fro '$FILE2'"
            return 1
         fi
      fi
   done
   return 0
}

# ---
# Main
# ---

ARG1=${1:-''}
ARG2=${2:-''}

if [[ -n $ARG1 && -n $ARG2 ]]; then
   two_args_assess "$ARG1" "$ARG2"
   RES=$?
   FILE=
   HASH=
   case $RES in
   0) 
      echo "None of the arguments designates a file" >&2
      exit 2
      # 2: Bad arguments
      ;;
   1) 
      FILE=$ARG1; HASH=$ARG2
      ;;
   2) 
      FILE=$ARG2; HASH=$ARG1
      ;;
   3) 
      compare_two_files "$ARG1" "$ARG2"
      exit $?
      #    0: All hashes match
      #    1: Some hashes do not match
      ;;
   *)  
   esac
   case $RES in
   1|2) 
      verify_hash_top "$FILE" "$HASH" 
      exit $?
      #    0: Hash matches
      #    1: Hash does not match
      #   99: Unrecognized hash
      #  100: Error computing hash
      #  101: Hash program not on path
      ;;
   esac
elif [[ -n $ARG1 ]]; then
   one_arg_perform "$ARG1"; 
   RES=$?
   case $RES in
   0) 
      exit 0
      ;;
   1) 
      echo "The argument '$ARG1' does not designate a file" >&2
      exit 2
      # 2: Bad arguments
      ;;
   *) 
      echo "Bad return value, fix code!!" >&2
      exit 102
      # 102: Internal error 
      ;;
   esac
else 
   echo "No arguments? Give at least a file and possibly a hashsum" >&2
   exit 2
   # 2: bad arguments
fi

