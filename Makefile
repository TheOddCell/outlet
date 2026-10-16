.PHONY: clean
outlet: busybox
	cp outlet.sh busybox/embed/outlet
	make -C busybox -j$$(nproc)
	cp busybox/busybox outlet
busybox: busybox-1.38.0.tar.bz2
	tar -xvjf busybox-1.38.0.tar.bz2
	mv busybox-1.38.0 busybox
	cp busybox_config busybox/.config
	yes ''|make -C busybox oldconfig
	mkdir -p busybox/embed
	touch busybox
busybox-1.38.0.tar.bz2:
	curl -fLO https://busybox.net/downloads/busybox-1.38.0.tar.bz2
clean:
	rm -rf busybox busybox-1.38.0.tar.bz2 outlet busybox-1.38.0
