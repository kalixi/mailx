#
# Makefile for s-nail
#

#
# See the file INSTALL if you need help.
#

PREFIX		= /usr/local
BINDIR		= $(PREFIX)/bin
MANDIR		= $(PREFIX)/man
SYSCONFDIR	= $(PREFIX)/etc
DESTDIR		=

MAILRC		= $(SYSCONFDIR)/s-nail.rc
MAILSPOOL	= /var/mail
SENDMAIL	= /usr/sbin/sendmail
INSTALL		= /usr/bin/install


# Define compiler, preprocessor, and linker flags here.
# Note that some Linux/glibc versions need -D_GNU_SOURCE in CPPFLAGS, or
# wcwidth() will not be available and multibyte characters will not be
# displayed correctly.
#CFLAGS		=
#CPPFLAGS	=
#LDFLAGS		=
#WARN		= -Wall -Wno-parentheses -Werror

# Some RedHat versions need INCLUDES = -I/usr/kerberos/include to compile
# with OpenSSL, or to compile with GSSAPI authentication included. In the
# latter case, they also need LDFLAGS = -L/usr/kerberos/lib.
#INCLUDES	= -I/usr/kerberos/include
#LDFLAGS	= -L/usr/kerberos/lib

# If you want to include SSL support using Mozilla NSS instead of OpenSSL,
# set something like the following paths. (You might also need to set LDFLAGS).
#MOZINC		= /usr/include/mozilla-seamonkey-1.0.5
#INCLUDES	= -I$(MOZINC)/nspr -I$(MOZINC)/nss
# These paths are suitable to activate NSS support on Solaris, provided that
# the packages SUNWmoznss, SUNWmoznss-devel, SUNWmoznspr, and SUNWmoznspr-devel
# are installed.
#MOZINC		= /usr/sfw/include/mozilla
#MOZLIB		= /usr/sfw/lib/mozilla
#INCLUDES	= -I$(MOZINC)/nspr -I$(MOZINC)/nss
#LDFLAGS	= -L$(MOZLIB) -R$(MOZLIB)

SHELL		= /bin/sh

# If you know that the IPv6 functions work on your machine, you can enable
# them here.
#IPv6		= -DHAVE_IPv6_FUNCS

#
# Binaries are stripped with this command after installation.
#
STRIP = strip

###########################################################################
###########################################################################
# You should really know what you do if you change anything below this line
###########################################################################
###########################################################################

FEATURES	= -DMAILRC='"$(MAILRC)"' -DMAILSPOOL='"$(MAILSPOOL)"' \
			-DSENDMAIL='"$(SENDMAIL)"' $(IPv6)

OBJ = aux.o base64.o cache.o cmd1.o cmd2.o cmd3.o cmdtab.o collect.o \
	dotlock.o edit.o fio.o getname.o getopt.o head.o hmac.o \
	imap.o imap_search.o junk.o lex.o list.o lzw.o \
	macro.o maildir.o main.o md5.o mime.o names.o nss.o \
	openssl.o pop3.o popen.o quit.o \
	send.o sendout.o smtp.o ssl.o strings.o temp.o thread.o tty.o \
	v7.local.o vars.o \
	version.o

.SUFFIXES: .o .c .x
.c.o:
	$(CC) $(CFLAGS) $(CPPFLAGS) $(FEATURES) $(INCLUDES) $(WARN) -c $<

.c.x:
	$(CC) $(CFLAGS) $(CPPFLAGS) $(FEATURES) $(INCLUDES) $(WARN) -E $< >$@

.c:
	$(CC) $(CFLAGS) $(CPPFLAGS) $(FEATURES) $(INCLUDES) $(WARN) \
		$(LDFLAGS) $< `grep '^[^#]' LIBS` $(LIBS) -o $@

all: s-nail

s-nail: $(OBJ)
	$(CC) $(LDFLAGS) $(OBJ) `grep '^[^#]' LIBS` $(LIBS) -o s-nail

$(OBJ): config.h def.h extern.h glob.h rcv.h
imap.o: imap_gssapi.c
md5.o imap.o hmac.o smtp.o aux.o pop3.o junk.o: md5.h
nss.o: nsserr.c
version.o: version.h

#version.h: $(OBJ:.o=.c)
version.h:
	eval VERSION=`git describe --dirty --tags`; \
	echo > version.h \
		"#define V \"<12.5 7/5/10; $${VERSION:-S-nail spooned}>\""

config.h: makeconfig
	$(SHELL) ./makeconfig

install: all
	test -d $(DESTDIR)$(BINDIR) || mkdir -p $(DESTDIR)$(BINDIR)
	$(INSTALL) -c s-nail $(DESTDIR)$(BINDIR)/s-nail
	$(STRIP) $(DESTDIR)$(BINDIR)/s-nail
	test -d $(DESTDIR)$(MANDIR)/man1 || mkdir -p $(DESTDIR)$(MANDIR)/man1
	$(INSTALL) -c -m 644 mailx.1 $(DESTDIR)$(MANDIR)/man1/s-nail.1
	test -d $(DESTDIR)$(SYSCONFDIR) || mkdir -p $(DESTDIR)$(SYSCONFDIR)
	test -f $(DESTDIR)$(MAILRC) || \
		$(INSTALL) -c -m 644 nail.rc $(DESTDIR)$(MAILRC)

clean:
	rm -f $(OBJ) s-nail *~ core log

distclean: clean
	rm -f config.h config.log LIBS

