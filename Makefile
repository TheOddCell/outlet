.PHONY: clean
# etc files are only written if missing, so local edits to rootfs/etc survive
put = [ -e rootfs/etc/$(1) ] || printf '$(2)' > rootfs/etc/$(1)
define PROFILE
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PS1='\u@\h:\w\$$ '
endef
export PROFILE
outlet: busybox outlet.sh
	cp outlet.sh busybox/embed/outlet
	cp outlet.sh busybox/embed/init
	make -C busybox -j$$(nproc)
	cp busybox/busybox outlet
busybox: busybox-1.38.0.tar.bz2 busybox_config
	tar -xvjf busybox-1.38.0.tar.bz2
	mv busybox-1.38.0 busybox
	cp busybox_config busybox/.config
	yes ''|make -C busybox oldconfig
	mkdir -p busybox/embed
	touch busybox
busybox-1.38.0.tar.bz2:
	curl -fLO https://busybox.net/downloads/busybox-1.38.0.tar.bz2
rootfs: outlet
	mkdir -p rootfs/bin rootfs/sbin rootfs/usr/bin rootfs/usr/sbin rootfs/etc/outlet.services.d rootfs/dev rootfs/proc rootfs/sys rootfs/run rootfs/tmp rootfs/var/log rootfs/home rootfs/lib rootfs/root
	chmod 1777 rootfs/tmp
	chmod 700 rootfs/root
	cp outlet rootfs/bin/busybox
	for a in $$(rootfs/bin/busybox --list); do [ "$$a" = busybox ] || ln -sf busybox rootfs/bin/$$a; done
	$(call put,group,root:x:0:\ntty:x:5:\ndisk:x:6:\nwheel:x:10:\nnobody:x:65534:\n)
	$(call put,gshadow,root:::\nwheel:::\n)
	$(call put,hostname,outlet\n)
	$(call put,hosts,127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\toutlet\n)
	$(call put,issue,Welcome to outlet\n\n)
	$(call put,nsswitch.conf,hosts: files dns\n)
	$(call put,os-release,NAME="outlet"\nID=outlet\nPRETTY_NAME="outlet"\nVERSION_ID=1.0.0\nANSI_COLOR="1;33"\n)
	$(call put,passwd,root:x:0:0:root:/root:/bin/sh\nnobody:x:65534:65534:nobody:/:/bin/false\n)
	[ -e rootfs/etc/profile ] || printf '%s\n' "$$PROFILE" > rootfs/etc/profile
	$(call put,protocols,ip\t0\tIP\nicmp\t1\tICMP\ntcp\t6\tTCP\nudp\t17\tUDP\n)
	$(call put,resolv.conf,nameserver 1.1.1.1\n)
	$(call put,shadow,root:::0:99999:7:::\nnobody:!::0:99999:7:::\n)
	$(call put,shells,/bin/sh\n)
	chmod 600 rootfs/etc/shadow rootfs/etc/gshadow
clean:
	rm -rf busybox busybox-1.38.0.tar.bz2 outlet busybox-1.38.0 rootfs
