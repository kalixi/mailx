/*@ S-nail - a mail user agent derived from Berkeley Mail.
 *@ Message content preparation (sendmp()).
 *
 * Copyright (c) 2000-2004 Gunnar Ritter, Freiburg i. Br., Germany.
 * Copyright (c) 2012 - 2019 Steffen (Daode) Nurpmeso <steffen@sdaoden.eu>.
 * SPDX-License-Identifier: BSD-3-Clause
 */
/*
 * Copyright (c) 1980, 1993
 *      The Regents of the University of California.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the University nor the names of its contributors
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
 */
#undef su_FILE
#define su_FILE send
#define mx_SOURCE

#ifndef mx_HAVE_AMALGAMATION
# include "mx/nail.h"
#endif

#include <su/cs.h>
#include <su/mem.h>

#include "mx/child.h"
#include "mx/colour.h"
#include "mx/file-streams.h"
/* TODO but only for creating chain! */
#include "mx/filter-quote.h"
#include "mx/iconv.h"
#include "mx/random.h"
#include "mx/sigs.h"
#include "mx/tty.h"
#include "mx/ui-str.h"

/* TODO fake */
#include "su/code-in.h"

static sigjmp_buf _send_pipejmp;

/* Going for user display, print Part: info string */
static void          _print_part_info(FILE *obuf, struct mimepart const *mpp,
                        struct n_ignore const *doitp, int level,
                        struct quoteflt *qf, u64 *stats);

/* Create a pipe; if mpp is not NULL, place some n_PIPEENV_* environment
 * variables accordingly */
static FILE *        _pipefile(struct mime_handler *mhp,
                        struct mimepart const *mpp, FILE **qbuf,
                        char const *tmpname, int term_infd);

/* Call mime_write() as approbiate and adjust statistics */
su_SINLINE sz _out(char const *buf, uz len, FILE *fp,
      enum conversion convert, enum sendaction action, struct quoteflt *qf,
      u64 *stats, struct str *outrest, struct str *inrest);

/* Simply (!) print out a LF */
static boole a_send_out_nl(FILE *fp, u64 *stats);

/* SIGPIPE handler */
static void          _send_onpipe(int signo);

/* Send one part */
static int           sendpart(struct message *zmp, struct mimepart *ip,
                        FILE *obuf, struct n_ignore const *doitp,
                        struct quoteflt *qf, enum sendaction action,
                        char **linedat, uz *linesize,
                        u64 *stats, int level);

/* Dependent on *mime-alternative-favour-rich* (favour_rich) do a tree walk
 * and check whether there are any such down mpp, which is a .m_multipart of
 * an /alternative container..
 * Afterwards the latter will flag all the subtree accordingly, setting
 * MDISPLAY in mimepart.m_flag if a part shall be displayed.
 * TODO of course all this is hacky in that it should ONLY be done so */
static boole        _send_al7ive_have_better(struct mimepart *mpp,
                        enum sendaction action, boole want_rich);
static void          _send_al7ive_flag_tree(struct mimepart *mpp,
                        enum sendaction action, boole want_rich);

/* Get a file for an attachment */
static FILE *        newfile(struct mimepart *ip, boole volatile *ispipe);

static void          pipecpy(FILE *pipebuf, FILE *outbuf, FILE *origobuf,
                        struct quoteflt *qf, u64 *stats);

/* Output a reasonable looking status field */
static void          statusput(const struct message *mp, FILE *obuf,
                        struct quoteflt *qf, u64 *stats);
static void          xstatusput(const struct message *mp, FILE *obuf,
                        struct quoteflt *qf, u64 *stats);

static void          put_from_(FILE *fp, struct mimepart *ip, u64 *stats);

static void
_print_part_info(FILE *obuf, struct mimepart const *mpp, /* TODO strtofmt.. */
   struct n_ignore const *doitp, int level, struct quoteflt *qf, u64 *stats)
{
   char buf[64];
   struct str ti, to;
   boole want_ct, needsep;
   struct str const *cpre, *csuf;
   char const *cp;
   NYD2_IN;

   cpre = csuf = NULL;
#ifdef mx_HAVE_COLOUR
   if(mx_COLOUR_IS_ACTIVE()){
      struct mx_colour_pen *cpen;

      cpen = mx_colour_pen_create(mx_COLOUR_ID_VIEW_PARTINFO, NULL);
      if((cpre = mx_colour_pen_to_str(cpen)) != NIL)
         csuf = mx_colour_reset_to_str();
   }
#endif

   /* Take care of "99.99", i.e., 5 */
   if ((cp = mpp->m_partstring) == NULL || cp[0] == '\0')
      cp = n_qm;
   if (level || (cp[0] != '1' && cp[1] == '\0') || (cp[0] == '1' && /* TODO */
         cp[1] == '.' && cp[2] != '1')) /* TODO code should not look like so */
      _out("\n", 1, obuf, CONV_NONE, SEND_MBOX, qf, stats, NULL, NULL);

   /* Part id, content-type, encoding, charset */
   if (cpre != NULL)
      _out(cpre->s, cpre->l, obuf, CONV_NONE, SEND_MBOX, qf, stats, NULL,NULL);
   _out("[-- #", 5, obuf, CONV_NONE, SEND_MBOX, qf, stats, NULL,NULL);
   _out(cp, su_cs_len(cp), obuf, CONV_NONE, SEND_MBOX, qf, stats, NULL,NULL);

   to.l = snprintf(buf, sizeof buf, " %" PRIuZ "/%" PRIuZ " ",
         (uz)mpp->m_lines, (uz)mpp->m_size);
   _out(buf, to.l, obuf, CONV_NONE, SEND_MBOX, qf, stats, NULL,NULL);

   needsep = FAL0;

    if((cp = mpp->m_ct_type_usr_ovwr) != NULL){
      _out("+", 1, obuf, CONV_NONE, SEND_MBOX, qf, stats, NULL,NULL);
      want_ct = TRU1;
   }else if((want_ct = n_ignore_is_ign(doitp,
         "content-type", sizeof("content-type") -1)))
      cp = mpp->m_ct_type_plain;
   if (want_ct && (to.l = su_cs_len(cp)) > 30 &&
            su_cs_starts_with_case(cp, "application/")) {
      uz const al = sizeof("appl../") -1, fl = sizeof("application/") -1;
      uz i = to.l - fl;
      char *x = n_autorec_alloc(al + i +1);

      su_mem_copy(x, "appl../", al);
      su_mem_copy(x + al, cp + fl, i +1);
      cp = x;
      to.l = al + i;
   }
   if(cp != NULL){
      _out(cp, to.l, obuf, CONV_NONE, SEND_MBOX, qf, stats, NULL,NULL);
      needsep = TRU1;
   }

   if(mpp->m_multipart == NULL/* TODO */ && (cp = mpp->m_ct_enc) != NULL &&
         (!su_cs_cmp_case(cp, "7bit") ||
          n_ignore_is_ign(doitp, "content-transfer-encoding",
            sizeof("content-transfer-encoding") -1))){
      if(needsep)
         _out(", ", 2, obuf, CONV_NONE, SEND_MBOX, qf, stats, NULL,NULL);
      if (to.l > 25 && !su_cs_cmp_case(cp, "quoted-printable"))
         cp = "qu.-pr.";
      _out(cp, su_cs_len(cp), obuf, CONV_NONE, SEND_MBOX, qf, stats,
         NULL,NULL);
      needsep = TRU1;
   }

   if (want_ct && mpp->m_multipart == NULL/* TODO */ &&
         (cp = mpp->m_charset) != NULL) {
      if(needsep)
         _out(", ", 2, obuf, CONV_NONE, SEND_MBOX, qf, stats, NULL,NULL);
      _out(cp, su_cs_len(cp), obuf, CONV_NONE, SEND_MBOX, qf, stats,
         NULL,NULL);
   }

   needsep = !needsep;
   _out(&" --]"[su_S(su_u8,needsep)], 4 - needsep,
      obuf, CONV_NONE, SEND_MBOX, qf, stats, NULL,NULL);
   if (csuf != NULL)
      _out(csuf->s, csuf->l, obuf, CONV_NONE, SEND_MBOX, qf, stats, NULL,NULL);
   _out("\n", 1, obuf, CONV_NONE, SEND_MBOX, qf, stats, NULL,NULL);

   /* */
   if (mpp->m_content_info & CI_MIME_ERRORS) {
      if (cpre != NULL)
         _out(cpre->s, cpre->l, obuf, CONV_NONE, SEND_MBOX, qf, stats,
            NULL, NULL);
      _out("[-- ", 4, obuf, CONV_NONE, SEND_MBOX, qf, stats, NULL, NULL);

      ti.l = su_cs_len(ti.s = n_UNCONST(_("Defective MIME structure")));
      makeprint(&ti, &to);
      to.l = delctrl(to.s, to.l);
      _out(to.s, to.l, obuf, CONV_NONE, SEND_MBOX, qf, stats, NULL, NULL);
      n_free(to.s);

      _out(" --]", 4, obuf, CONV_NONE, SEND_MBOX, qf, stats, NULL, NULL);
      if (csuf != NULL)
         _out(csuf->s, csuf->l, obuf, CONV_NONE, SEND_MBOX, qf, stats,
            NULL, NULL);
      _out("\n", 1, obuf, CONV_NONE, SEND_MBOX, qf, stats, NULL, NULL);
   }

   /* Content-Description */
   if (n_ignore_is_ign(doitp, "content-description", 19) &&
         (cp = mpp->m_content_description) != NULL && *cp != '\0') {
      if (cpre != NULL)
         _out(cpre->s, cpre->l, obuf, CONV_NONE, SEND_MBOX, qf, stats,
            NULL, NULL);
      _out("[-- ", 4, obuf, CONV_NONE, SEND_MBOX, qf, stats, NULL, NULL);

      ti.l = su_cs_len(ti.s = n_UNCONST(mpp->m_content_description));
      mime_fromhdr(&ti, &to, TD_ISPR | TD_ICONV);
      _out(to.s, to.l, obuf, CONV_NONE, SEND_MBOX, qf, stats, NULL, NULL);
      n_free(to.s);

      _out(" --]", 4, obuf, CONV_NONE, SEND_MBOX, qf, stats, NULL, NULL);
      if (csuf != NULL)
         _out(csuf->s, csuf->l, obuf, CONV_NONE, SEND_MBOX, qf, stats,
            NULL, NULL);
      _out("\n", 1, obuf, CONV_NONE, SEND_MBOX, qf, stats, NULL, NULL);
   }

   /* Filename */
   if (n_ignore_is_ign(doitp, "content-disposition", 19) &&
         mpp->m_filename != NULL && *mpp->m_filename != '\0') {
      if (cpre != NULL)
         _out(cpre->s, cpre->l, obuf, CONV_NONE, SEND_MBOX, qf, stats,
            NULL, NULL);
      _out("[-- ", 4, obuf, CONV_NONE, SEND_MBOX, qf, stats, NULL, NULL);

      ti.l = su_cs_len(ti.s = mpp->m_filename);
      makeprint(&ti, &to);
      to.l = delctrl(to.s, to.l);
      _out(to.s, to.l, obuf, CONV_NONE, SEND_MBOX, qf, stats, NULL, NULL);
      n_free(to.s);

      _out(" --]", 4, obuf, CONV_NONE, SEND_MBOX, qf, stats, NULL, NULL);
      if (csuf != NULL)
         _out(csuf->s, csuf->l, obuf, CONV_NONE, SEND_MBOX, qf, stats,
            NULL, NULL);
      _out("\n", 1, obuf, CONV_NONE, SEND_MBOX, qf, stats, NULL, NULL);
   }
   NYD2_OU;
}

static FILE *
_pipefile(struct mime_handler *mhp, struct mimepart const *mpp, FILE **qbuf,
   char const *tmpname, int term_infd)
{
   static u32 reprocnt;
   struct str s;
   char const *env_addon[9 +8/*v15*/], *cp, *sh;
   uz i;
   FILE *rbuf;
   NYD_IN;

   rbuf = *qbuf;

   if(mhp->mh_flags & MIME_HDL_ISQUOTE){
      if((*qbuf = mx_fs_tmp_open("sendp", (mx_FS_O_RDWR | mx_FS_O_UNLINK |
               mx_FS_O_REGISTER), NIL)) == NIL){
         n_perr(_("tmpfile"), 0);
         *qbuf = rbuf;
      }
   }

   if ((mhp->mh_flags & MIME_HDL_TYPE_MASK) == MIME_HDL_PTF) {
      union {int (*ptf)(void); char const *sh;} u;

      fflush(*qbuf);
      if (*qbuf != n_stdout) /* xxx never?  v15: it'll be a filter anyway */
         fflush(n_stdout);

      u.ptf = mhp->mh_ptf;
      if((rbuf = mx_fs_pipe_open(R(char*,-1), "W", u.sh, NIL, fileno(*qbuf))
            ) == NIL)
         goto jerror;
      goto jleave;
   }

   i = 0;

   /* MAILX_FILENAME */
   if (mpp == NULL || (cp = mpp->m_filename) == NULL)
      cp = n_empty;
   env_addon[i++] = str_concat_csvl(&s, n_PIPEENV_FILENAME, "=", cp, NULL)->s;
env_addon[i++] = str_concat_csvl(&s, "NAIL_FILENAME", "=", cp, NULL)->s;/*v15*/

   /* MAILX_FILENAME_GENERATED *//* TODO pathconf NAME_MAX; but user can create
    * TODO a file wherever he wants!  *Do* create a zero-size temporary file
    * TODO and give *that* path as MAILX_FILENAME_TEMPORARY, clean it up once
    * TODO the pipe returns?  Like this we *can* verify path/name issues! */
   cp = mx_random_create_cp(MIN(NAME_MAX - 3, 16), &reprocnt);
   env_addon[i++] = str_concat_csvl(&s, n_PIPEENV_FILENAME_GENERATED, "=", cp,
         NULL)->s;
env_addon[i++] = str_concat_csvl(&s, "NAIL_FILENAME_GENERATED", "=", cp,/*v15*/
      NULL)->s;

   /* MAILX_CONTENT{,_EVIDENCE} */
   if (mpp == NULL || (cp = mpp->m_ct_type_plain) == NULL)
      cp = n_empty;
   env_addon[i++] = str_concat_csvl(&s, n_PIPEENV_CONTENT, "=", cp, NULL)->s;
env_addon[i++] = str_concat_csvl(&s, "NAIL_CONTENT", "=", cp, NULL)->s;/*v15*/

   if (mpp != NULL && mpp->m_ct_type_usr_ovwr != NULL)
      cp = mpp->m_ct_type_usr_ovwr;
   env_addon[i++] = str_concat_csvl(&s, n_PIPEENV_CONTENT_EVIDENCE, "=", cp,
         NULL)->s;
env_addon[i++] = str_concat_csvl(&s, "NAIL_CONTENT_EVIDENCE", "=", cp,/* v15 */
      NULL)->s;

   /* message/external-body, access-type=url */
   env_addon[i++] = str_concat_csvl(&s, n_PIPEENV_EXTERNAL_BODY_URL, "=",
         ((mpp != NULL && (cp = mpp->m_external_body_url) != NULL
            ) ? cp : n_empty), NULL)->s;

   /* MAILX_FILENAME_TEMPORARY? */
   if (tmpname != NULL) {
      env_addon[i++] = str_concat_csvl(&s,
            n_PIPEENV_FILENAME_TEMPORARY, "=", tmpname, NULL)->s;
env_addon[i++] = str_concat_csvl(&s,
         "NAIL_FILENAME_TEMPORARY", "=", tmpname, NULL)->s;/* v15 */
   }

   /* TODO we should include header information, especially From:, so
    * TODO that same-origin can be tested for e.g. external-body!!! */

   env_addon[i] = NULL;
   sh = ok_vlook(SHELL);

   if (mhp->mh_flags & MIME_HDL_NEEDSTERM) {
      struct mx_child_ctx cc;
      sigset_t nset;

      sigemptyset(&nset);
      mx_child_ctx_setup(&cc);
      cc.cc_flags = mx_CHILD_RUN_WAIT_LIFE;
      cc.cc_mask = &nset;
      cc.cc_fds[mx_CHILD_FD_IN] = term_infd;
      cc.cc_cmd = sh;
      cc.cc_args[0] = "-c";
      cc.cc_args[1] = mhp->mh_shell_cmd;
      cc.cc_env_addon = env_addon;

      rbuf = !mx_child_run(&cc) ? NIL : R(FILE*,-1);
   }else{
      rbuf = mx_fs_pipe_open(mhp->mh_shell_cmd, "W", sh, env_addon,
            (mhp->mh_flags & MIME_HDL_ASYNC ? mx_CHILD_FD_NULL
             : fileno(*qbuf)));
jerror:
      if(rbuf == NIL)
         n_err(_("Cannot run MIME type handler: %s: %s\n"),
            mhp->mh_msg, su_err_doc(su_err_no()));
      else{
         fflush(*qbuf);
         if(*qbuf != n_stdout)
            fflush(n_stdout);
      }
   }
jleave:
   NYD_OU;
   return rbuf;
}

su_SINLINE sz
_out(char const *buf, uz len, FILE *fp, enum conversion convert, enum
   sendaction action, struct quoteflt *qf, u64 *stats, struct str *outrest,
   struct str *inrest)
{
   sz size = 0, n;
   int flags;
   NYD_IN;

   /* TODO We should not need is_head() here, i think in v15 the actual Mailbox
    * TODO subclass should detect From_ cases and either re-encode the part
    * TODO in question, or perform From_ quoting as necessary!?!?!?  How?!? */
   /* C99 */{
      boole from_;

      if((action == SEND_MBOX || action == SEND_DECRYPT) &&
            (from_ = is_head(buf, len, TRU1))){
         if(from_ != TRUM1 || (mb.mb_active & MB_BAD_FROM_) ||
               ok_blook(mbox_rfc4155)){
            putc('>', fp);
            ++size;
         }
      }
   }

   flags = ((int)action & _TD_EOF);
   action &= ~_TD_EOF;
   n = mime_write(buf, len, fp,
         action == SEND_MBOX ? CONV_NONE : convert,
         flags | ((action == SEND_TODISP || action == SEND_TODISP_ALL ||
            action == SEND_TODISP_PARTS ||
            action == SEND_QUOTE || action == SEND_QUOTE_ALL)
         ?  TD_ISPR | TD_ICONV
         : (action == SEND_TOSRCH || action == SEND_TOPIPE ||
               action == SEND_TOFILE)
            ? TD_ICONV : (action == SEND_SHOW ? TD_ISPR : TD_NONE)),
         qf, outrest, inrest);
   if (n < 0)
      size = n;
   else if (n > 0) {
      size += n;
      if (stats != NULL)
         *stats += size;
   }
   NYD_OU;
   return size;
}

static boole
a_send_out_nl(FILE *fp, u64 *stats){
   struct quoteflt *qf;
   boole rv;
   NYD2_IN;

   quoteflt_reset(qf = quoteflt_dummy(), fp);
   rv = (_out("\n", 1, fp, CONV_NONE, SEND_MBOX, qf, stats, NULL,NULL) > 0);
   quoteflt_flush(qf);
   NYD2_OU;
   return rv;
}

static void
_send_onpipe(int signo)
{
   NYD; /* Signal handler */
   UNUSED(signo);
   siglongjmp(_send_pipejmp, 1);
}

static sigjmp_buf       __sendp_actjmp; /* TODO someday.. */
static int              __sendp_sig; /* TODO someday.. */
static n_sighdl_t  __sendp_opipe;
static void
__sendp_onsig(int sig) /* TODO someday, we won't need it no more */
{
   NYD; /* Signal handler */
   __sendp_sig = sig;
   siglongjmp(__sendp_actjmp, 1);
}

static int
sendpart(struct message *zmp, struct mimepart *ip, FILE * volatile obuf,
   struct n_ignore const *doitp, struct quoteflt *qf,
   enum sendaction volatile action,
   char **linedat, uz *linesize, u64 * volatile stats, int level)
{
   int volatile rv = 0;
   struct mime_handler mh_stack, * volatile mhp;
   struct str outrest, inrest;
   char *cp;
   char const * volatile tmpname = NULL;
   uz linelen, cnt;
   int volatile dostat, term_infd;
   int c;
   struct mimepart * volatile np;
   FILE * volatile ibuf = NULL, * volatile pbuf = obuf,
      * volatile qbuf = obuf, *origobuf = obuf;
   enum conversion volatile convert;
   n_sighdl_t volatile oldpipe = SIG_DFL;
   NYD_IN;

   UNINIT(term_infd, 0);
   UNINIT(cnt, 0);

   quoteflt_reset(qf, obuf);

#if 0 /* TODO PART_INFO should be displayed here!! search PART_INFO */
   if(ip->m_mimecontent != MIME_DISCARD && level > 0)
      _print_part_info(obuf, ip, doitp, level, qf, stats);
#endif

   if (ip->m_mimecontent == MIME_PKCS7) {
      if (ip->m_multipart &&
            action != SEND_MBOX && action != SEND_RFC822 && action != SEND_SHOW)
         goto jheaders_skip;
   }

   dostat = 0;
   if (level == 0 && action != SEND_TODISP_PARTS) {
      if (doitp != NULL) {
         if (!n_ignore_is_ign(doitp, "status", 6))
            dostat |= 1;
         if (!n_ignore_is_ign(doitp, "x-status", 8))
            dostat |= 2;
      } else
         dostat = 3;
   }

   if ((ibuf = setinput(&mb, (struct message*)ip, NEED_BODY)) == NULL) {
      rv = -1;
      goto jleave;
   }

   if(action == SEND_TODISP || action == SEND_TODISP_ALL ||
         action == SEND_TODISP_PARTS ||
         action == SEND_QUOTE || action == SEND_QUOTE_ALL ||
         action == SEND_TOSRCH)
      dostat |= 4;

   cnt = ip->m_size;

   if (ip->m_mimecontent == MIME_DISCARD)
      goto jheaders_skip;

   if (!(ip->m_flag & MNOFROM))
      while (cnt && (c = getc(ibuf)) != EOF) {
         cnt--;
         if (c == '\n')
            break;
      }
   convert = (dostat & 4) ? CONV_FROMHDR : CONV_NONE;

   /* Work the headers */
   /* C99 */{
   struct n_string hl, *hlp;
   uz lineno = 0;
   boole hstop/*see below, hany*/;

   hlp = n_string_creat_auto(&hl); /* TODO pool [or, v15: filter!] */
   /* Reserve three lines, still not enough for references and DKIM etc. */
   hlp = n_string_reserve(hlp, MAX(MIME_LINELEN, MIME_LINELEN_RFC2047) * 3);

   for(hstop = /*see below hany =*/ FAL0; !hstop;){
      uz lcnt;

      lcnt = cnt;
      if(fgetline(linedat, linesize, &cnt, &linelen, ibuf, 0) == NULL)
         break;
      ++lineno;
      if (linelen == 0 || (cp = *linedat)[0] == '\n')
         /* If line is blank, we've reached end of headers */
         break;
      if(cp[linelen - 1] == '\n'){
         cp[--linelen] = '\0';
         if(linelen == 0)
            break;
      }

      /* Are we in a header? */
      if(hlp->s_len > 0){
         if(!su_cs_is_blank(*cp)){
            fseek(ibuf, -(off_t)(lcnt - cnt), SEEK_CUR);
            cnt = lcnt;
            goto jhdrput;
         }
         goto jhdrpush;
      }else{
         /* Pick up the header field if we have one */
         while((c = *cp) != ':' && !su_cs_is_space(c) && c != '\0')
            ++cp;
         for(;;){
            if(!su_cs_is_space(c) || c == '\0')
               break;
            c = *++cp;
         }
         if(c != ':'){
            /* That won't work with MIME when saving etc., before v15 */
            if (lineno != 1)
               /* XXX This disturbs, and may happen multiple times, and we
                * XXX cannot heal it for multipart except for display <v15 */
               n_err(_("Malformed message: headers and body not separated "
                  "(with empty line)\n"));
            if(level != 0)
               dostat &= ~(1 | 2);
            fseek(ibuf, -(off_t)(lcnt - cnt), SEEK_CUR);
            cnt = lcnt;
            break;
         }

         cp = *linedat;
jhdrpush:
         if(!(dostat & 4)){
            hlp = n_string_push_buf(hlp, cp, (u32)linelen);
            hlp = n_string_push_c(hlp, '\n');
         }else{
            boole lblank, isblank;

            for(lblank = FAL0, lcnt = 0; lcnt < linelen; ++cp, ++lcnt){
               char c8;

               c8 = *cp;
               if(!(isblank = su_cs_is_blank(c8)) || !lblank){
                  if((lblank = isblank))
                     c8 = ' ';
                  hlp = n_string_push_c(hlp, c8);
               }
            }
         }
         continue;
      }

jhdrput:
      /* If it is an ignored header, skip it */
      *(cp = su_mem_find(hlp->s_dat, ':', hlp->s_len)) = '\0';
      /* C99 */{
         uz i;

         i = P2UZ(cp - hlp->s_dat);
         if((doitp != NULL && n_ignore_is_ign(doitp, hlp->s_dat, i)) ||
               !su_cs_cmp_case(hlp->s_dat, "status") ||
               !su_cs_cmp_case(hlp->s_dat, "x-status") ||
               (action == SEND_MBOX &&
                  (!su_cs_cmp_case(hlp->s_dat, "content-length") ||
                   !su_cs_cmp_case(hlp->s_dat, "lines")) &&
                !ok_blook(keep_content_length)))
            goto jhdrtrunc;
      }

      /* Dump it */
      mx_COLOUR(
         if(mx_COLOUR_IS_ACTIVE())
            mx_colour_put(mx_COLOUR_ID_VIEW_HEADER, hlp->s_dat);
      )
      *cp = ':';
      _out(hlp->s_dat, hlp->s_len, obuf, convert, action, qf, stats, NULL,NULL);
      mx_COLOUR(
         if(mx_COLOUR_IS_ACTIVE())
            mx_colour_reset();
      )
      if(dostat & 4)
         _out("\n", sizeof("\n") -1, obuf, convert, action, qf, stats,
            NULL,NULL);
      /*see below hany = TRU1;*/

jhdrtrunc:
      hlp = n_string_trunc(hlp, 0);
   }
   hstop = TRU1;
   if(hlp->s_len > 0)
      goto jhdrput;

   /* We've reached end of headers, so eventually force out status: field and
    * note that we are no longer in header fields */
   if(dostat & 1){
      statusput(zmp, obuf, qf, stats);
      /*see below hany = TRU1;*/
   }
   if(dostat & 2){
      xstatusput(zmp, obuf, qf, stats);
      /*see below hany = TRU1;*/
   }
   if(/* TODO PART_INFO hany && */ doitp != n_IGNORE_ALL)
      _out("\n", 1, obuf, CONV_NONE, SEND_MBOX, qf, stats, NULL,NULL);
   } /* C99 */

   quoteflt_flush(qf);

   if(ferror(obuf)){
      rv = -1;
      goto jleave;
   }

jheaders_skip:
   su_mem_set(mhp = &mh_stack, 0, sizeof mh_stack);

   switch (ip->m_mimecontent) {
   case MIME_822:
      switch (action) {
      case SEND_TODISP_PARTS:
         goto jleave;
      case SEND_TODISP:
      case SEND_TODISP_ALL:
      case SEND_QUOTE:
      case SEND_QUOTE_ALL:
         if (ok_blook(rfc822_body_from_)) {
            if (!qf->qf_bypass) {
               uz i = fwrite(qf->qf_pfix, sizeof *qf->qf_pfix,
                     qf->qf_pfix_len, obuf);
               if (i == qf->qf_pfix_len && stats != NULL)
                  *stats += i;
            }
            put_from_(obuf, ip->m_multipart, stats);
         }
         /* FALLTHRU */
      case SEND_TOSRCH:
      case SEND_DECRYPT:
         goto jmulti;
      case SEND_TOFILE:
      case SEND_TOPIPE:
         put_from_(obuf, ip->m_multipart, stats);
         /* FALLTHRU */
      case SEND_MBOX:
      case SEND_RFC822:
      case SEND_SHOW:
         break;
      }
      break;
   case MIME_TEXT_HTML:
   case MIME_TEXT:
   case MIME_TEXT_PLAIN:
      switch (action) {
      case SEND_TODISP:
      case SEND_TODISP_ALL:
      case SEND_TODISP_PARTS:
      case SEND_QUOTE:
      case SEND_QUOTE_ALL:
         if ((mhp = ip->m_handler) == NULL)
            n_mimetype_handler(mhp =
               ip->m_handler = n_autorec_alloc(sizeof(*mhp)), ip, action);
         switch (mhp->mh_flags & MIME_HDL_TYPE_MASK) {
         case MIME_HDL_NULL:
            if(action != SEND_TODISP_PARTS)
               break;
            /* FALLTHRU */
         case MIME_HDL_MSG:/* TODO these should be part of partinfo! */
            if(mhp->mh_msg.l > 0)
               _out(mhp->mh_msg.s, mhp->mh_msg.l, obuf, CONV_NONE, SEND_MBOX,
                  qf, stats, NULL, NULL);
            /* We would print this as plain text, so better force going home */
            goto jleave;
         case MIME_HDL_CMD:
            if(action == SEND_TODISP_PARTS &&
                  (mhp->mh_flags & MIME_HDL_COPIOUSOUTPUT))
               goto jleave;
            break;
         case MIME_HDL_TEXT:
         case MIME_HDL_PTF:
            if(action == SEND_TODISP_PARTS)
               goto jleave;
            break;
         default:
            break;
         }
         /* FALLTRHU */
      default:
         break;
      }
      break;
   case MIME_DISCARD:
      if (action != SEND_DECRYPT)
         goto jleave;
      break;
   case MIME_PKCS7:
      if (action != SEND_MBOX && action != SEND_RFC822 &&
            action != SEND_SHOW && ip->m_multipart != NULL)
         goto jmulti;
      /* FALLTHRU */
   default:
      switch (action) {
      case SEND_TODISP:
      case SEND_TODISP_ALL:
      case SEND_TODISP_PARTS:
      case SEND_QUOTE:
      case SEND_QUOTE_ALL:
         if ((mhp = ip->m_handler) == NULL)
            n_mimetype_handler(mhp = ip->m_handler =
               n_autorec_alloc(sizeof(*mhp)), ip, action);
         switch (mhp->mh_flags & MIME_HDL_TYPE_MASK) {
         default:
         case MIME_HDL_NULL:
            if (action != SEND_TODISP && action != SEND_TODISP_ALL &&
                  (level != 0 || cnt))
               goto jleave;
            /* FALLTHRU */
         case MIME_HDL_MSG:/* TODO these should be part of partinfo! */
            if(mhp->mh_msg.l > 0)
               _out(mhp->mh_msg.s, mhp->mh_msg.l, obuf, CONV_NONE, SEND_MBOX,
                  qf, stats, NULL, NULL);
            /* We would print this as plain text, so better force going home */
            goto jleave;
         case MIME_HDL_CMD:
            if(action == SEND_TODISP_PARTS){
               if(mhp->mh_flags & MIME_HDL_COPIOUSOUTPUT)
                  goto jleave;
               else{
                  _print_part_info(obuf, ip, doitp, level, qf, stats);
                  /* Because: interactive OR batch mode, so */
                  if(!mx_tty_yesorno(_("Run MIME handler for this part?"),
                        su_state_has(su_STATE_REPRODUCIBLE)))
                     goto jleave;
               }
            }
            break;
         case MIME_HDL_TEXT:
         case MIME_HDL_PTF:
            if(action == SEND_TODISP_PARTS)
               goto jleave;
            break;
         }
         break;
      case SEND_TOFILE:
      case SEND_TOPIPE:
      case SEND_TOSRCH:
      case SEND_DECRYPT:
      case SEND_MBOX:
      case SEND_RFC822:
      case SEND_SHOW:
         break;
      }
      break;
   case MIME_ALTERNATIVE:
      if ((action == SEND_TODISP || action == SEND_QUOTE) &&
            !ok_blook(print_alternatives)) {
         /* XXX This (a) should not remain (b) should be own fun
          * TODO (despite the fact that v15 will do this completely differently
          * TODO by having an action-specific "manager" that will traverse the
          * TODO parsed MIME tree and decide for each part whether it'll be
          * TODO displayed or not *before* we walk the tree for doing action */
         struct mpstack {
            struct mpstack *outer;
            struct mimepart *mp;
         } outermost, * volatile curr, * volatile mpsp;
         enum {
            _NONE,
            _DORICH  = 1<<0,  /* We are looking for rich parts */
            _HADPART = 1<<1,  /* Did print a part already */
            _NEEDNL  = 1<<3   /* Need a visual separator */
         } flags;
         struct n_sigman smalter;

         (curr = &outermost)->outer = NULL;
         curr->mp = ip;
         flags = ok_blook(mime_alternative_favour_rich) ? _DORICH : _NONE;
         if (!_send_al7ive_have_better(ip->m_multipart, action,
               ((flags & _DORICH) != 0)))
            flags ^= _DORICH;
         _send_al7ive_flag_tree(ip->m_multipart, action,
            ((flags & _DORICH) != 0));

         n_SIGMAN_ENTER_SWITCH(&smalter, n_SIGMAN_ALL) {
         case 0:
            break;
         default:
            rv = -1;
            goto jalter_leave;
         }

         for (np = ip->m_multipart;;) {
jalter_redo:
            for (; np != NULL; np = np->m_nextpart) {
               if (action != SEND_QUOTE && np->m_ct_type_plain != NULL) {
                  if (flags & _NEEDNL)
                     _out("\n", 1, obuf, CONV_NONE, SEND_MBOX, qf, stats,
                        NULL, NULL);
                  _print_part_info(obuf, np, doitp, level, qf, stats);
               }
               flags |= _NEEDNL;

               switch (np->m_mimecontent) {
               case MIME_ALTERNATIVE:
               case MIME_RELATED:
               case MIME_DIGEST:
               case MIME_SIGNED:
               case MIME_ENCRYPTED:
               case MIME_MULTI:
                  mpsp = n_autorec_alloc(sizeof *mpsp);
                  mpsp->outer = curr;
                  mpsp->mp = np->m_multipart;
                  curr->mp = np;
                  curr = mpsp;
                  np = mpsp->mp;
                  flags &= ~_NEEDNL;
                  goto jalter_redo;
               default:
                  if (!(np->m_flag & MDISPLAY))
                     break;
                  /* This thing we gonna do */
                  quoteflt_flush(qf);
                  if ((flags & _HADPART) && action == SEND_QUOTE)
                     /* XXX (void)*/a_send_out_nl(obuf, stats);
                  flags |= _HADPART;
                  flags &= ~_NEEDNL;
                  rv = sendpart(zmp, np, obuf, doitp, qf, action,
                        linedat, linesize, stats, level + 1);
                  quoteflt_reset(qf, origobuf);
                  if (rv < 0)
                     curr = &outermost; /* Cause overall loop termination */
                  break;
               }
            }

            mpsp = curr->outer;
            if (mpsp == NULL)
               break;
            curr = mpsp;
            np = curr->mp->m_nextpart;
         }
jalter_leave:
         n_sigman_leave(&smalter, n_SIGMAN_VIPSIGS_NTTYOUT);
         goto jleave;
      }
      /* FALLTHRU */
   case MIME_RELATED:
   case MIME_DIGEST:
   case MIME_SIGNED:
   case MIME_ENCRYPTED:
   case MIME_MULTI:
      switch (action) {
      case SEND_TODISP:
      case SEND_TODISP_ALL:
      case SEND_TODISP_PARTS:
      case SEND_QUOTE:
      case SEND_QUOTE_ALL:
      case SEND_TOFILE:
      case SEND_TOPIPE:
      case SEND_TOSRCH:
      case SEND_DECRYPT:
jmulti:
         if ((action == SEND_TODISP || action == SEND_TODISP_ALL) &&
             ip->m_multipart != NULL &&
             ip->m_multipart->m_mimecontent == MIME_DISCARD &&
             ip->m_multipart->m_nextpart == NULL) {
            char const *x = _("[Missing multipart boundary - use `show' "
                  "to display the raw message]\n");
            _out(x, su_cs_len(x), obuf, CONV_NONE, SEND_MBOX, qf, stats,
               NULL,NULL);
         }

         for (np = ip->m_multipart; np != NULL; np = np->m_nextpart) {
            boole volatile ispipe;

            if (np->m_mimecontent == MIME_DISCARD && action != SEND_DECRYPT)
               continue;

            ispipe = FAL0;
            switch (action) {
            case SEND_TOFILE:
               if (np->m_partstring &&
                     np->m_partstring[0] == '1' && np->m_partstring[1] == '\0')
                  break;
               stats = NULL;
               /* TODO Always open multipart on /dev/null, it's a hack to be
                * TODO able to dive into that structure, and still better
                * TODO than asking the user for something stupid.
                * TODO oh, wait, we did ask for a filename for this MIME mail,
                * TODO and that outer container is useless anyway ;-P */
               if(np->m_multipart != NULL && np->m_mimecontent != MIME_822) {
                  if((obuf = mx_fs_open(n_path_devnull, "w")) == NIL)
                     continue;
               }else if((obuf = newfile(np, &ispipe)) == NIL)
                  continue;
               if(ispipe){
                  oldpipe = safe_signal(SIGPIPE, &_send_onpipe);
                  if(sigsetjmp(_send_pipejmp, 1)){
                     rv = -1;
                     goto jpipe_close;
                  }
               }
               break;
            case SEND_TODISP:
            case SEND_TODISP_ALL:
               if (ip->m_mimecontent != MIME_ALTERNATIVE &&
                     ip->m_mimecontent != MIME_RELATED &&
                     ip->m_mimecontent != MIME_DIGEST &&
                     ip->m_mimecontent != MIME_SIGNED &&
                     ip->m_mimecontent != MIME_ENCRYPTED &&
                     ip->m_mimecontent != MIME_MULTI)
                  break;
               _print_part_info(obuf, np, doitp, level, qf, stats);
               break;
            case SEND_TODISP_PARTS:
            case SEND_QUOTE:
            case SEND_QUOTE_ALL:
            case SEND_MBOX:
            case SEND_RFC822:
            case SEND_SHOW:
            case SEND_TOSRCH:
            case SEND_DECRYPT:
            case SEND_TOPIPE:
               break;
            }

            quoteflt_flush(qf);
            if ((action == SEND_QUOTE || action == SEND_QUOTE_ALL) &&
                  np->m_multipart == NULL && ip->m_parent != NULL)
               /*XXX (void)*/a_send_out_nl(obuf, stats);
            if (sendpart(zmp, np, obuf, doitp, qf, action, linedat, linesize,
                  stats, level+1) < 0)
               rv = -1;
            quoteflt_reset(qf, origobuf);

            if (action == SEND_QUOTE) {
               if (ip->m_mimecontent != MIME_RELATED)
                  break;
            }
            if (action == SEND_TOFILE && obuf != origobuf) {
               if(!ispipe)
                  mx_fs_close(obuf);
               else {
jpipe_close:
                  mx_fs_pipe_close(obuf, TRU1);
                  safe_signal(SIGPIPE, oldpipe);
               }
            }
         }
         goto jleave;
      case SEND_MBOX:
      case SEND_RFC822:
      case SEND_SHOW:
         break;
      }
      break;
   }

   /* Copy out message body */
   if (doitp == n_IGNORE_ALL && level == 0) /* skip final blank line */
      --cnt;
   switch (ip->m_mime_enc) {
   case MIMEE_BIN:
   case MIMEE_7B:
   case MIMEE_8B:
      convert = CONV_NONE;
      break;
   case MIMEE_QP:
      convert = CONV_FROMQP;
      break;
   case MIMEE_B64:
      switch (ip->m_mimecontent) {
      case MIME_TEXT:
      case MIME_TEXT_PLAIN:
      case MIME_TEXT_HTML:
         convert = CONV_FROMB64_T;
         break;
      default:
         switch (mhp->mh_flags & MIME_HDL_TYPE_MASK) {
         case MIME_HDL_TEXT:
         case MIME_HDL_PTF:
            convert = CONV_FROMB64_T;
            break;
         default:
            convert = CONV_FROMB64;
            break;
         }
         break;
      }
      break;
   default:
      convert = CONV_NONE;
   }

   /* TODO Unless we have filters, ensure iconvd==-1 so that mime.c:fwrite_td()
    * TODO cannot mess things up misusing outrest as line buffer */
#ifdef mx_HAVE_ICONV
   if (iconvd != (iconv_t)-1) {
      n_iconv_close(iconvd);
      iconvd = (iconv_t)-1;
   }
#endif

   if (action == SEND_DECRYPT || action == SEND_MBOX ||
         action == SEND_RFC822 || action == SEND_SHOW)
      convert = CONV_NONE;
#ifdef mx_HAVE_ICONV
   else if ((action == SEND_TODISP || action == SEND_TODISP_ALL ||
            action == SEND_TODISP_PARTS ||
            action == SEND_QUOTE || action == SEND_QUOTE_ALL ||
            action == SEND_TOSRCH || action == SEND_TOFILE) &&
         (ip->m_mimecontent == MIME_TEXT_PLAIN ||
            ip->m_mimecontent == MIME_TEXT_HTML ||
            ip->m_mimecontent == MIME_TEXT ||
            (mhp->mh_flags & MIME_HDL_TYPE_MASK) == MIME_HDL_TEXT ||
            (mhp->mh_flags & MIME_HDL_TYPE_MASK) == MIME_HDL_PTF)) {
      char const *tcs;

      tcs = ok_vlook(ttycharset);
      if (su_cs_cmp_case(tcs, ip->m_charset) &&
            su_cs_cmp_case(ok_vlook(charset_7bit), ip->m_charset)) {
         iconvd = n_iconv_open(tcs, ip->m_charset);
         if (iconvd == (iconv_t)-1 && su_err_no() == su_ERR_INVAL) {
            n_err(_("Cannot convert from %s to %s\n"), ip->m_charset, tcs);
            /*rv = 1; goto jleave;*/
         }
      }
   }
#endif

   switch (mhp->mh_flags & MIME_HDL_TYPE_MASK) {
   case MIME_HDL_CMD:
      if(!(mhp->mh_flags & MIME_HDL_COPIOUSOUTPUT)){
         if(action != SEND_TODISP_PARTS)
            goto jmhp_default;
         /* Ach, what a hack!  We need filters.. v15! */
         if(convert != CONV_FROMB64_T)
            action = SEND_TOPIPE;
      }
      /* FALLTHRU */
   case MIME_HDL_PTF:
      tmpname = NULL;
      qbuf = obuf;

      term_infd = mx_CHILD_FD_PASS;
      if (mhp->mh_flags & (MIME_HDL_TMPF | MIME_HDL_NEEDSTERM)) {
         struct mx_fs_tmp_ctx *fstcp;
         enum mx_fs_oflags of;

         of = mx_FS_O_RDWR | mx_FS_O_REGISTER;
         if(!(mhp->mh_flags & MIME_HDL_TMPF)){
            term_infd = 0;
            mhp->mh_flags |= MIME_HDL_TMPF_FILL;
            of |= mx_FS_O_UNLINK;
         }else{
            /* (async and unlink are mutual exclusive) */
            if(mhp->mh_flags & MIME_HDL_TMPF_UNLINK)
               of |= mx_FS_O_REGISTER_UNLINK;
         }

         if((pbuf = mx_fs_tmp_open((mhp->mh_flags & MIME_HDL_TMPF_FILL
                     ? "mimehdlfill" : "mimehdl"), of,
               (mhp->mh_flags & MIME_HDL_TMPF ? &fstcp : NIL))) == NIL)
            goto jesend;

         if(mhp->mh_flags & MIME_HDL_TMPF)
            tmpname = fstcp->fstc_filename; /* In autorec storage! */

         if(mhp->mh_flags & MIME_HDL_TMPF_FILL){
            if(term_infd == 0)
               term_infd = fileno(pbuf);
            goto jsend;
         }
      }

jpipe_for_real:
      pbuf = _pipefile(mhp, ip, UNVOLATILE(FILE**,&qbuf), tmpname, term_infd);
      if (pbuf == NULL) {
jesend:
         pbuf = qbuf = NULL;
         rv = -1;
         goto jend;
      } else if ((mhp->mh_flags & MIME_HDL_NEEDSTERM) && pbuf == (FILE*)-1) {
         pbuf = qbuf = NULL;
         goto jend;
      }
      tmpname = NULL;
      action = SEND_TOPIPE;
      if (pbuf != qbuf) {
         oldpipe = safe_signal(SIGPIPE, &_send_onpipe);
         if (sigsetjmp(_send_pipejmp, 1))
            goto jend;
      }
      break;

   default:
jmhp_default:
      mhp->mh_flags = MIME_HDL_NULL;
      pbuf = qbuf = obuf;
      break;
   }

jsend:
   {
   boole volatile eof;
   boole save_qf_bypass = qf->qf_bypass;
   u64 *save_stats = stats;

   if (pbuf != origobuf) {
      qf->qf_bypass = TRU1;/* XXX legacy (remove filter instead) */
      stats = NULL;
   }
   eof = FAL0;
   outrest.s = inrest.s = NULL;
   outrest.l = inrest.l = 0;

   if (pbuf == qbuf) {
      __sendp_sig = 0;
      __sendp_opipe = safe_signal(SIGPIPE, &__sendp_onsig);
      if (sigsetjmp(__sendp_actjmp, 1)) {
         n_pstate &= ~n_PS_BASE64_STRIP_CR;/* (but protected by outer sigman) */
         if (outrest.s != NULL)
            n_free(outrest.s);
         if (inrest.s != NULL)
            n_free(inrest.s);
#ifdef mx_HAVE_ICONV
         if (iconvd != (iconv_t)-1)
            n_iconv_close(iconvd);
#endif
         safe_signal(SIGPIPE, __sendp_opipe);
         n_raise(__sendp_sig);
      }
   }

   quoteflt_reset(qf, pbuf);
   if((dostat & 4) && pbuf == origobuf) /* TODO */
      n_pstate |= n_PS_BASE64_STRIP_CR;
   while (!eof && fgetline(linedat, linesize, &cnt, &linelen, ibuf, 0)) {
joutln:
      if (_out(*linedat, linelen, pbuf, convert, action, qf, stats, &outrest,
            (action & _TD_EOF ? NULL : &inrest)) < 0 || ferror(pbuf)) {
         rv = -1; /* XXX Should bail away?! */
         break;
      }
   }
   if(eof <= FAL0 && rv >= 0 && (outrest.l != 0 || inrest.l != 0)){
      linelen = 0;
      if(eof || inrest.l == 0)
         action |= _TD_EOF;
      eof = eof ? TRU1 : TRUM1;
      goto joutln;
   }
   n_pstate &= ~n_PS_BASE64_STRIP_CR;
   action &= ~_TD_EOF;

   /* TODO HACK: when sending to the display we yet get fooled if a message
    * TODO doesn't end in a newline, because of our input/output 1:1.
    * TODO This should be handled automatically by a display filter, then */
   if(rv >= 0 && !qf->qf_nl_last &&
         (action == SEND_TODISP || action == SEND_TODISP_ALL ||
          action == SEND_QUOTE || action == SEND_QUOTE_ALL))
      rv = quoteflt_push(qf, "\n", 1);

   quoteflt_flush(qf);

   if (rv >= 0 && (mhp->mh_flags & MIME_HDL_TMPF_FILL)) {
      mhp->mh_flags &= ~MIME_HDL_TMPF_FILL;
      fflush(pbuf);
      really_rewind(pbuf);
      /* Don't fs_close() a tmp_open() thing due to FS_O_UNREGISTER_UNLINK++ */
      goto jpipe_for_real;
   }

   if (pbuf == qbuf)
      safe_signal(SIGPIPE, __sendp_opipe);

   if (outrest.s != NULL)
      n_free(outrest.s);
   if (inrest.s != NULL)
      n_free(inrest.s);

   if (pbuf != origobuf) {
      qf->qf_bypass = save_qf_bypass;
      stats = save_stats;
   }
   }

jend:
   if(pbuf != qbuf){
      mx_fs_pipe_close(pbuf, !(mhp->mh_flags & MIME_HDL_ASYNC));
      safe_signal(SIGPIPE, oldpipe);
      if (rv >= 0 && qbuf != NULL && qbuf != obuf)
         pipecpy(qbuf, obuf, origobuf, qf, stats);
   }

#ifdef mx_HAVE_ICONV
   if (iconvd != (iconv_t)-1)
      n_iconv_close(iconvd);
#endif

jleave:
   NYD_OU;
   return rv;
}

static boole
_send_al7ive_have_better(struct mimepart *mpp, enum sendaction action,
   boole want_rich)
{
   boole rv = FAL0;
   NYD_IN;

   for (; mpp != NULL; mpp = mpp->m_nextpart) {
      switch (mpp->m_mimecontent) {
      case MIME_TEXT_PLAIN:
         if (!want_rich)
            goto jflag;
         continue;
      case MIME_ALTERNATIVE:
      case MIME_RELATED:
      case MIME_DIGEST:
      case MIME_SIGNED:
      case MIME_ENCRYPTED:
      case MIME_MULTI:
         /* Be simple and recurse */
         if (_send_al7ive_have_better(mpp->m_multipart, action, want_rich))
            goto jleave;
         continue;
      default:
         break;
      }

      if (mpp->m_handler == NULL)
         n_mimetype_handler(mpp->m_handler =
            n_autorec_alloc(sizeof(*mpp->m_handler)), mpp, action);
      switch (mpp->m_handler->mh_flags & MIME_HDL_TYPE_MASK) {
      case MIME_HDL_TEXT:
         if (!want_rich)
            goto jflag;
         break;
      case MIME_HDL_PTF:
         if (want_rich) {
jflag:
            mpp->m_flag |= MDISPLAY;
            ASSERT(mpp->m_parent != NULL);
            mpp->m_parent->m_flag |= MDISPLAY;
            rv = TRU1;
         }
         break;
      case MIME_HDL_CMD:
         if (want_rich && (mpp->m_handler->mh_flags & MIME_HDL_COPIOUSOUTPUT))
            goto jflag;
         /* FALLTHRU */
      default:
         break;
      }
   }
jleave:
   NYD_OU;
   return rv;
}

static void
_send_al7ive_flag_tree(struct mimepart *mpp, enum sendaction action,
   boole want_rich)
{
   boole hot;
   NYD_IN;

   ASSERT(mpp->m_parent != NULL);
   hot = ((mpp->m_parent->m_flag & MDISPLAY) != 0);

   for (; mpp != NULL; mpp = mpp->m_nextpart) {
      switch (mpp->m_mimecontent) {
      case MIME_TEXT_PLAIN:
         if (hot && !want_rich)
            mpp->m_flag |= MDISPLAY;
         continue;
      case MIME_ALTERNATIVE:
      case MIME_RELATED:
      case MIME_DIGEST:
      case MIME_SIGNED:
      case MIME_ENCRYPTED:
      case MIME_MULTI:
         /* Be simple and recurse */
         if (_send_al7ive_have_better(mpp->m_multipart, action, want_rich))
            goto jleave;
         continue;
      default:
         break;
      }

      if (mpp->m_handler == NULL)
         n_mimetype_handler(mpp->m_handler =
            n_autorec_alloc(sizeof(*mpp->m_handler)), mpp, action);
      switch (mpp->m_handler->mh_flags & MIME_HDL_TYPE_MASK) {
      case MIME_HDL_TEXT:
         if (hot && !want_rich)
            mpp->m_flag |= MDISPLAY;
         break;
      case MIME_HDL_PTF:
         if (hot && want_rich)
            mpp->m_flag |= MDISPLAY;
         break;
      case MIME_HDL_CMD:
         if (hot && want_rich &&
               (mpp->m_handler->mh_flags & MIME_HDL_COPIOUSOUTPUT))
            mpp->m_flag |= MDISPLAY;
         break;
         break;
      default:
         break;
      }
   }
jleave:
   NYD_OU;
}

static FILE *
newfile(struct mimepart *ip, boole volatile *ispipe)
{
   struct str in, out;
   char *f;
   FILE *fp;
   NYD_IN;

   f = ip->m_filename;
   *ispipe = FAL0;

   if (f != NULL && f != (char*)-1) {
      in.s = f;
      in.l = su_cs_len(f);
      makeprint(&in, &out);
      out.l = delctrl(out.s, out.l);
      f = savestrbuf(out.s, out.l);
      n_free(out.s);
   }

   /* In interactive mode, let user perform all kind of expansions as desired,
    * and offer |SHELL-SPEC pipe targets, too */
   if (n_psonce & n_PSO_INTERACTIVE) {
      struct str prompt;
      struct n_string shou, *shoup;
      char *f2, *f3;

      shoup = n_string_creat_auto(&shou);

      /* TODO Generic function which asks for filename.
       * TODO If the current part is the first textpart the target
       * TODO is implicit from outer `write' etc! */
      /* I18N: Filename input prompt with file type indication */
      str_concat_csvl(&prompt, _("Enter filename for part "),
         (ip->m_partstring != NULL ? ip->m_partstring : n_qm),
         " (", ip->m_ct_type_plain, "): ", NULL);
jgetname:
      f2 = n_go_input_cp(n_GO_INPUT_CTX_DEFAULT | n_GO_INPUT_HIST_ADD,
            prompt.s, ((f != (char*)-1 && f != NULL)
               ? n_shexp_quote_cp(f, FAL0) : NULL));
      if(f2 != NULL){
         in.s = n_UNCONST(f2);
         in.l = UZ_MAX;
         if((n_shexp_parse_token((n_SHEXP_PARSE_TRUNC |
                  n_SHEXP_PARSE_TRIM_SPACE | n_SHEXP_PARSE_TRIM_IFSSPACE |
                  n_SHEXP_PARSE_LOG | n_SHEXP_PARSE_IGNORE_EMPTY),
                  shoup, &in, NULL
               ) & (n_SHEXP_STATE_STOP |
                  n_SHEXP_STATE_OUTPUT | n_SHEXP_STATE_ERR_MASK)
               ) != (n_SHEXP_STATE_STOP | n_SHEXP_STATE_OUTPUT))
            goto jgetname;
         f2 = n_string_cp(shoup);
      }
      if (f2 == NULL || *f2 == '\0') {
         if (n_poption & n_PO_D_V)
            n_err(_("... skipping this\n"));
         n_string_gut(shoup);
         fp = NULL;
         goto jleave;
      }

      if (*f2 == '|')
         /* Pipes are expanded by the shell */
         f = f2;
      else if ((f3 = fexpand(f2, FEXP_LOCAL | FEXP_NVAR)) == NULL)
         /* (Error message written by fexpand()) */
         goto jgetname;
      else
         f = f3;

      n_string_gut(shoup);
   }

   if (f == NULL || f == (char*)-1 || *f == '\0')
      fp = NULL;
   else if(n_psonce & n_PSO_INTERACTIVE){
      if(*f == '|'){
         fp = mx_fs_pipe_open(&f[1], "w", ok_vlook(SHELL), NIL, -1);
         if(!(*ispipe = (fp != NIL)))
            n_perr(f, 0);
      }else if((fp = mx_fs_open(f, "w")) == NIL)
         n_err(_("Cannot open %s\n"), n_shexp_quote_cp(f, FAL0));
   }else{
      /* Be very picky in non-interactive mode: actively disallow pipes,
       * prevent directory separators, and any filename member that would
       * become expanded by the shell if the name would be echo(1)ed */
      if(su_cs_first_of(f, "/" n_SHEXP_MAGIC_PATH_CHARS) != su_UZ_MAX){
         char c;

         for(out.s = n_autorec_alloc((su_cs_len(f) * 3) +1), out.l = 0;
               (c = *f++) != '\0';)
            if(su_cs_find_c("/" n_SHEXP_MAGIC_PATH_CHARS, c)){
               out.s[out.l++] = '%';
               n_c_to_hex_base16(&out.s[out.l], c);
               out.l += 2;
            }else
               out.s[out.l++] = c;
         out.s[out.l] = '\0';
         f = out.s;
      }

      /* Avoid overwriting of existing files */
      while((fp = mx_fs_open(f, "wx")) == NIL){
         int e;

         if((e = su_err_no()) != su_ERR_EXIST){
            n_err(_("Cannot open %s: %s\n"),
               n_shexp_quote_cp(f, FAL0), su_err_doc(e));
            break;
         }

         if(ip->m_partstring != NULL)
            f = savecatsep(f, '#', ip->m_partstring);
         else
            f = savecat(f, "#.");
      }
   }
jleave:
   NYD_OU;
   return fp;
}

static void
pipecpy(FILE *pipebuf, FILE *outbuf, FILE *origobuf, struct quoteflt *qf,
   u64 *stats)
{
   char *line;
   uz linesize, linelen, cnt;
   sz all_sz, i;
   NYD_IN;

   fflush(pipebuf);
   rewind(pipebuf);
   cnt = S(uz,fsize(pipebuf));
   all_sz = 0;

   mx_fs_linepool_aquire(&line, &linesize);
   quoteflt_reset(qf, outbuf);
   while(fgetline(&line, &linesize, &cnt, &linelen, pipebuf, 0) != NIL){
      if((i = quoteflt_push(qf, line, linelen)) < 0)
         break;
      all_sz += i;
   }
   if((i = quoteflt_flush(qf)) > 0)
      all_sz += i;
   mx_fs_linepool_release(line, linesize);

   if(all_sz > 0 && outbuf == origobuf && stats != NIL)
      *stats += all_sz;
   mx_fs_close(pipebuf);
   NYD_OU;
}

static void
statusput(const struct message *mp, FILE *obuf, struct quoteflt *qf,
   u64 *stats)
{
   char statout[3], *cp = statout;
   NYD_IN;

   if (mp->m_flag & MREAD)
      *cp++ = 'R';
   if (!(mp->m_flag & MNEW))
      *cp++ = 'O';
   *cp = 0;
   if (statout[0]) {
      int i = fprintf(obuf, "%.*sStatus: %s\n", (int)qf->qf_pfix_len,
            (qf->qf_bypass ? NULL : qf->qf_pfix), statout);
      if (i > 0 && stats != NULL)
         *stats += i;
   }
   NYD_OU;
}

static void
xstatusput(const struct message *mp, FILE *obuf, struct quoteflt *qf,
   u64 *stats)
{
   char xstatout[4];
   char *xp = xstatout;
   NYD_IN;

   if (mp->m_flag & MFLAGGED)
      *xp++ = 'F';
   if (mp->m_flag & MANSWERED)
      *xp++ = 'A';
   if (mp->m_flag & MDRAFTED)
      *xp++ = 'T';
   *xp = 0;
   if (xstatout[0]) {
      int i = fprintf(obuf, "%.*sX-Status: %s\n", (int)qf->qf_pfix_len,
            (qf->qf_bypass ? NULL : qf->qf_pfix), xstatout);
      if (i > 0 && stats != NULL)
         *stats += i;
   }
   NYD_OU;
}

static void
put_from_(FILE *fp, struct mimepart *ip, u64 *stats)
{
   char const *froma, *date, *nl;
   int i;
   NYD_IN;

   if (ip != NULL && ip->m_from != NULL) {
      froma = ip->m_from;
      date = n_time_ctime(ip->m_time, NULL);
      nl = "\n";
   } else {
      froma = ok_vlook(LOGNAME);
      date = time_current.tc_ctime;
      nl = n_empty;
   }

   mx_COLOUR(
      if(mx_COLOUR_IS_ACTIVE())
         mx_colour_put(mx_COLOUR_ID_VIEW_FROM_, NULL);
   )
   i = fprintf(fp, "From %s %s%s", froma, date, nl);
   mx_COLOUR(
      if(mx_COLOUR_IS_ACTIVE())
         mx_colour_reset();
   )
   if (i > 0 && stats != NULL)
      *stats += i;
   NYD_OU;
}

FL int
sendmp(struct message *mp, FILE *obuf, struct n_ignore const *doitp,
   char const *prefix, enum sendaction action, u64 *stats)
{
   struct n_sigman linedat_protect;
   struct quoteflt qf;
   FILE *ibuf;
   enum mime_parse_flags mpf;
   struct mimepart *ip;
   uz linesize, cnt, size, i;
   char *linedat;
   int rv, c;
   NYD_IN;

   time_current_update(&time_current, TRU1);
   rv = -1;
   linedat = NULL;
   linesize = 0;
   quoteflt_init(&qf, prefix, (prefix == NULL));

   n_SIGMAN_ENTER_SWITCH(&linedat_protect, n_SIGMAN_ALL){
   case 0:
      break;
   default:
      goto jleave;
   }

   if (mp == dot && action != SEND_TOSRCH)
      n_pstate |= n_PS_DID_PRINT_DOT;
   if (stats != NULL)
      *stats = 0;

   /* First line is the From_ line, so no headers there to worry about */
   if ((ibuf = setinput(&mb, mp, NEED_BODY)) == NULL)
      goto jleave;

   cnt = mp->m_size;
   size = 0;
   {
   boole nozap;
   char const *cpre = n_empty, *csuf = n_empty;

#ifdef mx_HAVE_COLOUR
   if(mx_COLOUR_IS_ACTIVE()){
      struct mx_colour_pen *cpen;
      struct str const *s;

      cpen = mx_colour_pen_create(mx_COLOUR_ID_VIEW_FROM_,NULL);
      if((s = mx_colour_pen_to_str(cpen)) != NIL){
         cpre = s->s;
         s = mx_colour_reset_to_str();
         if(s != NIL)
            csuf = s->s;
      }
   }
#endif

   nozap = (doitp != n_IGNORE_ALL && doitp != n_IGNORE_FWD &&
         action != SEND_RFC822 &&
         !n_ignore_is_ign(doitp, "from_", sizeof("from_") -1));
   if (mp->m_flag & (MNOFROM | MBADFROM_)) {
      if (nozap)
         size = fprintf(obuf, "%s%.*sFrom %s %s%s\n",
               cpre, (int)qf.qf_pfix_len,
               (qf.qf_bypass ? n_empty : qf.qf_pfix), fakefrom(mp),
               n_time_ctime(mp->m_time, NULL), csuf);
   } else if (nozap) {
      if (!qf.qf_bypass) {
         i = fwrite(qf.qf_pfix, sizeof *qf.qf_pfix, qf.qf_pfix_len, obuf);
         if (i != qf.qf_pfix_len)
            goto jleave;
         size += i;
      }
#ifdef mx_HAVE_COLOUR
      if(*cpre != '\0'){
         fputs(cpre, obuf);
         cpre = (char const*)0x1;
      }
#endif

      while (cnt > 0 && (c = getc(ibuf)) != EOF) {
#ifdef mx_HAVE_COLOUR
         if(c == '\n' && *csuf != '\0'){
            cpre = (char const*)0x1;
            fputs(csuf, obuf);
         }
#endif
         putc(c, obuf);
         ++size;
         --cnt;
         if (c == '\n')
            break;
      }

#ifdef mx_HAVE_COLOUR
      if(*csuf != '\0' && cpre != (char const*)0x1 && *cpre != '\0')
         fputs(csuf, obuf);
#endif
   } else {
      while (cnt > 0 && (c = getc(ibuf)) != EOF) {
         --cnt;
         if (c == '\n')
            break;
      }
   }
   }
   if (size > 0 && stats != NULL)
      *stats += size;

   mpf = MIME_PARSE_NONE;
   if (action != SEND_MBOX && action != SEND_RFC822 && action != SEND_SHOW)
      mpf |= MIME_PARSE_PARTS | MIME_PARSE_DECRYPT;
   if(action == SEND_TODISP || action == SEND_TODISP_ALL ||
         action == SEND_QUOTE || action == SEND_QUOTE_ALL)
      mpf |= MIME_PARSE_FOR_USER_CONTEXT;
   if ((ip = mime_parse_msg(mp, mpf)) == NULL)
      goto jleave;

   rv = sendpart(mp, ip, obuf, doitp, &qf, action, &linedat, &linesize,
         stats, 0);

   n_sigman_cleanup_ping(&linedat_protect);
jleave:
   n_pstate &= ~n_PS_BASE64_STRIP_CR;
   quoteflt_destroy(&qf);
   if(linedat != NULL)
      n_free(linedat);
   NYD_OU;
   n_sigman_leave(&linedat_protect, n_SIGMAN_VIPSIGS_NTTYOUT);
   return rv;
}

#include "su/code-ou.h"
/* s-it-mode */