@BOTTOM@
/* Sccsid: @(#)acconfig.h	2.2 (gritter) 10/21/02 */

/* The C shell's path. */
#ifndef PATH_CSHELL
#undef PATH_CSHELL
#endif

/* Path to `more'. */
#ifndef PATH_MORE
#undef PATH_MORE
#endif

/* Path to `pg'. */
#ifndef PATH_PG
#undef PATH_PG
#endif

/* Path to `ex'. */
#ifndef PATH_EX
#undef PATH_EX
#endif

/* Path to `vi'. */
#ifndef PATH_VI
#undef PATH_VI
#endif

/* Path to `sendmail'. */
#ifndef PATH_SENDMAIL
#undef PATH_SENDMAIL
#endif

/* Path to nail's support files. */
#undef PATH_MASTER_RC

/* The mail spool directory. */
#ifndef PATH_MAILDIR
#undef PATH_MAILDIR
#endif

#ifndef	CATNAME
#undef	CATNAME
#endif

/* The temporary directory. */
#ifndef PATH_TMP
#undef PATH_TMP
#endif

#include <sys/types.h>

#ifdef	HAVE_SYS_PARAM_H
#include <sys/param.h>
#endif

#ifdef	HAVE_SYS_STAT_H
#include <sys/stat.h>
#endif

#ifdef	HAVE_SYS_SOCKET_H
#include <sys/socket.h>
#endif

#ifdef	HAVE_NETDB_H
#include <netdb.h>
#endif

/* Define if you have the Socket API. */
#ifndef	HAVE_SOCKETS
#undef	HAVE_SOCKETS
#endif

#ifdef	HAVE_NETINET_IN_H
#include <netinet/in.h>
#endif

#ifdef	HAVE_ARPA_INET_H
#include <arpa/inet.h>
#endif

/* Define if we need libnsl. */
#ifndef	HAVE_LIBNSL
#undef	HABE_LIBNSL
#endif

/* Define if we need libsocket. */
#ifndef	HAVE_LIBSOCKET
#undef	HABE_LIBSOCKET
#endif

#ifdef	HAVE_SIGNAL_H
#include <signal.h>
#endif

#ifdef	TIME_WITH_SYS_TIME
#include <sys/time.h>
#include <time.h>
#else
#ifdef	HAVE_SYS_TIME_H
#include <sys/time.h>
#else
#include <time.h>
#endif
#endif

#include <termios.h>
#ifdef	HAVE_UNISTD_H
#include <unistd.h>
#endif
#ifdef	HAVE_FCNTL_H
#include <fcntl.h>
#endif
#ifdef	HAVE_LOCALE_H
#include <locale.h>
#endif
#ifdef	HAVE_ICONV_H
#include <iconv.h>
#endif
#ifdef	STDC_HEADERS
#include <stdlib.h>
#include <string.h>
#endif
#include <stdio.h>
#include <ctype.h>
#ifdef	HAVE_WCHAR_H
#include <wchar.h>
#endif
#ifdef	HAVE_WCTYPE_H
#include <wctype.h>
#endif
#ifdef	HAVE_LANGINFO_H
#include <langinfo.h>
#endif
#ifdef	HAVE_NL_TYPES_H
#include <nl_types.h>
#endif
#ifdef	HAVE_ALLOCA_H
#include <alloca.h>
#endif
/* The number of signals in the system. */
#ifndef	NSIG
#undef	NSIG
#endif

/* The maximum number of open files. */
#ifndef NOFILE
#undef	NOFILE
#endif

/* Nail's release date. */
#ifndef	REL_DATE
#undef	REL_DATE
#endif

/* The maximum length of a host name. */
#ifndef MAXHOSTNAMELEN
#undef MAXHOSTNAMELEN
#endif

#ifdef	NEED_OPTIND
extern int	optind;
#endif

#ifdef	NEED_OPTARG
extern char	*optarg;
#endif

#ifndef	USE_SSL
#undef	USE_SSL
#endif
