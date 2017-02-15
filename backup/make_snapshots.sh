#!/usr/bin/env bash

MY_HOME=$(dirname $(readlink -f "${0}"))

if [ ! -f "${1}" ]
then
   echo "Usage: ${0} <config>" >&2
   exit 1
fi

echo "Using config '${1}'"
source "${1}"


# ------------- sanity checks --------------------------------------

if ! [[ "${NUM_SNAPSHOTS}" =~ ^[\-0-9]+$ ]] || (( NUM_SNAPSHOTS < 1))
then
   echo "NUM_SNAPSHOTS (${NUM_SNAPSHOTS}) is not an integer that is at least 1." >&2
   exit 1
fi
if [ ! -f "${SNAPSHOT_EXCLUDES}" ]
then
   echo "SNAPSHOT_EXCLUDES (${SNAPSHOT_EXCLUDES}) needs to be an existing file - possibly empty." >&2
   exit 1
fi


function snapshot_path {
   printf "%s/snapshot-%02d" "${BACKUP_HOME}" "${1}"
}

# ------------- the script itself --------------------------------------


# # attempt to remount the RW mount point as RW; else abort
# $MOUNT -o remount,rw $MOUNT_DEVICE $SNAPSHOT_RW ;
# if (( $? )); then
#    {
#       $ECHO "snapshot: could not remount $SNAPSHOT_RW readwrite";
#        exit;
#    }
# fi;

# STEP 1: delete the oldest snapshot, if it exists:
OLDEST="$(snapshot_path $((NUM_SNAPSHOTS-1)))"
if [ -d "${OLDEST}" ]
then
   rm -rfv "${OLDEST}"
fi

# STEP 2: shift the middle snapshots(s) back by one, if they exist
for NUM in $(seq $((NUM_SNAPSHOTS-2)) -1 1)
do
   OLD="$(snapshot_path ${NUM})"
   if [ -d "${OLD}" ]
   then
      mv -v "${OLD}" "$(snapshot_path $((NUM+1)))"
   fi
done

# STEP 3: make a hard-link-only (except for dirs) copy of the latest snapshot,
# if that exists
LATEST="$(snapshot_path 0)"
if [ -d "${LATEST}" ]
then
   cp -alv "${LATEST}" "$(snapshot_path 1)"
fi

# step 4: rsync from the system into the latest snapshot (notice that
# rsync behaves like cp --remove-destination by default, so the destination
# is unlinked first.  If it were not so, this would copy over the other
# snapshot(s) too!
mkdir -vp ${LATEST}
for SRC in ${!SNAPSHOT_ORIGINS[@]}
do
   # Src with trailing '/', tgt without.
   rsync -va --delete --delete-excluded --exclude-from="${SNAPSHOT_EXCLUDES}" \
      "$(readlink -m "${SRC}")/" \
      "$(readlink -m ${LATEST}/${SNAPSHOT_ORIGINS[${SRC}]})"
done

# STEP 5: update the mtime of hourly.0 to reflect the snapshot time
touch "${LATEST}"

# and thats it for home.

# now remount the RW snapshot mountpoint as readonly
# $MOUNT -o remount,ro $MOUNT_DEVICE $SNAPSHOT_RW ;
# if (( $? )); then
#    {
#       $ECHO "snapshot: could not remount $SNAPSHOT_RW readonly";
#       exit;
#    } fi;

