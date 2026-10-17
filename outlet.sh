#!/bin/sh
# outlet init
# BSD0 licence
set -eu
VERSION=2.1.1
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
  printf 'welcome to \033[%sm%s\033[0m!\n' "$ANSI_COLOR" "$NAME"
elif [ -f /usr/lib/os-release ]; then
  . /usr/lib/os-release
  printf 'welcome to \033[%sm%s\033[0m!\n' "$ANSI_COLOR" "$NAME"
fi

# basic filesystems
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

# "extract" built in utils
# this assumes that you are calling a symlink to this file, as a busybox, which you should be.
# this program is meant to be with it's own dedicated busybox, under the name outlet so it gets treated like a symlink
# if you do not run it like this, bad things may happen

mkdir -p /run/outlet/busybox
cp "$0" /run/outlet/busybox/busybox
/run/outlet/busybox/busybox --install /run/outlet/busybox
PATH="/run/outlet/busybox/:$PATH" # add priority; as not exported should not apply to booted system

# tmpfiles-style runtime dirs and files
mkdir -p /run/lock /run/user /run/faillock /var/log /var/cache /var/lib /var/spool /var/tmp
chmod 1777 /tmp /var/tmp
[ -e /var/run ] || ln -s ../run /var/run
[ -e /var/lock ] || ln -s ../run/lock /var/lock
[ -e /etc/mtab ] || ln -s ../proc/self/mounts /etc/mtab
for f in /run/utmp /var/log/wtmp /var/log/lastlog; do
  [ -e "$f" ] || : > "$f"
  chgrp utmp "$f" 2>/dev/null || chgrp 43 "$f" || : # utmp is gid 43 on arch
  chmod 664 "$f"
done

# hotplug n drivers
if [ -e /proc/sys/kernel/hotplug ]; then
  echo /run/outlet/busybox/mdev > /proc/sys/kernel/hotplug
  /run/outlet/busybox/mdev -s
else
  /run/outlet/busybox/mdev -s
  /run/outlet/busybox/mdev -d
fi
if [ -d /lib/modules/"$(uname -r)" ]; then
  sh -c "find /sys -name modalias -exec cat {} + | xargs modprobe -ba 2>/dev/null"||: # this gets rid of the priority path
fi

# networking!
hostname -F /etc/hostname 2>/dev/null||:
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
cat > /run/outlet/udhcpc.script <<'EOF'
#!/bin/sh
case $1 in
  deconfig) ip addr flush dev "$interface" ;;
  bound|renew)
    ip addr flush dev "$interface"
    ip addr add "$ip/$mask" dev "$interface"
    [ -n "$router" ] && ip route add default via "${router%% *}" dev "$interface"
    for d in $dns; do echo "nameserver $d"; done > /etc/resolv.conf
    ;;
esac
EOF
chmod +x /run/outlet/udhcpc.script
[ -n "$n" ] && ( out=$(udhcpc -i "$n" -b -s /run/outlet/udhcpc.script 2>&1) || { echo "$out"; } )

hwclock -s||:

# services

if [ -d /etc/outlet.services.d/ ]; then
  for i in /etc/outlet.services.d/*.sh; do
    [ -e "$i" ] || continue
    sh "$i" &
    echo "started $(basename "${i%.*}")"
  done
fi

# focket: startserv
mkfifo /run/outlet/startserv
(
  exec 3<>/run/outlet/startserv
  while read -r svc <&3; do
    case $svc in ''|*/*) continue ;; esac
    sh "/etc/outlet.services.d/$svc" 3<&- &
  done
) &

# focket: run
mkfifo /run/outlet/run
(
  exec 3<>/run/outlet/run
  while read -r command <&3; do
    sh -c "$command" 3<&- &
  done
) &


PATH=${PATH#*:} # get rid of that override
GETTY=/run/outlet/busybox/getty
for g in getty agetty; do
  command -v "$g" >/dev/null 2>&1 && { GETTY=$g; break; }
done

# gettys: every console= from the kernel command line, then tty1 to tty6
spawned=" "
spawn_getty() {
  [ -c "/dev/$1" ] || return 0
  case $spawned in *" $1 "*) return 0 ;; esac
  spawned="$spawned$1 "
  while true; do
    case $GETTY in
      *agetty)
        case $1 in
          tty[0-9]*) $GETTY --noreset --noclear "$1" ;;
          *) $GETTY --noreset --noclear --keep-baud 115200,57600,38400,9600 "$1" ;;
        esac ;;
      *) $GETTY -L "$2" "$1" ;;
    esac || :
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
# focket: getty
mkfifo /run/outlet/getty
(
  exec 3<>/run/outlet/getty
  while read -r tty baud <&3; do
    case $tty in ''|*/*) continue ;; esac
    case $baud in ''|*[!0-9]*) baud=0 ;; esac
    spawn_getty "$tty" "$baud" 3<&-
  done
) &
while true; do
  wait || :
  sleep 1
done
