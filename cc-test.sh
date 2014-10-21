#!/bin/sh -
#@ Usage: ./cc-test.sh [--check-only [s-nail-binary]]

SNAIL=./s-nail
ARGS='-n# -Sstealthmua -Sexpandaddr=restrict'
CONF=./make.rc
BODY=./.cc-body.txt
MBOX=./.cc-test.mbox

MAKE="${MAKE:-`command -v make`}"
awk=${awk:-`command -v awk`}
cat=${cat:-`command -v cat`}
# TODO cksum not fixated via mk-conf.sh, mk.mk should export variables!!
cksum=${cksum:-`command -v cksum`}
rm=${rm:-`command -v rm`}
sed=${sed:-`command -v sed`}
grep=${grep:-`command -v grep`}

##  --  >8  --  8<  --  ##

export SNAIL ARGS CONF BODY MBOX MAKE awk cat cksum rm sed grep

# NOTE!  UnixWare 7.1.4 gives ISO-10646-Minimum-European-Subset for
# nl_langinfo(CODESET), then, so also overwrite ttycharset.
# (In addition this setup allows us to succeed on TinyCore 4.4 that has no
# other locales than C/POSIX installed by default!)
LC=en_US.UTF-8
LC_ALL=${LC} LANG=${LC}
ttycharset=UTF-8
export LC_ALL LANG ttycharset

ESTAT=0

usage() {
   echo >&2 "Usage: ./cc-test.sh [--check-only [s-nail-binary]]"
   exit 1
}

CHECK_ONLY=
[ ${#} -gt 0 ] && {
   [ "${1}" = --check-only ] || usage
   [ ${#} -gt 2 ] && usage
   [ ${#} -eq 2 ] && SNAIL="${2}"
   [ -x "${SNAIL}" ] || usage
   CHECK_ONLY=1
}

# cc_all_configs()
# Test all configs TODO doesn't cover all *combinations*, stupid!
cc_all_configs() {
   < ${CONF} ${awk} '
      BEGIN {i = 0}
      /^[[:space:]]*WANT_/ {
         sub(/^[[:space:]]*/, "")
         # This bails for UnixWare 7.1.4 awk(1), but preceeding = with \
         # does not seem to be a compliant escape for =
         #sub(/=.*$/, "")
         $1 = substr($1, 1, index($1, "=") - 1)
         if ($1 == "WANT_AUTOCC")
            next
         data[i++] = $1
      }
      END {
         for (j = 0; j < i; ++j) {
            for (k = 0; k < j; ++k)
               printf data[k] "=1 "
            for (k = j; k < i; ++k)
               printf data[k] "=0 "
            printf "WANT_AUTOCC=1\n"

            for (k = 0; k < j; ++k)
               printf data[k] "=0 "
            for (k = j; k < i; ++k)
               printf data[k] "=1 "
            printf "WANT_AUTOCC=1\n"
         }
      }
   ' | while read c; do
      printf "\n\n##########\n$c\n"
      printf "\n\n##########\n$c\n" >&2
      sh -c "${MAKE} ${c}"
      t_all
      ${MAKE} distclean
   done
}

# cksum_test()
# Read mailbox $2, strip non-constant headers and MIME boundaries, query the
# cksum(1) of the resulting data and compare against the checksum $3
cksum_test() {
   tid=${1} f=${2} s=${3}
   printf "${tid}: "
   csum="`${sed} -e '/^From /d' -e '/^Date: /d' \
         -e '/^ boundary=/d' -e '/^--=_/d' < \"${f}\" \
         -e '/^\[-- Message/d' | ${cksum}`";
   if [ "${csum}" = "${s}" ]; then
      printf 'ok\n'
   else
      ESTAT=1
      printf 'error: checksum mismatch (got %s)\n' "${csum}"
   fi
}

have_feat() {
   (
   echo 'feat' |
   MAILRC=/dev/null "${SNAIL}" ${ARGS} |
   ${grep} ${1}
   ) >/dev/null 2>&1
}

# t_behave()
# Basic (easily testable) behaviour tests
t_behave() {
   # Test for [d1f1a19]
   ${rm} -f "${MBOX}"
   printf 'echo +nix\nset folder=/\necho +nix\nset nofolder\necho +nix\nx' |
      MAILRC=/dev/null "${SNAIL}" ${ARGS} -SPAGER="${cat}" > "${MBOX}"
   cksum_test behave:001 "${MBOX}" '4214021069 15'

   # POSIX: setting *noprompt*/prompt='' shall prevent prompting TODO
   # TODO for this to be testable we need a way to echo a variable
   # TODO or to force echo of the prompt

   __behave_ifelse

   # FIXME __behave_alias

   have_feat SSL/TLS && have_feat S/MIME && __behave_smime
}

__behave_ifelse() {
   # Nestable conditions test
   ${rm} -f "${MBOX}"
   ${cat} <<- '__EOT' | MAILRC=/dev/null "${SNAIL}" ${ARGS} > "${MBOX}"
		if 0
		   echo 1.err
		else
		   echo 1.ok
		endif
		if 1
		   echo 2.ok
		else
		   echo 2.err
		endif
		if $dietcurd
		   echo 3.err
		else
		   echo 3.ok
		endif
		set dietcurd=yoho
		if $dietcurd
		   echo 4.ok
		else
		   echo 4.err
		endif
		if $dietcurd == 'yoho'
		   echo 5.ok
		else
		   echo 5.err
		endif
		if $dietcurd != 'yoho'
		   echo 6.err
		else
		   echo 6.ok
		endif
		# Nesting
		if 0
		   echo 7.err1
		   if 1
		      echo 7.err2
		      if 1
		         echo 7.err3
		      else
		         echo 7.err4
		      endif
		      echo 7.err5
		   endif
		   echo 7.err6
		else
		   echo 7.ok7
		   if 1
		      echo 7.ok8
		      if 0
		         echo 7.err9
		      else
		         echo 7.ok9
		      endif
		      echo 7.ok10
		   else
		      echo 7.err11
		      if 1
		         echo 7.err12
		      else
		         echo 7.err13
		      endif
		   endif
		   echo 7.ok14
		endif
		if r
		   echo 8.ok1
		   if R
		      echo 8.ok2
		   else
		      echo 8.err2
		   endif
		   echo 8.ok3
		else
		   echo 8.err1
		endif
		if s
		   echo 9.err1
		else
		   echo 9.ok1
		   if S
		      echo 9.err2
		   else
		      echo 9.ok2
		   endif
		   echo 9.ok3
		endif
		# `elif'
		if $dietcurd == 'yohu'
		   echo 10.err1
		elif $dietcurd == 'yoha'
		   echo 10.err2
		elif $dietcurd == 'yohe'
		   echo 10.err3
		elif $dietcurd == 'yoho'
		   echo 10.ok1
		   if $dietcurd == 'yohu'
		      echo 10.err4
		   elif $dietcurd == 'yoha'
		      echo 10.err5
		   elif $dietcurd == 'yohe'
		      echo 10.err6
		   elif $dietcurd == 'yoho'
		      echo 10.ok2
		      if $dietcurd == 'yohu'
		         echo 10.err7
		      elif $dietcurd == 'yoha'
		         echo 10.err8
		      elif $dietcurd == 'yohe'
		         echo 10.err9
		      elif $dietcurd == 'yoho'
		         echo 10.ok3
		      else
		         echo 10.err10
		      endif
		   else
		      echo 10.err11
		   endif
		else
		   echo 10.err12
		endif
		# integer conversion, <..>..
		set dietcurd=10
		if $dietcurd < 11
		   echo 11.ok1
		   if $dietcurd > 9
		      echo 11.ok2
		   else
		      echo 11.err2
		   endif
		   if $dietcurd == 10
		      echo 11.ok3
		   else
		      echo 11.err3
		   endif
		   if $dietcurd >= 10
		      echo 11.ok4
		   else
		      echo 11.err4
		   endif
		   if $dietcurd <= 10
		      echo 11.ok5
		   else
		      echo 11.err5
		   endif
		   if $dietcurd >= 11
		      echo 11.err6
		   else
		      echo 11.ok6
		   endif
		   if $dietcurd <= 9
		      echo 11.err7
		   else
		      echo 11.ok7
		   endif
		else
		   echo 11.err1
		endif
		set dietcurd=Abc
		if $dietcurd < aBd
		   echo 12.ok1
		   if $dietcurd > abB
		      echo 12.ok2
		   else
		      echo 12.err2
		   endif
		   if $dietcurd == aBC
		      echo 12.ok3
		   else
		      echo 12.err3
		   endif
		   if $dietcurd >= AbC
		      echo 12.ok4
		   else
		      echo 12.err4
		   endif
		   if $dietcurd <= ABc
		      echo 12.ok5
		   else
		      echo 12.err5
		   endif
		   if $dietcurd >= abd
		      echo 12.err6
		   else
		      echo 12.ok6
		   endif
		   if $dietcurd <= abb
		      echo 12.err7
		   else
		      echo 12.ok7
		   endif
		else
		   echo 12.err1
		endif
	__EOT
   cksum_test behave:if-normal "${MBOX}" '2487694811 217'

   if have_feat REGEX; then
      ${rm} -f "${MBOX}"
      ${cat} <<- '__EOT' | MAILRC=/dev/null "${SNAIL}" ${ARGS} > "${MBOX}"
			set dietcurd=yoho
			if $dietcurd =~ '^yo.*'
			   echo 1.ok
			else
			   echo 1.err
			endif
			if $dietcurd =~ '^yoho.+'
			   echo 2.err
			else
			   echo 2.ok
			endif
			if $dietcurd !~ '.*ho$'
			   echo 3.err
			else
			   echo 3.ok
			endif
			if $dietcurd !~ '.+yoho$'
			   echo 4.ok
			else
			   echo 4.err
			endif
		__EOT
      cksum_test behave:if-regex "${MBOX}" '3930005258 20'
   fi
}

__behave_smime() { # FIXME add test/ dir, unroll tests therein, regular enable!
   printf 'behave:s/mime: .. generating test key and certificate ..\n'
   ${cat} <<-_EOT > ./t.conf
		[ req ]
		default_bits           = 1024
		default_keyfile        = keyfile.pem
		distinguished_name     = req_distinguished_name
		attributes             = req_attributes
		prompt                 = no
		output_password        =

		[ req_distinguished_name ]
		C                      = GB
		ST                     = Over the
		L                      = rainbow
		O                      = S-nail
		OU                     = S-nail.smime
		CN                     = S-nail.test
		emailAddress           = test@localhost

		[ req_attributes ]
		challengePassword =
	_EOT
   openssl req -x509 -nodes -days 3650 -config ./t.conf \
      -newkey rsa:1024 -keyout ./tkey.pem -out ./tcert.pem >/dev/null 2>&1
   ${rm} -f ./t.conf
   ${cat} ./tkey.pem ./tcert.pem > ./tpair.pem

   printf "behave:s/mime:sign/verify: "
   echo bla |
   MAILRC=/dev/null "${SNAIL}" ${ARGS} \
      -Ssmime-ca-file=./tcert.pem -Ssmime-sign-cert=./tpair.pem \
      -Ssmime-sign -Sfrom=test@localhost \
      -s 'S/MIME test' ./VERIFY
   # TODO CHECK
   printf 'verify\nx\n' |
   MAILRC=/dev/null "${SNAIL}" ${ARGS} \
      -Ssmime-ca-file=./tcert.pem -Ssmime-sign-cert=./tpair.pem \
      -Ssmime-sign -Sfrom=test@localhost \
      -Sbatch-exit-on-error -R \
      -f ./VERIFY >/dev/null 2>&1
   if [ $? -eq 0 ]; then
      printf 'ok\n'
   else
      ESTAT=1
      printf 'error: verification failed\n'
      ${rm} -f ./VERIFY ./tkey.pem ./tcert.pem ./tpair.pem
      return
   fi
   ${rm} -rf ./VERIFY

   printf "behave:s/mime:encrypt/decrypt: "
   ${cat} <<-_EOT > ./tsendmail.sh
		#!/bin/sh -
		(echo 'From S-Postman Thu May 10 20:40:54 2012' && ${cat}) > ./ENCRYPT
	_EOT
   chmod 0755 ./tsendmail.sh

   echo bla |
   MAILRC=/dev/null "${SNAIL}" ${ARGS} \
      -Ssmime-force-encryption \
      -Ssmime-encrypt-recei@ver.com=./tpair.pem \
      -Ssendmail=./tsendmail.sh \
      -Ssmime-ca-file=./tcert.pem -Ssmime-sign-cert=./tpair.pem \
      -Ssmime-sign -Sfrom=test@localhost \
      -s 'S/MIME test' recei@ver.com
   # TODO CHECK
   printf 'decrypt ./DECRYPT\nfi ./DECRYPT\nverify\nx\n' |
   MAILRC=/dev/null "${SNAIL}" ${ARGS} \
      -Ssmime-force-encryption \
      -Ssmime-encrypt-recei@ver.com=./tpair.pem \
      -Ssendmail=./tsendmail.sh \
      -Ssmime-ca-file=./tcert.pem -Ssmime-sign-cert=./tpair.pem \
      -Ssmime-sign -Sfrom=test@localhost \
      -Sbatch-exit-on-error -R \
      -f ./ENCRYPT >/dev/null 2>&1
   if [ $? -eq 0 ]; then
      printf 'ok\n'
   else
      ESTAT=1
      printf 'error: decryption+verification failed\n'
   fi
   ${rm} -f ./tsendmail.sh ./ENCRYPT ./DECRYPT \
      ./tkey.pem ./tcert.pem ./tpair.pem
}

# t_content()
# Some basic tests regarding correct sending of mails, via STDIN / -t / -q,
# including basic MIME Content-Transfer-Encoding correctness (quoted-printable)
# Note we unfortunately need to place some statements without proper
# indentation because of continuation problems
t_content() {
   ${rm} -f "${BODY}" "${MBOX}"

   # MIME CTE (QP) stress message body
printf \
'Ich bin eine DÖS-Datäi mit sehr langen Zeilen und auch '\
'sonst bin ich ganz schön am Schleudern, da kannste denke '\
"wasde willst, gelle, gelle, gelle, gelle, gelle.\r\n"\
"Ich bin eine DÖS-Datäi mit langen Zeilen und auch sonst \r\n"\
"Ich bin eine DÖS-Datäi mit langen Zeilen und auch sonst 1\r\n"\
"Ich bin eine DÖS-Datäi mit langen Zeilen und auch sonst 12\r\n"\
"Ich bin eine DÖS-Datäi mit langen Zeilen und auch sonst 123\r\n"\
"Ich bin eine DÖS-Datäi mit langen Zeilen und auch sonst 1234\r\n"\
"Ich bin eine DÖS-Datäi mit langen Zeilen und auch sonst 12345\r\n"\
"Ich bin eine DÖS-Datäi mit langen Zeilen und auch sonst 123456\r\n"\
"Ich bin eine DÖS-Datäi mit langen Zeilen und auch sonst 1234567\r\n"\
"Ich bin eine DÖS-Datäi mit langen Zeilen und auch sonst 12345678\r\n"\
"Ich bin eine DÖS-Datäi mit langen Zeilen und auch sonst 123456789\r\n"\
"Unn ausserdem habe ich trailing SP/HT/SP/HT whitespace 	 	\r\n"\
"Unn ausserdem habe ich trailing HT/SP/HT/SP whitespace	 	 \r\n"\
"auf den zeilen vorher.\r\n"\
"From am Zeilenbeginn und From der Mitte gibt es auch.\r\n"\
".\r\n"\
"Die letzte Zeile war nur ein Punkt.\r\n"\
"..\r\n"\
"Das waren deren zwei.\r\n"\
" \r\n"\
"Die letzte Zeile war ein Leerschritt.\n"\
"=VIER = EQUAL SIGNS=ON A LINE=\r\n"\
"Prösterchen.\r\n"\
".\n"\
"Die letzte Zeile war nur ein Punkt, mit Unix Zeilenende.\n"\
"..\n"\
"Das waren deren zwei.  ditto.\n"\
"Prösterchen.\n"\
"Unn ausseerdem habe ich trailing SP/HT/SP/HT whitespace 	 	\n"\
"Unn ausseerdem habe ich trailing HT/SP/HT/SP whitespace	 	 \n"\
"auf den zeilen vorher.\n"\
"ditto.\n"\
"Ich bin eine ziemlich lange, steile, scharfe Zeile mit Unix Zeilenende.\n"\
"Ich bin eine ziemlich lange, steile, scharfe Zeile mit Unix Zeilenende.1"\
"\n"\
"Ich bin eine ziemlich lange, steile, scharfe Zeile mit Unix Zeilenende.12"\
"\n"\
"Ich bin eine ziemlich lange, steile, scharfe Zeile mit Unix Zeilenende.12"\
"3\n"\
"Ich bin eine ziemlich lange, steile, scharfe Zeile mit Unix Zeilenende.12"\
"34\n"\
"Ich bin eine ziemlich lange, steile, scharfe Zeile mit Unix Zeilenende.12"\
"345\n"\
"Ich bin eine ziemlich lange, steile, scharfe Zeile mit Unix Zeilenende.12"\
"3456\n"\
"=VIER = EQUAL SIGNS=ON A LINE=\n"\
" \n"\
"Die letzte Zeile war ein Leerschritt.\n"\
' '\
 > "${BODY}"

   # MIME CTE (QP) stress message subject
SUB="Äbrä  Kä?dä=brö 	 Fü?di=bus? \
adadaddsssssssddddddddddddddddddddd\
ddddddddddddddddddddddddddddddddddd\
ddddddddddddddddddddddddddddddddddd\
dddddddddddddddddddd Hallelulja? Od\
er?? eeeeeeeeeeeeeeeeeeeeeeeeeeeeee\
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee f\
fffffffffffffffffffffffffffffffffff\
fffffffffffffffffffff ggggggggggggg\
ggggggggggggggggggggggggggggggggggg\
ggggggggggggggggggggggggggggggggggg\
ggggggggggggggggggggggggggggggggggg\
gggggggggggggggg"

   # Three tests for MIME-CTE and (a bit) content classification.
   # At the same time testing -q FILE, < FILE and -t FILE

   # TODO Note: because of our weird putline() handling in <-> collect.c
   ${rm} -f "${MBOX}"
   < "${BODY}" MAILRC=/dev/null \
   "${SNAIL}" -nSstealthmua -Sexpandaddr -a "${BODY}" -s "${SUB}" "${MBOX}"
   cksum_test content:001-0 "${MBOX}" '2289641826 5632'

   ${rm} -f "${MBOX}"
   < "${BODY}" MAILRC=/dev/null \
   "${SNAIL}" ${ARGS} -Snodot -a "${BODY}" -s "${SUB}" "${MBOX}"
   cksum_test content:001 "${MBOX}" '2898659780 5631'

   ${rm} -f "${MBOX}"
   < /dev/null MAILRC=/dev/null \
   "${SNAIL}" ${ARGS} -a "${BODY}" -s "${SUB}" \
      -q "${BODY}" "${MBOX}"
   cksum_test content:002 "${MBOX}" '2289641826 5632'

   ${rm} -f "${MBOX}"
   (  echo "To: ${MBOX}" && echo "Subject: ${SUB}" && echo &&
      ${cat} "${BODY}"
   ) | MAILRC=/dev/null "${SNAIL}" ${ARGS} -Snodot -a "${BODY}" -t
   cksum_test content:003 "${MBOX}" '2898659780 5631'

   # Test for [260e19d] (Juergen Daubert)
   ${rm} -f "${MBOX}"
   echo body | MAILRC=/dev/null "${SNAIL}" ${ARGS} "${MBOX}"
   cksum_test content:004 "${MBOX}" '506144051 104'

   # Sending of multiple mails in a single invocation
   ${rm} -f "${MBOX}"
   (  printf "m ${MBOX}\n~s subject1\nE-Mail Körper 1\n.\n" &&
      printf "m ${MBOX}\n~s subject2\nEmail body 2\n.\n" &&
      echo x
   ) | MAILRC=/dev/null "${SNAIL}" ${ARGS}
   cksum_test content:005 "${MBOX}" '2028749685 277'

   ## $BODY CHANGED

   # "Test for" [d6f316a] (Gavin Troy)
   ${rm} -f "${MBOX}"
   printf "m ${MBOX}\n~s subject1\nEmail body\n.\nfi ${MBOX}\np\nx\n" |
   MAILRC=/dev/null "${SNAIL}" ${ARGS} \
      -SPAGER="${cat}" -Spipe-text/plain="${cat}" > "${BODY}"
   ${sed} -e 1d < "${BODY}" > "${MBOX}"
   cksum_test content:006 "${MBOX}" '1520300594 138'

   # "Test for" [c299c45] (Peter Hofmann) TODO shouldn't end up QP-encoded?
   # TODO Note: because of our weird putline() handling in <-> collect.c
   ${rm} -f "${MBOX}"
   LC_ALL=C ${awk} 'BEGIN{
      for(i = 0; i < 10000; ++i)
         printf "\xC3\xBC"
         #printf "\xF0\x90\x87\x90"
      }' |
   MAILRC=/dev/null "${SNAIL}" -nSstealthmua -Sexpandaddr \
      -s TestSubject "${MBOX}"
   cksum_test content:007-0 "${MBOX}" '2747333583 61729'

   ${rm} -f "${MBOX}"
   LC_ALL=C ${awk} 'BEGIN{
      for(i = 0; i < 10000; ++i)
         printf "\xC3\xBC"
         #printf "\xF0\x90\x87\x90"
      }' |
   MAILRC=/dev/null "${SNAIL}" ${ARGS} -s TestSubject "${MBOX}"
   cksum_test content:007 "${MBOX}" '3343002941 61728'

   ## Test some more corner cases for header bodies (as good as we can today) ##

   #
   ${rm} -f "${MBOX}"
   echo |
   MAILRC=/dev/null "${SNAIL}" ${ARGS} \
      -s 'a̲b̲c̲d̲e̲f̲h̲i̲k̲l̲m̲n̲o̲r̲s̲t̲u̲v̲w̲x̲z̲a̲b̲c̲d̲e̲f̲h̲i̲k̲l̲m̲n̲o̲r̲s̲t̲u̲v̲w̲x̲z̲' \
      "${MBOX}"
   cksum_test content:008 "${MBOX}" '1428748699 320'

   # Single word (overlong line split -- bad standard! Requires injection of
   # artificial data!!  Bad can be prevented by using RFC 2047 encoding)
   ${rm} -f "${MBOX}"
   i=`LC_ALL=C ${awk} 'BEGIN{for(i=0; i<92; ++i) printf "0123456789_"}'`
   echo | MAILRC=/dev/null "${SNAIL}" ${ARGS} -s "${i}" "${MBOX}"
   cksum_test content:009 "${MBOX}" '141403131 1663'

   # Combination of encoded words, space and tabs of varying sort
   ${rm} -f "${MBOX}"
   echo | MAILRC=/dev/null "${SNAIL}" ${ARGS} \
      -s "1Abrä Kaspas1 2Abra Katä	b_kaspas2  \
3Abrä Kaspas3   4Abrä Kaspas4    5Abrä Kaspas5     \
6Abra Kaspas6      7Abrä Kaspas7       8Abra Kaspas8        \
9Abra Kaspastäb4-3 	 	 	 10Abra Kaspas1 _ 11Abra Katäb1	\
12Abra Kadabrä1 After	Tab	after	Täb	this	is	NUTS" \
      "${MBOX}"
   cksum_test content:010 "${MBOX}" '2324198710 536'

   # Overlong multibyte sequence that must be forcefully split
   # todo This works even before v15.0, but only by accident
   ${rm} -f "${MBOX}"
   echo | MAILRC=/dev/null "${SNAIL}" ${ARGS} \
      -s "✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄\
✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄\
✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄" \
      "${MBOX}"
   cksum_test content:011 "${MBOX}" '3085014590 604'

   # Trailing WS
   ${rm} -f "${MBOX}"
   echo |
   MAILRC=/dev/null "${SNAIL}" ${ARGS} \
      -s "1-1 	 B2 	 B3 	 B4 	 B5 	 B6 	 B\
1-2 	 B2 	 B3 	 B4 	 B5 	 B6 	 B\
1-3 	 B2 	 B3 	 B4 	 B5 	 B6 	 B\
1-4 	 B2 	 B3 	 B4 	 B5 	 B6 	 B\
1-5 	 B2 	 B3 	 B4 	 B5 	 B6 	 B\
1-6 	 B2 	 B3 	 B4 	 B5 	 B6 	 " \
      "${MBOX}"
   cksum_test content:012 "${MBOX}" '2868799725 303'

   # Leading and trailing WS
   ${rm} -f "${MBOX}"
   echo |
   MAILRC=/dev/null "${SNAIL}" ${ARGS} \
      -s "	 	 2-1 	 B2 	 B3 	 B4 	 B5 	 B6 	 B\
1-2 	 B2 	 B3 	 B4 	 B5 	 B6 	 B\
1-3 	 B2 	 B3 	 B4 	 B5 	 B6 	 B\
1-4 	 B2 	 B3 	 B4 	 B5 	 B6 	 " \
      "${MBOX}"
   cksum_test content:013 "${MBOX}" '3962521045 243'

   ${rm} -f "${BODY}" "${MBOX}"
}

t_all() {
   t_behave
   t_content
}

if [ -z "${CHECK_ONLY}" ]; then
   cc_all_configs
else
   t_all
fi

[ ${ESTAT} -eq 0 ] && echo Ok || echo >&2 'Errors occurred'

exit ${ESTAT}
# s-sh-mode
