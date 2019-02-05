/*@ S-nail - a mail user agent derived from Berkeley Mail.
 *@ `charsetalias'.
 *
 * Copyright (c) 2017 - 2019 Steffen (Daode) Nurpmeso <steffen@sdaoden.eu>.
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
#ifndef mx_CHARSETALIAS_H
#define mx_CHARSETALIAS_H

#include <mx/nail.h>

#include <su/code-in.h>

/* `(un)?charsetalias' */
FL int c_charsetalias(void *vp);
FL int c_uncharsetalias(void *vp);

/* Try to expand a charset, return mapping or itself.
 * If is_normalized is true iconv_normalize_name() will not be called on cp */
FL char const *mx_charsetalias_expand(char const *cp, boole is_normalized);

#include <su/code-ou.h>
#endif /* mx_CHARSETALIAS_H */
/* s-it-mode */
