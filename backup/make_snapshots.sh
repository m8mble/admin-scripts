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


# ------------- helpers --------------------------------------


is_callable() {
   type -t "${@}" | grep -cE 'file|alias|function'
}

# Make a full, hard-link-only copy of LINK_DEST, if that
# exists. Afterwards rsync from the system (SRC) into TGT.
#
# Do this in a single step (time for some rsync magic):
# Use --link-dest flag which upon syncing SRC hard-links to LINK_DEST
# iff the file in SRC is the same.
create_rsync_snapshot() {
   SRC="${1}"
   TGT="${2}"
   LINK_DEST="${3}"
   EXCLUDES="${4}"

   RSYNC_ARGS=(-va --delete --delete-excluded \
      "$(readlink -m "${SRC}")/" \
      "$(readlink -m "${TGT}")")

   # ... with link-dest iff available
   if [ -e "${EXCLUDES}" ]
   then
      RSYNC_ARGS=("${RSYNC_ARGS[@]}" "--exclude-from=${EXCLUDES}")
   fi
   # ... with link-dest iff available
   if [ -d "${LINK_DEST}" ]
   then
      RSYNC_ARGS=("${RSYNC_ARGS[@]}" "--link-dest=$(readlink -m "${LINK_DEST}")")
   fi

   # ... run it.
   rsync "${RSYNC_ARGS[@]}"
}

# Plain hardlink copy SRC -> TGT
create_hardlink_snapshot() {
   SRC="${1}"
   TGT="${2}"
   # ... ignore everything else

   cp -alv "${SRC}" "${TGT}"
}


# ------------- sanity checks --------------------------------------


if ! [[ "${NUM_SNAPSHOTS}" =~ ^[-0-9]+$ ]] || (( NUM_SNAPSHOTS < 1))
then
   echo "NUM_SNAPSHOTS (${NUM_SNAPSHOTS}) is not an integer that is at least 1." >&2
   exit 1
fi
if [ -z "${SNAPSHOT_PREFIX}" ]
then
   SNAPSHOT_PREFIX="snapshot"
fi
if [ -z "${NUM_SNAPSHOT_PLACES}" ]
then
   NUM_SNAPSHOT_PLACES=$(echo "${NUM_SNAPSHOTS}" \
      | awk 'function ceil(v){ return (v == int(v))?v: int(v)+1} {printf "%d", ceil(log($1)/log(10))}')
fi
snapshot_path () {
   printf "%s/${SNAPSHOT_PREFIX}-%0${NUM_SNAPSHOT_PLACES}d" "${BACKUP_HOME}" "${1}"
}

if [ "$(is_callable create_new_snapshot)" -ne 0 ]
then
   echo "Config must not overwrite \`create_new_snapshot\`." >&2
   exit 1
fi
case "${SNAPSHOT_CREATION_MODE}" in
   'hardlink-rsync')
      create_new_snapshot() {
         create_rsync_snapshot "${@}"
      }
      ;;

   'hardlink')
      create_new_snapshot() {
         create_hardlink_snapshot "${@}"
      }
      ;;

   *)
      echo "Unsupported SNAPSHOT_CREATION_MODE '${SNAPSHOT_CREATION_MODE}'." \
         "Must be 'hardlink-rsync' or 'hardlink'." >&2
      exit 1
esac


# ------------- the script itself --------------------------------------


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

# STEP 3: Create a new first snapshot for all SNAPSHOT_ORIGINS.
LATEST="$(snapshot_path 0)"
mkdir -vp "${LATEST}"
for SRC in "${!SNAPSHOT_ORIGINS[@]}"
do
   create_new_snapshot \
      "${SRC}" \
      "${LATEST}/${SNAPSHOT_ORIGINS[${SRC}]}" \
      "$(snapshot_path 1)/${SNAPSHOT_ORIGINS[${SRC}]}" \
      "${SNAPSHOT_EXCLUDES}"
done

# STEP 4: Sync snapshot config
cp -v "${CONFIG}" "${LATEST}/config.sh"

# STEP 5: update mtime of latest snapshot to reflect the snapshot time
touch "${LATEST}"
