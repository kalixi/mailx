/*
 * Nail - a mail user agent derived from Berkeley Mail.
 *
 * Copyright (c) 2000-2002 Gunnar Ritter, Freiburg i. Br., Germany.
 */
/*
 * Copyright (c) 1980, 1993
 *	The Regents of the University of California.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. All advertising materials mentioning features or use of this software
 *    must display the following acknowledgement:
 *	This product includes software developed by the University of
 *	California, Berkeley and its contributors.
 * 4. Neither the name of the University nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *	Sccsid @(#)def.h	2.19 (gritter) 11/1/02
 */

/*
 * Mail -- a mail program
 *
 * Author: Kurt Shoens (UCB) March 25, 1978
 */

#include "config.h"

#ifndef	FD_CLOEXEC
#define	FD_CLOEXEC	1
#endif

#define	APPEND				/* New mail goes to end of mailbox */

#define	ESCAPE		'~'		/* Default escape for sending */
#ifndef	MAXPATHLEN
#ifdef	PATH_MAX
#define	MAXPATHLEN	PATH_MAX
#else
#define	MAXPATHLEN	1024
#endif
#endif
#ifndef	PATHSIZE
#define	PATHSIZE	MAXPATHLEN	/* Size of pathnames throughout */
#endif
#define	HSHSIZE		59		/* Hash size for aliases and vars */
#define	LINESIZE	2560		/* max readable line width */
#define	STRINGSIZE	((unsigned) 128)/* Dynamic allocation units */
#define	MAXARGC		1024		/* Maximum list of raw strings */
#define	MAXEXP		25		/* Maximum expansion of aliases */

#define	equal(a, b)	(strcmp(a,b)==0)/* A nice function to string compare */

#ifndef	__P
#ifdef	__STDC__
#define	__P(a)	a
#else
#define	__P(a)	()
#endif
#endif

#ifdef	HAVE_CATGETS
#define	CATSET	1
#else	/* !HAVE_CATGETS */
#define	catgets(a, b, c, d)	(d)
#endif	/* !HAVE_CATGETS */

typedef RETSIGTYPE (*sighandler_type) __P((int));

enum okay {
	STOP = 0,
	OKAY = 1
};

enum mimeenc {
	MIME_NONE,			/* message is not in MIME format */
	MIME_BIN,			/* message is in binary encoding */
	MIME_8B,			/* message is in 8bit encoding */
	MIME_7B,			/* message is in 7bit encoding */
	MIME_QP,			/* message is quoted-printable */
	MIME_B64			/* message is in base64 encoding */
};

enum conversion {
	CONV_NONE,			/* no conversion */
	CONV_7BIT,			/* no conversion, is 7bit */
	CONV_TODISP,			/* convert in displayable form */
	CONV_TOFILE,			/* convert for saving to a file */
	CONV_QUOTE,			/* first part body only */
	CONV_FROMQP,			/* convert from quoted-printable */
	CONV_TOQP,			/* convert to quoted-printable */
	CONV_FROMB64,			/* convert from base64 */
	CONV_FROMB64_T,			/* convert from base64/text */
	CONV_TOB64,			/* convert to base64 */
	CONV_FROMHDR,			/* convert from RFC1522 format */
	CONV_TOHDR,			/* convert to RFC1522 format */
	CONV_TOHDR_A			/* convert addresses for header */
};

enum mimecontent {
	MIME_UNKNOWN,			/* unknown content */
	MIME_SUBHDR,			/* inside a multipart subheader */
	MIME_822,			/* message/rfc822 content */
	MIME_MESSAGE,			/* message/ content */
	MIME_TEXT,			/* text/ content */
	MIME_MULTI,			/* multipart/ content */
	MIME_DISCARD			/* content is discarded */
};

enum mimeclean {
	MIME_CLEAN	= 000,		/* plain RFC 2822 message */
	MIME_HIGHBIT	= 001,		/* characters >= 0200 */
	MIME_LONGLINES	= 002,		/* has lines too long for RFC 2822 */
	MIME_CTRLCHAR	= 004,		/* contains control characters */
	MIME_HASNUL	= 010		/* contains \0 characters */
};

enum tdflags {
	TD_NONE	= 0,		/* no display conversion */
	TD_ISPR	= 01,		/* use isprint() checks */
	TD_ICONV= 02		/* use iconv() */
};

struct str {
	char *s;			/* the string's content */
	size_t l;			/* the stings's length */
};

enum protocol {
	PROTO_FILE,			/* refers to a local file */
	PROTO_POP3,			/* is a pop3 server string */
	PROTO_UNKNOWN			/* unknown protocol */
};

struct mailbox {
	int mb_sock;			/* socket file descriptor */
	char *mb_ptr;			/* read pointer to mb_buf */
	int mb_sz;			/* size of last read in mb_buf */
	enum {
		MB_NONE = 00,		/* no reply expected */
		MB_COMD = 01,		/* command reply expected */
		MB_MULT = 02		/* multiline reply expected */
	} mb_active;
	char mb_buf[LINESIZE+1];	/* read buffer */
	FILE *mb_itf;			/* temp file with messages, read open */
	FILE *mb_otf;			/* same, write open */
	enum {
		MB_VOID,		/* no type (e. g. connection failed) */
		MB_FILE,		/* local file */
		MB_POP3			/* POP3 mailbox */
	} mb_type;			/* type of mailbox */
	enum {
		MB_DELE = 01,		/* may delete messages in mailbox */
		MB_EDIT = 02		/* may edit messages in mailbox */
	} mb_perm;
#ifdef	USE_SSL
	void *mb_ssl;			/* SSL object */
	void *mb_ctx;			/* SSL context object */
#endif	/* USE_SSL */
};

enum needspec {
	NEED_HEADER,			/* need the header of a message */
	NEED_BODY			/* need header and body of a message */
};

enum havespec {
	HAVE_NOTHING = 0,		/* nothing downloaded yet */
	HAVE_HEADER = 01,		/* header is downloaded */
	HAVE_BODY = 02			/* entire message is downloaded */
};

/*
 * flag bits.
 */
enum mflag {
	MUSED		= (1<<0),	/* entry is used, but this bit isn't */
	MDELETED	= (1<<1),	/* entry has been deleted */
	MSAVED		= (1<<2),	/* entry has been saved */
	MTOUCH		= (1<<3),	/* entry has been noticed */
	MPRESERVE	= (1<<4),	/* keep entry in sys mailbox */
	MMARK		= (1<<5),	/* message is marked! */
	MODIFY		= (1<<6),	/* message has been modified */
	MNEW		= (1<<7),	/* message has never been seen */
	MREAD		= (1<<8),	/* message has been read sometime. */
	MSTATUS		= (1<<9),	/* message status has changed */
	MBOX		= (1<<10),	/* Send this to mbox, regardless */
	MNOFROM		= (1<<11)	/* no From line */
};

struct message {
	enum mflag	m_flag;		/* flags */
	time_t	m_time;			/* time in the 'Date:' field */
	int	m_block;		/* block number of this message */
	size_t	m_offset;		/* offset in block of message */
	size_t	m_size;			/* Bytes in the message */
	size_t	m_xsize;		/* Bytes in the full message */
	int	m_lines;		/* Lines in the message */
	int	m_xlines;		/* Lines in the full message */
	enum havespec	m_have;		/* downloaded parts of the message */
};

/*
 * Given a file address, determine the block number it represents.
 */
#define nail_blockof(off)		((int) ((off) / 4096))
#define nail_offsetof(off)		((int) ((off) % 4096))
#define nail_positionof(block, offset)	((off_t)(block) * 4096 + (offset))

/*
 * Argument types.
 */
enum argtype {
	MSGLIST	= 0,		/* Message list type */
	STRLIST	= 1,		/* A pure string */
	RAWLIST	= 2,		/* Shell string list */
	NOLIST	= 3,		/* Just plain 0 */
	NDMLIST	= 4,		/* Message list, no defaults */
	P	= 040,		/* Autoprint dot after command */
	I	= 0100,		/* Interactive command bit */
	M	= 0200,		/* Legal from send mode bit */
	W	= 0400,		/* Illegal when read only bit */
	F	= 01000,	/* Is a conditional command */
	T	= 02000,	/* Is a transparent command */
	R	= 04000,	/* Cannot be called from collect */
	A	= 010000	/* Needs an active mailbox */
};

/*
 * Oft-used mask values
 */

#define	MMNORM		(MDELETED|MSAVED)/* Look at both save and delete bits */
#define	MMNDEL		MDELETED	/* Look only at deleted bit */

/*
 * Format of the command description table.
 * The actual table is declared and initialized
 * in lex.c
 */
struct cmd {
	char	*c_name;		/* Name of command */
	int	(*c_func) __P((void *));/* Implementor of the command */
	enum argtype	c_argtype;	/* Type of arglist (see below) */
	short	c_msgflag;		/* Required flags of messages */
	short	c_msgmask;		/* Relevant flags of messages */
};

/* Yechh, can't initialize unions */

#define	c_minargs c_msgflag		/* Minimum argcount for RAWLIST */
#define	c_maxargs c_msgmask		/* Max argcount for RAWLIST */

/*
 * Structure used to return a break down of a head
 * line (hats off to Bill Joy!)
 */

struct headline {
	char	*l_from;	/* The name of the sender */
	char	*l_tty;		/* His tty string (if any) */
	char	*l_date;	/* The entire date string */
};

enum gfield {
	GTO	= 1,		/* Grab To: line */
	GSUBJECT= 2,		/* Likewise, Subject: line */
	GCC	= 4,		/* And the Cc: line */
	GBCC	= 8,		/* And also the Bcc: line */

	GNL	= 16,		/* Print blank line after */
	GDEL	= 32,		/* Entity removed from list */
	GCOMMA	= 64,		/* detract puts in commas */
	GUA	= 128,		/* User-Agent field */
	GMIME	= 256,		/* MIME 1.0 fields */
	GMSGID	= 512,		/* a Message-ID */
	/*	  1024 */	/* unused */
	GIDENT	= 2048,		/* From:, Reply-To: and Organization header */
	GREF	= 4096,		/* References: header */
	GDATE	= 8192		/* Date: header */
};

#define	GMASK	(GTO|GSUBJECT|GCC|GBCC)	/* Mask of places from whence */

/*
 * Structure used to pass about the current
 * state of the user-typed message header.
 */

struct header {
	struct name *h_to;		/* Dynamic "To:" string */
	char *h_subject;		/* Subject string */
	struct name *h_cc;		/* Carbon copies string */
	struct name *h_bcc;		/* Blind carbon copies */
	struct name *h_ref;		/* References */
	struct name *h_smopts;		/* Sendmail options */
	struct attachment *h_attach;	/* MIME attachments */
};

/*
 * Structure of namelist nodes used in processing
 * the recipients of mail and aliases and all that
 * kind of stuff.
 */

struct name {
	struct	name *n_flink;		/* Forward link in list. */
	struct	name *n_blink;		/* Backward list link */
	short	n_type;			/* From which list it came */
	char	*n_name;		/* This fella's name */
};

/*
 * Structure of a MIME attachment.
 */

struct attachment {
	struct attachment *a_flink;	/* Forward link in list. */
	struct attachment *a_blink;	/* Backward list link */
	char	*a_name;		/* file name */
	char	*a_content_type;	/* content type */
	char	*a_content_disposition;	/* content disposition */
	char	*a_content_id;		/* content id */
	char	*a_content_description;	/* content description */
};

/*
 * Structure of a variable node.  All variables are
 * kept on a singly-linked list of these, rooted by
 * "variables"
 */

struct var {
	struct	var *v_link;		/* Forward link to next variable */
	char	*v_name;		/* The variable's name */
	char	*v_value;		/* And it's current value */
};

struct group {
	struct	group *ge_link;		/* Next person in this group */
	char	*ge_name;		/* This person's user name */
};

struct grouphead {
	struct	grouphead *g_link;	/* Next grouphead in list */
	char	*g_name;		/* Name of this group */
	struct	group *g_list;		/* Users in group. */
};

#define	NIL	((struct name *) 0)	/* The nil pointer for namelists */
#define	NONE	((struct cmd *) 0)	/* The nil pointer to command tab */
#define	NOVAR	((struct var *) 0)	/* The nil pointer to variables */
#define	NOGRP	((struct grouphead *) 0)/* The nil grouphead pointer */
#define	NOGE	((struct group *) 0)	/* The nil group pointer */

/*
 * Structure of the hash table of ignored header fields
 */
struct ignoretab {
	int i_count;			/* Number of entries */
	struct ignore {
		struct ignore *i_link;	/* Next ignored field in bucket */
		char *i_field;		/* This ignored field */
	} *i_head[HSHSIZE];
};

/*
 * Token values returned by the scanner used for argument lists.
 * Also, sizes of scanner-related things.
 */
enum ltoken {
	TEOL	= 0,			/* End of the command line */
	TNUMBER	= 1,			/* A message number */
	TDASH	= 2,			/* A simple dash */
	TSTRING	= 3,			/* A string (possibly containing -) */
	TDOT	= 4,			/* A "." */
	TUP	= 5,			/* An "^" */
	TDOLLAR	= 6,			/* A "$" */
	TSTAR	= 7,			/* A "*" */
	TOPEN	= 8,			/* An '(' */
	TCLOSE	= 9,			/* A ')' */
	TPLUS	= 10,			/* A '+' */
	TERROR	= 11,			/* A lexical error */
	TCOMMA	= 12,			/* A ',' */
	TSEMI	= 13			/* A ';' */
};

#define	REGDEP	2			/* Maximum regret depth. */
#define	STRINGLEN	1024		/* Maximum length of string token */

/*
 * Constants for conditional commands.  These describe whether
 * we should be executing stuff or not.
 */
enum condition {
	CANY	= 0,	/* Execute in send or receive mode */
	CRCV	= 1,	/* Execute in receive mode only */
	CSEND	= 2,	/* Execute in send mode only */
	CTERM	= 3,	/* Execute only if stdin is a tty */
	CNONTERM= 4	/* Execute only if stdin not tty */
};

/*
 * For the 'shortcut' and 'unshortcut' functionality.
 */
struct shortcut {
	struct shortcut	*sh_next;	/* next shortcut in list */
	char	*sh_short;		/* shortcut string */
	char	*sh_long;		/* expanded form */
};

/*
 * Kludges to handle the change from setexit / reset to setjmp / longjmp
 */

#define	setexit()	sigsetjmp(srbuf, 1)
#define	reset(x)	siglongjmp(srbuf, x)

/*
 * Locale-independent character classes.
 */
enum {
	C_CNTRL	= 0001,
	C_BLANK	= 0002,
	C_SPACE	= 0004,
	C_PUNCT	= 0010,
	C_DIGIT	= 0020,
	C_UPPER	= 0040,
	C_LOWER	= 0100,
	C_WHITE = 0200
};

extern const unsigned char	class_char[];

#define	asciichar(c) ((unsigned)(c) <= 0177)
#define	alnumchar(c) (asciichar(c)&&(class_char[c]&(C_DIGIT|C_UPPER|C_LOWER)))
#define	alphachar(c) (asciichar(c)&&(class_char[c]&(C_UPPER|C_LOWER)))
#define	blankchar(c) (asciichar(c)&&(class_char[c]&(C_BLANK)))
#define	cntrlchar(c) (asciichar(c)&&(class_char[c]&(C_CNTRL)))
#define	digitchar(c) (asciichar(c)&&(class_char[c]&(C_DIGIT)))
#define	lowerchar(c) (asciichar(c)&&(class_char[c]&(C_LOWER)))
#define	punctchar(c) (asciichar(c)&&(class_char[c]&(C_PUNCT)))
#define	spacechar(c) (asciichar(c)&&(class_char[c]&(C_BLANK|C_SPACE|C_WHITE)))
#define	upperchar(c) (asciichar(c)&&(class_char[c]&(C_UPPER)))
#define	whitechar(c) (asciichar(c)&&(class_char[c]&(C_BLANK|C_WHITE)))

#define	upperconv(c) (lowerchar(c) ? (c)-'a'+'A' : (c))
#define	lowerconv(c) (upperchar(c) ? (c)-'A'+'a' : (c))

/*	RFC 822, 3.2.	*/
#define	fieldnamechar(c) (asciichar(c)&&(c)>040&&(c)!=0177&&(c)!=':')

/*
 * Truncate a file to the last character written. This is
 * useful just before closing an old file that was opened
 * for read/write.
 */
#define trunc(stream) {							\
	(void)fflush(stream); 						\
	(void)ftruncate(fileno(stream), (off_t)ftell(stream));		\
}

/*
 * Use either alloca() or smalloc()/free(). ac_alloc can be used to
 * allocate space within a function. ac_free must be called when the
 * space is no longer needed, but expands to nothing if using alloca().
 */
#ifdef	HAVE_ALLOCA
#define	ac_alloc(n)	alloca(n)
#define	ac_free(n)
#else	/* !HAVE_ALLOCA */
#define	ac_alloc(n)	smalloc(n)
#define	ac_free(n)	free(n)
#endif	/* !HAVE_ALLOCA */

/*
 * glibc uses the slow thread-safe getc() even if _REENTRANT is not
 * defined. Work around it.
 */
#if defined (HAVE_GETC_UNLOCKED) && defined (__GLIBC__)
#define	sgetc(c)	getc_unlocked(c)
#else	/* !HAVE_GETC_UNLOCKED */
#define	sgetc(c)	getc(c)
#endif	/* !HAVE_GETC_UNLOCKED */

#if defined (HAVE_PUTC_UNLOCKED) && defined (__GLIBC__)
#define	sputc(c, f)	putc_unlocked(c, f)
#else	/* !HAVE_PUTC_UNLOCKED */
#define	sputc(c, f)	putc(c, f)
#endif	/* !HAVE_PUTC_UNLOCKED */
