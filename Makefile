APP_VERSION=1.1.1

LINUX_RUNTIME=./tclkit-8.5.17-rhel5-x86_64
WINDOWS32_RUNTIME=tclkit-8.5.8-win32.upx.exe
WINDOWS64_RUNTIME=tclkit-8.5.8-win32-x86_64.exe

all:	dist

manual:
	m4 --define=APP_VERSION=$(APP_VERSION) doc/title.tex.m4 > doc/title.tex
	cd doc; pdflatex manual.tex
	cd doc; pdflatex release-notes.tex

kit:
	cd starkit; $(LINUX_RUNTIME) sdx.kit wrap stress-strain-assembly.kit

exe:
	cd starkit; $(LINUX_RUNTIME) sdx.kit wrap stress-strain-assembly.exe -runtime $(WINDOWS32_RUNTIME); mkdir win32; mv -f stress-strain-assembly.exe win32/
	cd starkit; $(LINUX_RUNTIME) sdx.kit wrap stress-strain-assembly.exe -runtime $(WINDOWS64_RUNTIME); mkdir win64; mv -f stress-strain-assembly.exe win64/

dist: kit exe manual
	rm -f stress-strain-assembly-$(APP_VERSION).zip
	zip -j stress-strain-assembly-$(APP_VERSION).zip starkit/stress-strain-assembly.kit
	zip -j stress-strain-assembly-$(APP_VERSION).zip doc/release-notes.pdf
	zip -j stress-strain-assembly-$(APP_VERSION).zip doc/manual.pdf
	rm -f stress-strain-assembly-$(APP_VERSION)-win32.zip
	zip -j stress-strain-assembly-$(APP_VERSION)-win32.zip starkit/win32/stress-strain-assembly.exe
	zip -j stress-strain-assembly-$(APP_VERSION)-win32.zip doc/release-notes.pdf
	zip -j stress-strain-assembly-$(APP_VERSION)-win32.zip doc/manual.pdf
	rm -f stress-strain-assembly-$(APP_VERSION)-win64.zip
	zip -j stress-strain-assembly-$(APP_VERSION)-win64.zip starkit/win64/stress-strain-assembly.exe
	zip -j stress-strain-assembly-$(APP_VERSION)-win64.zip doc/release-notes.pdf
	zip -j stress-strain-assembly-$(APP_VERSION)-win64.zip doc/manual.pdf

