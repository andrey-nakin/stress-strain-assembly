APP_VERSION=1.0.1
LINUX_RUNTIME=./tclkit-8.5.8-linux-ix86
WINDOWS_RUNTIME=tclkit-8.5.8-win32.upx.exe

all:	dist

manual:
	m4 --define=APP_VERSION=$(APP_VERSION) doc/title.tex.m4 > doc/title.tex
#	cd doc; pdflatex manual.tex
	cd doc; pdflatex release-notes.tex

kit:
	cd starkit; $(LINUX_RUNTIME) sdx.kit wrap stress-strain-assembly.kit

exe:
	cd starkit; $(LINUX_RUNTIME) sdx.kit wrap stress-strain-assembly.exe -runtime $(WINDOWS_RUNTIME)

dist: exe manual
	rm -f stress-strain-assembly-$(APP_VERSION).zip
	zip -j stress-strain-assembly-$(APP_VERSION).zip starkit/stress-strain-assembly.exe
	zip -j stress-strain-assembly-$(APP_VERSION).zip doc/release-notes.pdf

