/*@ S-nail - a mail user agent derived from Berkeley Mail.
 *@ String support routines.
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
#define su_FILE strings
#define mx_SOURCE

#ifndef mx_HAVE_AMALGAMATION
# include "mx/nail.h"
#endif

#ifdef mx_HAVE_C90AMEND1
# include <wctype.h>
#endif

#include <su/cs.h>

FL char *
(savestr)(char const *str  su_DBG_LOC_ARGS_DECL)
{
   size_t size;
   char *news;
   n_NYD_IN;

   size = su_cs_len(str);
   news = su_MEM_BAG_SELF_AUTO_ALLOC_LOCOR(size +1,  su_DBG_LOC_ARGS_ORUSE);
   if(size > 0)
      su_mem_copy(news, str, size);
   news[size] = '\0';
   n_NYD_OU;
   return news;
}

FL char *
(savestrbuf)(char const *sbuf, size_t sbuf_len  su_DBG_LOC_ARGS_DECL)
{
   char *news;
   n_NYD_IN;

   news = su_MEM_BAG_SELF_AUTO_ALLOC_LOCOR(sbuf_len +1, su_DBG_LOC_ARGS_ORUSE);
   if(sbuf_len > 0)
      su_mem_copy(news, sbuf, sbuf_len);
   news[sbuf_len] = 0;
   n_NYD_OU;
   return news;
}

FL char *
(savecatsep)(char const *s1, char sep, char const *s2  su_DBG_LOC_ARGS_DECL)
{
   size_t l1, l2;
   char *news;
   n_NYD_IN;

   l1 = (s1 != NULL) ? su_cs_len(s1) : 0;
   l2 = su_cs_len(s2);
   news = su_MEM_BAG_SELF_AUTO_ALLOC_LOCOR(l1 + (sep != '\0') + l2 +1,
         su_DBG_LOC_ARGS_ORUSE);
   if (l1 > 0) {
      su_mem_copy(news + 0, s1, l1);
      if (sep != '\0')
         news[l1++] = sep;
   }
   if(l2 > 0)
      su_mem_copy(news + l1, s2, l2);
   news[l1 + l2] = '\0';
   n_NYD_OU;
   return news;
}

/*
 * Support routines, auto-reclaimed storage
 */

FL struct str *
str_concat_csvl(struct str *self, ...) /* XXX onepass maybe better here */
{
   va_list vl;
   size_t l;
   char const *cs;
   n_NYD_IN;

   va_start(vl, self);
   for (l = 0; (cs = va_arg(vl, char const*)) != NULL;)
      l += su_cs_len(cs);
   va_end(vl);

   self->l = l;
   self->s = n_autorec_alloc(l +1);

   va_start(vl, self);
   for (l = 0; (cs = va_arg(vl, char const*)) != NULL;) {
      size_t i;

      i = su_cs_len(cs);
      if(i > 0){
         su_mem_copy(self->s + l, cs, i);
         l += i;
      }
   }
   self->s[l] = '\0';
   va_end(vl);
   n_NYD_OU;
   return self;
}

FL struct str *
(str_concat_cpa)(struct str *self, char const * const *cpa,
   char const *sep_o_null  su_DBG_LOC_ARGS_DECL)
{
   size_t sonl, l;
   char const * const *xcpa;
   n_NYD_IN;

   sonl = (sep_o_null != NULL) ? su_cs_len(sep_o_null) : 0;

   for (l = 0, xcpa = cpa; *xcpa != NULL; ++xcpa)
      l += su_cs_len(*xcpa) + sonl;

   self->l = l;
   self->s = su_MEM_BAG_SELF_AUTO_ALLOC_LOCOR(l +1, su_DBG_LOC_ARGS_ORUSE);

   for (l = 0, xcpa = cpa; *xcpa != NULL; ++xcpa) {
      size_t i;

      i = su_cs_len(*xcpa);
      if(i > 0){
         su_mem_copy(self->s + l, *xcpa, i);
         l += i;
      }
      if (sonl > 0) {
         su_mem_copy(self->s + l, sep_o_null, sonl);
         l += sonl;
      }
   }
   self->s[l] = '\0';
   n_NYD_OU;
   return self;
}

/*
 * Routines that are not related to auto-reclaimed storage follow.
 */

FL char *
string_quote(char const *v) /* TODO too simpleminded (getrawlist(), +++ ..) */
{
   char const *cp;
   size_t i;
   char c, *rv;
   n_NYD2_IN;

   for (i = 0, cp = v; (c = *cp) != '\0'; ++i, ++cp)
      if (c == '"' || c == '\\')
         ++i;
   rv = n_autorec_alloc(i +1);

   for (i = 0, cp = v; (c = *cp) != '\0'; rv[i++] = c, ++cp)
      if (c == '"' || c == '\\')
         rv[i++] = '\\';
   rv[i] = '\0';
   n_NYD2_OU;
   return rv;
}

FL void
makelow(char *cp) /* TODO isn't that crap? --> */
{
      n_NYD_IN;
#ifdef mx_HAVE_C90AMEND1
   if (n_mb_cur_max > 1) {
      char *tp = cp;
      wchar_t wc;
      int len;

      while (*cp != '\0') {
         len = mbtowc(&wc, cp, n_mb_cur_max);
         if (len < 0)
            *tp++ = *cp++;
         else {
            wc = towlower(wc);
            if (wctomb(tp, wc) == len)
               tp += len, cp += len;
            else
               *tp++ = *cp++; /* <-- at least here */
         }
      }
   } else
#endif
          for(;; ++cp){
      char c;

      *cp = su_cs_to_lower(c = *cp);
      if(c == '\0')
         break;
   }
   n_NYD_OU;
}

FL bool_t
substr(char const *str, char const *sub)
{
   char const *cp, *backup;
   n_NYD_IN;

   cp = sub;
   backup = str;
   while (*str != '\0' && *cp != '\0') {
#ifdef mx_HAVE_C90AMEND1
      if (n_mb_cur_max > 1) {
         wchar_t c, c2;
         int sz;

         if ((sz = mbtowc(&c, cp, n_mb_cur_max)) == -1)
            goto Jsinglebyte;
         cp += sz;
         if ((sz = mbtowc(&c2, str, n_mb_cur_max)) == -1)
            goto Jsinglebyte;
         str += sz;
         c = towupper(c);
         c2 = towupper(c2);
         if (c != c2) {
            if ((sz = mbtowc(&c, backup, n_mb_cur_max)) > 0) {
               backup += sz;
               str = backup;
            } else
               str = ++backup;
            cp = sub;
         }
      } else
Jsinglebyte:
#endif
      {
         int c, c2;

         c = *cp++ & 0377;
         c = su_cs_to_upper(c);
         c2 = *str++ & 0377;
         c2 = su_cs_to_upper(c2);
         if (c != c2) {
            str = ++backup;
            cp = sub;
         }
      }
   }
   n_NYD_OU;
   return (*cp == '\0');
}

FL struct str *
(n_str_assign_buf)(struct str *self, char const *buf, uiz_t buflen
      su_DBG_LOC_ARGS_DECL){
   n_NYD_IN;
   if(buflen == UIZ_MAX)
      buflen = (buf == NULL) ? 0 : su_cs_len(buf);

   assert(buflen == 0 || buf != NULL);

   if(n_LIKELY(buflen > 0)){
      self->s = su_MEM_REALLOC_LOCOR(self->s, (self->l = buflen) +1,
            su_DBG_LOC_ARGS_ORUSE);
      su_mem_copy(self->s, buf, buflen);
      self->s[buflen] = '\0';
   }else
      self->l = 0;
   n_NYD_OU;
   return self;
}

FL struct str *
(n_str_add_buf)(struct str *self, char const *buf, uiz_t buflen
      su_DBG_LOC_ARGS_DECL){
   n_NYD_IN;
   if(buflen == UIZ_MAX)
      buflen = (buf == NULL) ? 0 : su_cs_len(buf);

   assert(buflen == 0 || buf != NULL);

   if(buflen > 0) {
      size_t osl = self->l, nsl = osl + buflen;

      self->s = su_MEM_REALLOC_LOCOR(self->s, (self->l = nsl) +1,
            su_DBG_LOC_ARGS_ORUSE);
      su_mem_copy(self->s + osl, buf, buflen);
      self->s[nsl] = '\0';
   }
   n_NYD_OU;
   return self;
}

FL struct str *
n_str_trim(struct str *self, enum n_str_trim_flags stf){
   size_t l;
   char const *cp;
   n_NYD2_IN;

   cp = self->s;

   if((l = self->l) > 0 && (stf & n_STR_TRIM_FRONT)){
      while(su_cs_is_space(*cp)){
         ++cp;
         if(--l == 0)
            break;
      }
      self->s = n_UNCONST(cp);
   }

   if(l > 0 && (stf & n_STR_TRIM_END)){
      for(cp += l -1; su_cs_is_space(*cp); --cp)
         if(--l == 0)
            break;
   }
   self->l = l;

   n_NYD2_OU;
   return self;
}

FL struct str *
n_str_trim_ifs(struct str *self, bool_t dodefaults){
   char s, t, n, c;
   char const *ifs, *cp;
   size_t l, i;
   n_NYD2_IN;

   if((l = self->l) == 0)
      goto jleave;

   ifs = ok_vlook(ifs_ws);
   cp = self->s;
   s = t = n = '\0';

   /* Check whether we can go fast(er) path */
   for(i = 0; (c = ifs[i]) != '\0'; ++i){
      switch(c){
      case ' ': s = c; break;
      case '\t': t = c; break;
      case '\n': n = c; break;
      default:
         /* Need to go the slow path */
         while(su_cs_find_c(ifs, *cp) != NULL){
            ++cp;
            if(--l == 0)
               break;
         }
         self->s = n_UNCONST(cp);

         if(l > 0){
            for(cp += l -1; su_cs_find_c(ifs, *cp) != NULL;){
               if(--l == 0)
                  break;
               /* An uneven number of reverse solidus escapes last WS! */
               else if(*--cp == '\\'){
                  siz_t j;

                  for(j = 1; l - (uiz_t)j > 0 && cp[-j] == '\\'; ++j)
                     ;
                  if(j & 1){
                     ++l;
                     break;
                  }
               }
            }
         }
         self->l = l;

         if(!dodefaults)
            goto jleave;
         cp = self->s;
         ++i;
         break;
      }
   }

   /* No ifs-ws?  No more data?  No trimming */
   if(l == 0 || (i == 0 && !dodefaults))
      goto jleave;

   if(dodefaults){
      s = ' ';
      t = '\t';
      n = '\n';
   }

   if(l > 0){
      while((c = *cp) != '\0' && (c == s || c == t || c == n)){
         ++cp;
         if(--l == 0)
            break;
      }
      self->s = n_UNCONST(cp);
   }

   if(l > 0){
      for(cp += l -1; (c = *cp) != '\0' && (c == s || c == t || c == n);){
         if(--l == 0)
            break;
         /* An uneven number of reverse solidus escapes last WS! */
         else if(*--cp == '\\'){
            siz_t j;

            for(j = 1; l - (uiz_t)j > 0 && cp[-j] == '\\'; ++j)
               ;
            if(j & 1){
               ++l;
               break;
            }
         }
      }
   }
   self->l = l;
jleave:
   n_NYD2_OU;
   return self;
}

/*
 * struct n_string TODO extend, optimize
 */

FL struct n_string *
(n_string_clear)(struct n_string *self su_DBG_LOC_ARGS_DECL){
   n_NYD_IN;

   assert(self != NULL);

   if(self->s_size != 0){
      if(!self->s_auto)
         su_MEM_FREE_LOCOR(self->s_dat, su_DBG_LOC_ARGS_ORUSE);
      self->s_len = self->s_auto = self->s_size = 0;
      self->s_dat = NULL;
   }
   n_NYD_OU;
   return self;
}

FL struct n_string *
(n_string_reserve)(struct n_string *self, size_t noof  su_DBG_LOC_ARGS_DECL){
   ui32_t i, l, s;
   n_NYD_IN;
   assert(self != NULL);

   s = self->s_size;
   l = self->s_len;
   if((size_t)SI32_MAX - n_ALIGN(1) - l <= noof)
      n_panic(_("Memory allocation too large"));

   if((i = s - l) <= ++noof){
      i += l + (ui32_t)noof;
      i = n_ALIGN(i);
      self->s_size = i -1;

      if(!self->s_auto)
         self->s_dat = su_MEM_REALLOC_LOCOR(self->s_dat, i,
               su_DBG_LOC_ARGS_ORUSE);
      else{
         char *ndat;

         ndat = su_MEM_BAG_SELF_AUTO_ALLOC_LOCOR(i, su_DBG_LOC_ARGS_ORUSE);
         if(l > 0)
            su_mem_copy(ndat, self->s_dat, l);
         self->s_dat = ndat;
      }
   }
   n_NYD_OU;
   return self;
}

FL struct n_string *
(n_string_resize)(struct n_string *self, size_t nlen  su_DBG_LOC_ARGS_DECL){
   n_NYD_IN;
   assert(self != NULL);

   if(UICMP(z, SI32_MAX, <=, nlen))
      n_panic(_("Memory allocation too large"));

   if(self->s_len < nlen)
      self = (n_string_reserve)(self, nlen  su_DBG_LOC_ARGS_USE);
   self->s_len = (ui32_t)nlen;
   n_NYD_OU;
   return self;
}

FL struct n_string *
(n_string_push_buf)(struct n_string *self, char const *buf, size_t buflen
      su_DBG_LOC_ARGS_DECL){
   n_NYD_IN;

   assert(self != NULL);
   assert(buflen == 0 || buf != NULL);

   if(buflen == UIZ_MAX)
      buflen = (buf == NULL) ? 0 : su_cs_len(buf);

   if(buflen > 0){
      ui32_t i;

      self = (n_string_reserve)(self, buflen  su_DBG_LOC_ARGS_USE);
      su_mem_copy(&self->s_dat[i = self->s_len], buf, buflen);
      self->s_len = (i += (ui32_t)buflen);
   }
   n_NYD_OU;
   return self;
}

FL struct n_string *
(n_string_push_c)(struct n_string *self, char c  su_DBG_LOC_ARGS_DECL){
   n_NYD_IN;

   assert(self != NULL);

   if(self->s_len + 1 >= self->s_size)
      self = (n_string_reserve)(self, 1  su_DBG_LOC_ARGS_USE);
   self->s_dat[self->s_len++] = c;
   n_NYD_OU;
   return self;
}

FL struct n_string *
(n_string_unshift_buf)(struct n_string *self, char const *buf, size_t buflen
      su_DBG_LOC_ARGS_DECL){
   n_NYD_IN;

   assert(self != NULL);
   assert(buflen == 0 || buf != NULL);

   if(buflen == UIZ_MAX)
      buflen = (buf == NULL) ? 0 : su_cs_len(buf);

   if(buflen > 0){
      self = (n_string_reserve)(self, buflen  su_DBG_LOC_ARGS_USE);
      if(self->s_len > 0)
         su_mem_move(&self->s_dat[buflen], self->s_dat, self->s_len);
      su_mem_copy(self->s_dat, buf, buflen);
      self->s_len += (ui32_t)buflen;
   }
   n_NYD_OU;
   return self;
}

FL struct n_string *
(n_string_unshift_c)(struct n_string *self, char c  su_DBG_LOC_ARGS_DECL){
   n_NYD_IN;

   assert(self != NULL);

   if(self->s_len + 1 >= self->s_size)
      self = (n_string_reserve)(self, 1  su_DBG_LOC_ARGS_USE);
   if(self->s_len > 0)
      su_mem_move(&self->s_dat[1], self->s_dat, self->s_len);
   self->s_dat[0] = c;
   ++self->s_len;
   n_NYD_OU;
   return self;
}

FL struct n_string *
(n_string_insert_buf)(struct n_string *self, size_t idx,
      char const *buf, size_t buflen  su_DBG_LOC_ARGS_DECL){
   n_NYD_IN;

   assert(self != NULL);
   assert(buflen == 0 || buf != NULL);
   assert(idx <= self->s_len);

   if(buflen == UIZ_MAX)
      buflen = (buf == NULL) ? 0 : su_cs_len(buf);

   if(buflen > 0){
      self = (n_string_reserve)(self, buflen  su_DBG_LOC_ARGS_USE);
      if(self->s_len > 0)
         su_mem_move(&self->s_dat[idx + buflen], &self->s_dat[idx],
            self->s_len - idx);
      su_mem_copy(&self->s_dat[idx], buf, buflen);
      self->s_len += (ui32_t)buflen;
   }
   n_NYD_OU;
   return self;
}

FL struct n_string *
(n_string_insert_c)(struct n_string *self, size_t idx,
      char c  su_DBG_LOC_ARGS_DECL){
   n_NYD_IN;

   assert(self != NULL);
   assert(idx <= self->s_len);

   if(self->s_len + 1 >= self->s_size)
      self = (n_string_reserve)(self, 1  su_DBG_LOC_ARGS_USE);
   if(self->s_len > 0)
      su_mem_move(&self->s_dat[idx + 1], &self->s_dat[idx], self->s_len - idx);
   self->s_dat[idx] = c;
   ++self->s_len;
   n_NYD_OU;
   return self;
}

FL struct n_string *
n_string_cut(struct n_string *self, size_t idx, size_t len){
   n_NYD_IN;

   assert(self != NULL);
   assert(UIZ_MAX - idx > len);
   assert(SI32_MAX >= idx + len);
   assert(idx + len <= self->s_len);

   if(len > 0)
      su_mem_move(&self->s_dat[idx], &self->s_dat[idx + len],
         (self->s_len -= len) - idx);
   n_NYD_OU;
   return self;
}

FL char *
(n_string_cp)(struct n_string *self  su_DBG_LOC_ARGS_DECL){
   char *rv;
   n_NYD2_IN;

   assert(self != NULL);

   if(self->s_size == 0)
      self = (n_string_reserve)(self, 1  su_DBG_LOC_ARGS_USE);

   (rv = self->s_dat)[self->s_len] = '\0';
   n_NYD2_OU;
   return rv;
}

FL char const *
n_string_cp_const(struct n_string const *self){
   char const *rv;
   n_NYD2_IN;

   assert(self != NULL);

   if(self->s_size != 0){
      ((struct n_string*)n_UNCONST(self))->s_dat[self->s_len] = '\0';
      rv = self->s_dat;
   }else
      rv = n_empty;
   n_NYD2_OU;
   return rv;
}

/* s-it-mode */
