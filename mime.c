/*@ S-nail - a mail user agent derived from Berkeley Mail.
 *@ MIME support functions.
 *
 * Copyright (c) 2000-2004 Gunnar Ritter, Freiburg i. Br., Germany.
 * Copyright (c) 2012 - 2016 Steffen (Daode) Nurpmeso <steffen@sdaoden.eu>.
 */
/*
 * Copyright (c) 2000
 * Gunnar Ritter.  All rights reserved.
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
 *    This product includes software developed by Gunnar Ritter
 *    and his contributors.
 * 4. Neither the name of Gunnar Ritter nor the names of his contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY GUNNAR RITTER AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL GUNNAR RITTER OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */
#undef n_FILE
#define n_FILE mime

#ifndef HAVE_AMALGAMATION
# include "nail.h"
#endif

static char                   *_cs_iter_base, *_cs_iter;
#ifdef HAVE_ICONV
# define _CS_ITER_GET() ((_cs_iter != NULL) ? _cs_iter : charset_get_8bit())
#else
# define _CS_ITER_GET() ((_cs_iter != NULL) ? _cs_iter : charset_get_lc())
#endif
#define _CS_ITER_STEP() _cs_iter = n_strsep(&_cs_iter_base, ',', TRU1)

/* Is 7-bit enough? */
#ifdef HAVE_ICONV
static bool_t           _has_highbit(char const *s);
static bool_t           _name_highbit(struct name *np);
#endif

/* fwrite(3) while checking for displayability */
static ssize_t          _fwrite_td(struct str const *input, enum tdflags flags,
                           struct str *rest, struct quoteflt *qf);

/* Convert header fields to RFC 1522 format and write to the file fo */
static ssize_t          mime_write_tohdr(struct str *in, FILE *fo);

/* Write len characters of the passed string to the passed file, doing charset
 * and header conversion */
static ssize_t          convhdra(char const *str, size_t len, FILE *fp);

/* Write an address to a header field */
static ssize_t          mime_write_tohdr_a(struct str *in, FILE *f);

/* Append to buf, handling resizing */
static void             _append_str(char **buf, size_t *sz, size_t *pos,
                           char const *str, size_t len);
static void             _append_conv(char **buf, size_t *sz, size_t *pos,
                           char const *str, size_t len);

#ifdef HAVE_ICONV
static bool_t
_has_highbit(char const *s)
{
   bool_t rv = TRU1;
   NYD_ENTER;

   if (s) {
      do
         if ((ui8_t)*s & 0x80)
            goto jleave;
      while (*s++ != '\0');
   }
   rv = FAL0;
jleave:
   NYD_LEAVE;
   return rv;
}

static bool_t
_name_highbit(struct name *np)
{
   bool_t rv = TRU1;
   NYD_ENTER;

   while (np) {
      if (_has_highbit(np->n_name) || _has_highbit(np->n_fullname))
         goto jleave;
      np = np->n_flink;
   }
   rv = FAL0;
jleave:
   NYD_LEAVE;
   return rv;
}
#endif /* HAVE_ICONV */

static sigjmp_buf       __mimefwtd_actjmp; /* TODO someday.. */
static int              __mimefwtd_sig; /* TODO someday.. */
static sighandler_type  __mimefwtd_opipe;
static void
__mimefwtd_onsig(int sig) /* TODO someday, we won't need it no more */
{
   NYD_X; /* Signal handler */
   __mimefwtd_sig = sig;
   siglongjmp(__mimefwtd_actjmp, 1);
}

static ssize_t
_fwrite_td(struct str const *input, enum tdflags flags, struct str *rest,
   struct quoteflt *qf)
{
   /* TODO note: after send/MIME layer rewrite we will have a string pool
    * TODO so that memory allocation count drops down massively; for now,
    * TODO v14.* that is, we pay a lot & heavily depend on the allocator */
   /* TODO well if we get a broken pipe here, and it happens to
    * TODO happen pretty easy when sleeping in a full pipe buffer,
    * TODO then the current codebase performs longjump away;
    * TODO this leaves memory leaks behind ('think up to 3 per,
    * TODO dep. upon alloca availability).  For this to be fixed
    * TODO we either need to get rid of the longjmp()s (tm) or
    * TODO the storage must come from the outside or be tracked
    * TODO in a carrier struct.  Best both.  But storage reuse
    * TODO would be a bigbig win besides */
   /* *input* _may_ point to non-modifyable buffer; but even then it only
    * needs to be dup'ed away if we have to transform the content */
   struct str in, out;
   ssize_t rv;
   NYD_ENTER;
   n_UNUSED(rest);

   in = *input;
   out.s = NULL;
   out.l = 0;

#ifdef HAVE_ICONV
   if ((flags & TD_ICONV) && iconvd != (iconv_t)-1) {
      char *buf = NULL;

      if (rest != NULL && rest->l > 0) {
         in.l = rest->l + input->l;
         in.s = buf = smalloc(in.l +1);
         memcpy(in.s, rest->s, rest->l);
         memcpy(in.s + rest->l, input->s, input->l);
         rest->l = 0;
      }

      if (n_iconv_str(iconvd, n_ICONV_DEFAULT, &out, &in, &in) != 0 &&
            rest != NULL && in.l > 0) {
         n_iconv_reset(iconvd);
         /* Incomplete multibyte at EOF is special */
         if (flags & _TD_EOF) {
            out.s = srealloc(out.s, out.l + 4);
            /* TODO 0xFFFD out.s[out.l++] = '[';*/
            out.s[out.l++] = '?'; /* TODO unicode replacement 0xFFFD !!! */
            /* TODO 0xFFFD out.s[out.l++] = ']';*/
         } else
            n_str_add(rest, &in);
      }
      in = out;
      out.l = 0;
      out.s = NULL;
      flags &= ~_TD_BUFCOPY;

      if (buf != NULL)
         free(buf);
   }
#endif

   if (flags & TD_ISPR)
      makeprint(&in, &out);
   else if (flags & _TD_BUFCOPY)
      n_str_dup(&out, &in);
   else
      out = in;
   if (flags & TD_DELCTRL)
      out.l = delctrl(out.s, out.l);

   __mimefwtd_sig = 0;
   __mimefwtd_opipe = safe_signal(SIGPIPE, &__mimefwtd_onsig);
   if (sigsetjmp(__mimefwtd_actjmp, 1)) {
      rv = 0;
      goto j__sig;
   }

   rv = quoteflt_push(qf, out.s, out.l);

j__sig:
   if (out.s != in.s)
      free(out.s);
   if (in.s != input->s)
      free(in.s);
   safe_signal(SIGPIPE, __mimefwtd_opipe);
   if (__mimefwtd_sig != 0)
      n_raise(__mimefwtd_sig);
   NYD_LEAVE;
   return rv;
}

static ssize_t
mime_write_tohdr(struct str *in, FILE *fo)
{
   /* TODO mime_write_tohdr(): we don't know the name of our header->maxcol..
    * TODO  MIME/send layer rewrite: more available state!!
    * TODO   Because of this we cannot make a difference in between structured
    * TODO   and unstructured headers (RFC 2047, 5. (2))
    * TODO NOT MULTIBYTE SAFE IF AN ENCODED WORD HAS TO BE SPLITTED!
    * TODO  To be better we had to mbtowc_l() (non-std! and no locale!!) and
    * TODO   work char-wise!  ->  S-CText..
    * TODO  The real problem for STD compatibility is however that "in" is
    * TODO   already iconv(3) encoded to the target character set!  We could
    * TODO   also solve it (very expensively!) if we would narrow down to an
    * TODO   encoded word and then iconv(3)+MIME encode in one go, in which
    * TODO   case multibyte errors could be catched! */
   enum {
      /* Maximum line length *//* XXX we are too inflexible and could use
       * XXX MIME_LINELEN unless an RFC 2047 encoding was actually used */
      _MAXCOL  = MIME_LINELEN_RFC2047
   };
   enum {
      _FIRST      = 1<<0,  /* Nothing written yet, start of string */
      _NO_QP      = 1<<1,  /* No quoted-printable allowed */
      _NO_B64     = 1<<2,  /* Ditto, base64 */
      _ENC_LAST   = 1<<3,  /* Last round generated encoded word */
      _SHOULD_BEE = 1<<4,  /* Avoid lines longer than SHOULD via encoding */
      _RND_SHIFT  = 5,
      _RND_MASK   = (1<<_RND_SHIFT) - 1,
      _SPACE      = 1<<(_RND_SHIFT+1),    /* Leading whitespace */
      _8BIT       = 1<<(_RND_SHIFT+2),    /* High bit set */
      _ENCODE     = 1<<(_RND_SHIFT+3),    /* Need encoding */
      _ENC_B64    = 1<<(_RND_SHIFT+4),    /* - let it be base64 */
      _OVERLONG   = 1<<(_RND_SHIFT+5)     /* Temporarily rised limit */
   } flags = _FIRST;

   struct str cout, cin;
   char const *cset7, *cset8, *wbot, *upper, *wend, *wcur;
   ui32_t cset7_len, cset8_len;
   size_t col, i, j;
   ssize_t sz;
   NYD_ENTER;

   cout.s = NULL, cout.l = 0;
   cset7 = charset_get_7bit();
   cset7_len = (ui32_t)strlen(cset7);
   cset8 = _CS_ITER_GET(); /* TODO MIME/send layer: iter active? iter! else */
   cset8_len = (ui32_t)strlen(cset8);

   /* RFC 1468, "MIME Considerations":
    *     ISO-2022-JP may also be used in MIME Part 2 headers.  The "B"
    *     encoding should be used with ISO-2022-JP text. */
   /* TODO of course, our current implementation won't deal properly with
    * TODO any stateful encoding at all... (the standard says each encoded
    * TODO word must include all necessary reset sequences..., i.e., each
    * TODO encoded word must be a self-contained iconv(3) life cycle) */
   if (!asccasecmp(cset8, "iso-2022-jp"))
      flags |= _NO_QP;

   wbot = in->s;
   upper = wbot + in->l;
   col = sizeof("Mail-Followup-To: ") -1; /* dreadful thing */

   for (sz = 0; wbot < upper; flags &= ~_FIRST, wbot = wend) {
      flags &= _RND_MASK;
      wcur = wbot;
      while (wcur < upper && whitechar(*wcur)) {
         flags |= _SPACE;
         ++wcur;
      }

      /* Any occurrence of whitespace resets prevention of lines >SHOULD via
       * enforced encoding (xxx SHOULD, but.. encoding is expensive!!) */
      if (flags & _SPACE)
         flags &= ~_SHOULD_BEE;

     /* Data ends with WS - dump it and done.
      * Also, if we have seen multiple successive whitespace characters, then
      * if there was no encoded word last, i.e., if we can simply take them
      * over to the output as-is, keep one WS for possible later separation
      * purposes and simply print the others as-is, directly! */
      if (wcur == upper) {
         wend = wcur;
         goto jnoenc_putws;
      }
      if ((flags & (_ENC_LAST | _SPACE)) == _SPACE && wcur - wbot > 1) {
         wend = wcur - 1;
         goto jnoenc_putws;
      }

      /* Skip over a word to next non-whitespace, keep track along the way
       * whether our 7-bit charset suffices to represent the data */
      for (wend = wcur; wend < upper; ++wend) {
         if (whitechar(*wend))
            break;
         if ((uc_i)*wend & 0x80)
            flags |= _8BIT;
      }

      /* Decide whether the range has to become encoded or not */
      i = PTR2SIZE(wend - wcur);
      j = mime_enc_mustquote(wcur, i, MIMEEF_ISHEAD);
      /* If it just cannot fit on a SHOULD line length, force encode */
      if (i >= _MAXCOL) {
         flags |= _SHOULD_BEE; /* (Sigh: SHOULD only, not MUST..) */
         goto j_beejump;
      }
      if ((flags & _SHOULD_BEE) || j > 0) {
j_beejump:
         flags |= _ENCODE;
         /* Use base64 if requested or more than 50% -37.5-% of the bytes of
          * the string need to be encoded */
         if ((flags & _NO_QP) || j >= i >> 1)/*(i >> 2) + (i >> 3))*/
            flags |= _ENC_B64;
      }
      DBG( if (flags & _8BIT) assert(flags & _ENCODE); )

      if (!(flags & _ENCODE)) {
         /* Encoded word produced, but no linear whitespace for necessary RFC
          * 2047 separation?  Generate artificial data (bad standard!) */
         if ((flags & (_ENC_LAST | _SPACE)) == _ENC_LAST) {
            if (col >= _MAXCOL) {
               putc('\n', fo);
               ++sz;
               col = 0;
            }
            putc(' ', fo);
            ++sz;
            ++col;
         }

jnoenc_putws:
         flags &= ~_ENC_LAST;

         /* todo No effort here: (1) v15.0 has to bring complete rewrite,
          * todo (2) the standard is braindead and (3) usually this is one
          * todo word only, and why be smarter than the standard? */
jnoenc_retry:
         i = PTR2SIZE(wend - wbot);
         if (i + col <= (flags & _OVERLONG ? MIME_LINELEN_MAX : _MAXCOL)) {
            i = fwrite(wbot, sizeof *wbot, i, fo);
            sz += i;
            col += i;
            continue;
         }

         /* Doesn't fit, try to break the line first; */
         if (col > 1) {
            putc('\n', fo);
            if (whitechar(*wbot)) {
               putc((uc_i)*wbot, fo);
               ++wbot;
            } else
               putc(' ', fo); /* Bad standard: artificial data! */
            sz += 2;
            col = 1;
            flags |= _OVERLONG;
            goto jnoenc_retry;
         }

         /* It is so long that it needs to be broken, effectively causing
          * artificial spaces to be inserted (bad standard), yuck */
         /* todo This is not multibyte safe, as above; and completely stupid
          * todo P.S.: our _SHOULD_BEE prevents these cases in the meanwhile */
/* FIXME OPT_UNICODE and parse using UTF-8 sync possibility! */
         wcur = wbot + MIME_LINELEN_MAX - 8;
         while (wend > wcur)
            wend -= 4;
         goto jnoenc_retry;
      } else {
         /* Encoding to encoded word(s); deal with leading whitespace, place
          * a separator first as necessary: encoded words must always be
          * separated from text and other encoded words with linear WS.
          * And if an encoded word was last, intermediate whitespace must
          * also be encoded, otherwise it would get stripped away! */
         wcur = n_UNCONST("");
         if ((flags & (_ENC_LAST | _SPACE)) != _SPACE) {
            /* Reinclude whitespace */
            flags &= ~_SPACE;
            /* We don't need to place a separator at the very beginning */
            if (!(flags & _FIRST))
               wcur = n_UNCONST(" ");
         } else
            wcur = wbot++;

         flags |= _ENC_LAST;
         pstate |= PS_HEADER_NEEDED_MIME;

         /* RFC 2047:
          *    An 'encoded-word' may not be more than 75 characters long,
          *    including 'charset', 'encoding', 'encoded-text', and
          *    delimiters.  If it is desirable to encode more text than will
          *    fit in an 'encoded-word' of 75 characters, multiple
          *    'encoded-word's (separated by CRLF SPACE) may be used.
          *
          *    While there is no limit to the length of a multiple-line
          *    header field, each line of a header field that contains one
          *    or more 'encoded-word's is limited to 76 characters */
jenc_retry:
         cin.s = n_UNCONST(wbot);
         cin.l = PTR2SIZE(wend - wbot);

         /* C99 */{
            struct str *xout;

            if(flags & _ENC_B64)
               xout = b64_encode(&cout, &cin, B64_ISHEAD | B64_ISENCWORD);
            else
               xout = qp_encode(&cout, &cin, QP_ISHEAD | QP_ISENCWORD);
            if(xout == NULL){
               sz = -1;
               break;
            }
            j = xout->l;
         }
         /* (Avoid trigraphs in the RFC 2047 placeholder..) */
         i = j + (flags & _8BIT ? cset8_len : cset7_len) + sizeof("=!!B!!=") -1;
         if (*wcur != '\0')
            ++i;

jenc_retry_same:
         /* Unfortunately RFC 2047 explicitly disallows encoded words to be
          * longer (just like RFC 5322's "a line SHOULD fit in 78 but MAY be
          * 998 characters long"), so we cannot use the _OVERLONG mechanism,
          * even though all tested mailers seem to support it */
         if (i + col <= (/*flags & _OVERLONG ? MIME_LINELEN_MAX :*/ _MAXCOL)) {
            fprintf(fo, "%.1s=?%s?%c?%.*s?=",
               wcur, (flags & _8BIT ? cset8 : cset7),
               (flags & _ENC_B64 ? 'B' : 'Q'),
               (int)cout.l, cout.s);
            sz += i;
            col += i;
            continue;
         }

         /* Doesn't fit, try to break the line first */
         /* TODO I've commented out the _FIRST test since we (1) cannot do
          * TODO _OVERLONG since (MUAs support but) the standard disallows,
          * TODO and because of our iconv problem i prefer an empty first line
          * TODO in favour of a possibly messed up multibytes character. :-( */
         if (col > 1 /* TODO && !(flags & _FIRST)*/) {
            putc('\n', fo);
            sz += 2;
            col = 1;
            if (!(flags & _SPACE)) {
               putc(' ', fo);
               wcur = n_UNCONST("");
               /*flags |= _OVERLONG;*/
               goto jenc_retry_same;
            } else {
               putc((uc_i)*wcur, fo);
               if (whitechar(*(wcur = wbot)))
                  ++wbot;
               else {
                  flags &= ~_SPACE;
                  wcur = n_UNCONST("");
               }
               /*flags &= ~_OVERLONG;*/
               goto jenc_retry;
            }
         }

         /* It is so long that it needs to be broken, effectively causing
          * artificial data to be inserted (bad standard), yuck */
         /* todo This is not multibyte safe, as above */
         /*if (!(flags & _OVERLONG)) { Mechanism explicitly forbidden by 2047
            flags |= _OVERLONG;
            goto jenc_retry;
         }*/

/* FIXME OPT_UNICODE and parse using UTF-8 sync possibility! */
         i = PTR2SIZE(wend - wbot) + !!(flags & _SPACE);
         j = 3 + !(flags & _ENC_B64);
         for (;;) {
            wend -= j;
            i -= j;
            /* (Note the problem most likely is the transfer-encoding blow,
             * which is why we test this *after* the decrements.. */
            if (i <= _MAXCOL)
               break;
         }
         goto jenc_retry;
      }
   }

   if (cout.s != NULL)
      free(cout.s);
   NYD_LEAVE;
   return sz;
}

static ssize_t
convhdra(char const *str, size_t len, FILE *fp)
{
#ifdef HAVE_ICONV
   struct str ciconv;
#endif
   struct str cin;
   ssize_t ret = 0;
   NYD_ENTER;

   cin.s = n_UNCONST(str);
   cin.l = len;
#ifdef HAVE_ICONV
   ciconv.s = NULL;
   if (iconvd != (iconv_t)-1) {
      ciconv.l = 0;
      if(n_iconv_str(iconvd, n_ICONV_IGN_NOREVERSE, &ciconv, &cin, NULL) != 0){
         n_iconv_reset(iconvd);
         goto jleave;
      }
      cin = ciconv;
   }
#endif
   ret = mime_write_tohdr(&cin, fp);
#ifdef HAVE_ICONV
jleave:
   if (ciconv.s != NULL)
      free(ciconv.s);
#endif
   NYD_LEAVE;
   return ret;
}

static ssize_t
mime_write_tohdr_a(struct str *in, FILE *f) /* TODO error handling */
{
   char const *cp, *lastcp;
   ssize_t sz, x;
   NYD_ENTER;

   in->s[in->l] = '\0';
   lastcp = in->s;
   if ((cp = routeaddr(in->s)) != NULL && cp > lastcp) {
      if ((sz = convhdra(lastcp, PTR2SIZE(cp - lastcp), f)) < 0)
         goto jleave;
      lastcp = cp;
   } else {
      cp = in->s;
      sz = 0;
   }

   for ( ; *cp != '\0'; ++cp) {
      switch (*cp) {
      case '(':
         sz += fwrite(lastcp, 1, PTR2SIZE(cp - lastcp + 1), f);
         lastcp = ++cp;
         cp = skip_comment(cp);
         if (--cp > lastcp) {
            if ((x = convhdra(lastcp, PTR2SIZE(cp - lastcp), f)) < 0) {
               sz = x;
               goto jleave;
            }
            sz += x;
         }
         lastcp = cp;
         break;
      case '"':
         while (*cp) {
            if (*++cp == '"')
               break;
            if (*cp == '\\' && cp[1] != '\0')
               ++cp;
         }
         break;
      }
   }
   if (cp > lastcp)
      sz += fwrite(lastcp, 1, PTR2SIZE(cp - lastcp), f);
jleave:
   NYD_LEAVE;
   return sz;
}

static void
_append_str(char **buf, size_t *sz, size_t *pos, char const *str, size_t len)
{
   NYD_ENTER;
   *buf = srealloc(*buf, *sz += len);
   memcpy(&(*buf)[*pos], str, len);
   *pos += len;
   NYD_LEAVE;
}

static void
_append_conv(char **buf, size_t *sz, size_t *pos, char const *str, size_t len)
{
   struct str in, out;
   NYD_ENTER;

   in.s = n_UNCONST(str);
   in.l = len;
   mime_fromhdr(&in, &out, TD_ISPR | TD_ICONV);
   _append_str(buf, sz, pos, out.s, out.l);
   free(out.s);
   NYD_LEAVE;
}

FL char const *
charset_get_7bit(void)
{
   char const *t;
   NYD_ENTER;

   if ((t = ok_vlook(charset_7bit)) == NULL)
      t = CHARSET_7BIT;
   NYD_LEAVE;
   return t;
}

#ifdef HAVE_ICONV
FL char const *
charset_get_8bit(void)
{
   char const *t;
   NYD_ENTER;

   if ((t = ok_vlook(CHARSET_8BIT_OKEY)) == NULL)
      t = CHARSET_8BIT;
   NYD_LEAVE;
   return t;
}
#endif

FL char const *
charset_get_lc(void)
{
   char const *t;
   NYD_ENTER;

   if ((t = ok_vlook(ttycharset)) == NULL)
      t = CHARSET_8BIT;
   NYD_LEAVE;
   return t;
}

FL bool_t
charset_iter_reset(char const *a_charset_to_try_first)
{
   char const *sarr[3];
   size_t sarrl[3], len;
   char *cp;
   NYD_ENTER;
   n_UNUSED(a_charset_to_try_first);

#ifdef HAVE_ICONV
   sarr[0] = a_charset_to_try_first;
   if ((sarr[1] = ok_vlook(sendcharsets)) == NULL &&
         ok_blook(sendcharsets_else_ttycharset))
      sarr[1] = charset_get_lc();
   sarr[2] = charset_get_8bit();
#else
   sarr[2] = charset_get_lc();
#endif

   sarrl[2] = len = strlen(sarr[2]);
#ifdef HAVE_ICONV
   if ((cp = n_UNCONST(sarr[1])) != NULL)
      len += (sarrl[1] = strlen(cp));
   else
      sarrl[1] = 0;
   if ((cp = n_UNCONST(sarr[0])) != NULL)
      len += (sarrl[0] = strlen(cp));
   else
      sarrl[0] = 0;
#endif

   _cs_iter_base = cp = salloc(len + 1 + 1 +1);

#ifdef HAVE_ICONV
   if ((len = sarrl[0]) != 0) {
      memcpy(cp, sarr[0], len);
      cp[len] = ',';
      cp += ++len;
   }
   if ((len = sarrl[1]) != 0) {
      memcpy(cp, sarr[1], len);
      cp[len] = ',';
      cp += ++len;
   }
#endif
   len = sarrl[2];
   memcpy(cp, sarr[2], len);
   cp[len] = '\0';

   _CS_ITER_STEP();
   NYD_LEAVE;
   return (_cs_iter != NULL);
}

FL bool_t
charset_iter_next(void)
{
   bool_t rv;
   NYD_ENTER;

   _CS_ITER_STEP();
   rv = (_cs_iter != NULL);
   NYD_LEAVE;
   return rv;
}

FL bool_t
charset_iter_is_valid(void)
{
   bool_t rv;
   NYD_ENTER;

   rv = (_cs_iter != NULL);
   NYD_LEAVE;
   return rv;
}

FL char const *
charset_iter(void)
{
   char const *rv;
   NYD_ENTER;

   rv = _cs_iter;
   NYD_LEAVE;
   return rv;
}

FL char const *
charset_iter_or_fallback(void)
{
   char const *rv;
   NYD_ENTER;

   rv = _CS_ITER_GET();
   NYD_LEAVE;
   return rv;
}

FL void
charset_iter_recurse(char *outer_storage[2]) /* TODO LEGACY FUN, REMOVE */
{
   NYD_ENTER;
   outer_storage[0] = _cs_iter_base;
   outer_storage[1] = _cs_iter;
   NYD_LEAVE;
}

FL void
charset_iter_restore(char *outer_storage[2]) /* TODO LEGACY FUN, REMOVE */
{
   NYD_ENTER;
   _cs_iter_base = outer_storage[0];
   _cs_iter = outer_storage[1];
   NYD_LEAVE;
}

#ifdef HAVE_ICONV
FL char const *
need_hdrconv(struct header *hp) /* TODO once only, then iter */
{
   struct n_header_field *hfp;
   char const *rv;
   NYD_ENTER;

   rv = NULL;

   if((hfp = hp->h_user_headers) != NULL)
      do if(_has_highbit(hfp->hf_dat + hfp->hf_nl +1))
         goto jneeds;
      while((hfp = hfp->hf_next) != NULL);

   if((hfp = hp->h_custom_headers) != NULL ||
         (hp->h_custom_headers = hfp = n_customhdr_query()) != NULL)
      do if(_has_highbit(hfp->hf_dat + hfp->hf_nl +1))
         goto jneeds;
      while((hfp = hfp->hf_next) != NULL);

   if (hp->h_mft != NULL) {
      if (_name_highbit(hp->h_mft))
         goto jneeds;
   }
   if (hp->h_from != NULL) {
      if (_name_highbit(hp->h_from))
         goto jneeds;
   } else if (_has_highbit(myaddrs(NULL)))
      goto jneeds;
   if (hp->h_replyto) {
      if (_name_highbit(hp->h_replyto))
         goto jneeds;
   } else if (_has_highbit(ok_vlook(replyto)))
      goto jneeds;
   if (hp->h_sender) {
      if (_name_highbit(hp->h_sender))
         goto jneeds;
   } else if (_has_highbit(ok_vlook(sender)))
      goto jneeds;

   if (_name_highbit(hp->h_to))
      goto jneeds;
   if (_name_highbit(hp->h_cc))
      goto jneeds;
   if (_name_highbit(hp->h_bcc))
      goto jneeds;
   if (_has_highbit(hp->h_subject))
jneeds:
      rv = _CS_ITER_GET(); /* TODO MIME/send: iter active? iter! else */
   NYD_LEAVE;
   return rv;
}
#endif /* HAVE_ICONV */

FL void
mime_fromhdr(struct str const *in, struct str *out, enum tdflags flags)
{
   /* TODO mime_fromhdr(): is called with strings that contain newlines;
    * TODO this is the usual newline problem all around the codebase;
    * TODO i.e., if we strip it, then the display misses it ;>
    * TODO this is why it is so messy and why S-nail v14.2 plus additional
    * TODO patch for v14.5.2 (and maybe even v14.5.3 subminor) occurred, and
    * TODO why our display reflects what is contained in the message: the 1:1
    * TODO relationship of message content and display!
    * TODO instead a header line should be decoded to what it is (a single
    * TODO line that is) and it should be objective to the backend whether
    * TODO it'll be folded to fit onto the display or not, e.g., for search
    * TODO purposes etc.  then the only condition we have to honour in here
    * TODO is that whitespace in between multiple adjacent MIME encoded words
    * TODO á la RFC 2047 is discarded; i.e.: this function should deal with
    * TODO RFC 2047 and be renamed: mime_fromhdr() -> mime_rfc2047_decode() */
   struct str cin, cout;
   char *p, *op, *upper;
   ui32_t convert, lastenc, lastoutl;
#ifdef HAVE_ICONV
   char const *tcs;
   char *cbeg;
   iconv_t fhicd = (iconv_t)-1;
#endif
   NYD_ENTER;

   out->l = 0;
   if (in->l == 0) {
      *(out->s = smalloc(1)) = '\0';
      goto jleave;
   }
   out->s = NULL;

#ifdef HAVE_ICONV
   tcs = charset_get_lc();
#endif
   p = in->s;
   upper = p + in->l;
   lastenc = lastoutl = 0;

   while (p < upper) {
      op = p;
      if (*p == '=' && *(p + 1) == '?') {
         p += 2;
#ifdef HAVE_ICONV
         cbeg = p;
#endif
         while (p < upper && *p != '?')
            ++p;  /* strip charset */
         if (p >= upper)
            goto jnotmime;
         ++p;
#ifdef HAVE_ICONV
         if (flags & TD_ICONV) {
            size_t i = PTR2SIZE(p - cbeg);
            char *ltag, *cs = ac_alloc(i);

            memcpy(cs, cbeg, --i);
            cs[i] = '\0';
            /* RFC 2231 extends the RFC 2047 character set definition in
             * encoded words by language tags - silently strip those off */
            if ((ltag = strchr(cs, '*')) != NULL)
               *ltag = '\0';

            if (fhicd != (iconv_t)-1)
               n_iconv_close(fhicd);
            fhicd = asccasecmp(cs, tcs) ? n_iconv_open(tcs, cs) : (iconv_t)-1;
            ac_free(cs);
         }
#endif
         switch (*p) {
         case 'B': case 'b':
            convert = CONV_FROMB64;
            break;
         case 'Q': case 'q':
            convert = CONV_FROMQP;
            break;
         default: /* invalid, ignore */
            goto jnotmime;
         }
         if (*++p != '?')
            goto jnotmime;
         cin.s = ++p;
         cin.l = 1;
         for (;;) {
            if (PTRCMP(p + 1, >=, upper))
               goto jnotmime;
            if (*p++ == '?' && *p == '=')
               break;
            ++cin.l;
         }
         ++p;
         --cin.l;

         cout.s = NULL;
         cout.l = 0;
         if (convert == CONV_FROMB64) {
            if(!b64_decode(&cout, &cin, NULL))
               n_str_assign_cp(&cout, _("[Invalid Base64 encoding]"));
         }else if(!qp_decode(&cout, &cin, NULL))
            n_str_assign_cp(&cout, _("[Invalid Quoted-Printable encoding]"));

         out->l = lastenc;
#ifdef HAVE_ICONV
         if ((flags & TD_ICONV) && fhicd != (iconv_t)-1) {
            cin.s = NULL, cin.l = 0; /* XXX string pool ! */
            convert = n_iconv_str(fhicd, n_ICONV_DEFAULT, &cin, &cout, NULL);
            out = n_str_add(out, &cin);
            if (convert) {/* EINVAL at EOS */
               n_iconv_reset(fhicd);
               out = n_str_add_buf(out, "?", 1); /* TODO unicode replacement */
            }
            free(cin.s);
         } else
#endif
            out = n_str_add(out, &cout);
         lastenc = lastoutl = out->l;
         free(cout.s);
      } else
jnotmime: {
         bool_t onlyws;

         p = op;
         onlyws = (lastenc > 0);
         for (;;) {
            if (++op == upper)
               break;
            if (op[0] == '=' && (PTRCMP(op + 1, ==, upper) || op[1] == '?'))
               break;
            if (onlyws && !blankchar(*op))
               onlyws = FAL0;
         }

         out = n_str_add_buf(out, p, PTR2SIZE(op - p));
         p = op;
         if (!onlyws || lastoutl != lastenc)
            lastenc = out->l;
         lastoutl = out->l;
      }
   }
   out->s[out->l] = '\0';

   if (flags & TD_ISPR) {
      makeprint(out, &cout);
      free(out->s);
      *out = cout;
   }
   if (flags & TD_DELCTRL)
      out->l = delctrl(out->s, out->l);
#ifdef HAVE_ICONV
   if (fhicd != (iconv_t)-1)
      n_iconv_close(fhicd);
#endif
jleave:
   NYD_LEAVE;
   return;
}

FL char *
mime_fromaddr(char const *name)
{
   char const *cp, *lastcp;
   char *res = NULL;
   size_t ressz = 1, rescur = 0;
   NYD_ENTER;

   if (name == NULL)
      goto jleave;
   if (*name == '\0') {
      res = savestr(name);
      goto jleave;
   }

   if ((cp = routeaddr(name)) != NULL && cp > name) {
      _append_conv(&res, &ressz, &rescur, name, PTR2SIZE(cp - name));
      lastcp = cp;
   } else
      cp = lastcp = name;

   for ( ; *cp; ++cp) {
      switch (*cp) {
      case '(':
         _append_str(&res, &ressz, &rescur, lastcp, PTR2SIZE(cp - lastcp + 1));
         lastcp = ++cp;
         cp = skip_comment(cp);
         if (--cp > lastcp)
            _append_conv(&res, &ressz, &rescur, lastcp, PTR2SIZE(cp - lastcp));
         lastcp = cp;
         break;
      case '"':
         while (*cp) {
            if (*++cp == '"')
               break;
            if (*cp == '\\' && cp[1] != '\0')
               ++cp;
         }
         break;
      }
   }
   if (cp > lastcp)
      _append_str(&res, &ressz, &rescur, lastcp, PTR2SIZE(cp - lastcp));
   /* TODO rescur==0: inserted to silence Coverity ...; check that */
   if (rescur == 0)
      res = n_UNCONST("");
   else
      res[rescur] = '\0';
   {  char *x = res;
      res = savestr(res);
      free(x);
   }
jleave:
   NYD_LEAVE;
   return res;
}

FL ssize_t
xmime_write(char const *ptr, size_t size, FILE *f, enum conversion convert,
   enum tdflags dflags)
{
   ssize_t rv;
   struct quoteflt *qf;
   NYD_ENTER;

   quoteflt_reset(qf = quoteflt_dummy(), f);
   rv = mime_write(ptr, size, f, convert, dflags, qf, NULL);
   quoteflt_flush(qf);
   NYD_LEAVE;
   return rv;
}

static sigjmp_buf       __mimemw_actjmp; /* TODO someday.. */
static int              __mimemw_sig; /* TODO someday.. */
static sighandler_type  __mimemw_opipe;
static void
__mimemw_onsig(int sig) /* TODO someday, we won't need it no more */
{
   NYD_X; /* Signal handler */
   __mimemw_sig = sig;
   siglongjmp(__mimemw_actjmp, 1);
}

FL ssize_t
mime_write(char const *ptr, size_t size, FILE *f,
   enum conversion convert, enum tdflags volatile dflags,
   struct quoteflt *qf, struct str * volatile rest)
{
   /* TODO note: after send/MIME layer rewrite we will have a string pool
    * TODO so that memory allocation count drops down massively; for now,
    * TODO v14.0 that is, we pay a lot & heavily depend on the allocator */
   struct str in, out;
   ssize_t volatile sz;
   int state;
   NYD_ENTER;

   in.s = n_UNCONST(ptr);
   in.l = size;
   out.s = NULL;
   out.l = 0;

   dflags |= _TD_BUFCOPY;
   if ((sz = size) == 0) {
      if (rest != NULL && rest->l != 0)
         goto jconvert;
      goto jleave;
   }

#ifdef HAVE_ICONV
   if ((dflags & TD_ICONV) && iconvd != (iconv_t)-1 &&
         (convert == CONV_TOQP || convert == CONV_8BIT ||
         convert == CONV_TOB64 || convert == CONV_TOHDR)) {
      if (n_iconv_str(iconvd, n_ICONV_IGN_NOREVERSE, &out, &in, NULL) != 0) {
         /* XXX report conversion error? */;
         n_iconv_reset(iconvd);
         sz = -1;
         goto jleave;
      }
      in = out;
      out.s = NULL;
      dflags &= ~_TD_BUFCOPY;
   }
#endif

jconvert:
   __mimemw_sig = 0;
   __mimemw_opipe = safe_signal(SIGPIPE, &__mimemw_onsig);
   if (sigsetjmp(__mimemw_actjmp, 1))
      goto jleave;

   switch (convert) {
   case CONV_FROMQP:
      if(!qp_decode(&out, &in, rest)){
         n_err(_("Invalid Quoted-Printable encoding ignored\n"));
         sz = 0;
         state = STOP; /* TODO sz = -1 stops outer levels! */
         break;
      }
      state = OKAY;
      goto jqpb64_dec;
   case CONV_TOQP:
      if(qp_encode(&out, &in, QP_NONE) == NULL){
         sz = -1;
         break;
      }
      goto jqpb64_enc;
   case CONV_8BIT:
      sz = quoteflt_push(qf, in.s, in.l);
      break;
   case CONV_FROMB64:
      rest = NULL;
      /* FALLTHRU */
   case CONV_FROMB64_T:
      if(!b64_decode(&out, &in, rest)){
         n_err(_("Invalid Base64 encoding ignored\n"));
         sz = 0;
         state = STOP; /* TODO sz = -1 stops outer levels! */
         break;
      }
      state = OKAY;
jqpb64_dec:
      if ((sz = out.l) != 0) {
         ui32_t opl = qf->qf_pfix_len;
         if (state != OKAY)
            qf->qf_pfix_len = 0;
         sz = _fwrite_td(&out, (dflags & ~_TD_BUFCOPY), rest, qf);
         qf->qf_pfix_len = opl;
      }
      if (state != OKAY)
         sz = -1;
      break;
   case CONV_TOB64:
      if(b64_encode(&out, &in, B64_LF | B64_MULTILINE) == NULL){
         sz = -1;
         break;
      }
jqpb64_enc:
      sz = fwrite(out.s, sizeof *out.s, out.l, f);
      if (sz != (ssize_t)out.l)
         sz = -1;
      break;
   case CONV_FROMHDR:
      mime_fromhdr(&in, &out, TD_ISPR | TD_ICONV | (dflags & TD_DELCTRL));
      sz = quoteflt_push(qf, out.s, out.l);
      break;
   case CONV_TOHDR:
      sz = mime_write_tohdr(&in, f);
      break;
   case CONV_TOHDR_A:
      sz = mime_write_tohdr_a(&in, f);
      break;
   default:
      sz = _fwrite_td(&in, dflags, NULL, qf);
      break;
   }
jleave:
   if (out.s != NULL)
      free(out.s);
   if (in.s != ptr)
      free(in.s);
   safe_signal(SIGPIPE, __mimemw_opipe);
   if (__mimemw_sig != 0)
      n_raise(__mimemw_sig);
   NYD_LEAVE;
   return sz;
}

/* s-it-mode */
