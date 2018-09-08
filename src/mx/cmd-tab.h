/*@ S-nail - a mail user agent derived from Berkeley Mail.
 *@ This is included by ./cmd-tab.c and defines the command array.
 *@ TODO This should be generated by a script from a template.  It should
 *@ TODO sort the entries alphabetically, and create an array that is indexed
 *@ TODO by first cmd letter with modulo, the found number is used to index a
 *@ TODO multi-dimensional array with alphasorted entries.  It should ensure
 *@ TODO that (exact!) POSIX abbreviations order first.
 *@ TODO And the data (and n_cmd_arg_desc) should be placed in special crafted
 *@ TODO comments in or before the function source, to be collected by script.
 *
 * Copyright (c) 2000-2004 Gunnar Ritter, Freiburg i. Br., Germany.
 * Copyright (c) 2012 - 2018 Steffen (Daode) Nurpmeso <steffen@sdaoden.eu>.
 * SPDX-License-Identifier: BSD-3-Clause TODO ISC
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

/* Because of the largish TODO, we yet become included twice.
 * Not indented for that */
#ifndef n_CMD_TAB_H
# define n_CMD_TAB_H

#ifdef mx_HAVE_KEY_BINDINGS
# define a_CTAB_CAD_BIND n_CMD_ARG_DESC_SUBCLASS_CAST(&a_ctab_cad_bind)
n_CMD_ARG_DESC_SUBCLASS_DEF(bind, 3, a_ctab_cad_bind){
   {n_CMD_ARG_DESC_SHEXP, n_SHEXP_PARSE_TRIM_IFSSPACE}, /* context */
   {n_CMD_ARG_DESC_SHEXP | n_CMD_ARG_DESC_OPTION | n_CMD_ARG_DESC_HONOUR_STOP,
      n_SHEXP_PARSE_DRYRUN}, /* subcommand / key sequence */
   {n_CMD_ARG_DESC_SHEXP | n_CMD_ARG_DESC_OPTION |
         n_CMD_ARG_DESC_GREEDY | n_CMD_ARG_DESC_GREEDY_JOIN |
         n_CMD_ARG_DESC_HONOUR_STOP,
      n_SHEXP_PARSE_IGNORE_EMPTY | n_SHEXP_PARSE_TRIM_IFSSPACE} /* expansion */
}n_CMD_ARG_DESC_SUBCLASS_DEF_END;
#else
# define a_CTAB_CAD_BIND NULL
#endif

n_CMD_ARG_DESC_SUBCLASS_DEF(call, 2, a_ctab_cad_call){
   {n_CMD_ARG_DESC_SHEXP | n_CMD_ARG_DESC_HONOUR_STOP,
      n_SHEXP_PARSE_TRIM_IFSSPACE}, /* macro name */
   {n_CMD_ARG_DESC_SHEXP | n_CMD_ARG_DESC_OPTION |
         n_CMD_ARG_DESC_GREEDY | n_CMD_ARG_DESC_HONOUR_STOP,
      n_SHEXP_PARSE_IFS_VAR | n_SHEXP_PARSE_TRIM_IFSSPACE} /* args */
}n_CMD_ARG_DESC_SUBCLASS_DEF_END;

#ifdef mx_HAVE_TLS
# define a_CTAB_CAD_CERTSAVE n_CMD_ARG_DESC_SUBCLASS_CAST(&a_ctab_cad_certsave)
n_CMD_ARG_DESC_SUBCLASS_DEF(certsave, 1, a_ctab_cad_certsave){
   {n_CMD_ARG_DESC_MSGLIST_AND_TARGET | n_CMD_ARG_DESC_GREEDY,
      n_SHEXP_PARSE_TRIM_IFSSPACE}
}n_CMD_ARG_DESC_SUBCLASS_DEF_END;
#else
# define a_CTAB_CAD_CERTSAVE NULL
#endif

n_CMD_ARG_DESC_SUBCLASS_DEF(copy, 1, a_ctab_cad_copy){
   {n_CMD_ARG_DESC_MSGLIST_AND_TARGET | n_CMD_ARG_DESC_GREEDY,
      n_SHEXP_PARSE_TRIM_IFSSPACE}
}n_CMD_ARG_DESC_SUBCLASS_DEF_END;

n_CMD_ARG_DESC_SUBCLASS_DEF(Copy, 1, a_ctab_cad_Copy){
   {n_CMD_ARG_DESC_MSGLIST | n_CMD_ARG_DESC_GREEDY,
      n_SHEXP_PARSE_TRIM_IFSSPACE}
}n_CMD_ARG_DESC_SUBCLASS_DEF_END;

n_CMD_ARG_DESC_SUBCLASS_DEF(decrypt, 1, a_ctab_cad_decrypt){
   {n_CMD_ARG_DESC_MSGLIST_AND_TARGET | n_CMD_ARG_DESC_GREEDY,
      n_SHEXP_PARSE_TRIM_IFSSPACE}
}n_CMD_ARG_DESC_SUBCLASS_DEF_END;

n_CMD_ARG_DESC_SUBCLASS_DEF(Decrypt, 1, a_ctab_cad_Decrypt){
   {n_CMD_ARG_DESC_MSGLIST | n_CMD_ARG_DESC_GREEDY,
      n_SHEXP_PARSE_TRIM_IFSSPACE}
}n_CMD_ARG_DESC_SUBCLASS_DEF_END;

n_CMD_ARG_DESC_SUBCLASS_DEF(digmsg, 3, a_ctab_cad_digmsg){ /* XXX 2 OR 3 */
   {n_CMD_ARG_DESC_SHEXP | n_CMD_ARG_DESC_HONOUR_STOP,
      n_SHEXP_PARSE_TRIM_IFSSPACE}, /* subcommand (/ msgno/-) */
   {n_CMD_ARG_DESC_SHEXP | n_CMD_ARG_DESC_HONOUR_STOP,
      n_SHEXP_PARSE_TRIM_IFSSPACE}, /* msgno/- (/ first part of user cmd) */
   {n_CMD_ARG_DESC_SHEXP | n_CMD_ARG_DESC_OPTION |
         n_CMD_ARG_DESC_GREEDY | n_CMD_ARG_DESC_GREEDY_JOIN |
         n_CMD_ARG_DESC_HONOUR_STOP,
      n_SHEXP_PARSE_IGNORE_EMPTY | n_SHEXP_PARSE_TRIM_IFSSPACE} /* args */
}n_CMD_ARG_DESC_SUBCLASS_DEF_END;

n_CMD_ARG_DESC_SUBCLASS_DEF(forward, 1, a_ctab_cad_forward){
   {n_CMD_ARG_DESC_MSGLIST_AND_TARGET | n_CMD_ARG_DESC_GREEDY |
         n_CMD_ARG_DESC_MSGLIST_NEEDS_SINGLE,
      n_SHEXP_PARSE_TRIM_IFSSPACE}
}n_CMD_ARG_DESC_SUBCLASS_DEF_END;

n_CMD_ARG_DESC_SUBCLASS_DEF(Forward, 1, a_ctab_cad_Forward){
   {n_CMD_ARG_DESC_MSGLIST | n_CMD_ARG_DESC_GREEDY |
         n_CMD_ARG_DESC_MSGLIST_NEEDS_SINGLE,
      n_SHEXP_PARSE_TRIM_IFSSPACE}
}n_CMD_ARG_DESC_SUBCLASS_DEF_END;

n_CMD_ARG_DESC_SUBCLASS_DEF(move, 1, a_ctab_cad_move){
   {n_CMD_ARG_DESC_MSGLIST_AND_TARGET | n_CMD_ARG_DESC_GREEDY,
      n_SHEXP_PARSE_TRIM_IFSSPACE}
}n_CMD_ARG_DESC_SUBCLASS_DEF_END;

n_CMD_ARG_DESC_SUBCLASS_DEF(Move, 1, a_ctab_cad_Move){
   {n_CMD_ARG_DESC_MSGLIST | n_CMD_ARG_DESC_GREEDY,
      n_SHEXP_PARSE_TRIM_IFSSPACE}
}n_CMD_ARG_DESC_SUBCLASS_DEF_END;

n_CMD_ARG_DESC_SUBCLASS_DEF(pdot, 1, a_ctab_cad_pdot){
   {n_CMD_ARG_DESC_MSGLIST | n_CMD_ARG_DESC_GREEDY,
      n_SHEXP_PARSE_TRIM_IFSSPACE}
}n_CMD_ARG_DESC_SUBCLASS_DEF_END;

n_CMD_ARG_DESC_SUBCLASS_DEF(pipe, 1, a_ctab_cad_pipe){
   {n_CMD_ARG_DESC_MSGLIST_AND_TARGET | n_CMD_ARG_DESC_GREEDY,
      n_SHEXP_PARSE_TRIM_IFSSPACE}
}n_CMD_ARG_DESC_SUBCLASS_DEF_END;

n_CMD_ARG_DESC_SUBCLASS_DEF(readctl, 2, a_ctab_cad_readctl){
   {n_CMD_ARG_DESC_SHEXP | n_CMD_ARG_DESC_OPTION | n_CMD_ARG_DESC_HONOUR_STOP,
      n_SHEXP_PARSE_TRIM_IFSSPACE}, /* subcommand */
   {n_CMD_ARG_DESC_SHEXP | n_CMD_ARG_DESC_OPTION |
         n_CMD_ARG_DESC_GREEDY | n_CMD_ARG_DESC_GREEDY_JOIN |
         n_CMD_ARG_DESC_HONOUR_STOP,
      n_SHEXP_PARSE_IGNORE_EMPTY | n_SHEXP_PARSE_TRIM_IFSSPACE} /* var names */
}n_CMD_ARG_DESC_SUBCLASS_DEF_END;

n_CMD_ARG_DESC_SUBCLASS_DEF(resend, 1, a_ctab_cad_resend){
   {n_CMD_ARG_DESC_MSGLIST_AND_TARGET | n_CMD_ARG_DESC_GREEDY,
      n_SHEXP_PARSE_TRIM_IFSSPACE}
}n_CMD_ARG_DESC_SUBCLASS_DEF_END;

n_CMD_ARG_DESC_SUBCLASS_DEF(Resend, 1, a_ctab_cad_Resend){
   {n_CMD_ARG_DESC_MSGLIST_AND_TARGET | n_CMD_ARG_DESC_GREEDY,
      n_SHEXP_PARSE_TRIM_IFSSPACE}
}n_CMD_ARG_DESC_SUBCLASS_DEF_END;

n_CMD_ARG_DESC_SUBCLASS_DEF(save, 1, a_ctab_cad_save){
   {n_CMD_ARG_DESC_MSGLIST_AND_TARGET | n_CMD_ARG_DESC_GREEDY,
      n_SHEXP_PARSE_TRIM_IFSSPACE}
}n_CMD_ARG_DESC_SUBCLASS_DEF_END;

n_CMD_ARG_DESC_SUBCLASS_DEF(Save, 1, a_ctab_cad_Save){
   {n_CMD_ARG_DESC_MSGLIST | n_CMD_ARG_DESC_GREEDY,
      n_SHEXP_PARSE_TRIM_IFSSPACE}
}n_CMD_ARG_DESC_SUBCLASS_DEF_END;

#ifdef mx_HAVE_KEY_BINDINGS
# define a_CTAB_CAD_UNBIND n_CMD_ARG_DESC_SUBCLASS_CAST(&a_ctab_cad_unbind)
n_CMD_ARG_DESC_SUBCLASS_DEF(unbind, 2, a_ctab_cad_unbind){
   {n_CMD_ARG_DESC_SHEXP, n_SHEXP_PARSE_TRIM_IFSSPACE}, /* context */
   /* key sequence or * */
   {n_CMD_ARG_DESC_SHEXP | n_CMD_ARG_DESC_HONOUR_STOP, n_SHEXP_PARSE_DRYRUN}
}n_CMD_ARG_DESC_SUBCLASS_DEF_END;
#else
# define a_CTAB_CAD_UNBIND NULL
#endif

n_CMD_ARG_DESC_SUBCLASS_DEF(vpospar, 2, a_ctab_cad_vpospar){
   {n_CMD_ARG_DESC_SHEXP | n_CMD_ARG_DESC_HONOUR_STOP,
      n_SHEXP_PARSE_TRIM_IFSSPACE}, /* subcommand */
   {n_CMD_ARG_DESC_SHEXP | n_CMD_ARG_DESC_OPTION |
         n_CMD_ARG_DESC_GREEDY | n_CMD_ARG_DESC_HONOUR_STOP,
      n_SHEXP_PARSE_IFS_VAR | n_SHEXP_PARSE_TRIM_IFSSPACE} /* args */
}n_CMD_ARG_DESC_SUBCLASS_DEF_END;

n_CMD_ARG_DESC_SUBCLASS_DEF(write, 1, a_ctab_cad_write){
   {n_CMD_ARG_DESC_MSGLIST_AND_TARGET | n_CMD_ARG_DESC_GREEDY,
      n_SHEXP_PARSE_TRIM_IFSSPACE}
}n_CMD_ARG_DESC_SUBCLASS_DEF_END;

#else /* ifndef n_CMD_TAB_H */

#ifdef mx_HAVE_DOCSTRINGS
# define DS(S) , S
#else
# define DS(S)
#endif

#undef MAC
#define MAC (n_MAXARGC - 1)

/* Some shorter aliases to be able to define a command in two lines */
#define TMSGLST n_CMD_ARG_TYPE_MSGLIST
#define TNDMLST n_CMD_ARG_TYPE_NDMLIST
#define TRAWDAT n_CMD_ARG_TYPE_RAWDAT
#  define TSTRING n_CMD_ARG_TYPE_STRING
#define TWYSH n_CMD_ARG_TYPE_WYSH
#  define TRAWLST n_CMD_ARG_TYPE_RAWLIST
#  define TWYRA n_CMD_ARG_TYPE_WYRA
#define TARG n_CMD_ARG_TYPE_ARG

#define A n_CMD_ARG_A
#define F n_CMD_ARG_F
#define G n_CMD_ARG_G
#define H n_CMD_ARG_H
#define I n_CMD_ARG_I
#define L n_CMD_ARG_L
#define M n_CMD_ARG_M
#define O n_CMD_ARG_O
#define P n_CMD_ARG_P
#define R n_CMD_ARG_R
#define SC n_CMD_ARG_SC
#define S n_CMD_ARG_S
#define T n_CMD_ARG_T
#define V n_CMD_ARG_V
#define W n_CMD_ARG_W
#define X n_CMD_ARG_X
#define EM n_CMD_ARG_EM

   /* Note: the first command in here may NOT expand to an unsupported one!
    * It is used for n_cmd_default() */
   { "next", &c_next, (A | TNDMLST), 0, MMNDEL, NULL
     DS(N_("Goes to the next message (-list) and prints it")) },


   { "alias", &c_alias, (M | TWYRA), 0, MAC, NULL
     DS(N_("Show all (or <alias>), or (re)define <alias> to :<data>:")) },
   { "print", &c_type, (A | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Type all messages of <msglist>, honouring `ignore' / `retain'")) },
   { "type", &c_type, (A | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Type all messages of <msglist>, honouring `ignore' / `retain'")) },
   { "Type", &c_Type, (A | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Like `type', but bypass `ignore' / `retain'")) },
   { "Print", &c_Type, (A | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Like `print', but bypass `ignore' / `retain'")) },
   { "visual", &c_visual, (A | I | S | TMSGLST), 0, MMNORM, NULL
     DS(N_("Edit <msglist>")) },
   { "top", &c_top, (A | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Type first *toplines* of all messages in <msglist>")) },
   { "Top", &c_Top, (A | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Like `top', but bypass `ignore' / `retain'")) },
   { "touch", &c_stouch, (A | W | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Mark <msglist> for saving in *mbox*")) },
   { "preserve", &c_preserve, (A | SC | W | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Save <msglist> in system mailbox instead of *MBOX*")) },
   { "delete", &c_delete, (A | W | P | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Delete <msglist>")) },
   { "dp", &c_deltype, (A | W | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Delete the current message, then type the next")) },
   { "dt", &c_deltype, (A | W | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Delete the current message, then type the next")) },
   { "undelete", &c_undelete, (A | P | TMSGLST), MDELETED, MMNDEL, NULL
     DS(N_("Un`delete' <msglist>")) },
   { "mail", &c_sendmail, (I | M | R | SC | EM | TSTRING), 0, 0, NULL
     DS(N_("Compose mail; recipients may be given as arguments")) },
   { "Mail", &c_Sendmail, (I | M | R | SC | EM | TSTRING), 0, 0, NULL
     DS(N_("Like `mail', but derive filename from first recipient")) },
   { "mbox", &c_mboxit, (A | W | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Indicate that <msglist> is to be stored in *MBOX*")) },
   { "more", &c_more, (A | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Invoke the pager on the given messages")) },
   { "page", &c_more, (A | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Invoke the pager on the given messages")) },
   { "More", &c_More, (A | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Invoke the pager on the given messages")) },
   { "Page", &c_More, (A | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Invoke the pager on the given messages")) },
   { "unread", &c_unread, (A | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Mark <msglist> as not being read")) },
   { "Unread", &c_unread, (A | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Mark <msglist> as not being read")) },
   { "new", &c_unread, (A | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Mark <msglist> as not being read")) },
   { "New", &c_unread, (A | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Mark <msglist> as not being read")) },
   { n_em, &c_shell, (M | SC | V | X | EM | TRAWDAT), 0, 0, NULL
     DS(N_("Execute <shell-command>")) },
   { "copy", &c_copy, (A | M | TARG), 0, 0,
     n_CMD_ARG_DESC_SUBCLASS_CAST(&a_ctab_cad_copy)
     DS(N_("Copy [<msglist>], but do not mark them for deletion")) },
   { "Copy", &c_Copy, (A | M | SC | TARG), 0, 0,
     n_CMD_ARG_DESC_SUBCLASS_CAST(&a_ctab_cad_Copy)
     DS(N_("Like `copy', but derive filename from first sender")) },
   { "chdir", &c_chdir, (M | TWYRA), 0, 1, NULL
     DS(N_("Change CWD to the specified/the login directory")) },
   { "cd", &c_chdir, (M | X | TWYRA), 0, 1, NULL
     DS(N_("Change working directory to the specified/the login directory")) },
   { "save", &c_save, (A | TARG), 0, 0,
     n_CMD_ARG_DESC_SUBCLASS_CAST(&a_ctab_cad_save)
     DS(N_("Append [<msglist>] to <file>")) },
   { "Save", &c_Save, (A | SC | TARG), 0, 0,
     n_CMD_ARG_DESC_SUBCLASS_CAST(&a_ctab_cad_Save)
     DS(N_("Like `save', but derive filename from first sender")) },
   { "set", &c_set, (G | L | M | X | TWYRA), 0, MAC, NULL
     DS(N_("Print all variables, or set (a) <variable>(s)")) },
   { "unalias", &c_unalias, (M | TWYRA), 1, MAC, NULL
     DS(N_("Un`alias' <name-list> (* for all)")) },
   { "write", &c_write, (A | TARG), 0, 0,
     n_CMD_ARG_DESC_SUBCLASS_CAST(&a_ctab_cad_write)
     DS(N_("Write (append) [<msglist>] to [<file>]")) },
   { "from", &c_from, (A | TMSGLST), 0, MMNORM, NULL
     DS(N_("Type (matching) headers of <msglist> (a search specification)")) },
   { "search", &c_from, (A | TMSGLST), 0, MMNORM, NULL
     DS(N_("Search for <msglist>, type matching headers")) },
   { "file", &c_file, (M | T | TWYRA), 0, 1, NULL
     DS(N_("Open a new <mailbox> or show the current one")) },
   { "followup", &c_followup, (A | I | R | SC | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Like `reply', but derive filename from first sender")) },
   { "followupall", &c_followupall, (A | I | R | SC | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Like `reply', but derive filename from first sender")) },
   { "followupsender", &c_followupsender, (A | I | R | SC | TMSGLST),
      0, MMNDEL, NULL
     DS(N_("Like `Followup', but always reply to the sender only")) },
   { "folder", &c_file, (M | T | TWYRA), 0, 1, NULL
     DS(N_("Open a new <mailbox> or show the current one")) },
   { "folders", &c_folders, (M | T | TWYRA), 0, 1, NULL
     DS(N_("List mailboxes below the given or the global folder")) },
   { "headers", &c_headers, (A | M | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Type a page of headers (with the first of <msglist> if given)")) },
   { "help", &a_ctab_c_help, (G | M | X | TWYSH), 0, 1, NULL
     DS(N_("Show help [[Option] for the given command]]")) },
   { n_qm, &a_ctab_c_help, (G | M | X | TWYSH), 0, 1, NULL
     DS(N_("Show help [[Option] for the given command]]")) },
   { "Reply", &c_Reply, (A | I | R | SC | EM | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Reply to originator, exclusively")) },
   { "Respond", &c_Reply, (A | I | R | SC | EM | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Reply to originator, exclusively")) },
   { "Followup", &c_Followup, (A | I | R | SC | EM | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Like `Reply', but derive filename from first sender")) },
   { "reply", &c_reply, (A | I | R | SC | EM | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Reply to originator and recipients of <msglist>")) },
   { "replyall", &c_replyall, (A | I | R | SC | EM | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Reply to originator and recipients of <msglist>")) },
   { "replysender", &c_replysender, (A | I | R | SC | EM | TMSGLST),
         0, MMNDEL, NULL
     DS(N_("Reply to originator, exclusively")) },
   { "respond", &c_reply, (A | I | R | SC | EM | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Reply to originators and recipients of <msglist>")) },
   { "respondall", &c_replyall, (A | I | R | SC | EM | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Reply to originators and recipients of <msglist>")) },
   { "respondsender", &c_replysender, (A | I | R | SC | EM | TMSGLST),
         0, MMNDEL, NULL
     DS(N_("Reply to originator, exclusively")) },
   { "resend", &c_resend, (A | R | SC | EM | TARG), 0, MMNDEL,
     n_CMD_ARG_DESC_SUBCLASS_CAST(&a_ctab_cad_resend)
     DS(N_("Resend <msglist> to <user>, add Resent-* header lines")) },
   { "Resend", &c_Resend, (A | R | SC | EM | TARG), 0, MMNDEL,
     n_CMD_ARG_DESC_SUBCLASS_CAST(&a_ctab_cad_Resend)
     DS(N_("Like `resend', but do not add Resent-* header lines")) },
   { "forward", &c_forward, (A | R | SC | EM | TARG), 0, MMNDEL,
     n_CMD_ARG_DESC_SUBCLASS_CAST(&a_ctab_cad_forward)
     DS(N_("Forward <message> to <address>")) },
   { "Forward", &c_Forward, (A | R | SC | EM | TARG), 0, MMNDEL,
     n_CMD_ARG_DESC_SUBCLASS_CAST(&a_ctab_cad_Forward)
     DS(N_("Like `forward', but derive filename from <address>")) },
   { "edit", &c_editor, (G | A | I | S | TMSGLST), 0, MMNORM, NULL
     DS(N_("Edit <msglist>")) },
   { "pipe", &c_pipe, (A | TARG), 0, MMNDEL,
     n_CMD_ARG_DESC_SUBCLASS_CAST(&a_ctab_cad_pipe)
     DS(N_("Pipe [<msglist>] to [<command>], honour `ignore' / `retain'")) },
   { "|", &c_pipe, (A | TARG), 0, MMNDEL,
     n_CMD_ARG_DESC_SUBCLASS_CAST(&a_ctab_cad_pipe)
     DS(N_("Pipe [<msglist>] to [<command>], honour `ignore' / `retain'")) },
   { "Pipe", &c_Pipe, (A | TARG), 0, MMNDEL,
     n_CMD_ARG_DESC_SUBCLASS_CAST(&a_ctab_cad_pipe)
     DS(N_("Like `pipe', but do not honour `ignore' / `retain'")) },
   { "size", &c_messize, (A | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Show size in bytes for <msglist>")) },
   { "hold", &c_preserve, (A | SC | W | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Save <msglist> in system mailbox instead of *MBOX*")) },
   { "if", &c_if, (G | F | M | X | TRAWLST), 1, MAC, NULL
     DS(N_("Part of the if/elif/else/endif statement")) },
   { "else", &c_else, (G | F | M | X | TWYSH), 0, 0, NULL
     DS(N_("Part of the if/elif/else/endif statement")) },
   { "elif", &c_elif, (G | F | M | X | TRAWLST), 1, MAC, NULL
     DS(N_("Part of the if/elif/else/endif statement")) },
   { "endif", &c_endif, (G | F | M | X | TWYSH), 0, 0, NULL
     DS(N_("Part of the if/elif/else/endif statement")) },
   { "alternates", &c_alternates, (M | V | TWYSH), 0, MAC, NULL
     DS(N_("Show or define alternate <address-list> for the invoking user")) },
   { "unalternates", &c_unalternates, (M | TWYSH), 1, MAC, NULL
     DS(N_("Delete alternate <address-list> (* for all)")) },
   { "ignore", &c_ignore, (M | TWYRA), 0, MAC, NULL
     DS(N_("Add <header-list> to the ignored LIST, or show that list")) },
   { "discard", &c_ignore, (M | TWYRA), 0, MAC, NULL
     DS(N_("Add <header-list> to the ignored LIST, or show that list")) },
   { "retain", &c_retain, (M | TWYRA), 0, MAC, NULL
     DS(N_("Add <header-list> to retained list, or show that list")) },
   { "saveignore", &c_saveignore, (O | M | TRAWLST), 0, MAC, NULL
     DS(N_("Obsoleted by `headerpick'")) },
   { "savediscard", &c_saveignore, (O | M | TRAWLST), 0, MAC, NULL
     DS(N_("Obsoleted by `headerpick'")) },
   { "saveretain", &c_saveretain, (O | M | TRAWLST), 0, MAC, NULL
     DS(N_("Obsoleted by `headerpick'")) },
   { "unignore", &c_unignore, (M | TWYRA), 0, MAC, NULL
     DS(N_("Un`ignore' <header-list>")) },
   { "unretain", &c_unretain, (M | TWYRA), 0, MAC, NULL
     DS(N_("Un`retain' <header-list>")) },
   { "unsaveignore", &c_unsaveignore, (O | M | TRAWLST), 0, MAC, NULL
     DS(N_("Obsoleted by `unheaderpick'")) },
   { "unsaveretain", &c_unsaveretain, (O | M | TRAWLST), 0, MAC, NULL
     DS(N_("Obsoleted by `unheaderpick'")) },
   { "newmail", &c_newmail, (A | T | TWYSH), 0, 0, NULL
     DS(N_("Check for new mail in current folder")) },
   { "shortcut", &c_shortcut, (M | TWYRA), 0, MAC, NULL
     DS(N_("Define <shortcut>s and their <expansion>, or list shortcuts")) },
   { "unshortcut", &c_unshortcut, (M | TWYRA), 1, MAC, NULL
     DS(N_("Delete <shortcut-list> (* for all)")) },
   { "thread", &c_thread, (O | A | TMSGLST), 0, 0, NULL
     DS(N_("Obsoleted by `sort' \"thread\"")) },
   { "unthread", &c_unthread, (O | A | TMSGLST), 0, 0, NULL
     DS(N_("Obsolete (use `unsort')")) },
   { "sort", &c_sort, (A | TWYSH), 0, 1, NULL
     DS(N_("Change sorting to: date,from,size,spam,status,subject,thread,to"))},
   { "unsort", &c_unthread, (A | TMSGLST), 0, 0, NULL
     DS(N_("Disable sorted or threaded mode")) },
   { "flag", &c_flag, (A | M | TMSGLST), 0, 0, NULL
     DS(N_("(Un)Flag <msglist> (for special attention)")) },
   { "unflag", &c_unflag, (A | M | TMSGLST), 0, 0, NULL
     DS(N_("(Un)Flag <msglist> (for special attention)")) },
   { "answered", &c_answered, (A | M | TMSGLST), 0, 0, NULL
     DS(N_("Mark the given <msglist> as answered")) },
   { "unanswered", &c_unanswered, (A | M | TMSGLST), 0, 0, NULL
     DS(N_("Un`answered' <msglist>")) },
   { "draft", &c_draft, (A | M | TMSGLST), 0, 0, NULL
     DS(N_("Mark <msglist> as draft")) },
   { "undraft", &c_undraft, (A | M | TMSGLST), 0, 0, NULL
     DS(N_("Un`draft' <msglist>")) },
   { "move", &c_move, (A | M | TARG), 0, 0,
     n_CMD_ARG_DESC_SUBCLASS_CAST(&a_ctab_cad_move)
     DS(N_("Like `copy', but mark messages for deletion")) },
   { "Move", &c_Move, (A | M | SC | TARG), 0, 0,
     n_CMD_ARG_DESC_SUBCLASS_CAST(&a_ctab_cad_Move)
     DS(N_("Like `move', but derive filename from first sender")) },
   { "mv", &c_move, (O | A | M | TARG), 0, 0,
     n_CMD_ARG_DESC_SUBCLASS_CAST(&a_ctab_cad_move)
     DS(N_("Like `copy', but mark messages for deletion")) },
   { "Mv", &c_Move, (O | A | M | SC | TARG), 0, 0,
     n_CMD_ARG_DESC_SUBCLASS_CAST(&a_ctab_cad_Move)
     DS(N_("Like `move', but derive filename from first sender")) },
   { "noop", &c_noop, (A | M | TWYSH), 0, 0, NULL
     DS(N_("NOOP command if current `file' is accessed via network")) },
   { "collapse", &c_collapse, (A | TMSGLST), 0, 0, NULL
     DS(N_("Collapse thread views for <msglist>")) },
   { "uncollapse", &c_uncollapse, (A | TMSGLST), 0, 0, NULL
     DS(N_("Uncollapse <msglist> if in threaded view")) },
   { "verify",
#ifdef mx_HAVE_XTLS
      &c_verify,
#else
      NULL,
#endif
      (A | TMSGLST), 0, 0, NULL
     DS(N_("Verify <msglist>")) },
   { "decrypt", &c_decrypt, (A | M | TARG), 0, 0,
     n_CMD_ARG_DESC_SUBCLASS_CAST(&a_ctab_cad_decrypt)
     DS(N_("Like `copy', but decrypt first, if encrypted")) },
   { "Decrypt", &c_Decrypt, (A | M | SC | TARG), 0, 0,
     n_CMD_ARG_DESC_SUBCLASS_CAST(&a_ctab_cad_Decrypt)
     DS(N_("Like `decrypt', but derive filename from first sender")) },
   { "certsave",
#ifdef mx_HAVE_TLS
      &c_certsave,
#else
      NULL,
#endif
      (A | TARG), 0, MMNDEL, a_CTAB_CAD_CERTSAVE
     DS(N_("Save S/MIME certificates of [<msglist>] to <file>")) },
   { "rename", &c_rename, (M | TWYRA), 0, 2, NULL
     DS(N_("Rename <existing-folder> to <new-folder>")) },
   { "remove", &c_remove, (M | TWYRA), 0, MAC, NULL
     DS(N_("Remove the named folders")) },
   { "show", &c_show, (A | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Like `type', but show raw message content of <msglist>")) },
   { "Show", &c_show, (A | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Like `Type', but show raw message content of <msglist>")) },
   { "mimeview", &c_mimeview, (A | I | EM | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Show non-text parts of the given <message>")) },
   { "seen", &c_seen, (A | M | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Mark <msglist> as seen")) },
   { "Seen", &c_seen, (A | M | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Mark <msglist> as seen")) },
   { "fwdignore", &c_fwdignore, (O | M | TRAWLST), 0, MAC, NULL
     DS(N_("Obsoleted by `headerpick'")) },
   { "fwddiscard", &c_fwdignore, (O | M | TRAWLST), 0, MAC, NULL
     DS(N_("Obsoleted by `headerpick'")) },
   { "fwdretain", &c_fwdretain, (O | M | TRAWLST), 0, MAC, NULL
     DS(N_("Obsoleted by `headerpick'")) },
   { "unfwdignore", &c_unfwdignore, (O | M | TRAWLST), 0, MAC, NULL
     DS(N_("Obsoleted by `unheaderpick'")) },
   { "unfwdretain", &c_unfwdretain, (O | M | TRAWLST), 0, MAC, NULL
     DS(N_("Obsoleted by `unheaderpick'")) },
   { "mimetype", &c_mimetype, (M | TWYSH), 0, MAC, NULL
     DS(N_("(Load and) show all known MIME types, or define some")) },
   { "unmimetype", &c_unmimetype, (M | TWYSH), 1, MAC, NULL
     DS(N_("Delete <type>s (reset, * for all; former reinitializes)")) },

   { "spamclear",
#ifdef mx_HAVE_SPAM
      &c_spam_clear,
#else
      NULL,
#endif
      (A | M | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Clear the spam flag for each message in <msglist>")) },
   { "spamset",
#ifdef mx_HAVE_SPAM
      &c_spam_set,
#else
      NULL,
#endif
      (A | M | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Set the spam flag for each message in <msglist>")) },
   { "spamforget",
#ifdef mx_HAVE_SPAM
      &c_spam_forget,
#else
      NULL,
#endif
      (A | M | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Force the spam detector to unlearn <msglist>")) },
   { "spamham",
#ifdef mx_HAVE_SPAM
      &c_spam_ham,
#else
      NULL,
#endif
      (A | M | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Teach the spam detector that <msglist> is ham")) },
   { "spamrate",
#ifdef mx_HAVE_SPAM
      &c_spam_rate,
#else
      NULL,
#endif
      (A | M | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Rate <msglist> via the spam detector")) },
   { "spamspam",
#ifdef mx_HAVE_SPAM
      &c_spam_spam,
#else
      NULL,
#endif
      (A | M | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Teach the spam detector that <msglist> is spam")) },

   { "File", &c_File, (M | T | TWYRA), 0, 1, NULL
     DS(N_("Open a new mailbox readonly, or show the current mailbox")) },
   { "Folder", &c_File, (M | T | TWYRA), 0, 1, NULL
     DS(N_("Open a new mailbox readonly, or show the current mailbox")) },
   { "mlist", &c_mlist, (M | TWYRA), 0, MAC, NULL
     DS(N_("Show all known mailing lists or define some")) },
   { "unmlist", &c_unmlist, (M | TWYRA), 1, MAC, NULL
     DS(N_("Un`mlist' <name-list> (* for all)")) },
   { "mlsubscribe", &c_mlsubscribe, (M | TWYRA), 0, MAC, NULL
     DS(N_("Show all mailing list subscriptions or define some")) },
   { "unmlsubscribe", &c_unmlsubscribe, (M | TWYRA), 1, MAC, NULL
     DS(N_("Un`mlsubscribe' <name-list> (* for all)"))},
   { "Lreply", &c_Lreply, (A | I | R | SC | EM | TMSGLST), 0, MMNDEL, NULL
     DS(N_("Mailing-list reply to the given <msglist>")) },
   { "dotmove", &c_dotmove, (A | TSTRING), 1, 1, NULL
     DS(N_("Move the dot up <-> or down <+> by one")) },

   /* New-style commands without un* counterpart */

   { "=", &c_pdot, (A | G | V | X | EM | TARG), 0, MMNDEL,
     n_CMD_ARG_DESC_SUBCLASS_CAST(&a_ctab_cad_pdot)
     DS(N_("Show message number of [<msglist>] (or the \"dot\")")) },

   { "call", &c_call, (M | X | EM | TARG), 0, 0,
      n_CMD_ARG_DESC_SUBCLASS_CAST(&a_ctab_cad_call)
     DS(N_("Call macro <name> [:<arg>:]")) },
   { "call_if", &c_call_if, (M | X | EM | TARG), 0, 0,
      n_CMD_ARG_DESC_SUBCLASS_CAST(&a_ctab_cad_call)
     DS(N_("Call macro <name> like `call', but be silent if non-existent")) },
   { "cwd", &c_cwd, (M | V | X | TWYSH), 0, 0, NULL
     DS(N_("Print current working directory (CWD)")) },

   { "digmsg", &c_digmsg, (G | M | X | EM | TARG), 0, 0,
      n_CMD_ARG_DESC_SUBCLASS_CAST(&a_ctab_cad_digmsg)
     DS(N_("<create|remove> <-|msgno> | <-|msgno> <cmd>: "
         "message dig object control"))},

   { "echo", &c_echo, (G | M | V | X | EM | TWYSH), 0, MAC, NULL
     DS(N_("Echo arguments, and a trailing newline, to standard output")) },
   { "echoerr", &c_echoerr, (G | M | V | X | EM | TWYSH), 0, MAC, NULL
     DS(N_("Echo arguments, and a trailing newline, to standard error")) },
   { "echon", &c_echon, (G | M | V | X | EM | TWYSH), 0, MAC, NULL
     DS(N_("Echo arguments, without a trailing newline, to standard output")) },
   { "echoerrn", &c_echoerrn, (G | M | V| X | EM | TWYSH), 0, MAC, NULL
     DS(N_("Echo arguments, without a trailing newline, to standard error")) },
   { "environ", &c_environ, (G | M | X | TWYSH), 2, MAC, NULL
     DS(N_("<link|set|unset> (an) environment <variable>(s)")) },
   { "errors",
#ifdef mx_HAVE_ERRORS
      &c_errors,
#else
      NULL,
#endif
      (H | I | M | TWYSH), 0, 1, NULL
     DS(N_("Either [<show>] or <clear> the error message ring")) },
   { "eval", &c_eval, (G | M | X | EM | TWYSH), 1, MAC, NULL
     DS(N_("Construct command from :<arguments>:, reuse its $? and $!")) },
   { "exit", &c_exit, (M | X | TWYSH), 0, 1, NULL
     DS(N_("Immediately return [<status>] to the shell without saving")) },

   { "history",
#ifdef mx_HAVE_HISTORY
      &c_history,
#else
      NULL,
#endif
      (H | I | M | TWYSH), 0, 1, NULL
     DS(N_("<show (default)|load|save|clear> or select history <NO>")) },

   { "list", &a_ctab_c_list, (M | TWYSH), 0, 1, NULL
     DS(N_("List all commands (with argument: in prefix search order)")) },
   { "localopts", &c_localopts, (H | M | X | TWYSH), 1, 2, NULL
     DS(N_("Localize variable modifications? [<attribute>] <boolean>"))},

   { "netrc",
#ifdef mx_HAVE_NETRC
      &c_netrc,
#else
      NULL,
#endif
      (M | TWYSH), 0, 1, NULL
     DS(N_("[<show>], <load> or <clear> the .netrc cache")) },

   { "quit", &c_quit, TWYSH, 0, 1, NULL
     DS(N_("Exit session with [<status>], saving messages as necessary")) },

   { "read", &c_read, (G | M | X | EM | TWYSH), 1, MAC, NULL
     DS(N_("Read a line from standard input into <variable>(s)")) },
   { "readall", &c_readall, (G | M | X | EM | TWYSH), 1, 1, NULL
     DS(N_("Read anything from standard input until EOF into <variable>")) },
   { "readctl", &c_readctl, (G | M | X | EM | TARG), 0, 0,
      n_CMD_ARG_DESC_SUBCLASS_CAST(&a_ctab_cad_readctl)
     DS(N_("[<show>] or <create|set|remove> <spec> read channels"))},
   { "return", &c_return, (M | X | EM | TWYSH), 0, 2, NULL
     DS(N_("Return control [with <return value> [<exit status>]] from macro"))},

   { "shell", &c_dosh, (I | S | EM | TWYSH), 0, 0, NULL
     DS(N_("Invoke an interactive shell")) },
   { "shift", &c_shift, (M | X | TWYSH), 0, 1, NULL
     DS(N_("In a `call'ed macro, shift positional parameters")) },
   { "sleep", &c_sleep, (H | M | X | EM | TWYSH), 1, 3, NULL
     DS(N_("Sleep for <seconds> [<milliseconds>]"))},
   { "source", &c_source, (M | TWYSH), 1, 1, NULL
     DS(N_("Read commands from <file>")) },
   { "source_if", &c_source_if, (M | TWYSH), 1, 1, NULL
     DS(N_("If <file> can be opened successfully, read commands from it")) },

   { "unset", &c_unset, (G | L | M | X | TWYSH), 1, MAC, NULL
     DS(N_("Unset <option-list>")) },

   { "varshow", &c_varshow, (G | M | X | TWYSH), 1, MAC, NULL
     DS(N_("Show some information about the given <variables>")) },
   { "varedit", &c_varedit, (O | G | I | M | S | TWYSH), 1, MAC, NULL
     DS(N_("Edit the value(s) of (an) variable(s), or create them")) },
   { "vexpr", &c_vexpr, (G | M | V | X | EM | TWYSH), 2, MAC, NULL
     DS(N_("Evaluate according to <operator> any :<arguments>:")) },
   { "vpospar", &c_vpospar, (G | M | V | X | EM | TARG), 0, 0,
      n_CMD_ARG_DESC_SUBCLASS_CAST(&a_ctab_cad_vpospar)
     DS(N_("Positional parameters: <clear>, <quote>, or <set> from :<arg>:"))},

   { "version", &c_version, (H | M | V | X | TWYSH), 0, 0, NULL
     DS(N_("Show the version and feature set of the program")) },

   { "xit"/*POSIX, first!*/, &c_exit, (M | X | TWYSH), 0, 1, NULL
     DS(N_("Immediately return [<status>] to the shell without saving")) },
   { "xcall", &c_xcall, (M | X | EM | TARG), 0, 0,
      n_CMD_ARG_DESC_SUBCLASS_CAST(&a_ctab_cad_call)
     DS(N_("Replace currently executing macro with macro <name> [:<arg>:]")) },

   { "z", &c_scroll, (A | M | TWYSH), 0, 1, NULL
     DS(N_("Scroll header display as indicated by the argument (0,-,+,$)")) },
   { "Z", &c_Scroll, (A | M | TWYSH), 0, 1, NULL
     DS(N_("Like `z', but continues to the next flagged message")) },

   /* New-style commands with un* counterpart */

   { "account", &c_account, (M | TWYSH), 0, MAC, NULL
     DS(N_("Create or select <account>, or list all accounts")) },
   { "unaccount", &c_unaccount, (M | TWYSH), 1, MAC, NULL
     DS(N_("Delete all given <accounts> (* for all)")) },

   { "bind",
#ifdef mx_HAVE_KEY_BINDINGS
      &c_bind,
#else
      NULL,
#endif
      (M | TARG), 1, MAC, a_CTAB_CAD_BIND
     DS(N_("For <context> (base), [<show>] or bind <key[:,key:]> [:<data>:]"))},
   { "unbind",
#ifdef mx_HAVE_KEY_BINDINGS
      &c_unbind,
#else
      NULL,
#endif
      (M | TARG), 2, 2, a_CTAB_CAD_UNBIND
     DS(N_("Un`bind' <context> <key[:,key:]> (* for all)")) },

   { "charsetalias", &c_charsetalias, (M | TWYSH), 0, MAC, NULL
     DS(N_("Define [:<charset> <charset-alias>:]s, or list mappings")) },
   { "uncharsetalias", &c_uncharsetalias, (M | TWYSH), 1, MAC, NULL
     DS(N_("Delete <charset-mapping-list> (* for all)")) },

   { "colour",
#ifdef mx_HAVE_COLOUR
      &c_colour,
#else
      NULL,
#endif
      (M | TWYSH), 1, 4, NULL
     DS(N_("Show colour settings of <type> (1,8,256,all/*) or define one")) },
   { "uncolour",
#ifdef mx_HAVE_COLOUR
      &c_uncolour,
#else
      NULL,
#endif
      (M | TWYSH), 2, 3, NULL
     DS(N_("Un`colour' <type> <mapping> (* for all) [<precondition>]")) },

   { "commandalias", &c_commandalias, (M | X | TWYSH), 0, MAC, NULL
     DS(N_("Print/create command <alias> [<command>], or list all aliases")) },
   { "uncommandalias", &c_uncommandalias, (M | X | TWYSH), 1, MAC, NULL
     DS(N_("Delete <command-alias-list> (* for all)")) },
      { "ghost", &c_commandalias, (O | M | X | TWYRA), 0, MAC, NULL
        DS(N_("Obsoleted by `commandalias'")) },
      { "unghost", &c_uncommandalias, (O | M | X | TWYRA), 1, MAC, NULL
        DS(N_("Obsoleted by `uncommandalias'")) },

   { "define", &c_define, (M | X | TWYSH), 0, 2, NULL
     DS(N_("Define a <macro> or show the currently defined ones")) },
   { "undefine", &c_undefine, (M | X | TWYSH), 1, MAC, NULL
     DS(N_("Un`define' all given <macros> (* for all)")) },

   { "filetype", &c_filetype, (M | TWYSH), 0, MAC, NULL
     DS(N_("Create [:<extension> <load-cmd> <save-cmd>:] "
      "or list file handlers"))},
   { "unfiletype", &c_unfiletype, (M | TWYSH), 1, MAC, NULL
     DS(N_("Delete file handler for [:<extension>:] (* for all)")) },

   { "headerpick", &c_headerpick, (M | TWYSH), 0, MAC, NULL
     DS(N_("Header selection: [<context> [<type> [<header-list>]]]"))},
   { "unheaderpick", &c_unheaderpick, (M | TWYSH), 3, MAC, NULL
     DS(N_("Header deselection: <context> <type> <header-list>"))},

   { "tls",
#ifdef mx_HAVE_TLS
      &c_tls,
#else
      NULL,
#endif
      (G | V | EM | TWYSH), 1, MAC, NULL
     DS(N_("TLS information and management: <command> [<:argument:>]")) },

   /* Codec commands */

   { "addrcodec", &c_addrcodec, (G | M | V | X | EM | TRAWDAT), 0, 0, NULL
    DS(N_("Email address <[+[+[+]]]e[ncode]|d[ecode]|s[kin]> <rest-of-line>"))},

   { "shcodec", &c_shcodec, (G | M | V | X | EM | TRAWDAT), 0, 0, NULL
     DS(N_("Shell quoting: <[+]e[ncode]|d[ecode]> <rest-of-line>")) },

   { "urlcodec", &c_urlcodec, (G | M | V | X | EM | TRAWDAT), 0, 0, NULL
     DS(N_("URL percent <[path]e[ncode]|[path]d[ecode]> <rest-of-line>")) },
      { "urlencode", &c_urlencode, (O | G | M | X | TWYRA), 1, MAC, NULL
        DS(N_("Obsoleted by `urlcodec'")) },
      { "urldecode", &c_urldecode, (O | G | M | X | TWYRA), 1, MAC, NULL
        DS(N_("Obsoleted by `urlcodec'")) }

#ifdef mx_HAVE_MEMORY_DEBUG
   ,{ "memtrace", &c_memtrace, (I | M | TWYSH), 0, 0, NULL
     DS(N_("Trace current memory usage afap")) }
#endif
#ifdef mx_HAVE_DEVEL
   ,{ "sigstate", &c_sigstate, (I | M | TWYSH), 0, 0, NULL
     DS(N_("Show signal handler states")) }
#endif

   /* Obsolete stuff */

#ifdef mx_HAVE_IMAP
   ,{ "imap", &c_imap_imap, (A | TSTRING), 0, MAC, NULL
     DS(N_("Send command strings directly to the IMAP server")) },
   { "connect", &c_connect, (A | TSTRING), 0, 0, NULL
     DS(N_("If disconnected, connect to IMAP mailbox")) },
   { "disconnect", &c_disconnect, (A | TNDMLST), 0, 0, NULL
     DS(N_("If connected, disconnect from IMAP mailbox")) },
   { "cache", &c_cache, (A | TMSGLST), 0, 0, NULL
     DS(N_("Read specified <message list> into the IMAP cache")) },

   { "imapcodec", &c_imapcodec, (G | M | V | X | TRAWDAT), 0, 0, NULL
     DS(N_("IMAP mailbox name <e[ncode]|d[ecode]> <rest-of-line>")) }
#endif

#undef DS

#undef MAC

#undef TMSGLST
#undef TNDMLST
#undef TRAWDAT
#  undef TSTRING
#undef TWYSH
#  undef TRAWLST
#  undef TWYRA
#undef TARG

#undef A
#undef F
#undef G
#undef H
#undef I
#undef L
#undef M
#undef O
#undef P
#undef R
#undef SC
#undef S
#undef T
#undef V
#undef W
#undef X
#undef EM

#endif /* n_CMD_TAB_H */

/* s-it-mode */
