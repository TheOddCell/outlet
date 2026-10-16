#!/bin/sh
# outlet init
# BSD0 licence
set -eu
VERSION=1.0.0
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
trap shutdown KILL
echo 8 > /proc/sys/kernel/printk
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
mount -t proc     proc     /proc
mount -t sysfs    sysfs    /sys
mount -t devtmpfs devtmpfs /dev
mkdir -p /dev/pts /dev/shm /run /tmp
mount -t devpts   devpts   /dev/pts
mount -t tmpfs    tmpfs    /dev/shm
mount -t tmpfs    tmpfs    /run
mount -t tmpfs    tmpfs    /tmp

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

mkdir /run/outlet/busybox
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

find /sys -name modalias -exec cat {} + | xargs modprobe -ba
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
  for i in "$(ls /etc/outlet.services.d/*.sh 2>/dev/null)"; do
    sh "$i" &
    echo "started $(basename "${i%.*}")"
  done
fi

mkfifo /run/outlet/startserv
sh <(cat <<'EOF'
while true; do
  sh "/etc/outlet.services.d/$(cat /run/outlet/startserv)"&
fi
EOF
)
while true; do
  sh getty /dev/tty1
fi
