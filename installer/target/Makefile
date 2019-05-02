all:
	@echo "Specify a target:\nmake rbp1\nmake rbp2\nmake vero2\nmake vero3"

rbp1:
	sudo bash build.sh "rbp1"

rbp2:
	sudo bash build.sh "rbp2"

vero2:
	sudo bash build.sh "vero2"

vero3:
	sudo bash build.sh "vero3"

clean:
	sudo rm -rf buildroot*/ > /dev/null 2>&1
	sudo rm -f filesystem.tar.xz >/dev/null 2>&1

distclean: clean
	sudo rm -f *.img.gz *.img.gz.md5 >/dev/null 2>&1
	sudo rm -rf downloads-buildroot >/dev/null 2>&1
