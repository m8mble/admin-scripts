#!/usr/bin/env bash

if [ ! -f "${1}" ]
then
   echo "Usage: ${0} <config>" >&2
   exit 1
fi

CONFIG="${1}"
echo "Using config '${CONFIG}'"
# shellcheck source=/dev/null
source "${CONFIG}"


# ------------- sanity checks --------------------------------------

if ! [[ "${NUM_SNAPSHOTS}" =~ ^[-0-9]+$ ]] || (( NUM_SNAPSHOTS < 1))
then
   echo "NUM_SNAPSHOTS (${NUM_SNAPSHOTS}) is not an integer that is at least 1." >&2
   exit 1
fi
if [ ! -f "${SNAPSHOT_EXCLUDES}" ]
then
   echo "SNAPSHOT_EXCLUDES (${SNAPSHOT_EXCLUDES}) needs to be an existing file - possibly empty." >&2
   exit 1
fi


snapshot_path () {
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

# STEP 2: shift remaining snapshots(s) back by one (including the first)
for NUM in $(seq $((NUM_SNAPSHOTS-2)) -1 0)
do
   OLD="$(snapshot_path "${NUM}")"
   if [ -d "${OLD}" ]
   then
      mv -v "${OLD}" "$(snapshot_path $((NUM+1)))"
   fi
done

# STEP 3: Create a new first snapshot for all SNAPSHOT_ORIGINS:
# Make a full, hard-link-only copy of the latest snapshot, if that
# exists. Afterwards rsync from the system into this latest snapshot.
#
# Do this in a single step (time for some rsync magic):
# Use --link-dest=LDST flag which upon syncing SRC hard-links to LDST
# iff the file in SRC is the same.
LATEST="$(snapshot_path 0)"
mkdir -vp "${LATEST}"
for SRC in "${!SNAPSHOT_ORIGINS[@]}"
do
   RSYNC_ARGS=(-va --delete --delete-excluded \
      "--exclude-from=${SNAPSHOT_EXCLUDES}" \
      "$(readlink -m "${SRC}")/" \
      "$(readlink -m "${LATEST}/${SNAPSHOT_ORIGINS[${SRC}]}")")

   # ... with link-dest iff available
   LINK_DEST="$(snapshot_path 1)/${SNAPSHOT_ORIGINS[${SRC}]}"
   if [ -d "${LINK_DEST}" ]
   then
      RSYNC_ARGS=("${RSYNC_ARGS[@]}" "--link-dest=$(readlink -m "${LINK_DEST}")")
   fi

   # ... run it.
   rsync "${RSYNC_ARGS[@]}"
done

# STEP 4: update the mtime of hourly.0 to reflect the snapshot time
touch "${LATEST}"

# now remount the RW snapshot mountpoint as readonly
# $MOUNT -o remount,ro $MOUNT_DEVICE $SNAPSHOT_RW ;
# if (( $? )); then
#    {
#       $ECHO "snapshot: could not remount $SNAPSHOT_RW readonly";
#       exit;
#    } fi;
