#!/usr/bin/env bash
set -euo pipefail
state=${STATE_DIRECTORY:?}
stage=${RUNTIME_DIRECTORY:?}
[[ ! -e "$state/complete-v1" ]] || exit 0
exec 9>"$state/lock"
flock -n 9
[[ ! -e "$state/complete-v1" ]] || exit 0
zfs list -H -o name storage >/dev/null

die() { echo "storage migration: $*" >&2; exit 1; }
mounted=()
cleanup() {
  local target
  for ((i=${#mounted[@]}-1; i>=0; i--)); do
    target=${mounted[i]}
    if mountpoint -q "$target"; then umount "$target" || true; fi
  done
}
trap cleanup EXIT

# Stop only running old units, not new consumers already waiting for us.
# Queue stops without blocking on a switch transaction that also needs us.
for unit in samba-smbd.service dufs.service storage-syncthing.service storage-scratch-clean.timer storage-scratch-clean.service; do
  if systemctl is-active --quiet "$unit"; then
    systemctl --no-block stop "$unit"
    while [[ $(systemctl show "$unit" -p ActiveState --value) != inactive ]]; do
      [[ $(systemctl show "$unit" -p ActiveState --value) != failed ]] || break
      sleep 1
    done
  fi
done
if systemctl is-active --quiet "user@$(id -u xsy).service"; then
  systemctl --user --machine=xsy@.host stop deltachat-archive-capture.service deltachat-archive-reader.service
fi

# A busy mount is a real error: never force/lazy unmount an unknown writer.
for suffix in games media archives/deltachat archives/cold-backups nixos-archive sync; do
  target="/srv/storage/$suffix"
  if mountpoint -q "$target"; then
    [[ $(findmnt -rn -M "$target" -o SOURCE) == "storage/$suffix" ]] || die "unexpected source at $target"
    umount "$target"
  fi
done

ensure_dataset() {
  local dataset=$1; shift
  if ! zfs list -H -o name "$dataset" >/dev/null 2>&1; then zfs create "$@" "$dataset"; fi
}
rename_dataset() {
  local old=$1 new=$2
  if zfs list -H -o name "$old" >/dev/null 2>&1; then
    ! zfs list -H -o name "$new" >/dev/null 2>&1 || die "both $old and $new exist"
    zfs rename "$old" "$new"
  else
    zfs list -H -o name "$new" >/dev/null
  fi
}
stage_mount() {
  local dataset=$1 target=$2 mode=$3
  if mountpoint -q "$target"; then
    [[ $(findmnt -rn -M "$target" -o SOURCE) == "$dataset" ]] || die "unexpected staging mount at $target"
    mounted+=("$target")
    return
  fi
  ! findmnt -rn -S "$dataset" >/dev/null || die "$dataset is still mounted"
  mkdir -p "$target"
  mount -t zfs -o "$mode" "$dataset" "$target"
  mounted+=("$target")
}
copy_tree() {
  local source=$1 target=$2
  mkdir -p "$target"
  rsync -aHAX --numeric-ids -- "$source/" "$target/"
  rsync -aHAXnc --numeric-ids --itemize-changes -- "$source/" "$target/" >"$stage/compare"
  [[ ! -s "$stage/compare" ]] || die "copy verification failed: $source -> $target"
}

# Refuse pre-existing destinations on the first run. Later runs can resume only
# the migration-owned destinations while the completion gate remains closed.
if [[ ! -e "$state/started-v1" ]]; then
  for dataset in storage/public storage/private; do
    ! zfs list -H -o name "$dataset" >/dev/null 2>&1 || die "unowned destination $dataset exists"
  done
  if [[ -e /var/lib/storage-syncthing ]]; then
    [[ -d /var/lib/storage-syncthing && ! -L /var/lib/storage-syncthing ]] || die "invalid Syncthing destination"
    [[ -z $(find /var/lib/storage-syncthing -mindepth 1 -maxdepth 1 -print -quit) ]] || die "Syncthing destination is not empty"
  fi
  touch "$state/started-v1"
  sync -f "$state"
fi

ensure_dataset storage/public -o mountpoint=legacy -o canmount=on -o recordsize=1M
ensure_dataset storage/private -o mountpoint=legacy -o canmount=on
for person in xsy shj ly; do
  ensure_dataset "storage/private/$person" -o mountpoint=legacy -o canmount=on -o recordsize=1M
done
ensure_dataset storage/private/xsy/archives -o mountpoint=none -o canmount=off
ensure_dataset storage/ballast -o mountpoint=none -o refreservation=200G

stage_mount storage/games "$stage/games" ro
stage_mount storage/public "$stage/public" rw
stage_mount storage/private "$stage/private" rw
stage_mount storage/private/xsy "$stage/xsy" rw
stage_mount storage/private/shj "$stage/shj" rw
stage_mount storage/private/ly "$stage/ly" rw

# Retry incomplete copies only while destinations are inaccessible to consumers.
[[ ! -e "$stage/games/public/media" && ! -L "$stage/games/public/media" ]] || die "legacy public/media conflicts with new media mount"
[[ -d "$stage/games/public" && ! -L "$stage/games/public" ]] || die "invalid legacy public tree"
[[ -d "$stage/games/private" && ! -L "$stage/games/private" ]] || die "invalid legacy private tree"
[[ ! -L "$stage/games/private/xsy/archives" ]] || die "xsy archives is a symlink"
for reserved in deltachat cold-backups nixos-archive legacy-games; do
  [[ ! -e "$stage/games/private/xsy/archives/$reserved" && ! -L "$stage/games/private/xsy/archives/$reserved" ]] || die "legacy xsy archive name conflicts: $reserved"
done
copy_tree "$stage/games/public" "$stage/public"
for person in xsy shj ly; do
  [[ ! -L "$stage/games/private/$person" ]] || die "private/$person is a symlink"
  if [[ -d "$stage/games/private/$person" ]]; then
    copy_tree "$stage/games/private/$person" "$stage/$person"
  fi
done
# Preserve every other entry, including dotfiles and unknown private identities.
mkdir -p "$stage/xsy/archives/legacy-games"
rsync -aHAX --numeric-ids --exclude=/public --exclude=/private/xsy --exclude=/private/shj --exclude=/private/ly \
  -- "$stage/games/" "$stage/xsy/archives/legacy-games/"
rsync -aHAXnc --numeric-ids --itemize-changes --exclude=/public --exclude=/private/xsy --exclude=/private/shj --exclude=/private/ly \
  -- "$stage/games/" "$stage/xsy/archives/legacy-games/" >"$stage/compare"
[[ ! -s "$stage/compare" ]] || die "legacy archive verification failed"

rename_dataset storage/media storage/public/media
rename_dataset storage/archives/deltachat storage/private/xsy/archives/deltachat
rename_dataset storage/archives/cold-backups storage/private/xsy/archives/cold-backups
rename_dataset storage/nixos-archive storage/private/xsy/archives/nixos-archive
stage_mount storage/public/media "$stage/media" rw
# Explicitly approved one-time publication, without following symlinks.
find "$stage/media/." -xdev ! -type l -exec chmod go+rX -- {} +

stage_mount storage/sync "$stage/sync" ro
[[ -s "$stage/sync/state/config.xml" ]] || die "missing existing Syncthing configuration"
copy_tree "$stage/sync/state" /var/lib/storage-syncthing

for dataset in public public/media private private/xsy private/shj private/ly private/xsy/archives private/xsy/archives/deltachat private/xsy/archives/cold-backups private/xsy/archives/nixos-archive sync; do
  zfs set compression=zstd copies=1 redundant_metadata=all "storage/$dataset"
done
zfs set atime=on relatime=on recordsize=1M storage/public
zfs set atime=off recordsize=1M storage/public/media
zfs set atime=off storage/private
zfs set refquota=none recordsize=1M storage/private/xsy
zfs set refquota=500G recordsize=1M storage/private/shj
zfs set refquota=500G recordsize=1M storage/private/ly
zfs set recordsize=128K storage/sync

# Seal private roots BEFORE final mounts expose them, including absent old
# user directories. Ordinary startup tmpfiles remains the declarative owner.
chown root:root "$stage/private" "$stage/public"
chmod 0711 "$stage/private"
chmod 1777 "$stage/public"
chown xsy:users "$stage/xsy" "$stage/xsy/archives"
chown shj:roommates "$stage/shj"
chown ly:roommates "$stage/ly"
chmod 0700 "$stage/xsy" "$stage/xsy/archives" "$stage/shj" "$stage/ly"
chown xsy:roommates "$stage/media"
chmod 0755 "$stage/media"

for ((i=${#mounted[@]}-1; i>=0; i--)); do umount "${mounted[i]}"; done
mounted=()
sync
touch "$state/complete-v1"
chmod 0644 "$state/complete-v1"
sync -f "$state"
# Queue consumers stopped during a live switch; their dependencies still apply.
systemctl --no-block start storage-directories.service samba-smbd.service dufs.service storage-syncthing.service storage-scratch-clean.timer
# Home Manager must not wait for the HDD (it precedes user logins). Restore
# enrolled archive services asynchronously; their native mount check/restart
# handles the short interval until the new mounts and HM config are ready.
if systemctl is-active --quiet "user@$(id -u xsy).service"; then
  systemctl --user --machine=xsy@.host --no-block start deltachat-archive-capture.service deltachat-archive-reader.service
fi
