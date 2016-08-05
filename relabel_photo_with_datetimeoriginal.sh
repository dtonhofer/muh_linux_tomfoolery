#!/bin/bash

# BUGS: This program fails hard if the filename STARTS WITH A "--" as can happen via erroneous renaming

# -------
# This renames the images given on the command line
#
# One might run this as follows:
#
# ls | xargs ~qq/assorted/relabel_photo_with_datetimeoriginal.sh
#
# Or better:
#
# find . -name "*.jpg" -exec ~qq/assorted/relabel_photo_with_datetimeoriginal.sh '{}' ';'
#
# Or else one can grab several files and several directories (all examined at level 1 only):
#
# ~qq/assorted/relabel_photo_with_datetimeoriginal.sh --directory=SOMEDIR SOMEFILE1 SOMEFILE2 --directory=SOMEOTHERDIR
# -------

# ---
# Is exiftool there?
# ---

which exiftool >/dev/null 2>&1

if [[ $? != 0 ]]; then
   echo "Command 'exiftool' does not exist -- exiting" >&2
   echo "Maybe install it using 'dnf install perl-Image-ExifTool'" >&2
   exit 1
fi

which file >/dev/null 2>&1

if [[ $? != 0 ]]; then
   echo "Command 'file' does not exist -- exiting" >&2
   exit 1
fi


# ---
# Transform a datetime "YYYY:MM:DD hh:mm:ss" into "Y=....;M=..;D=..;h=..;m=..;s=.." which is 
# shell command that can be evaled later.
# The result is printed to STDOUT.
# ---

function transformDatetime {
   local NAME=$1
   local DATETIME=$2
   local FILE=$3
   # get rid of surrounding whitespace
   DATETIME=$(echo $DATETIME) 
   if [[ -z $DATETIME ]]; then
      echo "$NAME(): No value found" >&2
      return
   fi
   echo "$NAME(): File '$FILE' has time '$DATETIME'" >&2
   local RESULT=$(echo $DATETIME | perl -e 'if (<> =~ /^\s*(\d\d\d\d):(\d\d):(\d\d) (\d\d):(\d\d):(\d\d)\s*$/) { print "Y=$1;M=$2;D=$3;h=$4;m=$5;s=$6" }')
   if [[ -z $RESULT ]]; then
      echo "$NAME(): Some values from the date/time are unset or invalid" >&2
      return
   fi
   echo $RESULT
}

# ---
# Get datetime from "datetimeoriginal"
# The result is printed to STDOUT
# ---

function dateTimeFromDateTimeOriginal {
   local NAME=dateTimeFromDateTimeOriginal
   local FILE=$1
   local DATETIME=$(exiftool -l "-EXIF:DateTimeOriginal" "$FILE" | tail -1)
   if [[ $? != 0 ]]; then
      echo "$NAME(): exiftool returned $?" >&2
      return
   fi
   transformDatetime "$NAME" "$DATETIME" "$FILE"
}

# ---
# Get datetime form "profile" (doesn't work)
# The result is printed to STDOUT
# ---

function dateTimeFromProfileDateTime {
   local NAME=dateTimeFromProfileDateTime
   local FILE=$1
   local DATETIME=$(exiftool -l "-ProfileDateTime" "$FILE" | tail -1)
   if [[ $? != 0 ]]; then
      echo "$NAME(): exiftool returned $?" >&2
      return
   fi
   transformDatetime "$NAME" "$DATETIME" "$FILE"
}

# ---
# Process a single file
# ---

function processFile {
   local FILE=$1

   # Sanity checks

   if [[ -z $FILE ]]; then
      echo "Empty file argument -- skipping!" >&2
      return
   fi

   if [[ ! -f $FILE ]]; then
      echo "File '$FILE' does not exist -- skipping this file!" >&2
      return
   fi 

   # Determine suffix for later renaming

   local MIME=$(file --mime-type --brief -- "$FILE")
   if [[ $? != 0 ]]; then
      echo "Could not run 'file' command -- exiting" >&2
      exit 1
   fi

   echo "Mime type of '$FILE': $MIME" >&2
   local SUFFIX=

   if [[ $MIME == 'image/jpeg' ]]; then
      SUFFIX=".jpg"
   elif [[ $MIME == 'image/png' ]]; then
      SUFFIX=".png"
   elif [[ $MIME == 'image/gif' ]]; then
      SUFFIX=".gif"
   elif [[ $MIME == 'image/x-canon-cr2' ]]; then
      SUFFIX=".cr2"
   else
      echo "Unknown mime type '$MIME' for file '$FILE' -- skipping this file!" >&2
      return
   fi

   # Try to get a good datetime

   local CMD=$(dateTimeFromDateTimeOriginal "$FILE")

   # This does not actually work:
   # if [[ -z $CMD ]]; then
   #    CMD=$(dateTimeFromProfileDateTime "$FILE")
   # fi

   if [[ -z $CMD ]]; then
      echo "No good datetime could be extracted from file '$FILE' -- skipping this file" >&2
      return 
   fi

   eval "$CMD"

   local NEW="${Y}-${M}-${D}_${h}:${m}:${s}"

   echo "New name base: $NEW" >&2

   local DIR=$(dirname -- "$FILE")

   local PRIOR_FILE=$(basename -- "$FILE") 
   local NEW_FILE="${NEW}${SUFFIX}"

   if [[ $PRIOR_FILE == $NEW_FILE ]]; then
      echo "File '$FILE' already has correct name -- skipping this file" >&2
      return
   fi

   local INDEX=1
   local NEWFQFILE="${DIR}/${NEW}${SUFFIX}"

   while [[ -f ${NEWFQFILE} ]]; do
      echo "Cannot rename '$FILE' to '$NEWFQFILE' -- destination exists. Attaching index $INDEX" >&2
      NEWFQFILE="${DIR}/${NEW}.${INDEX}${SUFFIX}"
      let INDEX=${INDEX}+1
   done

   /bin/mv -- "$FILE" "$NEWFQFILE"

   if [[ $? != 0 ]]; then
      echo "Could not rename '$FILE' to '$NEWFQFILE' -- skipping this file!" >&2
   else
      echo "Successfully renamed '$FILE' to '$NEWFQFILE'" >&2
   fi
}

# ---
# Loop over a whole directory, collecting files at level 1
# We (ugly-ly) fill the global variable MORE_FILES (an array)
# with the files found. No selection on files is done yet.
# ---

MORE_FILES=()

function handleDirectory {

   local DIR=$1

   if [[ -z $DIR ]]; then
      echo "Empty directory argument -- skipping!" >&2
      return
   fi

   if [[ ! -d $DIR ]]; then
      echo "Directory '$DIR' does not exist (or is not a directory) -- skipping this!" >&2
      return
   fi 

   # http://stackoverflow.com/questions/8213328/bash-script-find-output-to-array

   local FILE=

   while IFS= read -d $'\0' -r FILE ; do
      MORE_FILES=("${MORE_FILES[@]}" "$FILE")
   done < <(find "$DIR" -maxdepth 1 -type f -print0)

   # echo "$DIR --> ${MORE_FILES[@]}"
}

# ------
# Process all files given on the command line
# ------

# An argument that reads as "--directory=X" means "process all the files from that directory"
# Any other argument is taken to indicate a file directly

ALL_FILES=()
NEXT_COMES_DIRECTORY=

for PARAM in "$@"; do   

   if [[ -n $NEXT_COMES_DIRECTORY ]]; then
      DIRECTORY=$PARAM
      NEXT_COMES_DIRECTORY=
   elif [[ $PARAM =~ --directory(=.+)? ]]; then
      if [[ $PARAM =~ --directory=(.+)? ]]; then
         DIRECTORY=`echo $PARAM | cut --delimiter="=" --fields=2`
         NEXT_COMES_DIRECTORY=
      else
         DIRECTORY=
         NEXT_COMES_DIRECTORY=1
      fi
   else 
      # Assume this is a file
      ALL_FILES=("${ALL_FILES[@]}" "$PARAM")
   fi

   if [[ -n $DIRECTORY ]]; then
      MORE_FILES=()
      handleDirectory $DIRECTORY
      DIRECTORY=''
      # MORE_FILES now contains more files
      ALL_FILES=("${ALL_FILES[@]}" "${MORE_FILES[@]}")
      MORE_FILES=()
   fi

done

COUNT=0

for FILE in "${ALL_FILES[@]}"; do
   echo "--------------------------" >&2
   echo $FILE >&2
   echo "--------------------------" >&2
   processFile "$FILE"
   let COUNT=$COUNT+1
done

echo "Done, processed $COUNT files" >&2


