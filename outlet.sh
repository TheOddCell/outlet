#!/bin/sh
# outlet init
# BSD0 licence
set -eu
VERSION=2.0.0
trap 'echo Something went wrong, dropping to an emergency shell.;echo Good luck.;exec sh' EXIT
byeprep() {
  printf '%s\n' 1 > /proc/sys/kernel/sysrq || return 1
  printf '%s' e > /proc/sysrq-trigger || return 1
  sleep 2
  printf '%s' i > /proc/sysrq-trigger || return 1
  sleep 1
  sync
  printf '%s' s > /proc/sysrq-trigger || return 1
  sleep 1
  printf '%s' u > /proc/sysrq-trigger || return 1
  sleep 1
cat<<EOF
       __
 __-\-\\\\_\-\-
 \_\_\ \\\\_  \\
EOF
  echo "bye!"
}
reboot()   { byeprep; printf '%s' b > /proc/sysrq-trigger; }
shutdown() { byeprep; printf '%s' o > /proc/sysrq-trigger; }
trap reboot TERM
trap shutdown INT
cat<<EOF
you're __ using
 __-\-\\\\_\-\-
 \_\_\ \\\\_  \\
   init v$VERSION
EOF
if [ -f /etc/os-release ]; then
  . /etc/os-release
  printf 'Welcome to \033[%sm%s\033[0m!\n' "$ANSI_COLOR" "$NAME"
fi

# basic filesystems
echo "creating and mounting basic filesystems"
mkdir -p /proc    /dev     /sys
mnt() { mountpoint -q "$3" || mount -t "$1" "$2" "$3"; }
mnt proc     proc     /proc
mnt sysfs    sysfs    /sys
mnt devtmpfs devtmpfs /dev
mkdir -p /dev/pts /dev/shm /run /tmp
mnt devpts   devpts   /dev/pts
mnt tmpfs    tmpfs    /dev/shm
mnt tmpfs    tmpfs    /run
mnt tmpfs    tmpfs    /tmp

if mountpoint -q /; then
  mount -o remount,rw /
fi
if [ -f /etc/fstab ]; then
  mount -a
fi

hostname -F /etc/hostname

# "extract" built in utils
# this assumes that you are calling a symlink to this file, as a busybox, which you should be.
# this program is meant to be with it's own dedicated busybox, under the name outlet so it gets treated like a symlink
# if you do not run it like this, bad things may happen

mkdir -p /run/outlet/busybox
cp "$0" /run/outlet/busybox/busybox
/run/outlet/busybox/busybox --install /run/outlet/busybox

# hotplug n drivers
if [ -e /proc/sys/kernel/hotplug ]; then
  echo /run/outlet/busybox/mdev > /proc/sys/kernel/hotplug
  /run/outlet/busybox/mdev -s
else
  /run/outlet/busybox/mdev -s
  /run/outlet/busybox/mdev -d
fi
if [ -d /lib/modules ]; then
  find /sys -name modalias -exec cat {} + | xargs modprobe -ba
fi
echo "initialized hardware"

# networking!
ip link set lo up
for d in /sys/class/net/*; do
  [ -e "$d/device" ] && [ ! -d "$d/wireless" ] && ip link set "${d##*/}" up
done
i=0; n=
while [ -z "$n" ] && [ "$i" -lt 50 ]; do
  for d in /sys/class/net/*; do
    [ -e "$d/device" ] && [ ! -d "$d/wireless" ] && [ "$(cat "$d/carrier" 2>/dev/null)" = 1 ] && { n=${d##*/}; break; }
  done
  [ -z "$n" ] && { sleep 0.1; i=$((i+1)); }
done
[ -n "$n" ] && udhcpc -i "$n" -b -q
echo "initialized networking"

hwclock -s || true

# services

if [ -d /etc/outlet.services.d/ ]; then
  for i in /etc/outlet.services.d/*.sh; do
    [ -e "$i" ] || continue
    sh "$i" &
    echo "started $(basename "${i%.*}")"
  done
fi

mkfifo /run/outlet/startserv
(
  exec 3<>/run/outlet/startserv
  while read -r svc <&3; do
    case $svc in ''|*/*) continue ;; esac
    sh "/etc/outlet.services.d/$svc" 3<&- &
  done
) &

# gettys: every console= from the kernel command line, then tty1 to tty6
spawned=" "
spawn_getty() {
  [ -c "/dev/$1" ] || return 0
  case $spawned in *" $1 "*) return 0 ;; esac
  spawned="$spawned$1 "
  while true; do
    getty -L "$2" "$1" || :
    sleep 1
  done &
}
for w in $(cat /proc/cmdline); do
  case $w in
    console=*)
      c=${w#console=}
      t=${c%%,*}
      t=${t#/dev/}
      b=0
      case $c in *,*) b=${c#*,}; b=${b%%[!0-9]*} ;; esac
      [ "$t" = tty0 ] || spawn_getty "$t" "${b:-0}"
      ;;
  esac
done
for n in 1 2 3 4 5 6; do
  spawn_getty "tty$n" 0
done
while true; do
  wait || :
  sleep 1
done
