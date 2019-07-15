/*@ S-nail - a mail user agent derived from Berkeley Mail.
 *@ URL parsing, credential handling and crypto hooks.
 *@ .netrc parser quite loosely based upon NetBSD usr.bin/ftp/
 *@   $NetBSD: ruserpass.c,v 1.33 2007/04/17 05:52:04 lukem Exp $
 *
 * Copyright (c) 2014 - 2019 Steffen (Daode) Nurpmeso <steffen@sdaoden.eu>.
 * SPDX-License-Identifier: ISC
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */
#undef su_FILE
#define su_FILE urlcrecry
#define mx_SOURCE

#ifndef mx_HAVE_AMALGAMATION
# include "mx/nail.h"
#endif

#include <su/cs.h>
#include <su/mem.h>

#ifdef mx_HAVE_NET
# include <su/icodec.h>
#endif

#include "mx/cred-auth.h"
#include "mx/cred-netrc.h"
#include "mx/file-streams.h"
#include "mx/ui-str.h"

/* TODO fake */
#include "su/code-in.h"

/* Find the last @ before a slash
 * TODO Casts off the const but this is ok here; obsolete function! */
#ifdef mx_HAVE_NET /* temporary (we'll have file://..) */
static char *           _url_last_at_before_slash(char const *cp);
#endif

#ifdef mx_HAVE_NET
static char *
_url_last_at_before_slash(char const *cp){
   char const *xcp;
   char c;
   NYD2_IN;

   for(xcp = cp; (c = *xcp) != '\0'; ++xcp)
      if(c == '/')
         break;
   while(xcp > cp && *--xcp != '@')
      ;
   if(*xcp != '@')
      xcp = NIL;
   NYD2_OU;
   return UNCONST(char*,xcp);
}
#endif

FL char *
(urlxenc)(char const *cp, boole ispath  su_DBG_LOC_ARGS_DECL)
{
   char *n, *np, c1;
   NYD2_IN;

   /* C99 */{
      uz i;

      i = su_cs_len(cp);
      if(i >= UZ_MAX / 3){
         n = NULL;
         goto jleave;
      }
      i *= 3;
      ++i;
      np = n = su_MEM_BAG_SELF_AUTO_ALLOC_LOCOR(i, su_DBG_LOC_ARGS_ORUSE);
   }

   for (; (c1 = *cp) != '\0'; ++cp) {
      /* (RFC 1738) RFC 3986, 2.3 Unreserved Characters:
       *    ALPHA / DIGIT / "-" / "." / "_" / "~"
       * However add a special is[file]path mode for file-system friendliness */
      if (su_cs_is_alnum(c1) || c1 == '_')
         *np++ = c1;
      else if (!ispath) {
         if (c1 != '-' && c1 != '.' && c1 != '~')
            goto jesc;
         *np++ = c1;
      } else if (PCMP(np, >, n) && (*cp == '-' || *cp == '.')) /* XXX imap */
         *np++ = c1;
      else {
jesc:
         np[0] = '%';
         n_c_to_hex_base16(np + 1, c1);
         np += 3;
      }
   }
   *np = '\0';
jleave:
   NYD2_OU;
   return n;
}

FL char *
(urlxdec)(char const *cp  su_DBG_LOC_ARGS_DECL)
{
   char *n, *np;
   s32 c;
   NYD2_IN;

   np = n = su_MEM_BAG_SELF_AUTO_ALLOC_LOCOR(su_cs_len(cp) +1,
         su_DBG_LOC_ARGS_ORUSE);

   while ((c = (uc)*cp++) != '\0') {
      if (c == '%' && cp[0] != '\0' && cp[1] != '\0') {
         s32 o = c;
         if (LIKELY((c = n_c_from_hex_base16(cp)) >= '\0'))
            cp += 2;
         else
            c = o;
      }
      *np++ = (char)c;
   }
   *np = '\0';
   NYD2_OU;
   return n;
}

FL int
c_urlcodec(void *vp){
   boole ispath;
   uz alen;
   char const **argv, *varname, *varres, *act, *cp;
   NYD_IN;

   argv = vp;
   varname = (n_pstate & n_PS_ARGMOD_VPUT) ? *argv++ : NULL;

   act = *argv;
   for(cp = act; *cp != '\0' && !su_cs_is_space(*cp); ++cp)
      ;
   if((ispath = (*act == 'p'))){
      if(!su_cs_cmp_case_n(++act, "ath", 3))
         act += 3;
   }
   if(act >= cp)
      goto jesynopsis;
   alen = P2UZ(cp - act);
   if(*cp != '\0')
      ++cp;

   n_pstate_err_no = su_ERR_NONE;

   if(su_cs_starts_with_case_n("encode", act, alen))
      varres = urlxenc(cp, ispath);
   else if(su_cs_starts_with_case_n("decode", act, alen))
      varres = urlxdec(cp);
   else
      goto jesynopsis;

   if(varres == NULL){
      n_pstate_err_no = su_ERR_CANCELED;
      varres = cp;
      vp = NULL;
   }

   if(varname != NULL){
      if(!n_var_vset(varname, (up)varres)){
         n_pstate_err_no = su_ERR_NOTSUP;
         cp = NULL;
      }
   }else{
      struct str in, out;

      in.l = su_cs_len(in.s = n_UNCONST(varres));
      makeprint(&in, &out);
      if(fprintf(n_stdout, "%s\n", out.s) < 0){
         n_pstate_err_no = su_err_no();
         vp = NULL;
      }
      n_free(out.s);
   }

jleave:
   NYD_OU;
   return (vp != NULL ? 0 : 1);
jesynopsis:
   n_err(_("Synopsis: urlcodec: "
      "<[path]e[ncode]|[path]d[ecode]> <rest-of-line>\n"));
   n_pstate_err_no = su_ERR_INVAL;
   vp = NULL;
   goto jleave;
}

FL int
c_urlencode(void *v) /* XXX IDNA?? */
{
   char **ap;
   NYD_IN;

   n_OBSOLETE("`urlencode': please use `urlcodec enc[ode]' instead");

   for (ap = v; *ap != NULL; ++ap) {
      char *in = *ap, *out = urlxenc(in, FAL0);

      if(out == NULL)
         out = n_UNCONST(V_(n_error));
      fprintf(n_stdout,
         " in: <%s> (%" PRIuZ " bytes)\nout: <%s> (%" PRIuZ " bytes)\n",
         in, su_cs_len(in), out, su_cs_len(out));
   }
   NYD_OU;
   return 0;
}

FL int
c_urldecode(void *v) /* XXX IDNA?? */
{
   char **ap;
   NYD_IN;

   n_OBSOLETE("`urldecode': please use `urlcodec dec[ode]' instead");

   for (ap = v; *ap != NULL; ++ap) {
      char *in = *ap, *out = urlxdec(in);

      if(out == NULL)
         out = n_UNCONST(V_(n_error));
      fprintf(n_stdout,
         " in: <%s> (%" PRIuZ " bytes)\nout: <%s> (%" PRIuZ " bytes)\n",
         in, su_cs_len(in), out, su_cs_len(out));
   }
   NYD_OU;
   return 0;
}

FL char *
url_mailto_to_address(char const *mailtop){ /* TODO hack! RFC 6068; factory? */
   uz i;
   char *rv;
   char const *mailtop_orig;
   NYD_IN;

   if(!su_cs_starts_with(mailtop_orig = mailtop, "mailto:")){
      rv = NULL;
      goto jleave;
   }
   mailtop += sizeof("mailto:") -1;

   /* TODO This is all intermediate, and for now just enough to understand
    * TODO a little bit of a little more advanced List-Post: headers. */
   /* Strip any hfield additions, keep only to addr-spec's */
   if((rv = su_cs_find_c(mailtop, '?')) != NULL)
      rv = savestrbuf(mailtop, i = P2UZ(rv - mailtop));
   else
      rv = savestrbuf(mailtop, i = su_cs_len(mailtop));

   i = su_cs_len(rv);

   /* Simply perform percent-decoding if there is a percent % */
   if(su_mem_find(rv, '%', i) != NULL){
      char *rv_base;
      boole err;

      for(err = FAL0, mailtop = rv_base = rv; i > 0;){
         char c;

         if((c = *mailtop++) == '%'){
            s32 cc;

            if(i < 3 || (cc = n_c_from_hex_base16(mailtop)) < 0){
               if(!err && (err = TRU1, n_poption & n_PO_D_V))
                  n_err(_("Invalid RFC 6068 'mailto' URL: %s\n"),
                     n_shexp_quote_cp(mailtop_orig, FAL0));
               goto jhex_putc;
            }
            *rv++ = (char)cc;
            mailtop += 2;
            i -= 3;
         }else{
jhex_putc:
            *rv++ = c;
            --i;
         }
      }
      *rv = '\0';
      rv = rv_base;
   }
jleave:
   NYD_OU;
   return rv;
}

FL char const *
n_servbyname(char const *proto, u16 *port_or_nil, boole *issnd_or_nil){
   static struct{
      char const name[14];
      char const port[7];
      boole issnd;
      u16 portno;
   } const tbl[] = {
      { "smtp", "25", TRU1, 25},
      { "smtps", "465", TRU1, 465},
      { "submission", "587", TRU1, 587},
      { "submissions", "465", TRU1, 465},
      { "pop3", "110", FAL0, 110},
      { "pop3s", "995", FAL0, 995},
      { "imap", "143", FAL0, 143},
      { "imaps", "993", FAL0, 993},
      { "file", "", TRU1, 0},
      { "test", "", TRU1, U16_MAX}
   };
   char const *rv;
   uz l, i;
   NYD2_IN;

   for(rv = proto; *rv != '\0'; ++rv)
      if(*rv == ':')
         break;
   l = P2UZ(rv - proto);

   for(rv = NIL, i = 0; i < NELEM(tbl); ++i)
      if(!su_cs_cmp_case_n(tbl[i].name, proto, l)){
         rv = tbl[i].port;
         if(port_or_nil != NIL)
            *port_or_nil = tbl[i].portno;
         if(issnd_or_nil != NIL)
            *issnd_or_nil = tbl[i].issnd;
         break;
      }
   NYD2_OU;
   return rv;
}

#ifdef mx_HAVE_NET /* Note: not indented for that -- later: file:// etc.! */
FL boole
url_parse(struct url *urlp, enum cproto cproto, char const *data)
{
#if defined mx_HAVE_SMTP && defined mx_HAVE_POP3 && defined mx_HAVE_IMAP
# define a_ALLPROTO
#endif
#if defined mx_HAVE_SMTP || defined mx_HAVE_POP3 || defined mx_HAVE_IMAP || \
      defined mx_HAVE_TLS
# define a_ANYPROTO
   char *cp, *x;
#endif
   boole rv = FAL0;
   NYD_IN;
   UNUSED(data);

   su_mem_set(urlp, 0, sizeof *urlp);
   urlp->url_input = data;
   urlp->url_cproto = cproto;

   /* Network protocol */
#define a_PROTOX(X,Y,Z) \
   urlp->url_portno = Y;\
   su_mem_copy(urlp->url_proto, X "://\0", sizeof(X "://\0"));\
   urlp->url_proto[sizeof(X) -1] = '\0';\
   urlp->url_proto_len = sizeof(X) -1;\
   do{ Z; }while(0)
#define a_PRIVPROTOX(X,Y,Z) \
   do{ a_PROTOX(X, Y, Z); }while(0)
#define a__IF(X,Y,Z)  \
   if(!su_cs_cmp_case_n(data, X "://", sizeof(X "://") -1)){\
      a_PROTOX(X, Y, Z);\
      data += sizeof(X "://") -1;\
      goto juser;\
   }
#define a_IF(X,Y) a__IF(X, Y, (void)0)
#ifdef mx_HAVE_TLS
# define a_IFS(X,Y) a__IF(X, Y, urlp->url_flags |= n_URL_TLS_REQUIRED)
# define a_IFs(X,Y) a__IF(X, Y, urlp->url_flags |= n_URL_TLS_OPTIONAL)
#else
# define a_IFS(X,Y) goto jeproto;
# define a_IFs(X,Y) a_IF(X, Y)
#endif

   switch(cproto){
   case CPROTO_CERTINFO:
      /* The special `tls' certificate info protocol
       * We do allow all protos here, for later getaddrinfo() usage! */
#ifdef mx_HAVE_TLS
      if((cp = su_cs_find(data, "://")) == NULL)
         a_PRIVPROTOX("https", 443, urlp->url_flags |= n_URL_TLS_REQUIRED);
      else{
         uz i;

         if((i = P2UZ(&cp[sizeof("://") -1] - data)) + 2 >=
               sizeof(urlp->url_proto))
            goto jeproto;
         su_mem_copy(urlp->url_proto, data, i);
         data += i;
         i -= sizeof("://") -1;
         urlp->url_proto[i] = '\0';\
         urlp->url_proto_len = i;
         urlp->url_flags |= n_URL_TLS_REQUIRED;
      }
      break;
#else
      goto jeproto;
#endif
   case CPROTO_CCRED:
      /* The special S/MIME etc. credential lookup TODO TLS client cert! */
#ifdef mx_HAVE_TLS
      a_PRIVPROTOX("ccred", 0, (void)0);
      break;
#else
      goto jeproto;
#endif
   case CPROTO_SOCKS:
      a_IF("socks5", 1080);
      a_IF("socks", 1080);
      a_PROTOX("socks", 1080, (void)0);
      break;
   case CPROTO_SMTP:
#ifdef mx_HAVE_SMTP
      a_IFS("smtps", 465)
      a_IFs("smtp", 25)
      a_IFs("submission", 587)
      a_IFS("submissions", 465)
      a_PROTOX("smtp", 25, urlp->url_flags |= n_URL_TLS_OPTIONAL);
      break;
#else
      goto jeproto;
#endif
   case CPROTO_POP3:
#ifdef mx_HAVE_POP3
      a_IFS("pop3s", 995)
      a_IFs("pop3", 110)
      a_PROTOX("pop3", 110, urlp->url_flags |= n_URL_TLS_OPTIONAL);
      break;
#else
      goto jeproto;
#endif
#ifdef mx_HAVE_IMAP
   case CPROTO_IMAP:
      a_IFS("imaps", 993)
      a_IFs("imap", 143)
      a_PROTOX("imap", 143, urlp->url_flags |= n_URL_TLS_OPTIONAL);
      break;
#else
      goto jeproto;
#endif
   }

#undef a_PRIVPROTOX
#undef a_PROTOX
#undef a__IF
#undef a_IF
#undef a_IFS
#undef a_IFs

   if (su_cs_find(data, "://") != NULL) {
jeproto:
      n_err(_("URL proto:// invalid (protocol or TLS support missing?): %s\n"),
         urlp->url_input);
      goto jleave;
   }
#ifdef a_ANYPROTO

   /* User and password, I */
juser:
   if ((cp = _url_last_at_before_slash(data)) != NULL) {
      uz l;
      char const *urlpe, *d;
      char *ub;

      l = P2UZ(cp - data);
      ub = n_lofi_alloc(l +1);
      d = data;
      urlp->url_flags |= n_URL_HAD_USER;
      data = &cp[1];

      /* And also have a password? */
      if((cp = su_mem_find(d, ':', l)) != NULL){
         uz i = P2UZ(cp - d);

         l -= i + 1;
         su_mem_copy(ub, cp + 1, l);
         ub[l] = '\0';

         if((urlp->url_pass.s = urlxdec(ub)) == NULL)
            goto jurlp_err;
         urlp->url_pass.l = su_cs_len(urlp->url_pass.s);
         if((urlpe = urlxenc(urlp->url_pass.s, FAL0)) == NULL)
            goto jurlp_err;
         if(su_cs_cmp(ub, urlpe))
            goto jurlp_err;
         l = i;
      }

      su_mem_copy(ub, d, l);
      ub[l] = '\0';
      if((urlp->url_user.s = urlxdec(ub)) == NULL)
         goto jurlp_err;
      urlp->url_user.l = su_cs_len(urlp->url_user.s);
      if((urlp->url_user_enc.s = urlxenc(urlp->url_user.s, FAL0)) == NULL)
         goto jurlp_err;
      urlp->url_user_enc.l = su_cs_len(urlp->url_user_enc.s);

      if(urlp->url_user_enc.l != l || su_mem_cmp(urlp->url_user_enc.s, ub, l)){
jurlp_err:
         n_err(_("String is not properly URL percent encoded: %s\n"), ub);
         d = NULL;
      }

      n_lofi_free(ub);
      if(d == NULL)
         goto jleave;
   }

   /* Servername and port -- and possible path suffix */
   if ((cp = su_cs_find_c(data, ':')) != NULL) { /* TODO URL: use IPAddress! */
      urlp->url_port = x = savestr(x = &cp[1]);
      if ((x = su_cs_find_c(x, '/')) != NULL) {
         *x = '\0';
         while(*++x == '/')
            ;
      }

      if((su_idec_u16_cp(&urlp->url_portno, urlp->url_port, 10, NULL
               ) & (su_IDEC_STATE_EMASK | su_IDEC_STATE_CONSUMED)
            ) != su_IDEC_STATE_CONSUMED || urlp->url_portno == 0){
         n_err(_("URL with invalid port number: %s\n"), urlp->url_input);
         goto jleave;
      }
   } else {
      if ((x = su_cs_find_c(data, '/')) != NULL) {
         data = savestrbuf(data, P2UZ(x - data));
         while(*++x == '/')
            ;
      }
      cp = n_UNCONST(data + su_cs_len(data));
   }

   /* A (non-empty) path may only occur with IMAP */
   if (x != NULL && *x != '\0') {
      /* Take care not to count adjacent solidus for real, on either end */
      char *x2;
      uz i;
      boole trailsol;

      for(trailsol = FAL0, x2 = savestrbuf(x, i = su_cs_len(x)); i > 0;
            trailsol = TRU1, --i)
         if(x2[i - 1] != '/')
            break;
      x2[i] = '\0';

      if (i > 0) {
         if (cproto != CPROTO_IMAP) {
            n_err(_("URL protocol doesn't support paths: \"%s\"\n"),
               urlp->url_input);
            goto jleave;
         }
# ifdef mx_HAVE_IMAP
         if(trailsol){
            urlp->url_path.s = n_autorec_alloc(i + sizeof("/INBOX"));
            su_mem_copy(urlp->url_path.s, x, i);
            su_mem_copy(&urlp->url_path.s[i], "/INBOX", sizeof("/INBOX"));
            urlp->url_path.l = (i += sizeof("/INBOX") -1);
         }else
# endif
            urlp->url_path.l = i, urlp->url_path.s = x2;
      }
   }
# ifdef mx_HAVE_IMAP
   if(cproto == CPROTO_IMAP && urlp->url_path.s == NULL)
      urlp->url_path.s = savestrbuf("INBOX",
            urlp->url_path.l = sizeof("INBOX") -1);
# endif

   urlp->url_host.s = savestrbuf(data, urlp->url_host.l = P2UZ(cp - data));
   {  uz i;
      for (cp = urlp->url_host.s, i = urlp->url_host.l; i != 0; ++cp, --i)
         *cp = su_cs_to_lower(*cp);
   }
# ifdef mx_HAVE_IDNA
   if(!ok_blook(idna_disable)){
      struct n_string idna;

      if(!n_idna_to_ascii(n_string_creat_auto(&idna), urlp->url_host.s,
               urlp->url_host.l)){
         n_err(_("URL host fails IDNA conversion: %s\n"), urlp->url_input);
         goto jleave;
      }
      urlp->url_host.s = n_string_cp(&idna);
      urlp->url_host.l = idna.s_len;
   }
# endif /* mx_HAVE_IDNA */

   /* .url_h_p: HOST:PORT */
   {  uz upl, i;
      struct str *s = &urlp->url_h_p;

      upl = (urlp->url_port == NULL) ? 0 : 1u + su_cs_len(urlp->url_port);
      s->s = n_autorec_alloc(urlp->url_host.l + upl +1);
      su_mem_copy(s->s, urlp->url_host.s, i = urlp->url_host.l);
      if(upl > 0){
         s->s[i++] = ':';
         su_mem_copy(&s->s[i], urlp->url_port, --upl);
         i += upl;
      }
      s->s[s->l = i] = '\0';
   }

   /* User, II
    * If there was no user in the URL, do we have *user-HOST* or *user*? */
   if (!(urlp->url_flags & n_URL_HAD_USER)) {
      if ((urlp->url_user.s = xok_vlook(user, urlp, OXM_PLAIN | OXM_H_P))
            == NULL) {
         /* No, check whether .netrc lookup is desired */
# ifdef mx_HAVE_NETRC
         if (ok_vlook(v15_compat) == su_NIL ||
               !xok_blook(netrc_lookup, urlp, OXM_PLAIN | OXM_H_P) ||
               !mx_netrc_lookup(urlp, FAL0))
# endif
            urlp->url_user.s = n_UNCONST(ok_vlook(LOGNAME));
      }

      urlp->url_user.l = su_cs_len(urlp->url_user.s);
      urlp->url_user.s = savestrbuf(urlp->url_user.s, urlp->url_user.l);
      if((urlp->url_user_enc.s = urlxenc(urlp->url_user.s, FAL0)) == NULL){
         n_err(_("Cannot URL encode %s\n"), urlp->url_user.s);
         goto jleave;
      }
      urlp->url_user_enc.l = su_cs_len(urlp->url_user_enc.s);
   }

   /* And then there are a lot of prebuild string combinations TODO do lazy */

   /* .url_u_h: .url_user@.url_host
    * For SMTP we apply ridiculously complicated *v15-compat* plus
    * *smtp-hostname* / *hostname* dependent rules */
   {  struct str h, *s;
      uz i;

      if (cproto == CPROTO_SMTP && ok_vlook(v15_compat) != su_NIL &&
            (cp = ok_vlook(smtp_hostname)) != NULL) {
         if (*cp == '\0')
            cp = n_nodename(TRU1);
         h.s = savestrbuf(cp, h.l = su_cs_len(cp));
      } else
         h = urlp->url_host;

      s = &urlp->url_u_h;
      i = urlp->url_user.l;

      s->s = n_autorec_alloc(i + 1 + h.l +1);
      if (i > 0) {
         su_mem_copy(s->s, urlp->url_user.s, i);
         s->s[i++] = '@';
      }
      su_mem_copy(s->s + i, h.s, h.l +1);
      i += h.l;
      s->l = i;
   }

   /* .url_u_h_p: .url_user@.url_host[:.url_port] */
   {  struct str *s = &urlp->url_u_h_p;
      uz i = urlp->url_user.l;

      s->s = n_autorec_alloc(i + 1 + urlp->url_h_p.l +1);
      if (i > 0) {
         su_mem_copy(s->s, urlp->url_user.s, i);
         s->s[i++] = '@';
      }
      su_mem_copy(s->s + i, urlp->url_h_p.s, urlp->url_h_p.l +1);
      i += urlp->url_h_p.l;
      s->l = i;
   }

   /* .url_eu_h_p: .url_user_enc@.url_host[:.url_port] */
   {  struct str *s = &urlp->url_eu_h_p;
      uz i = urlp->url_user_enc.l;

      s->s = n_autorec_alloc(i + 1 + urlp->url_h_p.l +1);
      if (i > 0) {
         su_mem_copy(s->s, urlp->url_user_enc.s, i);
         s->s[i++] = '@';
      }
      su_mem_copy(s->s + i, urlp->url_h_p.s, urlp->url_h_p.l +1);
      i += urlp->url_h_p.l;
      s->l = i;
   }

   /* .url_p_u_h_p: .url_proto://.url_u_h_p */
   {  uz i;
      char *ud;

      ud = n_autorec_alloc((i = urlp->url_proto_len + sizeof("://") -1 +
            urlp->url_u_h_p.l) +1);
      urlp->url_proto[urlp->url_proto_len] = ':';
      su_mem_copy(su_cs_pcopy(ud, urlp->url_proto), urlp->url_u_h_p.s,
         urlp->url_u_h_p.l +1);
      urlp->url_proto[urlp->url_proto_len] = '\0';

      urlp->url_p_u_h_p = ud;
   }

   /* .url_p_eu_h_p, .url_p_eu_h_p_p: .url_proto://.url_eu_h_p[/.url_path] */
   {  uz i;
      char *ud;

      ud = n_autorec_alloc((i = urlp->url_proto_len + sizeof("://") -1 +
            urlp->url_eu_h_p.l) + 1 + urlp->url_path.l +1);
      urlp->url_proto[urlp->url_proto_len] = ':';
      su_mem_copy(su_cs_pcopy(ud, urlp->url_proto), urlp->url_eu_h_p.s,
         urlp->url_eu_h_p.l +1);
      urlp->url_proto[urlp->url_proto_len] = '\0';

      if (urlp->url_path.l == 0)
         urlp->url_p_eu_h_p = urlp->url_p_eu_h_p_p = ud;
      else {
         urlp->url_p_eu_h_p = savestrbuf(ud, i);
         urlp->url_p_eu_h_p_p = ud;
         ud += i;
         *ud++ = '/';
         su_mem_copy(ud, urlp->url_path.s, urlp->url_path.l +1);
      }
   }

   rv = TRU1;
#endif /* a_ANYPROTO */
jleave:
   NYD_OU;
   return rv;
#undef a_ANYPROTO
#undef a_ALLPROTO
}
#endif /* mx_HAVE_NET */

#include "su/code-ou.h"
/* s-it-mode */
