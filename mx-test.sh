#!/bin/sh -
#@ Synopsis: [OBJDIR=XY] ./mx-test.sh --check-only [s-mailx-binary]
#@           [OBJDIR=XY] ./mx-test.sh --run-test s-mailx-binary [:TESTNAME:]
#@           [./mx-test.sh # Note: performs hundreds of compilations!]
#@ --no-jobs can be used to prevent spawning concurrent tests.
# Public Domain

: ${OBJDIR:=.obj}

# Instead of figuring out the environment in here, require a configured build
# system and include that!  Our makefile and configure ensure that this test
# does not run in the configured, but the user environment nonetheless!
i=
while true; do
   if [ -f ./mk-config.env ]; then
      break
   elif [ -f snailmail.jpg ] && [ -f "${OBJDIR}"/mk-config.env ]; then
      i=`pwd`/ # not from environment, sic
      cd "${OBJDIR}"
      break
   else
      echo >&2 'S-nail/S-mailx is not configured.'
      echo >&2 'This test script requires the shell environment that only the'
      echo >&2 'configuration script can figure out, even if used to test'
      echo >&2 'a different binary than the one that would be produced!'
      echo >&2 '(The information will be in ${OBJDIR:=.obj}/mk-config.env.)'
      echo >&2 'Hit RETURN to run "make config"'
      read l
      make config
   fi
done
. ./mk-config.env
if [ -z "${MAILX__CC_TEST_RUNNING}" ]; then
   MAILX__CC_TEST_RUNNING=1
   export MAILX__CC_TEST_RUNNING
   exec "${SHELL}" "${i}${0}" "${@}"
fi

# We need *stealthmua* regardless of $SOURCE_DATE_EPOCH, the program name as
# such is a compile-time variable
ARGS='-Sv15-compat -:/ -Sdotlock-disable -Smta=test -Smemdebug -Sstealthmua'
   ARGS="${ARGS}"' -Smime-encoding=quoted-printable -Snosave'
NOBATCH_ARGS="${ARGS}"' -Sexpandaddr'
   ARGS="${ARGS}"' -Sexpandaddr=restrict -#'
ADDARG_UNI=-Sttycharset=UTF-8
CONF=../make.rc
BODY=./.cc-body.txt
MBOX=./.cc-test.mbox
ERR=./.cc-test.err # Covers some which cannot be checksummed; not quoted!
MAIL=/dev/null
#UTF8_LOCALE= autodetected unless set
TMPDIR=`${pwd}`

# When testing mass mail/loops, maximum number of receivers/loops.
# TODO note we do not gracefully handle ARG_MAX excess yet!
# Those which use this have checksums for 2001 and 201.
# Some use the smaller automatically if +debug
LOOPS_BIG=2001 LOOPS_SMALL=201
LOOPS_MAX=$LOOPS_SMALL

# How long unless started tests get reaped (avoid endless looping)
JOBWAIT=42

# Note valgrind has problems with FDs in forked childs, which causes some tests
# to fail (the FD is rewound and thus will be dumped twice)
MEMTESTER=
#MEMTESTER='valgrind --leak-check=full --log-file=.vl-%p '

##  --  >8  --  8<  --  ##

t_all() {
   # Absolute Basics
   jspawn X_Y_opt_input_go_stack
   jspawn X_errexit
   jspawn Y_errexit
   jspawn S_freeze
   jspawn f_batch_order
   jspawn input_inject_semicolon_seq
   jspawn wysh
   jspawn commandalias # test now, save space later on!
   jspawn posix_abbrev
   jsync

   # Basics
   jspawn shcodec
   jspawn ifelse
   jspawn localopts
   jspawn local
   jspawn environ
   jspawn macro_param_shift
   jspawn addrcodec
   jspawn csop
   jspawn vexpr
   jspawn call_ret
   jspawn xcall
   jspawn vpospar
   jspawn atxplode
   jspawn read
   jspawn headerpick # so we have a notion that it works a bit
   jsync

   # Send/RFC absolute basics
   jspawn can_send_rfc
   jspawn reply
   jspawn forward
   jspawn resend
   jsync

   # VFS
   jspawn copy
   jspawn save
   jspawn move
   jspawn mbox
   jspawn maildir
   jsync

   # MIME and RFC basics
   jspawn mime_if_not_ascii
   jspawn mime_encoding
   jspawn xxxheads_rfc2047
   jspawn iconv_mbyte_base64
   jspawn iconv_mainbody
   jspawn mime_force_sendout
   jspawn binary_mainbody
   jspawn C_opt_customhdr
   jsync

   # Operational basics with trivial tests
   jspawn alias
   jspawn charsetalias
   jspawn shortcut
   jsync

   # Operational basics with easy tests
   jspawn expandaddr # (after t_alias)
   jspawn mta_aliases # (after t_expandaddr)
   jspawn filetype
   jspawn e_H_L_opts
   jspawn q_t_etc_opts
   jspawn message_injections
   jspawn attachments
   jspawn rfc2231 # (after attachments)
   jspawn mime_types_load_control
   jsync

   # Around state machine, after basics
   jspawn alternates
   jspawn cmd_escapes
   jspawn compose_edits
   jspawn digmsg
   jspawn on_main_loop_tick
   jspawn on_program_exit
   jsync

   # Heavy use of/rely on state machine (behaviour) and basics
   jspawn compose_hooks
   jspawn mass_recipients
   jspawn lreply_futh_rth_etc
   jspawn pipe_handlers
   jsync

   # Unclassified rest
   jspawn top
   jspawn s_mime
   jspawn z
   jsync

   jsync 1
}

## Now it is getting really weird. You have been warned.
# Setup and support {{{
export ARGS ADDARG_UNI CONF BODY MBOX MAIL TMPDIR  \
   MAKE awk cat cksum rm sed grep

LC_ALL=C LANG=C
TZ=UTC
# Wed Oct  2 01:50:07 UTC 1996
SOURCE_DATE_EPOCH=844221007

export LC_ALL LANG TZ SOURCE_DATE_EPOCH
unset POSIXLY_CORRECT LOGNAME USER

# usage {{{
usage() {
   ${cat} >&2 <<_EOT
Synopsis: [OBJDIR=x] mx-test.sh [--no-jobs] --check-only s-mailx-binary
Synopsis: [OBJDIR=x] mx-test.sh [--no-jobs] --run-test s-mailx-binary [:TEST:]
Synopsis: [OBJDIR=x] mx-test.sh [--no-jobs]

 --check-only EXE         run the test series, exit success or error;
                          if run in a git(1) checkout then failed tests
                          create test output data files
 --run-test EXE [:TEST:]  run all or only the given TESTs, and create
                          test output data files; if run in a git(1)
                          checkout with the [test-out] branch available,
                          it will also create file differences
 --no-jobs                do not spawn multiple jobs simultaneously

The last invocation style will compile and test as many different
configurations as possible.
OBJDIR= may be set to the location of the built objects etc.
_EOT
   exit 1
}

NOJOBS= DUMPERR= CHECK_ONLY= RUN_TEST= MAXJOBS=1 GIT_REPO= MAILX=
if [ "${1}" = --no-jobs ]; then
   NOJOBS=y
   shift
fi

if [ "${1}" = --check-only ]; then
   [ ${#} -eq 2 ] || usage
   CHECK_ONLY=1 MAILX=${2}
   [ -x "${MAILX}" ] || usage
   echo 'Mode: --check-only, binary: '"${MAILX}"
   [ -d ../.git ] && [ -z "${MAILX__CC_TEST_NO_DATA_FILES}" ] && GIT_REPO=1
elif [ "${1}" = --run-test ]; then
   [ ${#} -ge 2 ] || usage
   RUN_TEST=1 MAILX=${2}
   [ -x "${MAILX}" ] || usage
   shift 2
   echo 'Mode: --run-test, binary: '"${MAILX}"
   [ -d ../.git ] && GIT_REPO=1
else
   [ ${#} -eq 0 ] || usage
   echo 'Mode: full compile test, this will take a long time...'
   MAILX__CC_TEST_NO_DATA_FILES=1
   export MAILX__CC_TEST_NO_DATA_FILES
fi
# }}}

# Since we invoke $MAILX from within several directories we need a fully
# qualified path.  Or at least something similar.
{ echo ${MAILX} | ${grep} -q ^/; } || MAILX="${TMPDIR}"/${MAILX}
RAWMAILX=${MAILX}
MAILX="${MEMTESTER}${MAILX}"
export RAWMAILX MAILX

# We want an UTF-8 locale {{{
if [ -n "${CHECK_ONLY}${RUN_TEST}" ]; then
   if [ -z "${UTF8_LOCALE}" ]; then
      # Try ourselfs via nl_langinfo(CODESET) first (requires a new version)
      if command -v "${RAWMAILX}" >/dev/null 2>&1 &&
            ("${RAWMAILX}" -:/ -Xxit) >/dev/null 2>&1; then
         echo 'Trying to detect UTF-8 locale via '"${RAWMAILX}"
         i=`LC_ALL=C.utf8 "${RAWMAILX}" ${ARGS} -X '
            \define cset_test {
               \if "${ttycharset}" =%?case utf
                  \echo $LC_ALL
                  \xit 0
               \end
               \if "${#}" -gt 0
                  \wysh set LC_ALL=${1}
                  \shift
                  \eval xcall cset_test "${@}"
               \end
               \xit 1
            }
            \call cset_test C.UTF-8 POSIX.utf8 POSIX.UTF-8 \
               en_EN.utf8 en_EN.UTF-8 en_US.utf8 en_US.UTF-8
         '`
         [ $? -eq 0 ] && UTF8_LOCALE=$i
      fi

      if [ -z "${UTF8_LOCALE}" ] && (locale yesexpr) >/dev/null 2>&1; then
         echo 'Trying to detect UTF-8 locale via locale -a'
         UTF8_LOCALE=`locale -a | { m=
            while read n; do
               if { echo ${n} |
                     ${grep} -i -e utf8 -e utf-8; } >/dev/null 2>&1; then
                  m=${n}
                  if { echo ${n} |
                        ${grep} -e POSIX -e en_EN -e en_US; } \
                           >/dev/null 2>&1; then
                     break
                  fi
               fi
            done
            echo ${m}
         }`
      fi
   fi

   if [ -n "${UTF8_LOCALE}" ]; then
      echo 'Using Unicode locale '"${UTF8_LOCALE}"
   else
      echo 'No Unicode locale found, disabling Unicode tests'
   fi
fi
# }}}

TESTS_PERFORMED=0 TESTS_OK=0 TESTS_FAILED=0 TESTS_SKIPPED=0
JOBS=0 JOBLIST= JOBDESC= JOBREAPER= JOBSYNC=

COLOR_ERR_ON= COLOR_ERR_OFF=
COLOR_WARN_ON= COLOR_WARN_OFF=
COLOR_OK_ON= COLOR_OK_OFF=
ESTAT=0
TEST_NAME=

trap "${rm} -rf ./t.*.d ./t.*.io ./t.*.result; jobreaper_stop" EXIT
trap "exit 1" HUP INT TERM

# JOBS {{{
if [ -n "${NOJOBS}" ]; then
   jobs_max() { :; }
else
   jobs_max() {
      # Do only use half of the CPUs, since we live in pipes or do a lot of
      # shell stuff, and i have seen lesser timeouts like this (on SunOS 5.9)
      # ..the user desired variant
      if ( echo "${MAKEFLAGS}" | ${grep} -- -j ) >/dev/null 2>&1; then
         i=`echo "${MAKEFLAGS}" |
               ${sed} -e 's/^.*-j[ 	]*\([0-9]\{1,\}\).*$/\1/'`
         if ( echo "${i}" | grep -q -e '^[0-9]\{1,\}$' ); then
            printf 'Job number derived from MAKEFLAGS: %s\n' ${i}
            MAXJOBS=${i}
            [ "${MAXJOBS}" -eq 0 ] && MAXJOBS=1
            return
         fi
      fi

      # The actual hardware
      printf 'all:\n' > .t.mk.io
      if ( ${MAKE} -j 10 -f .t.mk.io ) >/dev/null 2>&1; then
         if command -v nproc >/dev/null 2>&1; then
            i=`nproc 2>/dev/null`
            [ ${?} -eq 0 ] && MAXJOBS=${i}
         else
            i=`getconf _NPROCESSORS_ONLN 2>/dev/null`
            j=${?}
            if [ ${j} -ne 0 ]; then
               i=`getconf NPROCESSORS_ONLN 2>/dev/null`
               j=${?}
            fi
            if [ ${j} -ne 0 ]; then
               # SunOS 5.9 ++
               if command -v kstat >/dev/null 2>&1; then
                  i=`PERL5OPT= kstat -p cpu | ${awk} '
                     BEGIN{no=0; FS=":"}
                     {if($2 > no) max = $2; next}
                     END{print ++max}
                     ' 2>/dev/null`
                  j=${?}
               fi
            fi
            if [ ${j} -eq 0 ] && [ -n "${i}" ]; then
               printf 'Job number derived from CPU number: %s\n' ${i}
               MAXJOBS=${i}
            fi
         fi
         [ "${MAXJOBS}" -eq 0 ] && MAXJOBS=1
      fi
   }
fi

jobreaper_start() {
   ( sleep .1 ) >/dev/null 2>&1 && sleep_subsecond=1 || sleep_subsecond=

   i=
   trap 'i=1' USR1
   printf 'Starting job reaper\n'
   (
      parent=${$}
      sleeper= int=0 hot=0
      trap '
         [ -n "${sleeper}" ] && kill -TERM ${sleeper} >/dev/null 2>&1
         int=1 hot=1
      ' USR1
      trap '
         [ -n "${sleeper}" ] && kill -TERM ${sleeper} >/dev/null 2>&1
         int=1 hot=0
      ' USR2
      trap '
         [ -n "${sleeper}" ] && kill -TERM ${sleeper} >/dev/null 2>&1
         echo "Stopping job reaper"
         exit 0
      ' TERM

      # traps are setup, notify parent that we are up and running
      kill -USR1 ${parent}

      while :; do
         int=0
         sleep ${JOBWAIT} &
         sleeper=${!}
         wait ${!}
         sleeper=
         [ "${int}${hot}" = 01 ] && kill -USR1 ${parent} >/dev/null 2>&1
      done
   ) </dev/null & #>/dev/null 2>&1 &
   JOBREAPER=${!}

   if [ ${?} -eq 0 ]; then
      while :; do
         if [ -n "${i}" ]; then
            trap '' USR1
            return
         fi
         printf '.. waiting for job reaper to come up\n'
         sleep 1 &
         wait ${!}
      done
   fi

   JOBREAPER=
   printf '%s!! Cannot start wild job reaper%s\n' \
      "${COLOR_ERR_ON}" "${COLOR_ERR_OFF}"
}

jobreaper_stop() {
   if [ -n "${JOBREAPER}" ]; then
      kill -TERM ${JOBREAPER}
      JOBREAPER=
   fi
}

jspawn() {
   if [ ${MAXJOBS} -gt 1 ]; then
      # We are spawning multiple jobs..
      [ ${JOBS} -eq 0 ] && printf '...'
      JOBS=`add ${JOBS} 1`
      printf ' [%s=%s]' ${JOBS} "${1}"
   else
      JOBS=1
      # Assume problems exist, do not let user hanging on terminal
      if [ -n "${RUN_TEST}" ]; then
         printf '... [%s]\n' "${1}"
      fi
   fi

   (
      ${mkdir} t.${JOBS}.d && cd t.${JOBS}.d &&
         eval t_${1} ${JOBS} ${1} &&
         ${rm} -f ../t.${JOBS}.id
   ) > t.${JOBS}.io </dev/null & # 2>&1 </dev/null &
   JOBLIST="${JOBLIST} ${!}"
   printf '%s\n%s\n' ${!} ${1} > t.${JOBS}.id

   # ..until we should sync or reach the maximum concurrent number
   [ ${JOBS} -lt ${MAXJOBS} ] && return

   jsync 1
}

jsync() {
   [ ${JOBS} -eq 0 ] && return
   [ -z "${JOBSYNC}" ] && [ ${#} -eq 0 ] && return

   [ ${MAXJOBS} -ne 1 ] && printf ' .. waiting\n'

   if [ -n "${JOBREAPER}" ]; then
      timeout= alldone=

      trap 'timeout=1' USR1
      kill -USR1 ${JOBREAPER}

      loops=0
      while [ -z "${timeout}" ]; do
         alldone=1
         i=0
         while [ ${i} -lt ${JOBS} ]; do
            i=`add ${i} 1`
            [ -f t.${i}.id ] || continue
            alldone=
            break
         done
         [ -n "${alldone}" ] && break

         if [ -z "${sleep_subsecond}" ]; then
            loops=`add ${loops} 1`
            [ ${loops} -lt 111 ] && continue
            sleep 1 &
         else
            sleep .1 &
         fi
         wait ${!}
      done

      kill -USR2 ${JOBREAPER}
      trap '' USR1

      if [ -n "${timeout}" ]; then
         i=0
         while [ ${i} -lt ${JOBS} ]; do
            i=`add ${i} 1`
            if [ -f t.${i}.id ] &&
                  read pid < t.${i}.id >/dev/null 2>&1; then
               kill -KILL ${pid}
            fi
         done
      fi
   fi

   # Now collect the zombies
   wait ${JOBLIST}
   JOBLIST=

   # Update global counters
   i=0
   while [ ${i} -lt ${JOBS} ]; do
      i=`add ${i} 1`

      [ -s t.${i}.io ] && ${cat} t.${i}.io
      if [ -n "${DUMPERR}" ] && [ -s ./t.${i}.d/${ERR} ]; then
         printf '%s   [Debug/Devel: nullified errors]\n' "${COLOR_ERR_ON}"
         while read l; do
            printf '   %s\n' "${l}"
         done < t.${i}.d/${ERR}
         printf '%s' "${COLOR_ERR_OFF}"
      fi

      if [ -f t.${i}.id ]; then
         { read pid; read desc; } < t.${i}.id
         desc=${desc#${desc%%[! ]*}}
         desc=${desc%${desc##*[! ]}}
         printf >&2 '%s!! Timeout: reaped job %s [%s]%s\n' \
            "${COLOR_ERR_ON}" ${i} "${desc}" "${COLOR_ERR_OFF}"
         TESTS_FAILED=`add ${TESTS_FAILED} 1`
      elif [ -s t.${i}.result ]; then
         read es tp to tf ts < t.${i}.result
         TESTS_PERFORMED=`add ${TESTS_PERFORMED} ${tp}`
         TESTS_OK=`add ${TESTS_OK} ${to}`
         TESTS_FAILED=`add ${TESTS_FAILED} ${tf}`
         TESTS_SKIPPED=`add ${TESTS_SKIPPED} ${ts}`
         [ "${es}" != 0 ] && ESTAT=${es}
      else
         TESTS_FAILED=`add ${TESTS_FAILED} 1`
         ESTAT=1
      fi
   done
   ${rm} -rf ./t.*.d ./t.*.id ./t.*.io t.*.result

   JOBS=0
}
# }}}

# echoes, checks, etc. {{{
t_prolog() {
   shift

   ESTAT=0 TESTS_PERFORMED=0 TESTS_OK=0 TESTS_FAILED=0 TESTS_SKIPPED=0 \
      TEST_NAME=${1} TEST_ANY=

   printf '%s[%s]%s\n' "" "${TEST_NAME}" ""
}

t_epilog() {
   [ -n "${TEST_ANY}" ] && printf '\n'

   printf '%s %s %s %s %s\n' \
      ${ESTAT} \
         ${TESTS_PERFORMED} ${TESTS_OK} ${TESTS_FAILED} ${TESTS_SKIPPED} \
      > ../t.${1}.result
}

t_echo() {
   [ -n "${TEST_ANY}" ] && __i__=' ' || __i__=
   printf "${__i__}"'%s' "${*}"
   TEST_ANY=1
}

t_echook() {
   [ -n "${TEST_ANY}" ] && __i__=' ' || __i__=
   printf "${__i__}"'%s%s:ok%s' "${COLOR_OK_ON}" "${*}" "${COLOR_OK_OFF}"
   TEST_ANY=1
}

t_echoerr() {
   ESTAT=1
   [ -n "${TEST_ANY}" ] && __i__="\n" || __i__=
   printf "${__i__}"'%sERROR: %s%s\n' \
      "${COLOR_ERR_ON}" "${*}" "${COLOR_ERR_OFF}"
   TEST_ANY=
}

t_echowarn() {
   [ -n "${TEST_ANY}" ] && __i__=' ' || __i__=
   printf "${__i__}"'%s%s%s' "${COLOR_WARN_ON}" "${*}" "${COLOR_WARN_OFF}"
   TEST_ANY=1
}

t_echoskip() {
   [ -n "${TEST_ANY}" ] && __i__=' ' || __i__=
   printf "${__i__}"'%s%s[skip]%s' \
      "${COLOR_WARN_ON}" "${*}" "${COLOR_WARN_OFF}"
   TEST_ANY=1
   TESTS_SKIPPED=`add ${TESTS_SKIPPED} 1`
}

check() {
   restat=${?} tid=${1} eestat=${2} f=${3} s=${4} optmode=${5}

   TESTS_PERFORMED=`add ${TESTS_PERFORMED} 1`

   case "${optmode}" in
   '') ;;
   async)
      [ "$eestat" = - ] || exit 200
      while :; do
         [ -f "${f}" ] && break
         t_echowarn "[${tid}:async=wait]"
         sleep 1 &
         wait ${!}
      done
      ;;
   *) exit 222;;
   esac

   check__bad= check__runx=

   if [ "${eestat}" != - ] && [ "${restat}" != "${eestat}" ]; then
      ESTAT=1
      t_echoerr "${tid}: bad-status: ${restat} != ${eestat}"
      check__bad=1
   fi

   csum="`${cksum} < "${f}" | ${sed} -e 's/[ 	]\{1,\}/ /g'`"
   if [ "${csum}" = "${s}" ]; then
      t_echook "${tid}"
   else
      ESTAT=1
      t_echoerr "${tid}: checksum mismatch (got ${csum})"
      check__bad=1 check__runx=1
   fi

   if [ -z "${check__bad}" ]; then
      TESTS_OK=`add ${TESTS_OK} 1`
   else
      TESTS_FAILED=`add ${TESTS_FAILED} 1`
   fi

   if [ -n "${CHECK_ONLY}${RUN_TEST}" ]; then
      x="t.${TEST_NAME}-${tid}"
      if [ -n "${RUN_TEST}" ] ||
            [ -n "${check__runx}" -a -n "${GIT_REPO}" ]; then
         ${cp} -f "${f}" ../"${x}"
      fi

      if [ -n "${check__runx}" ] && [ -n "${GIT_REPO}" ] &&
            command -v diff >/dev/null 2>&1 &&
            (git rev-parse --verify test-out) >/dev/null 2>&1 &&
            git show test-out:"${x}" > ../"${x}".old 2>/dev/null; then
         diff -ru ../"${x}".old ../"${x}" > ../"${x}".diff
      fi
   fi
}

check_ex0() {
   # $1=test name [$2=status]
   __qm__=${?}
   [ ${#} -gt 1 ] && __qm__=${2}

   TESTS_PERFORMED=`add ${TESTS_PERFORMED} 1`

   if [ ${__qm__} -ne 0 ]; then
      ESTAT=1
      t_echoerr "${1}: unexpected non-0 exit status: ${__qm__}"
      TESTS_FAILED=`add ${TESTS_FAILED} 1`
   else
      t_echook "${1}"
      TESTS_OK=`add ${TESTS_OK} 1`
   fi
}

check_exn0() {
   # $1=test name [$2=status]
   __qm__=${?}
   [ ${#} -gt 1 ] && __qm__=${2}

   TESTS_PERFORMED=`add ${TESTS_PERFORMED} 1`

   if [ ${__qm__} -eq 0 ]; then
      ESTAT=1
      t_echoerr "${1}: unexpected 0 exit status: ${__qm__}"
      TESTS_FAILED=`add ${TESTS_FAILED} 1`
   else
      t_echook "${1}"
      TESTS_OK=`add ${TESTS_OK} 1`
   fi
}
# }}}

color_init() {
   if (command -v tput && tput sgr0 && tput setaf 1 && tput sgr0) \
         >/dev/null 2>&1; then
      COLOR_ERR_ON=`tput setaf 1``tput bold`  COLOR_ERR_OFF=`tput sgr0`
      COLOR_WARN_ON=`tput setaf 3``tput bold`  COLOR_WARN_OFF=`tput sgr0`
      COLOR_OK_ON=`tput setaf 2`  COLOR_OK_OFF=`tput sgr0`
   fi
}

if ( [ "$((1 + 1))" = 2 ] ) >/dev/null 2>&1; then
   add() {
      echo "$((${1} + ${2}))"
   }
else
   add() {
      ${awk} 'BEGIN{print '${1}' + '${2}'}'
   }
fi

if ( [ "$((2 % 3))" = 2 ] ) >/dev/null 2>&1; then
   modulo() {
      echo "$((${1} % ${2}))"
   }
else
   modulo() {
      ${awk} 'BEGIN{print '${1}' % '${2}'}'
   }
fi

have_feat() {
   ( "${RAWMAILX}" ${ARGS} -X'echo $features' -Xx |
      ${grep} +${1}, ) >/dev/null 2>&1
}
# }}}

# Absolute Basics {{{
t_X_Y_opt_input_go_stack() {
   t_prolog "${@}"

   ${cat} <<- '__EOT' > "${BODY}"
	echo 1
	define mac0 {
	   echo mac0-1 via1 $0
	}
	call mac0
	echo 2
	source '\
	   echo "define mac1 {";\
	   echo "  echo mac1-1 via1 \$0";\
	   echo "  call mac0";\
	   echo "  echo mac1-2";\
	   echo "  call mac2";\
	   echo "  echo mac1-3";\
	   echo "}";\
	   echo "echo 1-1";\
	   echo "define mac2 {";\
	   echo "  echo mac2-1 via1 \$0";\
	   echo "  call mac0";\
	   echo "  echo mac2-2";\
	   echo "}";\
	   echo "echo 1-2";\
	   echo "call mac1";\
	   echo "echo 1-3";\
	   echo "source \"\
	      echo echo 1-1-1 via1 \$0;\
	      echo call mac0;\
	      echo echo 1-1-2;\
	   | \"";\
	   echo "echo 1-4";\
	|  '
	echo 3
	call mac2
	echo 4
	undefine *
	__EOT

   # The -X option supports multiline arguments, and those can internally use
   # reverse solidus newline escaping.  And all -X options are joined...
   APO=\'
   < "${BODY}" ${MAILX} ${ARGS} \
      -X 'e\' \
      -X ' c\' \
      -X '  h\' \
      -X '   o \' \
      -X 1 \
      -X'
   define mac0 {
      echo mac0-1 via2 $0
   }
   call mac0
   echo 2
   ' \
      -X'
   source '${APO}'\
      echo "define mac1 {";\
      echo "  echo mac1-1 via2 \$0";\
      echo "  call mac0";\
      echo "  echo mac1-2";\
      echo "  call mac2";\
      echo "  echo mac1-3";\
      echo "}";\
      echo "echo 1-1";\
      echo "define mac2 {";\
      echo "  echo mac2-1 via2 \$0";\
      echo "  call mac0";\
      echo "  echo mac2-2";\
      echo "}";\
      echo "echo 1-2";\
      echo "call mac1";\
      echo "echo 1-3";\
      echo "source \"\
         echo echo 1-1-1 via2 \$0;\
         echo call mac0;\
         echo echo 1-1-2;\
      | \"";\
      echo "echo 1-4";\
   |  '${APO}'
   echo 3
   ' \
      -X'
   call mac2
   echo 4
   undefine *
   ' > "${MBOX}"

   check 1 0 "${MBOX}" '1786542668 416'

   # The -Y option supports multiline arguments, and those can internally use
   # reverse solidus newline escaping.
   APO=\'
   < "${BODY}" ${MAILX} ${ARGS} \
      -X 'echo FIRST_X' \
      -X 'echo SECOND_X' \
      -Y 'e\' \
      -Y ' c\' \
      -Y '  h\' \
      -Y '   o \' \
      -Y 1 \
      -Y'
   define mac0 {
      echo mac0-1 via2 $0
   }
   call mac0
   echo 2
   ' \
      -Y'
   source '${APO}'\
      echo "define mac1 {";\
      echo "  echo mac1-1 via2 \$0";\
      echo "  call mac0";\
      echo "  echo mac1-2";\
      echo "  call mac2";\
      echo "  echo mac1-3";\
      echo "}";\
      echo "echo 1-1";\
      echo "define mac2 {";\
      echo "  echo mac2-1 via2 \$0";\
      echo "  call mac0";\
      echo "  echo mac2-2";\
      echo "}";\
      echo "echo 1-2";\
      echo "call mac1";\
      echo "echo 1-3";\
      echo "source \"\
         echo echo 1-1-1 via2 \$0;\
         echo call mac0;\
         echo echo 1-1-2;\
      | \"";\
      echo "echo 1-4";\
   |  '${APO}'
   echo 3
   ' \
      -Y'
   call mac2
   echo 4
   undefine *
   ' \
      -Y 'echo LAST_Y' > "${MBOX}"

   check 2 0 "${MBOX}" '1845176711 440'

   # Compose mode, too!
   </dev/null ${MAILX} ${ARGS} \
      -X 'echo X before compose mode' \
      -Y '~s Subject via -Y' \
      -Y 'Body via -Y' -. ./.tybox > "${MBOX}" 2>&1
   check 3 0 ./.tybox '264636255 125'
   check 4 - "${MBOX}" '467429373 22'

   ${cat} <<-_EOT | ${MAILX} ${ARGS} -t \
      -X 'echo X before compose mode' \
      -Y '~s Subject via -Y' \
      -Y 'Additional body via -Y' -. ./.tybox > "${MBOX}" 2>&1
	from: heya@exam.ple
	subject:diet not to be seen!

	this body via -t.
	_EOT
   check 5 0 ./.tybox '3313167452 299'
   check 6 - "${MBOX}" '467429373 22'

   #
   printf 'this body via stdin pipe.\n' | ${MAILX} ${NOBATCH_ARGS} \
      -X 'echo X before compose mode' \
      -Y '~s Subject via -Y (not!)' \
      -Y 'Additional body via -Y, nobatch mode' -. ./.tybox > "${MBOX}" 2>&1
   check 7 0 ./.tybox '1561798488 476'
   check 8 - "${MBOX}" '467429373 22'

   printf 'this body via stdin pipe.\n' | ${MAILX} ${ARGS} \
      -X 'echo X before compose mode' \
      -Y '~s Subject via -Y' \
      -Y 'Additional body via -Y, batch mode' -. ./.tybox > "${MBOX}" 2>&1
   check 9 0 ./.tybox '3245082485 650'
   check 10 - "${MBOX}" '467429373 22'

   # Test for [8412796a] (n_cmd_arg_parse(): FIX token error -> crash, e.g.
   # "-RX 'bind;echo $?' -Xx".., 2018-08-02)
   ${MAILX} ${ARGS} -RX'call;echo $?' -Xx > ./.tall 2>&1
   ${MAILX} ${ARGS} -RX'call ;echo $?' -Xx >> ./.tall 2>&1
   ${MAILX} ${ARGS} -RX'call	;echo $?' -Xx >> ./.tall 2>&1
   ${MAILX} ${ARGS} -RX'call      ;echo $?' -Xx >> ./.tall 2>&1
   check cmdline 0 ./.tall '1867586969 8'

   t_epilog "${@}"
}

t_X_errexit() {
   t_prolog "${@}"

   if have_feat uistrings; then :; else
      t_echoskip '[!UISTRINGS]'
      t_epilog "${@}"
      return
   fi

   ${cat} <<- '__EOT' > "${BODY}"
	echo one
	echos nono
	echo two
	__EOT

   </dev/null ${MAILX} ${ARGS} -Snomemdebug \
         -X'echo one' -X' echos nono ' -X'echo two' \
      > "${MBOX}" 2>&1
   check 1 0 "${MBOX}" '916157812 53'

   </dev/null ${MAILX} ${ARGS} -X'source '"${BODY}" -Snomemdebug \
      > "${MBOX}" 2>&1
   check 2 0 "${MBOX}" '916157812 53'

   </dev/null MAILRC="${BODY}" ${MAILX} ${ARGS} -:u -Snomemdebug \
      > "${MBOX}" 2>&1
   check 3 0 "${MBOX}" '916157812 53'

   ##

   </dev/null ${MAILX} ${ARGS} -Serrexit -Snomemdebug \
         -X'echo one' -X' echos nono ' -X'echo two' \
      > "${MBOX}" 2>&1
   check 4 1 "${MBOX}" '2118430867 49'

   </dev/null ${MAILX} ${ARGS} -X'source '"${BODY}" -Serrexit -Snomemdebug \
      > "${MBOX}" 2>&1
   check 5 1 "${MBOX}" '2118430867 49'

   </dev/null MAILRC="${BODY}" ${MAILX} ${ARGS} -:u -Serrexit -Snomemdebug \
      > "${MBOX}" 2>&1
   check 6 1 "${MBOX}" '12955965 172'

   </dev/null MAILRC="${BODY}" ${MAILX} ${ARGS} -:u -Sposix -Snomemdebug \
      > "${MBOX}" 2>&1
   check 7 1 "${MBOX}" '12955965 172'

   ## Repeat 4-7 with ignerr set

   ${sed} -e 's/^echos /ignerr echos /' < "${BODY}" > "${MBOX}"

   </dev/null ${MAILX} ${ARGS} -Serrexit -Snomemdebug \
         -X'echo one' -X'ignerr echos nono ' -X'echo two' \
      > "${BODY}" 2>&1
   check 8 0 "${BODY}" '916157812 53'

   </dev/null ${MAILX} ${ARGS} -X'source '"${MBOX}" -Serrexit -Snomemdebug \
      > "${BODY}" 2>&1
   check 9 0 "${BODY}" '916157812 53'

   </dev/null MAILRC="${MBOX}" ${MAILX} ${ARGS} -:u -Serrexit -Snomemdebug \
      > "${BODY}" 2>&1
   check 10 0 "${BODY}" '916157812 53'

   </dev/null MAILRC="${MBOX}" ${MAILX} ${ARGS} -:u -Sposix -Snomemdebug \
      > "${BODY}" 2>&1
   check 11 0 "${BODY}" '916157812 53'

   t_epilog "${@}"
}

t_Y_errexit() {
   t_prolog "${@}"

   if have_feat uistrings; then :; else
      t_echoskip '[!UISTRINGS]'
      t_epilog "${@}"
      return
   fi

   ${cat} <<- '__EOT' > "${BODY}"
	echo one
	echos nono
	echo two
	__EOT

   </dev/null ${MAILX} ${ARGS} -Snomemdebug \
         -Y'echo one' -Y' echos nono ' -Y'echo two' \
      > "${MBOX}" 2>&1
   check 1 0 "${MBOX}" '916157812 53'

   </dev/null ${MAILX} ${ARGS} -Y'source '"${BODY}" -Snomemdebug \
      > "${MBOX}" 2>&1
   check 2 0 "${MBOX}" '916157812 53'

   ##

   </dev/null ${MAILX} ${ARGS} -Serrexit -Snomemdebug \
         -Y'echo one' -Y' echos nono ' -Y'echo two' \
      > "${MBOX}" 2>&1
   check 3 1 "${MBOX}" '2118430867 49'

   </dev/null ${MAILX} ${ARGS} -Y'source '"${BODY}" -Serrexit -Snomemdebug \
      > "${MBOX}" 2>&1
   check 4 1 "${MBOX}" '2118430867 49'

   ## Repeat 3-4 with ignerr set

   ${sed} -e 's/^echos /ignerr echos /' < "${BODY}" > "${MBOX}"

   </dev/null ${MAILX} ${ARGS} -Serrexit -Snomemdebug \
         -Y'echo one' -Y'ignerr echos nono ' -Y'echo two' \
      > "${BODY}" 2>&1
   check 5 0 "${BODY}" '916157812 53'

   </dev/null ${MAILX} ${ARGS} -Y'source '"${MBOX}" -Serrexit -Snomemdebug \
      > "${BODY}" 2>&1
   check 6 0 "${BODY}" '916157812 53'

   t_epilog "${@}"
}

t_S_freeze() {
   t_prolog "${@}"
   oterm=$TERM
   unset TERM

   # Test basic assumption
   </dev/null MAILRC="${BODY}" ${MAILX} ${ARGS} \
      -X'echo asksub<$asksub> dietcurd<$dietcurd>' \
      -Xx > "${MBOX}" 2>&1
   check 1 0 "${MBOX}" '270686329 21'

   #
   ${cat} <<- '__EOT' > "${BODY}"
	echo asksub<$asksub>
	set asksub
	echo asksub<$asksub>
	__EOT
   </dev/null MAILRC="${BODY}" ${MAILX} ${ARGS} -:u \
      -Snoasksub -Sasksub -Snoasksub \
      -X'echo asksub<$asksub>' -X'set asksub' -X'echo asksub<$asksub>' \
      -Xx > "${MBOX}" 2>&1
   check 2 0 "${MBOX}" '3182942628 37'

   ${cat} <<- '__EOT' > "${BODY}"
	echo asksub<$asksub>
	unset asksub
	echo asksub<$asksub>
	__EOT
   </dev/null MAILRC="${BODY}" ${MAILX} ${ARGS} -:u \
      -Snoasksub -Sasksub \
      -X'echo asksub<$asksub>' -X'unset asksub' -X'echo asksub<$asksub>' \
      -Xx > "${MBOX}" 2>&1
   check 3 0 "${MBOX}" '2006554293 39'

   #
   ${cat} <<- '__EOT' > "${BODY}"
	echo dietcurd<$dietcurd>
	set dietcurd=cherry
	echo dietcurd<$dietcurd>
	__EOT
   </dev/null MAILRC="${BODY}" ${MAILX} ${ARGS} -:u \
      -Sdietcurd=strawberry -Snodietcurd -Sdietcurd=vanilla \
      -X'echo dietcurd<$dietcurd>' -X'unset dietcurd' \
         -X'echo dietcurd<$dietcurd>' \
      -Xx > "${MBOX}" 2>&1
   check 4 0 "${MBOX}" '1985768109 65'

   ${cat} <<- '__EOT' > "${BODY}"
	echo dietcurd<$dietcurd>
	unset dietcurd
	echo dietcurd<$dietcurd>
	__EOT
   </dev/null MAILRC="${BODY}" ${MAILX} ${ARGS} -:u \
      -Sdietcurd=strawberry -Snodietcurd \
      -X'echo dietcurd<$dietcurd>' -X'set dietcurd=vanilla' \
         -X'echo dietcurd<$dietcurd>' \
      -Xx > "${MBOX}" 2>&1
   check 5 0 "${MBOX}" '151574279 51'

   # TODO once we have a detached one with env=1..
   if [ -n "`</dev/null ${MAILX} ${ARGS} -X'!echo \$TERM' -Xx`" ]; then
      t_echoskip 's_freeze-{6,7}:[shell sets $TERM]'
   else
      ${cat} <<- '__EOT' > "${BODY}"
		!echo "shell says TERM<$TERM>"
	echo TERM<$TERM>
		!echo "shell says TERM<$TERM>"
	set TERM=cherry
		!echo "shell says TERM<$TERM>"
	echo TERM<$TERM>
		!echo "shell says TERM<$TERM>"
		__EOT
      </dev/null MAILRC="${BODY}" ${MAILX} ${ARGS} -:u \
         -STERM=strawberry -SnoTERM -STERM=vanilla \
         -X'echo mail<$TERM>' -X'unset TERM' \
         -X'!echo "shell says TERM<$TERM>"' -X'echo TERM<$TERM>' \
         -Xx > "${MBOX}" 2>&1
   check 6 0 "${MBOX}" '1211476036 167'

      ${cat} <<- '__EOT' > "${BODY}"
		!echo "shell says TERM<$TERM>"
	echo TERM<$TERM>
		!echo "shell says TERM<$TERM>"
	set TERM=cherry
		!echo "shell says TERM<$TERM>"
	echo TERM<$TERM>
		!echo "shell says TERM<$TERM>"
	__EOT
      </dev/null MAILRC="${BODY}" ${MAILX} ${ARGS} -:u \
         -STERM=strawberry -SnoTERM \
         -X'echo TERM<$TERM>' -X'set TERM=vanilla' \
         -X'!echo "shell says TERM<$TERM>"' -X'echo TERM<$TERM>' \
         -Xx > "${MBOX}" 2>&1
      check 7 0 "${MBOX}" '3365080441 132'
   fi

   TERM=$oterm
   t_epilog "${@}"
}

t_f_batch_order() {
   t_prolog "${@}"

   t__gen_msg subject f-batch-order > "${MBOX}"

   # This would exit 64 (EX_USAGE) from ? to [fbddb3b3] (FIX: -f: add
   # n_PO_f_FLAG to avoid that command line order matters)
   </dev/null ${MAILX} ${NOBATCH_ARGS} -R -f -# \
      -Y 'echo du;h;echo da;x' "${MBOX}" >./.tall 2>&1
   check 1 0 ./.tall '1690247457 86'

   # And this ever worked (hopefully)
   </dev/null ${MAILX} ${NOBATCH_ARGS} -R -# -f \
      -Y 'echo du;h;echo da;x' "${MBOX}" >./.tall 2>&1
   check 2 0 ./.tall '1690247457 86'

   t_epilog "${@}"
}

t_input_inject_semicolon_seq() {
   t_prolog "${@}"

   ${cat} <<- '__EOT' | ${MAILX} ${ARGS} > "${MBOX}"
	define mydeepmac {
		echon '(mydeepmac)';
	}
	define mymac {
		echon this_is_mymac;call mydeepmac;echon ';';
	}
	echon one';';call mymac;echon two";";call mymac;echo three$';';
	define mymac {
		echon this_is_mymac;call mydeepmac;echon ,TOO'!;';
	}
	echon one';';call mymac;echon two";";call mymac;echo three$';';
	__EOT

   check 1 0 "${MBOX}" '512117110 140'

   t_epilog "${@}"
}

t_wysh() {
   t_prolog "${@}"

   ${cat} <<- '__EOT' > "${BODY}"
	#
	echo abcd
	echo a'b'c'd'
	echo a"b"c"d"
	echo a$'b'c$'d'
	echo 'abcd'
	echo "abcd"
	echo $'abcd'
	echo a\ b\ c\ d
	echo a 'b c' d
	echo a "b c" d
	echo a $'b c' d
	#
	echo 'a$`"\'
	echo "a\$\`'\"\\"
	echo $'a\$`\'\"\\'
	echo $'a\$`\'"\\'
	# DIET=CURD TIED=
	echo 'a${DIET}b${TIED}c\${DIET}d\${TIED}e' # COMMENT
	echo "a${DIET}b${TIED}c\${DIET}d\${TIED}e"
	echo $'a${DIET}b${TIED}c\${DIET}d\${TIED}e'
	#
	echo a$'\101\0101\x41\u0041\u41\U00000041\U41'c
	echo a$'\u0041\u41\u0C1\U00000041\U41'c
	echo a$'\377'c
	echo a$'\0377'c
	echo a$'\400'c
	echo a$'\0400'c
	echo a$'\U1100001'c
	#
	echo a$'b\0c'd
	echo a$'b\00c'de
	echo a$'b\000c'df
	echo a$'b\0000c'dg
	echo a$'b\x0c'dh
	echo a$'b\x00c'di
	echo a$'b\u0'dj
	echo a$'b\u00'dk
	echo a$'b\u000'dl
	echo a$'b\u0000'dm
	echo a$'b\U0'dn
	echo a$'b\U00'do
	echo a$'b\U000'dp
	echo a$'b\U0000'dq
	echo a$'b\U00000'dr
	echo a$'b\U000000'ds
	echo a$'b\U0000000'dt
	echo a$'b\U00000000'du
	#
	echo a$'\cI'b
	echo a$'\011'b
	echo a$'\x9'b
	echo a$'\u9'b
	echo a$'\U9'b
	echo a$'\c@'b c d
	__EOT

   if [ -z "${UTF8_LOCALE}" ]; then
      t_echoskip 'wysh-unicode:[no UTF-8 locale]'
   else
      < "${BODY}" DIET=CURD TIED= \
      LC_ALL=${UTF8_LOCALE} ${MAILX} ${ARGS} > "${MBOX}" 2>>${ERR}
      check unicode 0 "${MBOX}" '475805847 317'
   fi

   < "${BODY}" DIET=CURD TIED= ${MAILX} ${ARGS} > "${MBOX}" 2>>${ERR}
   check c 0 "${MBOX}" '1473887148 321'

   ${cat} <<- '__EOT' | ${MAILX} ${ARGS} > "${MBOX}"
   wysh set mager='\hey\'
   varshow mager
   wysh set mager="\hey\\"
   varshow mager
   wysh set mager=$'\hey\\'
   varshow mager
	__EOT
   check 3 0 "${MBOX}" '1289698238 69'

   t_epilog "${@}"
}

t_commandalias() {
   t_prolog "${@}"

   ${cat} <<- '__EOT' | ${MAILX} ${ARGS} > "${MBOX}"
	commandalias echo echo hoho
	echo stop.
	commandalias X Xx
	commandalias Xx XxX
	commandalias XxX XxXx
	commandalias XxXx XxXxX
	commandalias XxXxX XxXxXx
	commandalias XxXxXx echo huhu
	commandalias XxXxXxX echo huhu
	X
	commandalias XxXxXx XxXxXxX
	X
	uncommandalias echo
	commandalias XxXxXx echo huhu
	X
	__EOT

   check 1 0 "${MBOX}" '1638809585 36'

   t_epilog "${@}"
}

t_posix_abbrev() {
   t_prolog "${@}"

   # In POSIX C181 standard order
   </dev/null ${MAILX} ${ARGS} \
      -Y 'echon alias/a\ ; ? a; echon group/g\ ; ?g' \
      -Y 'echon alternates/alt\ ; ? alt' \
      -Y 'echon chdir/ch\ ; ? ch' \
      -Y 'echon copy/c\ ; ? c; echon Copy/C\ ; ?C' \
      -Y 'echon delete/d\ ; ? d' \
      -Y 'echon discard/di\ ; ? di; echon ignore/ig\ ; ?ig' \
      -Y 'echon echo/ec\ ; ? ec' \
      -Y 'echon edit/e\ ; ? e' \
      -Y 'echon exit/ex\ ; ? ex; echon xit/x\ ; ?x' \
      -Y 'echon file/fi\ ; ? fi; echon folder/fold\ ; ?  fold' \
      -Y 'echon followup/fo\ ; ? fo; echon Followup/F\ ; ?F' \
      -Y 'echon from/f\ ; ? f' \
      -Y 'echon headers/h\ ; ? h' \
      -Y 'echon help/hel\ ; ? hel' \
      -Y 'echon hold/ho\ ; ? ho; echon preserve/pre\ ; ? pre' \
      -Y 'echon if/i\ ; ? i; echon else/el\ ; ? el; echon endif/en\ ; ? en' \
      -Y 'echon list/l\ ; ? l' \
      -Y 'echon mail/m\ ; ? m' \
      -Y 'echon mbox/mb\ ; ? mb' \
      -Y 'echon next/n\ ; ? n' \
      -Y 'echon pipe/pi\ ; ? pi' \
      -Y 'echon Print/P\ ; ? P; echon Type/T\ ; ? T' \
      -Y 'echon print/p\ ; ? p; echon type/t\ ; ? t' \
      -Y 'echon quit/q\ ; ? q' \
      -Y 'echon Reply/R\ ; ? R' \
      -Y 'echon reply/r\ ; ? r' \
      -Y 'echon retain/ret\ ; ? ret' \
      -Y 'echon save/s\ ; ? s; echon Save/S\ ; ? S' \
      -Y 'echon set/se\ ; ? se' \
      -Y 'echon shell/sh\ ; ? sh' \
      -Y 'echon size/si\ ; ? si' \
      -Y 'echon source/so\ ; ? so' \
      -Y 'echon touch/tou\ ; ? tou' \
      -Y 'echon unalias/una\ ; ? una' \
      -Y 'echon undelete/u\ ; ? u' \
      -Y 'echon unset/uns\ ; ? uns' \
      -Y 'echon visual/v\ ; ? v' \
      -Y 'echon write/w\ ; ? w' \
      | ${sed} -e 's/:.*$//' > "${MBOX}"
   check 1 0 "${MBOX}" '1012680481 968'

   t_epilog "${@}"
}
# }}}

# Basics {{{
t_shcodec() {
   t_prolog "${@}"

   # XXX the first needs to be checked, it is quite dumb as such
   ${cat} <<- '__EOT' | ${MAILX} ${ARGS} > "${MBOX}" 2>&1
	commandalias x echo '$?/$^ERRNAME'
	shcodec e abcd
	x
	shcodec d abcd
	x
	shcodec e a'b'c'd'
	x
	shcodec d a'b'c'd'
	x
	shcodec e a"b"c"d"
	x
	shcodec d a"b"c"d"
	x
	shcodec e a$'b'c$'d'
	x
	shcodec d a$'b'c$'d'
	x
	shcodec e 'abcd'
	x
	shcodec d 'abcd'
	x
	shcodec e "abcd"
	x
	shcodec d "abcd"
	x
	shcodec e $'abcd'
	x
	shcodec d $'abcd'
	x
	# same but with vput
	commandalias y echo '$?/$^ERRNAME $res'
	vput shcodec res e abcd
	y
	eval shcodec d $res
	x
	vput shcodec res d abcd
	y
	eval shcodec d $res
	x
	vput shcodec res e a'b'c'd'
	y
	eval shcodec d $res
	x
	vput shcodec res d a'b'c'd'
	y
	eval shcodec d $res
	x
	vput shcodec res e a"b"c"d"
	y
	eval shcodec d $res
	x
	vput shcodec res d a"b"c"d"
	y
	eval shcodec d $res
	x
	vput shcodec res e a$'b'c$'d'
	y
	eval shcodec d $res
	x
	vput shcodec res d a$'b'c$'d'
	y
	eval shcodec d $res
	x
	vput shcodec res e 'abcd'
	y
	eval shcodec d $res
	x
	vput shcodec res d 'abcd'
	y
	eval shcodec d $res
	x
	vput shcodec res e "abcd"
	y
	eval shcodec d $res
	x
	vput shcodec res d "abcd"
	y
	eval shcodec d $res
	x
	vput shcodec res e $'abcd'
	y
	eval shcodec d $res
	x
	vput shcodec res d $'abcd'
	y
	eval shcodec d $res
	x
	#
	vput shcodec res e a b\ c d
	y
	eval shcodec d $res
	x
	vput shcodec res d a b\ c d
	y
	vput shcodec res e ab cd
	y
	eval shcodec d $res
	x
	vput shcodec res d 'ab cd'
	y
	vput shcodec res e a 'b c' d
	y
	eval shcodec d $res
	x
	vput shcodec res d a 'b c' d
	y
	vput shcodec res e a "b c" d
	y
	eval shcodec d $res
	x
	vput shcodec res d a "b c" d
	y
	vput shcodec res e a $'b c' d
	y
	eval shcodec d $res
	x
	vput shcodec res d a $'b c' d
	y
	#
	vput shcodec res e 'a$`"\'
	y
	eval shcodec d $res
	x
	vput shcodec res d 'a$`"\'
	y
	vput shcodec res e "a\$\`'\"\\"
	y
	eval shcodec d $res
	x
	vput shcodec res d "a\$\`'\"\\"
	y
	vput shcodec res e $'a\$`\'\"\\'
	y
	eval shcodec d $res
	x
	vput shcodec res d $'a\$`\'\"\\'
	y
	vput shcodec res e $'a\$`\'"\\'
	y
	eval shcodec d $res
	x
	vput shcodec res d $'a\$`\'"\\'
	y
	#
	set diet=curd
	vput shcodec res e a${diet}c
	y
	eval shcodec d $res
	x
	eval vput shcodec res e a${diet}c
	y
	eval shcodec d $res
	x
	vput shcodec res e "a${diet}c"
	y
	eval shcodec d $res
	x
	eval vput shcodec res e "a${diet}c"
	y
	eval shcodec d $res
	x
	__EOT
   check 1 0 "${MBOX}" '3316745312 1241'

   if [ -z "${UTF8_LOCALE}" ]; then
      t_echoskip 'unicode:[no UTF-8 locale]'
   else
      ${cat} <<- '__EOT' | LC_ALL=${UTF8_LOCALE} \
         ${MAILX} ${ARGS} > "${MBOX}" 2>>${ERR}
		#
		shcodec e täst
		shcodec +e täst
		shcodec d $'t\u00E4st'
		shcodec e aՍc
		shcodec +e aՍc
		shcodec d $'a\u054Dc'
		shcodec e a𝕂c
		shcodec +e a𝕂c
		shcodec d $'a\U0001D542c'
		__EOT
      check unicode 0 "${MBOX}" '1175985867 77'
   fi

   t_epilog "${@}"
}

t_ifelse() {
   t_prolog "${@}"

   # v15compat: old and new tests share the same result files!
   # v15compat: i.e., just throw away -old tests one day

   # Nestable conditions test
   ${cat} <<- '__EOT' | ${MAILX} ${ARGS} > "${MBOX}"
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
		if $dietcurd ==? 'Yoho'
			echo 5-1.ok
		else
			echo 5-1.err
		endif
		if $dietcurd == 'Yoho'
			echo 5-2.err
		else
			echo 5-2.ok
		endif
		if $dietcurd != 'yoho'
		   echo 6.err
		else
		   echo 6.ok
		endif
		if $dietcurd !=?case 'Yoho'
			echo 6-1.err
		else
			echo 6-1.ok
		endif
		if $dietcurd != 'Yoho'
			echo 6-2.ok
		else
			echo 6-2.err
		endif
		# Nesting
		if faLse
		   echo 7.err1
		   if tRue
		      echo 7.err2
		      if yEs
		         echo 7.err3
		      else
		         echo 7.err4
		      endif
		      echo 7.err5
		   endif
		   echo 7.err6
		else
		   echo 7.ok7
		   if YeS
		      echo 7.ok8
		      if No
		         echo 7.err9
		      else
		         echo 7.ok9
		      endif
		      echo 7.ok10
		   else
		      echo 7.err11
		      if yeS
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
		# integer
		set dietcurd=10
		if $dietcurd -lt 11
		   echo 11.ok1
		   if $dietcurd -gt 9
		      echo 11.ok2
		   else
		      echo 11.err2
		   endif
		   if $dietcurd -eq 10
		      echo 11.ok3
		   else
		      echo 11.err3
		   endif
		   if $dietcurd -ge 10
		      echo 11.ok4
		   else
		      echo 11.err4
		   endif
		   if $dietcurd -le 10
		      echo 11.ok5
		   else
		      echo 11.err5
		   endif
		   if $dietcurd -ge 11
		      echo 11.err6
		   else
		      echo 11.ok6
		   endif
		   if $dietcurd -le 9
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
		   if $dietcurd >? abB
		      echo 12.ok2
		   else
		      echo 12.err2
		   endif
		   if $dietcurd ==?case aBC
		      echo 12.ok3
		   else
		      echo 12.err3
		   endif
		   if $dietcurd >=?ca AbC
		      echo 12.ok4
		   else
		      echo 12.err4
		   endif
		   if $dietcurd <=? ABc
		      echo 12.ok5
		   else
		      echo 12.err5
		   endif
		   if $dietcurd >=?case abd
		      echo 12.err6
		   else
		      echo 12.ok6
		   endif
		   if $dietcurd <=? abb
		      echo 12.err7
		   else
		      echo 12.ok7
		   endif
		else
		   echo 12.err1
		endif
		if $dietcurd < aBc
		   echo 12-1.ok
		else
		   echo 12-1.err
		endif
		if $dietcurd <? aBc
		   echo 12-2.err
		else
		   echo 12-2.ok
		endif
		if $dietcurd > ABc
		   echo 12-3.ok
		else
		   echo 12-3.err
		endif
		if $dietcurd >? ABc
		   echo 12-3.err
		else
		   echo 12-3.ok
		endif
		if $dietcurd =%?case aB
		   echo 13.ok
		else
		   echo 13.err
		endif
		if $dietcurd =% aB
		   echo 13-1.err
		else
		   echo 13-1.ok
		endif
		if $dietcurd =%? bC
		   echo 14.ok
		else
		   echo 14.err
		endif
		if $dietcurd !% aB
		   echo 15-1.ok
		else
		   echo 15-1.err
		endif
		if $dietcurd !%? aB
		   echo 15-2.err
		else
		   echo 15-2.ok
		endif
		if $dietcurd !% bC
		   echo 15-3.ok
		else
		   echo 15-3.err
		endif
		if $dietcurd !%? bC
		   echo 15-4.err
		else
		   echo 15-4.ok
		endif
		if $dietcurd =% Cd
		   echo 16.err
		else
		   echo 16.ok
		endif
		if $dietcurd !% Cd
		   echo 17.ok
		else
		   echo 17.err
		endif
		set diet=abc curd=abc
		if $diet == $curd
		   echo 18.ok
		else
		   echo 18.err
		endif
		set diet=abc curd=abcd
		if $diet != $curd
		   echo 19.ok
		else
		   echo 19.err
		endif
		# 1. Shitty grouping capabilities as of today
		unset diet curd ndefined
		if [ [ false ] || [ false ] || [ true ] ] && \
		      [ [ false ] || [ true ] ] && \
		      [ yes ]
		   echo 20.ok
		else
		   echo 20.err
		endif
		if [ [ [ [ 0 ] || [ 1 ] ] && [ [ 1 ] || [ 0 ] ] ] && [ 1 ] ] && [ yes ]
		   echo 21.ok
		else
		   echo 21.err
		endif
		if [ [ 1 ] || [ 0 ] || [ 0 ] || [ 0 ] ]
		   echo 22.ok
		else
		   echo 22.err
		endif
		if [ [ 1 ] || [ 0 ] || [ 0 ] || [ 0 ] || [ [ 1 ] ] ]
		   echo 23.ok
		else
		   echo 23.err
		endif
		if [ [ 1 ] || [ 0 ] || [ 0 ] || [ 0 ] || [ [ 1 ] ] || [ 1 ] ] && [ no ]
		   echo 24.err
		else
		   echo 24.ok
		endif
		if [ [ 1 ] || [ 0 ] || [ 0 ] || [ 0 ] || [ [ 1 ] ] || [ 1 ] ] \
		      && [ no ] || [ yes ]
		   echo 25.ok
		else
		   echo 25.err
		endif
		if [ [ [ [ [ [ [ 1 ] ] && [ 1 ] ] && [ 1 ] ] && [ 1 ] ] ] && [ 1 ] ]
		   echo 26.ok
		else
		   echo 26.err
		endif
		if [ [ [ [ [ [ [ 1 ] ] && [ 1 ] ] && [ 1 ] ] && [ 1 ] ] ] && [ 0 ] ]
		   echo 27.err
		else
		   echo 27.ok
		endif
		if [ [ [ [ [ [ [ 1 ] ] && [ 1 ] ] && [ 0 ] ] && [ 1 ] ] ] && [ 1 ] ]
		   echo 28.err
		else
		   echo 28.ok
		endif
		if [ [ [ [ [ [ [ 0 ] ] && [ 1 ] ] && [ 1 ] ] && [ 1 ] ] ] && [ 1 ] ]
		   echo 29.err
		else
		   echo 29.ok
		endif
		if [ 1 ] || [ 0 ] || [ 0 ] || [ 0 ] && [ 0 ]
		   echo 30.err
		else
		   echo 30.ok
		endif
		if [ 1 ] || [ 0 ] || [ 0 ] || [ 0 ] && [ 1 ]
		   echo 31.ok
		else
		   echo 31.err
		endif
		if [ 0 ] || [ 0 ] || [ 0 ] || [ 1 ] && [ 0 ]
		   echo 32.err
		else
		   echo 32.ok
		endif
		if [ 0 ] || [ 0 ] || [ 0 ] || [ 1 ] && [ 1 ]
		   echo 33.ok
		else
		   echo 33.err
		endif
		if [ 0 ] || [ 0 ] || [ 0 ] || [ 1 ] && [ 0 ] || [ 1 ] && [ 0 ]
		   echo 34.err
		else
		   echo 34.ok
		endif
		if [ 0 ] || [ 0 ] || [ 0 ] || [ 1 ] && [ 0 ] || [ 1 ] && [ 1 ]
		   echo 35.ok
		else
		   echo 35.err
		endif
		set diet=yo curd=ho
		if [ [ $diet == 'yo' ] && [ $curd == 'ho' ] ] && [ $ndefined ]
		   echo 36.err
		else
		   echo 36.ok
		endif
		set ndefined
		if [ [ $diet == 'yo' ] && [ $curd == 'ho' ] ] && [ $ndefined ]
		   echo 37.ok
		else
		   echo 37.err
		endif
		# 2. Shitty grouping capabilities as of today
		unset diet curd ndefined
		if [ false || false || true ] && [ false || true ] && yes
		   echo 40.ok
		else
		   echo 40.err
		endif
		if [ [ [ 0 || 1 ] && [ 1 || 0 ] ] && 1 ] && [ yes ]
		   echo 41.ok
		else
		   echo 41.err
		endif
		if [ 1 || 0 || 0 || 0 ]
		   echo 42.ok
		else
		   echo 42.err
		endif
		if [ 1 || 0 || 0 || 0 || [ 1 ] ]
		   echo 43.ok
		else
		   echo 43.err
		endif
		if [ 1 || 0 || 0 || 0 || [ 1 ] || 1 ] && no
		   echo 44.err
		else
		   echo 44.ok
		endif
		if [ 1 || 0 || 0 || 0 || 1 || [ 1 ] ] && no || [ yes ]
		   echo 45.ok
		else
		   echo 45.err
		endif
		if [ [ [ [ [ [ 1 ] && 1 ] && 1 ] && 1 ] ] && [ 1 ] ]
		   echo 46.ok
		else
		   echo 46.err
		endif
		if [ [ [ [ [ [ 1 ] && 1 ] && 1 ] && [ 1 ] ] ] && 0 ]
		   echo 47.err
		else
		   echo 47.ok
		endif
		if [ [ [ [ [ [ [ 1 ] ] && 1 ] && 0 ] && [ 1 ] ] ] && 1 ]
		   echo 48.err
		else
		   echo 48.ok
		endif
		if [ [ [ [ [ [ 0 ] && 1 ] && 1 ] && 1 ] ] && 1 ]
		   echo 49.err
		else
		   echo 49.ok
		endif
		if 1 || 0 || 0 || 0 && 0
		   echo 50.err
		else
		   echo 50.ok
		endif
		if 1 || 0 || 0 || 0 && 1
		   echo 51.ok
		else
		   echo 51.err
		endif
		if 0 || 0 || 0 || 1 && 0
		   echo 52.err
		else
		   echo 52.ok
		endif
		if 0 || 0 || 0 || 1 && 1
		   echo 53.ok
		else
		   echo 53.err
		endif
		if 0 || 0 || 0 || 1 && 0 || 1 && 0
		   echo 54.err
		else
		   echo 54.ok
		endif
		if 0 || 0 || 0 || 1 && 0 || 1 && 1
		   echo 55.ok
		else
		   echo 55.err
		endif
		set diet=yo curd=ho
		if [ $diet == 'yo' && $curd == 'ho' ] && $ndefined
		   echo 56.err
		else
		   echo 56.ok
		endif
		if $diet == 'yo' && $curd == 'ho' && $ndefined
		   echo 57.err
		else
		   echo 57.ok
		endif
		set ndefined
		if [ $diet == 'yo' && $curd == 'ho' ] && $ndefined
		   echo 57.ok
		else
		   echo 57.err
		endif
		if $diet == 'yo' && $curd == 'ho' && $ndefined
		   echo 58.ok
		else
		   echo 58.err
		endif
		if [ [ [ [ [ [ $diet == 'yo' && $curd == 'ho' && $ndefined ] ] ] ] ] ]
		   echo 59.ok
		else
		   echo 59.err
		endif
		# Some more en-braced variables
		set diet=yo curd=ho
		if ${diet} == ${curd}
		   echo 70.err
		else
		   echo 70.ok
		endif
		if ${diet} != ${curd}
		   echo 71.ok
		else
		   echo 71.err
		endif
		if $diet == ${curd}
		   echo 72.err
		else
		   echo 72.ok
		endif
		if ${diet} == $curd
		   echo 73.err
		else
		   echo 73.ok
		endif
		# Unary !
		if ! 0 && ! ! 1 && ! ! ! ! 2 && 3
		   echo 80.ok
		else
		   echo 80.err
		endif
		if ! 0 && ! [ ! 1 ] && ! [ ! [ ! [ ! 2 ] ] ] && 3
		   echo 81.ok
		else
		   echo 81.err
		endif
		if [ ! 0 ] && [ ! [ ! 1 ] ] && [ ! [ ! [ ! [ ! [ 2 ] ] ] ] ] && 3
		   echo 82.ok
		else
		   echo 82.err
		endif
		if [ ! 0 ] && [ ! [ ! 1 ] ] && [ ! [ ! [ ! [ ! [ 2 ] ] ] ] ] && ! 3
		   echo 83.err
		else
		   echo 83.ok
		endif
		if [ ! 0 ] && [ ! [ ! 1 ] ] && ! [ [ ! [ ! [ ! [ 2 ] ] ] ] ] && ! 3
		   echo 84.err
		else
		   echo 84.ok
		endif
		if [ ! 0 ] && ! [ ! [ ! 1 ] ] && [ ! [ ! [ ! [ ! [ 2 ] ] ] ] ] && 3
		   echo 85.err
		else
		   echo 85.ok
		endif
		if ! [ ! 0 ] && [ ! [ ! 1 ] ] && [ ! [ ! [ ! [ ! [ 2 ] ] ] ] ] && 3
		   echo 86.err
		else
		   echo 86.ok
		endif
		if [ ! 0 ] && [ ! [ ! 1 ] ] && [ ! [ ! [ ! [ ! [ 2 ] ] ] ] ] || 3
		   echo 87.ok
		else
		   echo 87.err
		endif
		if [ ! 0 ] && [ ! ! [ ! ! 1 ] ] && [ ! ! [ ! ! [ ! ! [ ! ! [ 2 ] ] ] ] ]
		   echo 88.ok
		else
		   echo 88.err
		endif
		# Unary !, odd
		if ! 0 && ! ! 1 && ! ! ! 0 && 3
		   echo 90.ok
		else
		   echo 90.err
		endif
		if ! 0 && ! [ ! 1 ] && ! [ ! [ ! [ 0 ] ] ] && 3
		   echo 91.ok
		else
		   echo 91.err
		endif
		if [ ! 0 ] && [ ! [ ! 1 ] ] && [ ! [ ! [ ! [ [ 0 ] ] ] ] ] && 3
		   echo 92.ok
		else
		   echo 92.err
		endif
		if [ ! 0 ] && [ ! [ ! 1 ] ] && [ ! [ ! ! [ ! [ ! 0 ] ] ] ] && ! 3
		   echo 93.err
		else
		   echo 93.ok
		endif
		if [ ! 0 ] && [ ! [ ! 1 ] ] && ! [ ! [ ! [ ! [ ! 0 ] ] ] ] && 3
		   echo 94.ok
		else
		   echo 94.err
		endif
		if [ ! 0 ] && ! [ ! [ ! 1 ] ] && [ ! ! [ ! [ ! [ ! [ 0 ] ] ] ] ] && 3
		   echo 95.err
		else
		   echo 95.ok
		endif
		if ! [ ! 0 ] && [ ! [ ! 1 ] ] && [ ! [ ! [ ! [ ! ! 0 ] ] ] ] && 3
		   echo 96.err
		else
		   echo 96.ok
		endif
		if [ ! 0 ] && [ ! [ ! 1 ] ] && [ ! [ ! [ ! [ ! [ ! 0 ] ] ] ] ] || 3
		   echo 97.ok
		else
		   echo 97.err
		endif
		if [ ! 0 ] && [ ! ! [ ! ! 1 ] ] && [ ! ! [ ! ! [ ! ! [ ! [ 0 ] ] ] ] ]
		   echo 98.ok
		else
		   echo 98.err
		endif
	__EOT

   check normal-old 0 "${MBOX}" '1688759742 719' # pre v15compat

   if have_feat regex; then
      ${cat} <<- '__EOT' | ${MAILX} ${ARGS} > "${MBOX}"
			set dietcurd=yoho
			if $dietcurd =~ '^yo.*'
			   echo 1.ok
			else
			   echo 1.err
			endif
			if $dietcurd =~ '^Yo.*'
			   echo 1-1.err
			else
			   echo 1-1.ok
			endif
			if $dietcurd =~?case '^Yo.*'
			   echo 1-2.ok
			else
			   echo 1-2.err
			endif
			if $dietcurd =~ '^yOho.+'
			   echo 2.err
			else
			   echo 2.ok
			endif
			if $dietcurd !~? '.*Ho$'
			   echo 3.err
			else
			   echo 3.ok
			endif
			if $dietcurd !~ '.+yohO$'
			   echo 4.ok
			else
			   echo 4.err
			endif
			if [ $dietcurd !~?cas '.+yoho$' ]
			   echo 5.ok
			else
			   echo 5.err
			endif
			if ! [ $dietcurd =~?case '.+yoho$' ]
			   echo 6.ok
			else
			   echo 6.err
			endif
			if ! ! [ $dietcurd !~? '.+yoho$' ]
			   echo 7.ok
			else
			   echo 7.err
			endif
			if ! [ ! [ $dietcurd !~? '.+yoho$' ] ]
			   echo 8.ok
			else
			   echo 8.err
			endif
			if [ ! [ ! [ $dietcurd !~? '.+yoho$' ] ] ]
			   echo 9.ok
			else
			   echo 9.err
			endif
			if ! [ ! [ ! [ $dietcurd !~ '.+yoho$' ] ] ]
			   echo 10.err
			else
			   echo 10.ok
			endif
			if !  ! ! $dietcurd !~ '.+yoho$'
			   echo 11.err
			else
			   echo 11.ok
			endif
			if !  ! ! $dietcurd =~ '.+yoho$'
			   echo 12.ok
			else
			   echo 12.err
			endif
			if ! [ ! ! [ ! [ $dietcurd !~ '.+yoho$' ] ] ]
			   echo 13.ok
			else
			   echo 13.err
			endif
			set diet=abc curd='^abc$'
			if $diet =~ $curd
			   echo 14.ok
			else
			   echo 14.err
			endif
			set diet=abc curd='^abcd$'
			if $diet !~ $curd
			   echo 15.ok
			else
			   echo 15.err
			endif
		__EOT

      check regex-old 0 "${MBOX}" '1115671789 95' # pre v15compat
   else
      t_echoskip 'regex-old:[no regex option]'
   fi

   ## post v15compat

   ${cat} <<- '__EOT' | ${MAILX} ${ARGS} -Sv15-compat=X > "${MBOX}"
	\if -N xyz; echo 1.err-1; \
		\elif ! -Z xyz;echo 1.err-2;\
		\elif -n "$xyz"     ;      echo 1.err-3   ;    \
		\elif ! -z "$xyz"     ;      echo 1.err-4   ;    \
		\else;echo 1.ok;\
		\end
	\set xyz
	\if ! -N xyz; echo 2.err-1; \
		\elif -Z xyz;echo 2.err-2;\
		\elif -n "$xyz"     ;      echo 2.err-3   ;    \
		\elif ! -z "$xyz"     ;      echo 2.err-4   ;    \
		\else;echo 2.ok;\
		\end
	\set xyz=notempty
	\if ! -N xyz; echo 3.err-1; \
		\elif -Z xyz;echo 3.err-2;\
		\elif ! -n "$xyz";echo 3.err-3;\
		\elif -z "$xyz";echo 3.err-4;\
		\else;echo 3.ok;\
		\end
	\if $xyz != notempty;echo 4.err-1;else;echo 4.ok;\end
	\if $xyz == notempty;echo 5.ok;else;echo 5.err-1;\end
	__EOT

   check NnZz_whiteout 0 "${MBOX}" '4280687462 25'

   # TODO t_ifelse: individual tests as for NnZz_whiteout
   # Nestable conditions test
   ${cat} <<- '__EOT' | ${MAILX} ${ARGS} -Sv15-compat=x > "${MBOX}"
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
		if [ "$dietcurd" != "" ]
		   echo 3.err
		else
		   echo 3.ok
		endif
		set dietcurd=yoho
		if $'\$dietcurd' != ""
		   echo 4.ok
		else
		   echo 4.err
		endif
		if "$dietcurd" == 'yoho'
		   echo 5.ok
		else
		   echo 5.err
		endif
		if $'\$dietcurd' ==? 'Yoho'
			echo 5-1.ok
		else
			echo 5-1.err
		endif
		if $dietcurd == 'Yoho'
			echo 5-2.err
		else
			echo 5-2.ok
		endif
		if $dietcurd != 'yoho'
		   echo 6.err
		else
		   echo 6.ok
		endif
		if $dietcurd !=?case 'Yoho'
			echo 6-1.err
		else
			echo 6-1.ok
		endif
		if $dietcurd != 'Yoho'
			echo 6-2.ok
		else
			echo 6-2.err
		endif
		# Nesting
		if faLse
		   echo 7.err1
		   if tRue
		      echo 7.err2
		      if yEs
		         echo 7.err3
		      else
		         echo 7.err4
		      endif
		      echo 7.err5
		   endif
		   echo 7.err6
		else
		   echo 7.ok7
		   if YeS
		      echo 7.ok8
		      if No
		         echo 7.err9
		      else
		         echo 7.ok9
		      endif
		      echo 7.ok10
		   else
		      echo 7.err11
		      if yeS
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
		# integer
		set dietcurd=10
		if $dietcurd -lt 11
		   echo 11.ok1
		   if $dietcurd -gt 9
		      echo 11.ok2
		   else
		      echo 11.err2
		   endif
		   if $dietcurd -eq 10
		      echo 11.ok3
		   else
		      echo 11.err3
		   endif
		   if $dietcurd -ge 10
		      echo 11.ok4
		   else
		      echo 11.err4
		   endif
		   if $dietcurd -le 10
		      echo 11.ok5
		   else
		      echo 11.err5
		   endif
		   if $dietcurd -ge 11
		      echo 11.err6
		   else
		      echo 11.ok6
		   endif
		   if $dietcurd -ge?satu -0xFFFFFFFFFFFFFFFF1
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
		   if $dietcurd >? abB
		      echo 12.ok2
		   else
		      echo 12.err2
		   endif
		   if $dietcurd ==?case aBC
		      echo 12.ok3
		   else
		      echo 12.err3
		   endif
		   if $dietcurd >=?ca AbC
		      echo 12.ok4
		   else
		      echo 12.err4
		   endif
		   if $dietcurd <=? ABc
		      echo 12.ok5
		   else
		      echo 12.err5
		   endif
		   if $dietcurd >=?case abd
		      echo 12.err6
		   else
		      echo 12.ok6
		   endif
		   if $dietcurd <=? abb
		      echo 12.err7
		   else
		      echo 12.ok7
		   endif
		else
		   echo 12.err1
		endif
		if $dietcurd < aBc
		   echo 12-1.ok
		else
		   echo 12-1.err
		endif
		if $dietcurd <? aBc
		   echo 12-2.err
		else
		   echo 12-2.ok
		endif
		if $dietcurd > ABc
		   echo 12-3.ok
		else
		   echo 12-3.err
		endif
		if $dietcurd >? ABc
		   echo 12-3.err
		else
		   echo 12-3.ok
		endif
		if $dietcurd =%?case aB
		   echo 13.ok
		else
		   echo 13.err
		endif
		if $dietcurd =% aB
		   echo 13-1.err
		else
		   echo 13-1.ok
		endif
		if $dietcurd =%? bC
		   echo 14.ok
		else
		   echo 14.err
		endif
		if $dietcurd !% aB
		   echo 15-1.ok
		else
		   echo 15-1.err
		endif
		if $dietcurd !%? aB
		   echo 15-2.err
		else
		   echo 15-2.ok
		endif
		if $dietcurd !% bC
		   echo 15-3.ok
		else
		   echo 15-3.err
		endif
		if $dietcurd !%? bC
		   echo 15-4.err
		else
		   echo 15-4.ok
		endif
		if $dietcurd =% Cd
		   echo 16.err
		else
		   echo 16.ok
		endif
		if $dietcurd !% Cd
		   echo 17.ok
		else
		   echo 17.err
		endif
		set diet='ab c' curd='ab c'
		if "$diet" == "$curd"
		   echo 18.ok
		else
		   echo 18.err
		endif
		set diet='ab c' curd='ab cd'
		if "$diet" != "$curd"
		   echo 19.ok
		else
		   echo 19.err
		endif
		# 1. Shitty grouping capabilities as of today
		unset diet curd ndefined
		if [ [ false ] || [ false ] || [ true ] ] && \
		      [ [ false ] || [ true ] ] && \
		      [ yes ]
		   echo 20.ok
		else
		   echo 20.err
		endif
		if [ [ [ [ 0 ] || [ 1 ] ] && [ [ 1 ] || [ 0 ] ] ] && [ 1 ] ] && [ yes ]
		   echo 21.ok
		else
		   echo 21.err
		endif
		if [ [ 1 ] || [ 0 ] || [ 0 ] || [ 0 ] ]
		   echo 22.ok
		else
		   echo 22.err
		endif
		if [ [ 1 ] || [ 0 ] || [ 0 ] || [ 0 ] || [ [ 1 ] ] ]
		   echo 23.ok
		else
		   echo 23.err
		endif
		if [ [ 1 ] || [ 0 ] || [ 0 ] || [ 0 ] || [ [ 1 ] ] || [ 1 ] ] && [ no ]
		   echo 24.err
		else
		   echo 24.ok
		endif
		if [ [ 1 ] || [ 0 ] || [ 0 ] || [ 0 ] || [ [ 1 ] ] || [ 1 ] ] \
		      && [ no ] || [ yes ]
		   echo 25.ok
		else
		   echo 25.err
		endif
		if [ [ [ [ [ [ [ 1 ] ] && [ 1 ] ] && [ 1 ] ] && [ 1 ] ] ] && [ 1 ] ]
		   echo 26.ok
		else
		   echo 26.err
		endif
		if [ [ [ [ [ [ [ 1 ] ] && [ 1 ] ] && [ 1 ] ] && [ 1 ] ] ] && [ 0 ] ]
		   echo 27.err
		else
		   echo 27.ok
		endif
		if [ [ [ [ [ [ [ 1 ] ] && [ 1 ] ] && [ 0 ] ] && [ 1 ] ] ] && [ 1 ] ]
		   echo 28.err
		else
		   echo 28.ok
		endif
		if [ [ [ [ [ [ [ 0 ] ] && [ 1 ] ] && [ 1 ] ] && [ 1 ] ] ] && [ 1 ] ]
		   echo 29.err
		else
		   echo 29.ok
		endif
		if [ 1 ] || [ 0 ] || [ 0 ] || [ 0 ] && [ 0 ]
		   echo 30.err
		else
		   echo 30.ok
		endif
		if [ 1 ] || [ 0 ] || [ 0 ] || [ 0 ] && [ 1 ]
		   echo 31.ok
		else
		   echo 31.err
		endif
		if [ 0 ] || [ 0 ] || [ 0 ] || [ 1 ] && [ 0 ]
		   echo 32.err
		else
		   echo 32.ok
		endif
		if [ 0 ] || [ 0 ] || [ 0 ] || [ 1 ] && [ 1 ]
		   echo 33.ok
		else
		   echo 33.err
		endif
		if [ 0 ] || [ 0 ] || [ 0 ] || [ 1 ] && [ 0 ] || [ 1 ] && [ 0 ]
		   echo 34.err
		else
		   echo 34.ok
		endif
		if [ 0 ] || [ 0 ] || [ 0 ] || [ 1 ] && [ 0 ] || [ 1 ] && [ 1 ]
		   echo 35.ok
		else
		   echo 35.err
		endif
		set diet=yo curd=ho
		if [ [ $diet == 'yo' ] && [ $curd == 'ho' ] ] && \
		      [ -N ndefined || -n "$ndefined" || \
		      ! -Z ndefined || ! -z "$ndefined" ]
		   echo 36.err
		else
		   echo 36.ok
		endif
		set ndefined
		if [ [ $diet == 'yo' ] && [ $curd == 'ho' ] ] && \
		      -N ndefined && ! -n "$ndefined" && \
		      ! -Z ndefined && -z "$ndefined"
		   echo 37.ok
		else
		   echo 37.err
		endif
		# 2. Shitty grouping capabilities as of today
		unset diet curd ndefined
		if [ false || false || true ] && [ false || true ] && yes
		   echo 40.ok
		else
		   echo 40.err
		endif
		if [ [ [ 0 || 1 ] && [ 1 || 0 ] ] && 1 ] && [ yes ]
		   echo 41.ok
		else
		   echo 41.err
		endif
		if [ 1 || 0 || 0 || 0 ]
		   echo 42.ok
		else
		   echo 42.err
		endif
		if [ 1 || 0 || 0 || 0 || [ 1 ] ]
		   echo 43.ok
		else
		   echo 43.err
		endif
		if [ 1 || 0 || 0 || 0 || [ 1 ] || 1 ] && no
		   echo 44.err
		else
		   echo 44.ok
		endif
		if [ 1 || 0 || 0 || 0 || 1 || [ 1 ] ] && no || [ yes ]
		   echo 45.ok
		else
		   echo 45.err
		endif
		if [ [ [ [ [ [ 1 ] && 1 ] && 1 ] && 1 ] ] && [ 1 ] ]
		   echo 46.ok
		else
		   echo 46.err
		endif
		if [ [ [ [ [ [ 1 ] && 1 ] && 1 ] && [ 1 ] ] ] && 0 ]
		   echo 47.err
		else
		   echo 47.ok
		endif
		if [ [ [ [ [ [ [ 1 ] ] && 1 ] && 0 ] && [ 1 ] ] ] && 1 ]
		   echo 48.err
		else
		   echo 48.ok
		endif
		if [ [ [ [ [ [ 0 ] && 1 ] && 1 ] && 1 ] ] && 1 ]
		   echo 49.err
		else
		   echo 49.ok
		endif
		if 1 || 0 || 0 || 0 && 0
		   echo 50.err
		else
		   echo 50.ok
		endif
		if 1 || 0 || 0 || 0 && 1
		   echo 51.ok
		else
		   echo 51.err
		endif
		if 0 || 0 || 0 || 1 && 0
		   echo 52.err
		else
		   echo 52.ok
		endif
		if 0 || 0 || 0 || 1 && 1
		   echo 53.ok
		else
		   echo 53.err
		endif
		if 0 || 0 || 0 || 1 && 0 || 1 && 0
		   echo 54.err
		else
		   echo 54.ok
		endif
		if 0 || 0 || 0 || 1 && 0 || 1 && 1
		   echo 55.ok
		else
		   echo 55.err
		endif
		set diet=yo curd=ho
		if [ $diet == 'yo' && $curd == 'ho' ] && \
		      [ -N ndefined || -n "$ndefined" || \
		         ! -Z ndefined || ! -z "$ndefined" ]
		   echo 56.err
		else
		   echo 56.ok
		endif
		if [ $diet == 'yo' && $curd == 'ho' && \
		      [ [ -N ndefined || -n "$ndefined" || \
		         ! -Z ndefined || ! -z "$ndefined" ] ] ]
		   echo 57.err
		else
		   echo 57.ok
		endif
		set ndefined
		if [ $diet == 'yo' && $curd == 'ho' ] && \
		      -N ndefined && ! -n "$ndefined" && \
		      ! -Z ndefined && -z "$ndefined"
		   echo 57.ok
		else
		   echo 57.err
		endif
		if $diet == 'yo' && $curd == 'ho' && ! -Z ndefined
		   echo 58.ok
		else
		   echo 58.err
		endif
		if [ [ [ [ [ [ $diet == 'yo' && $curd == 'ho' && -N ndefined ] ] ] ] ] ]
		   echo 59.ok
		else
		   echo 59.err
		endif
		# Some more en-braced variables
		set diet=yo curd=ho
		if ${diet} == ${curd}
		   echo 70.err
		else
		   echo 70.ok
		endif
		if "${diet}" != "${curd}"
		   echo 71.ok
		else
		   echo 71.err
		endif
		if $diet == ${curd}
		   echo 72.err
		else
		   echo 72.ok
		endif
		if ${diet} == $curd
		   echo 73.err
		else
		   echo 73.ok
		endif
		# Unary !
		if ! 0 && ! ! 1 && ! ! ! ! 2 && 3
		   echo 80.ok
		else
		   echo 80.err
		endif
		if ! 0 && ! [ ! 1 ] && ! [ ! [ ! [ ! 2 ] ] ] && 3
		   echo 81.ok
		else
		   echo 81.err
		endif
		if [ ! 0 ] && [ ! [ ! 1 ] ] && [ ! [ ! [ ! [ ! [ 2 ] ] ] ] ] && 3
		   echo 82.ok
		else
		   echo 82.err
		endif
		if [ ! 0 ] && [ ! [ ! 1 ] ] && [ ! [ ! [ ! [ ! [ 2 ] ] ] ] ] && ! 3
		   echo 83.err
		else
		   echo 83.ok
		endif
		if [ ! 0 ] && [ ! [ ! 1 ] ] && ! [ [ ! [ ! [ ! [ 2 ] ] ] ] ] && ! 3
		   echo 84.err
		else
		   echo 84.ok
		endif
		if [ ! 0 ] && ! [ ! [ ! 1 ] ] && [ ! [ ! [ ! [ ! [ 2 ] ] ] ] ] && 3
		   echo 85.err
		else
		   echo 85.ok
		endif
		if ! [ ! 0 ] && [ ! [ ! 1 ] ] && [ ! [ ! [ ! [ ! [ 2 ] ] ] ] ] && 3
		   echo 86.err
		else
		   echo 86.ok
		endif
		if [ ! 0 ] && [ ! [ ! 1 ] ] && [ ! [ ! [ ! [ ! [ 2 ] ] ] ] ] || 3
		   echo 87.ok
		else
		   echo 87.err
		endif
		if [ ! 0 ] && [ ! ! [ ! ! 1 ] ] && [ ! ! [ ! ! [ ! ! [ ! ! [ 2 ] ] ] ] ]
		   echo 88.ok
		else
		   echo 88.err
		endif
		# Unary !, odd
		if ! 0 && ! ! 1 && ! ! ! 0 && 3
		   echo 90.ok
		else
		   echo 90.err
		endif
		if ! 0 && ! [ ! 1 ] && ! [ ! [ ! [ 0 ] ] ] && 3
		   echo 91.ok
		else
		   echo 91.err
		endif
		if [ ! 0 ] && [ ! [ ! 1 ] ] && [ ! [ ! [ ! [ [ 0 ] ] ] ] ] && 3
		   echo 92.ok
		else
		   echo 92.err
		endif
		if [ ! 0 ] && [ ! [ ! 1 ] ] && [ ! [ ! ! [ ! [ ! 0 ] ] ] ] && ! 3
		   echo 93.err
		else
		   echo 93.ok
		endif
		if [ ! 0 ] && [ ! [ ! 1 ] ] && ! [ ! [ ! [ ! [ ! 0 ] ] ] ] && 3
		   echo 94.ok
		else
		   echo 94.err
		endif
		if [ ! 0 ] && ! [ ! [ ! 1 ] ] && [ ! ! [ ! [ ! [ ! [ 0 ] ] ] ] ] && 3
		   echo 95.err
		else
		   echo 95.ok
		endif
		if ! [ ! 0 ] && [ ! [ ! 1 ] ] && [ ! [ ! [ ! [ ! ! 0 ] ] ] ] && 3
		   echo 96.err
		else
		   echo 96.ok
		endif
		if [ ! 0 ] && [ ! [ ! 1 ] ] && [ ! [ ! [ ! [ ! [ ! 0 ] ] ] ] ] || 3
		   echo 97.ok
		else
		   echo 97.err
		endif
		if [ ! 0 ] && [ ! ! [ ! ! 1 ] ] && [ ! ! [ ! ! [ ! ! [ ! [ 0 ] ] ] ] ]
		   echo 98.ok
		else
		   echo 98.err
		endif
	__EOT

   check normal 0 "${MBOX}" '1688759742 719'

   if have_feat regex; then
      ${cat} <<- '__EOT' | ${MAILX} ${ARGS} -Sv15-compat=X > "${MBOX}"
			set dietcurd=yoho
			if $dietcurd =~ '^yo.*'
			   echo 1.ok
			else
			   echo 1.err
			endif
			if "$dietcurd" =~ '^Yo.*'
			   echo 1-1.err
			else
			   echo 1-1.ok
			endif
			if $dietcurd =~?case '^Yo.*'
			   echo 1-2.ok
			else
			   echo 1-2.err
			endif
			if $dietcurd =~ '^yOho.+'
			   echo 2.err
			else
			   echo 2.ok
			endif
			if $dietcurd !~? '.*Ho$'
			   echo 3.err
			else
			   echo 3.ok
			endif
			if $dietcurd !~ '.+yohO$'
			   echo 4.ok
			else
			   echo 4.err
			endif
			if [ $dietcurd !~?cas '.+yoho$' ]
			   echo 5.ok
			else
			   echo 5.err
			endif
			if ! [ "$dietcurd" =~?case '.+yoho$' ]
			   echo 6.ok
			else
			   echo 6.err
			endif
			if ! ! [ $'\$dietcurd' !~? '.+yoho$' ]
			   echo 7.ok
			else
			   echo 7.err
			endif
			if ! [ ! [ $dietcurd !~? '.+yoho$' ] ]
			   echo 8.ok
			else
			   echo 8.err
			endif
			if [ ! [ ! [ $dietcurd !~? '.+yoho$' ] ] ]
			   echo 9.ok
			else
			   echo 9.err
			endif
			if ! [ ! [ ! [ $dietcurd !~ '.+yoho$' ] ] ]
			   echo 10.err
			else
			   echo 10.ok
			endif
			if !  ! ! $dietcurd !~ '.+yoho$'
			   echo 11.err
			else
			   echo 11.ok
			endif
			if !  ! ! $dietcurd =~ '.+yoho$'
			   echo 12.ok
			else
			   echo 12.err
			endif
			if ! [ ! ! [ ! [ $dietcurd !~ '.+yoho$' ] ] ]
			   echo 13.ok
			else
			   echo 13.err
			endif
			set diet=abc curd='^abc$'
			if $diet =~ $curd
			   echo 14.ok
			else
			   echo 14.err
			endif
			set diet=abc curd='^abcd$'
			if "$diet" !~ $'\$curd'
			   echo 15.ok
			else
			   echo 15.err
			endif
		__EOT

      check regex 0 "${MBOX}" '1115671789 95'
   else
      t_echoskip 'regex:[!REGEX]'
   fi

   t_epilog "${@}"
}

t_localopts() {
   t_prolog "${@}"

   # Nestable conditions test
   ${cat} <<- '__EOT' | ${MAILX} ${ARGS} > "${MBOX}" 2>&1
	define t2 {
	   echo in: t2
	   set t2=t2
	   echo $t2
	}
	define t1 {
	   echo in: t1
	   set gv1=gv1
	   localopts on
	   set lv1=lv1 lv2=lv2
	   set lv3=lv3
	   call t2
	   localopts off
	   set gv2=gv2
	   echo $gv1 $lv1 ${lv2} ${lv3} ${gv2}, $t2
	}
	define t0 {
	   echo in: t0
	   call t1
	   echo $gv1 $lv1 ${lv2} ${lv3} ${gv2}, $t2
	   echo "$gv1 $lv1 ${lv2} ${lv3} ${gv2}, $t2"
	}
	account trouble {
	   echo in: trouble
	   call t0
	}
	call t0
	unset gv1 gv2
	account trouble
	echo active trouble: $gv1 $lv1 ${lv2} ${lv3} ${gv2}, $t3
	account null
	echo active null: $gv1 $lv1 ${lv2} ${lv3} ${gv2}, $t3

   #
   define ll2 {
      localopts $1
      set x=2
      echo ll2=$x
   }
   define ll1 {
      wysh set y=$1; shift; eval localopts $y; localopts $1; shift
      set x=1
      echo ll1.1=$x
      call ll2 $1
      echo ll1.2=$x
   }
   define ll0 {
      wysh set y=$1; shift; eval localopts $y; localopts $1; shift
      set x=0
      echo ll0.1=$x
      call ll1 $y "$@"
      echo ll0.2=$x
   }
   define llx {
      echo ----- $1: $2 -> $3 -> $4
      echo ll-1.1=$x
      eval localopts $1
      call ll0 "$@"
      echo ll-1.2=$x
      unset x
   }
   define lly {
      call llx 'call off' on on on
      call llx 'call off' off on on
      call llx 'call off' on off on
      call llx 'call off' on off off
      localopts call-fixate on
      call llx 'call-fixate on' on on on
      call llx 'call-fixate on' off on on
      call llx 'call-fixate on' on off on
      call llx 'call-fixate on' on off off
      unset x;localopts call on
      call llx 'call on' on on on
      call llx 'call on' off on on
      call llx 'call on' on off on
      call llx 'call on' on off off
   }
   call lly
	__EOT

   check 1 0 "${MBOX}" '4016155249 1246'

   t_epilog "${@}"
}

t_local() {
   t_prolog "${@}"

   ${cat} <<- '__EOT' | ${MAILX} ${ARGS} > "${MBOX}" 2>&1
	define du2 {
	   echo du2-1 du=$du
	   local set du=$1
	   echo du2-2 du=$du
	   local unset du
	   echo du2-3 du=$du
	}
	define du {
	   local set du=dudu
	   echo du-1 du=$du
	   call du2 du2du2
	   echo du-2 du=$du
	   local set nodu
	   echo du-3 du=$du
	}
	define ich {
	   echo ich-1 du=$du
	   call du
	   echo ich-2 du=$du
	}
	define wir {
	   localopts $1
	   set du=wirwir
	   echo wir-1 du=$du
	   call ich
	   echo wir-2 du=$du
	}
	echo ------- global-1 du=$du
	call ich
	echo ------- global-2 du=$du
	set du=global
	call ich
	echo ------- global-3 du=$du
	call wir on
	echo ------- global-4 du=$du
	call wir off
	echo ------- global-5 du=$du
	__EOT

   check 1 0 "${MBOX}" '2411598140 641'

   t_epilog "${@}"
}

t_environ() {
   t_prolog "${@}"

   ${cat} <<- '__EOT' | EK1=EV1 EK2=EV2 ${MAILX} ${ARGS} > "${MBOX}" 2>&1
	echo "we: EK1<$EK1> EK2<$EK2> EK3<$EK3> EK4<$EK4> NEK5<$NEK5>"
	!echo "shell: EK1<$EK1> EK2<$EK2> EK3<$EK3> EK4<$EK4> NEK5<$NEK5>"
	varshow EK1 EK2 EK3 EK4 NEK5

	echo environ set EK3 EK4, set NEK5
	environ set EK3=EV3 EK4=EV4
	set NEK5=NEV5
	echo "we: EK1<$EK1> EK2<$EK2> EK3<$EK3> EK4<$EK4> NEK5<$NEK5>"
	!echo "shell: EK1<$EK1> EK2<$EK2> EK3<$EK3> EK4<$EK4> NEK5<$NEK5>"
	varshow EK1 EK2 EK3 EK4 NEK5

	echo removing NEK5 EK3
	unset NEK5
	environ unset EK3
	echo "we: EK1<$EK1> EK2<$EK2> EK3<$EK3> EK4<$EK4> NEK5<$NEK5>"
	!echo "shell: EK1<$EK1> EK2<$EK2> EK3<$EK3> EK4<$EK4> NEK5<$NEK5>"
	varshow EK1 EK2 EK3 EK4 NEK5

	echo changing EK1, EK4
	set EK1=EV1_CHANGED EK4=EV4_CHANGED
	echo "we: EK1<$EK1> EK2<$EK2> EK3<$EK3> EK4<$EK4> NEK5<$NEK5>"
	!echo "shell: EK1<$EK1> EK2<$EK2> EK3<$EK3> EK4<$EK4> NEK5<$NEK5>"
	varshow EK1 EK2 EK3 EK4 NEK5

	echo linking EK4, rechanging EK1, EK4
	environ link EK4
	set EK1=EV1 EK4=EV4
	echo "we: EK1<$EK1> EK2<$EK2> EK3<$EK3> EK4<$EK4> NEK5<$NEK5>"
	!echo "shell: EK1<$EK1> EK2<$EK2> EK3<$EK3> EK4<$EK4> NEK5<$NEK5>"
	varshow EK1 EK2 EK3 EK4 NEK5

	echo unset all
	unset EK1 EK2 EK4
	echo "we: EK1<$EK1> EK2<$EK2> EK3<$EK3> EK4<$EK4> NEK5<$NEK5>"
	!echo "shell: EK1<$EK1> EK2<$EK2> EK3<$EK3> EK4<$EK4> NEK5<$NEK5>"
	varshow EK1 EK2 EK3 EK4 NEK5
	__EOT

   check 1 0 "${MBOX}" '1685686686 1342'

t_epilog "${@}"
return


   ${cat} <<- '__EOT' | ${MAILX} ${ARGS} > "${MBOX}" 2>&1
	define l4 {
	   echo '-------> L4 (environ unlink EK1, own localopts)'
	   localopts yes
	   environ unlink EK1
	   set LK1=LK1_L4 EK1=EK1_L4
		echo "we: L4: LK1<$LK1> EK1<$EK1>"
		!echo "shell: L4: LK1<$LK1> EK1<$EK1>"
		varshow LK1 EK1
	   echo '-------< L4'
	}
	define l3 {
	   echo '-------> L3'
	   set LK1=LK1_L3 EK1=EK1_L3
		echo "we: L3-pre: LK1<$LK1> EK1<$EK1>"
		!echo "shell: L3-pre: LK1<$LK1> EK1<$EK1>"
		varshow LK1 EK1
	   call l4
		echo "we: L3-post: LK1<$LK1> EK1<$EK1>"
		!echo "shell: L3-post: LK1<$LK1> EK1<$EK1>"
		varshow LK1 EK1
	   echo '-------< L3'
	}
	define l2 {
	   echo '-------> L2'
	   set LK1=LK1_L2 EK1=EK1_L2
		echo "we: L2-pre: LK1<$LK1> EK1<$EK1>"
		!echo "shell: L2-pre: LK1<$LK1> EK1<$EK1>"
		varshow LK1 EK1
	   call l3
		echo "we: L2-post: LK1<$LK1> EK1<$EK1>"
		!echo "shell: L2-post: LK1<$LK1> EK1<$EK1>"
		varshow LK1 EK1
	   echo '-------< L2'
	}
	define l1 {
	   echo '-------> L1 (environ link EK1; localopts call-fixate)'
	   localopts call-fixate yes
	   set LK1=LK1_L1 EK1=EK1_L1
	   environ link EK1
		echo "we: L1-pre: LK1<$LK1> EK1<$EK1>"
		!echo "shell: L1-pre: LK1<$LK1> EK1<$EK1>"
		varshow LK1 EK1
	   call l2
		echo "we: L1-post: LK1<$LK1> EK1<$EK1>"
		!echo "shell: L1-post: LK1<$LK1> EK1<$EK1>"
		varshow LK1 EK1
	   echo '-------< L1'
	}
	echo "we: outer-pre: LK1<$LK1> EK1<$EK1>"
	!echo "shell: outer-pre: LK1<$LK1> EK1<$EK1>"
	varshow LK1 EK1
	call l1
	echo "we: outer-post: LK1<$LK1> EK1<$EK1>"
	!echo "shell: outer-post: LK1<$LK1> EK1<$EK1>"
	varshow LK1 EK1
	__EOT

   check 2 0 "${MBOX}" '1903030743 1131'

   t_epilog "${@}"
}

t_macro_param_shift() {
   t_prolog "${@}"

   ${cat} <<- '__EOT' | ${MAILX} ${ARGS} > "${MBOX}" 2>>${ERR}
	define t2 {
	   echo in: t2
	   echo t2.0 has $#/${#} parameters: "$1,${2},$3" (${*}) [$@]
	   localopts on
	   wysh set ignerr=$1
	   shift
	   localopts off
	   echo t2.1 has $#/${#} parameters: "$1,${2},$3" (${*}) [$@]
	   if [ $# > 1 ] || [ $ignerr == '' ]
	      shift 2
	   else
	      ignerr shift 2
	   endif
	   echo t2.2:$? has $#/${#} parameters: "$1,${2},$3" (${*}) [$@]
	   shift 0
	   echo t2.3:$? has $#/${#} parameters: "$1,${2},$3" (${*}) [$@]
	   if [ $# > 0 ]
	      shift
	   endif
	   echo t2.4:$? has $#/${#} parameters: "$1,${2},$3" (${*}) [$@]
	}
	define t1 {
	   set errexit
	   echo in: t1
	   call t2 1 you get four args
	   echo t1.1: $?';' ignerr ($ignerr) should not exist
	   call t2 1 you get 'three args'
	   echo t1.2: $?';' ignerr ($ignerr) should not exist
	   call t2 1 you 'get two args'
	   echo t1.3: $?';' ignerr ($ignerr) should not exist
	   call t2 1 'you get one arg'
	   echo t1.4: $?';' ignerr ($ignerr) should not exist
	   ignerr call t2 '' 'you get one arg'
	   echo t1.5: $?';' ignerr ($ignerr) should not exist
	}
	call t1
	__EOT

   check 1 0 "${MBOX}" '1402489146 1682'

   t_epilog "${@}"
}

t_addrcodec() {
   t_prolog "${@}"

   ${cat} <<- '__EOT' | ${MAILX} ${ARGS} > "${MBOX}" 2>&1
	commandalias x echo '$?/$^ERRNAME $res'
	vput addrcodec res e 1 <doog@def>
	x
	eval vput addrcodec res d $res
	x
	vput addrcodec res e 2 . <doog@def>
	x
	eval vput addrcodec res d $res
	x
	vput addrcodec res e 3 Sauer Dr. <doog@def>
	x
	eval vput addrcodec res d $res
	x
	vput addrcodec res e 3.50 Sauer (Ma) Dr. <doog@def>
	x
	eval vput addrcodec res d $res
	x
	vput addrcodec res e 3.51 Sauer (Ma) "Dr." <doog@def>
	x
	eval vput addrcodec res d $res
	x
	#
	vput addrcodec res +e 4 Sauer (Ma) Dr. <doog@def>
	x
	eval vput addrcodec res d $res
	x
	vput addrcodec res +e 5 Sauer (Ma) Braten Dr. <doog@def>
	x
	eval vput addrcodec res d $res
	x
	vput addrcodec res +e 6 Sauer (Ma) Braten Dr. (Heu) <doog@def>
	x
	eval vput addrcodec res d $res
	x
	vput addrcodec res +e 7 Sauer (Ma) Braten Dr. (Heu) <doog@def> (bu)
	x
	eval vput addrcodec res d $res
	x
	vput addrcodec res +e 8 \
		Dr. Sauer (Ma) Braten Dr. (Heu) <doog@def> (bu) Boom. Boom
	x
	eval vput addrcodec res d $res
	x
	vput addrcodec res +e 9 Dr.Sauer(Ma)Braten Dr. (Heu) <doog@def>
	x
	eval vput addrcodec res d $res
	x
	vput addrcodec res +e 10 (Ma)Braten Dr. (Heu) <doog@def>
	x
	eval vput addrcodec res d $res
	x
	vput addrcodec res +e 11 (Ma)Braten Dr"." (Heu) <doog@def>
	x
	eval vput addrcodec res d $res
	x
	vput addrcodec res +e 12 Dr.     Sauer  (Ma)   Braten    Dr.   (u) <doog@def>
	x
	eval vput addrcodec res d $res
	x
	vput addrcodec res +e 13(Ma)Braten    Dr.     (Heu)     <doog@def>
	x
	eval vput addrcodec res d $res
	x
	vput addrcodec res +e 14 Hey, Du <doog@def> Wie() findet Dr. das? ()
	x
	eval vput addrcodec res d $res
	x
	vput addrcodec res +e 15 \
		Hey, Du <doog@def> Wie() findet "" Dr. "" das? ()
	x
	eval vput addrcodec res d $res
	x
	vput addrcodec res +e 16 \
		"Hey," "Du" <doog@def> "Wie()" findet "" Dr. "" das? ()
	x
	eval vput addrcodec res d $res
	x
	vput addrcodec res +e 17 \
		"Hey" Du <doog@def> "Wie() findet " " Dr. """ das? ()
	x
	eval vput addrcodec res d $res
	x
	vput addrcodec res +e 18 \
		<doog@def> "Hey" Du "Wie() findet " " Dr. """ das? ()
	x
	eval vput addrcodec res d $res
	x
	vput addrcodec res +e 19 Hey\,\"  <doog@def> "Wie()" findet \" Dr. \" das?
	x
	eval vput addrcodec res d $res
	x
	#
	vput addrcodec res ++e 20 Hey\,\"  <doog@def> "Wie()" findet \" Dr. \" das?
	x
	vput addrcodec res ++e 21 Hey\,\""  <doog@def> "Wie()" findet \" Dr. \" das?
	x
	eval vput addrcodec res d $res
	x
	#
	vput addrcodec res \
	   +++e 22 Hey\\,\"  <doog@def> "Wie()" findet \" Dr. \" das?
	x
	eval vput addrcodec res d $res
	x
	#
	vput addrcodec res s \
		"23 Hey\\,\\\" \"Wie" () "\" findet \\\" Dr. \\\" das?" <doog@def>
	x
	#
	# Fix for [f3852f88]
	vput addrcodec res ++e <from2@exam.ple> 100 (comment) "Quot(e)d"
	x
	eval vput addrcodec res d $res
	x
	vput addrcodec res e <from2@exam.ple> 100 (comment) "Quot(e)d"
	x
	eval vput addrcodec res d $res
	x
	__EOT

   check 1 0 "${MBOX}" '1047317989 2612'

   ${cat} <<- '__EOT' | ${MAILX} ${ARGS} > "${MBOX}" 2>&1
	commandalias x echo '$?/$^ERRNAME $res'
   mlist isa1@list
   mlsubscribe isa2@list
   #
   vput addrcodec res skin Hey\\,\"  <isa0@list> "Wie()" find \" Dr. \" das?
   x
   vput addrcodec res skinlist Hey\\,\"  <isa0@list> "Wie()" find \" Dr. \" das?
   x
   vput addrcodec res skin Hey\\,\"  <isa1@list> "Wie()" find \" Dr. \" das?
   x
   vput addrcodec res skinlist Hey\\,\"  <isa1@list> "Wie()" find \" Dr. \" das?
   x
   vput addrcodec res skin Hey\\,\"  <isa2@list> "Wie()" find \" Dr. \" das?
   x
   vput addrcodec res skinlist Hey\\,\"  <isa2@list> "Wie()" find \" Dr. \" das?
   x
	__EOT

   check 2 0 "${MBOX}" '1391779299 104'

   if have_feat idna; then
      ${cat} <<- '__EOT' | ${MAILX} ${ARGS} ${ADDARG_UNI} > "${MBOX}" 2>&1
		commandalias x echo '$?/$^ERRNAME $res'
      vput addrcodec res e    (heu) <du@blödiän> "stroh" du   
      x
      eval vput addrcodec res d $res
      x
      vput addrcodec res e       <du@blödiän>   du     
      x
      eval vput addrcodec res d $res
      x
      vput addrcodec res e     du    <du@blödiän>   
      x
      eval vput addrcodec res d $res
      x
      vput addrcodec res e        <du@blödiän>    
      x
      eval vput addrcodec res d $res
      x
      vput addrcodec res e        du@blödiän    
      x
      eval vput addrcodec res d $res
      x
		__EOT

      check idna 0 "${MBOX}" '498775983 326'
   else
      t_echoskip 'idna:[!IDNA]'
   fi

   t_epilog "${@}"
}

t_csop() {
   t_prolog "${@}"

   if have_feat cmd-csop; then :; else
      t_echoskip '[!CMD_CSOP]'
      t_epilog "${@}"
      return
   fi

   ${cat} <<- '__EOT' | ${MAILX} ${ARGS} > "${MBOX}" 2>&1
	commandalias x echo '$?/$^ERRNAME :$res:'
	echo ' #-2'
	vput csop res find you y;x
	vput csop res find you o;x
	vput csop res find you u;x
	vput csop res find you yo;x
	vput csop res find you ou;x
	vput csop res find you you;x
	echo ' #-1'
	vput csop res find you Y;x
	vput csop res find? you Y;x
	vput csop res find?case you O;x
	vput csop res find? you U;x
	vput csop res find?ca you yO;x
	vput csop res find? you oU;x
	vput csop res find? you YoU;x
	echo ' #0'
	vput csop res find 'bananarama' 'nana';x
	vput csop res find 'bananarama' 'bana';x
	vput csop res find 'bananarama' 'Bana';x
	vput csop res find 'bananarama' 'rama';x
	echo ' #1'
	vput csop res find? 'bananarama' 'nana';x
	vput csop res find? 'bananarama' 'bana';x
	vput csop res find? 'bananarama' 'Bana';x
	vput csop res find? 'bananarama' 'rama';x
	echo ' #2'
	vput csop res substring 'bananarama' 1;x
	vput csop res substring 'bananarama' 3;x
	vput csop res substring 'bananarama' 5;x
	vput csop res substring 'bananarama' 7;x
	vput csop res substring 'bananarama' 9;x
	vput csop res substring 'bananarama' 10;x
	vput csop res substring 'bananarama' 1 3;x
	vput csop res substring 'bananarama' 3 3;x
	vput csop res substring 'bananarama' 5 3;x
	vput csop res substring 'bananarama' 7 3;x
	vput csop res substring 'bananarama' 9 3;x
	vput csop res substring 'bananarama' 10 3;x
	echo ' #3'
	vput csop res substring 'bananarama' -1;x
	vput csop res substring 'bananarama' -3;x
	vput csop res substring 'bananarama' -5;x
	vput csop res substring 'bananarama' -7;x
	vput csop res substring 'bananarama' -9;x
	vput csop res substring 'bananarama' -10;x
	vput csop res substring 'bananarama' 1 -3;x
	vput csop res substring 'bananarama' 3 -3;x
	vput csop res substring 'bananarama' 5 -3;x
	vput csop res substring 'bananarama' 7 -3;x
	vput csop res substring 'bananarama' 9 -3;x
	vput csop res substring 'bananarama' 10 -3;x
	echo ' #4'
	vput csop res trim 'Cocoon  Cocoon';x
	vput csop res trim '  Cocoon  Cocoon 	  ';x
	vput csop res trim-front 'Cocoon  Cocoon';x
	vput csop res trim-front '  Cocoon  Cocoon 	  ';x
	vput csop res trim-end 'Cocoon  Cocoon';x
	vput csop res trim-end '  Cocoon  Cocoon 	  ';x
	__EOT

   check 1 0 "${MBOX}" '1892119538 755'

   t_epilog "${@}"
}

t_vexpr() {
   t_prolog "${@}"

   if have_feat cmd-vexpr; then :; else
      t_echoskip '[!CMD_VEXPR]'
      t_epilog "${@}"
      return
   fi

   ${cat} <<- '__EOT' | ${MAILX} ${ARGS} > "${MBOX}" 2>>${ERR}
	commandalias x echo '$?/$^ERRNAME $res'
	echo ' #0.0'
	vput vexpr res = 9223372036854775807;x
	vput vexpr res = 9223372036854775808;x
	vput vexpr res = u9223372036854775808;x
	vput vexpr res =? 9223372036854775808;x
	vput vexpr res = -9223372036854775808;x
	vput vexpr res = -9223372036854775809;x
	vput vexpr res =?saturated -9223372036854775809;x
	vput vexpr res = U9223372036854775809;x
	echo ' #0.1'
	vput vexpr res = \
		0b0111111111111111111111111111111111111111111111111111111111111111;x
	vput vexpr res = \
		S0b1000000000000000000000000000000000000000000000000000000000000000;x
	vput vexpr res =? \
		S0b1000000000000000000000000000000000000000000000000000000000000000;x
	vput vexpr res = \
		U0b1000000000000000000000000000000000000000000000000000000000000000;x
	vput vexpr res = \
		0b1000000000000000000000000000000000000000000000000000000000000000;x
	vput vexpr res =? \
		0b1000000000000000000000000000000000000000000000000000000000000000;x
	vput vexpr res = \
		-0b1000000000000000000000000000000000000000000000000000000000000000;x
	vput vexpr res = \
		S0b1000000000000000000000000000000000000000000000000000000000000001;x
	vput vexpr res =? \
		S0b1000000000000000000000000000000000000000000000000000000000000001;x
	vput vexpr res =? \
		-0b1000000000000000000000000000000000000000000000000000000000000001;x
	vput vexpr res = \
		U0b1000000000000000000000000000000000000000000000000000000000000001;x
	echo ' #0.2'
	vput vexpr res = 0777777777777777777777;x
	vput vexpr res = S01000000000000000000000;x
	vput vexpr res =? S01000000000000000000000;x
	vput vexpr res = U01000000000000000000000;x
	vput vexpr res = 01000000000000000000000;x
	vput vexpr res =?satur 01000000000000000000000;x
	vput vexpr res = -01000000000000000000000;x
	vput vexpr res = S01000000000000000000001;x
	vput vexpr res =?sat S01000000000000000000001;x
	vput vexpr res = -01000000000000000000001;x
	vput vexpr res = U01000000000000000000001;x
	echo ' #0.3'
	vput vexpr res = 0x7FFFFFFFFFFFFFFF;x
	vput vexpr res = S0x8000000000000000;x
	vput vexpr res =? S0x8000000000000000;x
	vput vexpr res = U0x8000000000000000;x
	vput vexpr res = 0x8000000000000000;x
	vput vexpr res =? 0x8000000000000000;x
	vput vexpr res = -0x8000000000000000;x
	vput vexpr res = S0x8000000000000001;x
	vput vexpr res =? S0x8000000000000001;x
	vput vexpr res = -0x8000000000000001;x
	vput vexpr res = u0x8000000000000001;x
	vput vexpr res = 9223372036854775809;x
	vput vexpr res =? 9223372036854775809;x
	vput vexpr res = u9223372036854775809;x
	echo ' #1'
	vput vexpr res ~ 0;x
	vput vexpr res ~ 1;x
	vput vexpr res ~ -1;x
	echo ' #1.1'
	vput vexpr res - 0;x
	vput vexpr res - 1;x
	vput vexpr res - -1;x
	vput vexpr res - -0xAFFE;x
	vput vexpr res - 0xAFFE;x
	vput vexpr res - u0x8000000000000001;x
	vput vexpr res - 0x8000000000000001;x
	vput vexpr res - 0x8000000000000001;x
	vput vexpr res - 9223372036854775809;x
	vput vexpr res -? 9223372036854775809;x
	echo ' #1.2'
	vput vexpr res + 0;x
	vput vexpr res + 1;x
	vput vexpr res + -1;x
	vput vexpr res + -0xAFFE;x
	vput vexpr res + 0xAFFE;x
	vput vexpr res + u0x8000000000000001;x
	vput vexpr res + 0x8000000000000001;x
	vput vexpr res + 9223372036854775809;x
	vput vexpr res +? 9223372036854775809;x
	echo ' #2'
	vput vexpr res + 0 0;x
	vput vexpr res + 0 1;x
	vput vexpr res + 1 1;x
	echo ' #3'
	vput vexpr res + 9223372036854775807 0;x
	vput vexpr res + 9223372036854775807 1;x
	vput vexpr res +? 9223372036854775807 1;x
	vput vexpr res + 0 9223372036854775807;x
	vput vexpr res + 1 9223372036854775807;x
	vput vexpr res +? 1 9223372036854775807;x
	echo ' #4'
	vput vexpr res + -9223372036854775808 0;x
	vput vexpr res + -9223372036854775808 -1;x
	vput vexpr res +? -9223372036854775808 -1;x
	vput vexpr res + 0 -9223372036854775808;x
	vput vexpr res + -1 -9223372036854775808;x
	vput vexpr res +? -1 -9223372036854775808;x
	echo ' #5'
	vput vexpr res - 0 0;x
	vput vexpr res - 0 1;x
	vput vexpr res - 1 1;x
	echo ' #6'
	vput vexpr res - 9223372036854775807 0;x
	vput vexpr res - 9223372036854775807 -1;x
	vput vexpr res -? 9223372036854775807 -1;x
	vput vexpr res - 0 9223372036854775807;x
	vput vexpr res - -1 9223372036854775807;x
	vput vexpr res - -2 9223372036854775807;x
	vput vexpr res -? -2 9223372036854775807;x
	echo ' #7'
	vput vexpr res - -9223372036854775808 +0;x
	vput vexpr res - -9223372036854775808 +1;x
	vput vexpr res -? -9223372036854775808 +1;x
	vput vexpr res - 0 -9223372036854775808;x
	vput vexpr res - +1 -9223372036854775808;x
	vput vexpr res -? +1 -9223372036854775808;x
	echo ' #8'
	vput vexpr res + -13 -2;x
	vput vexpr res - 0 0;x
	vput vexpr res - 0 1;x
	vput vexpr res - 1 1;x
	vput vexpr res - -13 -2;x
	echo ' #9'
	vput vexpr res * 0 0;x
	vput vexpr res * 0 1;x
	vput vexpr res * 1 1;x
	vput vexpr res * -13 -2;x
	echo ' #10'
	vput vexpr res / 0 0;x
	vput vexpr res / 0 1;x
	vput vexpr res / 1 1;x
	vput vexpr res / -13 -2;x
	echo ' #11'
	vput vexpr res % 0 0;x
	vput vexpr res % 0 1;x
	vput vexpr res % 1 1;x
	vput vexpr res % -13 -2;x
	echo ' #12'
	vput vexpr res pbase 10 u0x8000000000000001;x
	vput vexpr res pbase 16 0x8000000000000001;x
	vput vexpr res pbase 16 s0x8000000000000001;x
	vput vexpr res pbase 16 u0x8000000000000001;x
	vput vexpr res pbase 36 0x8000000000000001;x
	vput vexpr res pbase 36 u0x8000000000000001;x
	__EOT

   check numeric 0 "${MBOX}" '163128733 2519'

   if have_feat regex; then
      ${cat} <<- '__EOT' | ${MAILX} ${ARGS} > "${MBOX}" 2>&1
		commandalias x echo '$?/$^ERRNAME :$res:'
		echo ' #-2'
		vput vexpr res regex you y;x
		vput vexpr res regex you o;x
		vput vexpr res regex you u;x
		vput vexpr res regex you yo;x
		vput vexpr res regex you ou;x
		vput vexpr res regex you you;x
		echo ' #-1'
		vput vexpr res regex you Y;x
		vput vexpr res regex? you Y;x
		vput vexpr res regex? you O;x
		vput vexpr res regex? you U;x
		vput vexpr res regex? you yO;x
		vput vexpr res regex? you oU;x
		vput vexpr res regex? you YoU;x
		echo ' #0'
		vput vexpr res regex 'bananarama' 'nana';x
		vput vexpr res regex 'bananarama' 'bana';x
		vput vexpr res regex 'bananarama' 'Bana';x
		vput vexpr res regex 'bananarama' 'rama';x
		echo ' #1'
		vput vexpr res regex? 'bananarama' 'nana';x
		vput vexpr res regex? 'bananarama' 'bana';x
		vput vexpr res regex? 'bananarama' 'Bana';x
		vput vexpr res regex? 'bananarama' 'rama';x
		echo ' #2'
		vput vexpr res regex 'bananarama' '(.*)nana(.*)' '\${1}a\${0}u{\$2}';x
		vput vexpr res regex 'bananarama' '(.*)bana(.*)' '\${1}a\${0}u\$2';x
		vput vexpr res regex 'bananarama' 'Bana(.+)' '\$1\$0';x
		vput vexpr res regex 'bananarama' '(.+)rama' '\$1\$0';x
		echo ' #3'
		vput vexpr res regex? 'bananarama' '(.*)nana(.*)' '\${1}a\${0}u{\$2}';x
		vput vexpr res regex? 'bananarama' '(.*)bana(.*)' '\${1}a\${0}u\$2';x
		vput vexpr res regex? 'bananarama' 'Bana(.+)' '\$1\$0';x
		vput vexpr res regex? 'bananarama' '(.+)rama' '\$1\$0';x
		echo ' #4'
		vput vexpr res regex 'banana' '(club )?(.*)(nana)(.*)' \
         '\$1\${2}\$4\${3}rama';x
		vput vexpr res regex 'Banana' '(club )?(.*)(nana)(.*)' \
         '\$1\$2\${2}\$2\$4\${3}rama';x
		vput vexpr res regex 'Club banana' '(club )?(.*)(nana)(.*)' \
         '\$1\${2}\$4\${3}rama';x
		echo ' #5'
		__EOT

      check regex 0 "${MBOX}" '2831099111 542'
   else
      t_echoskip 'regex:[!REGEX]'
   fi

   t_epilog "${@}"
}

t_call_ret() {
   t_prolog "${@}"

   if have_feat cmd-vexpr; then :; else
      t_echoskip '[!CMD_VEXPR]'
      t_epilog "${@}"
      return
   fi

   ${cat} <<- '__EOT' | ${MAILX} ${ARGS} -Snomemdebug > "${MBOX}" 2>&1
	define w1 {
		echon ">$1 "
		vput vexpr i + $1 1
		if [ $i -le 42 ]
			vput vexpr j '&' $i 7
			if [ $j -eq 7 ]
				echo .
			end
			call w1 $i
			wysh set i=$? k=$!
			vput vexpr j '&' $i 7
			echon "<$1/$i/$k "
			if [ $j -eq 7 ]
				echo .
			end
		else
			echo ! The end for $1
		end
		return $1
	}
	# Transport $?/$! up the call chain
	define w2 {
		echon ">$1 "
		vput vexpr i + $1 1
		if [ $1 -lt 42 ]
			call w2 $i
			wysh set i=$? j=$! k=$^ERRNAME
			echon "<$1/$i/$k "
			return $i $j
		else
			echo ! The end for $1
			return $i $^ERR-BUSY
		end
		echoerr au
	}
	# Up and down it goes
	define w3 {
		echon ">$1/$2 "
		vput vexpr i + $1 1
		if [ $1 -lt 42 ]
			call w3 $i $2
			wysh set i=$? j=$!
			vput vexpr k - $1 $2
			if [ $k -eq 21 ]
				vput vexpr i + $1 1
				vput vexpr j + $2 1
				echo "# <$i/$j> .. "
				call w3 $i $j
				wysh set i=$? j=$!
			end
			eval echon "<\$1=\$i/\$^ERRNAME-$j "
			return $i $j
		else
			echo ! The end for $1=$i/$2
         if [ "$2" != "" ]
            return $i $^ERR-DOM
         else
            return $i $^ERR-BUSY
         end
		end
		echoerr au
	}

	call w1 0; echo ?=$? !=$!; echo -----;
	call w2 0; echo ?=$? !=$^ERRNAME; echo -----;
	call w3 0 1; echo ?=$? !=$^ERRNAME; echo -----;
	__EOT

   check 1 0 "${MBOX}" '1572045517 5922'

   t_epilog "${@}"
}

t_xcall() {
   t_prolog "${@}"

   if have_feat cmd-vexpr; then :; else
      t_echoskip '[!CMD_VEXPR]'
      t_epilog "${@}"
      return
   fi

   ${cat} <<- '__EOT' | \
      ${MAILX} ${ARGS} -Snomemdebug \
         -Smax=${LOOPS_MAX} \
         > "${MBOX}" 2>&1
	define work {
		echon "$1 "
		vput vexpr i + $1 1
		if [ $i -le "$max" ]
			vput vexpr j '&' $i 7
			if [ $j -eq 7 ]
				echo .
			end
			\xcall work $i $2
		end
		echo ! The end for $1/$2
		if [ "$2" != "" ]
			return $i $^ERR-BUSY
		end
	}
	define xwork {
		\xcall work 0 $2
	}
	call work 0
	echo ?=$? !=$!
	call xwork
	echo ?=$? !=$!
	xcall xwork
	echo ?=$? !=$^ERRNAME
	#
	call work 0 yes
	echo ?=$? !=$^ERRNAME
	call xwork 0 yes
	echo ?=$? !=$^ERRNAME
	__EOT

   i=${?}
   if [ ${LOOPS_MAX} -eq ${LOOPS_BIG} ]; then
      check_ex0 1-${LOOPS_BIG} ${i}
      check 1-${LOOPS_BIG} - "${MBOX}" '1069764187 47161'
   else
      check_ex0 1-${LOOPS_SMALL} ${i}
      check 1-${LOOPS_SMALL} - "${MBOX}" '859201011 3894'
   fi

   ##

   if have_feat uistrings; then
      ${cat} <<- '__EOT' > "${BODY}"
			define __w {
				echon "$1 "
				vput vexpr i + $1 1
				if [ $i -le 111 ]
					vput vexpr j '&' $i 7
					if [ $j -eq 7 ]
						echo .
					end
					\xcall __w $i $2
				end
				echo ! The end for $1
				if [ $2 -eq 0 ]
					nonexistingcommand
					echo would be err with errexit
					return
				end
				echo calling exit
				exit
			}
			define work {
				echo eins
				call __w 0 0
				echo zwei, ?=$? !=$!
				localopts yes; set errexit
				ignerr call __w 0 0
				echo drei, ?=$? !=$^ERRNAME
				call __w 0 $1
				echo vier, ?=$? !=$^ERRNAME, this is an error
			}
			ignerr call work 0
			echo outer 1, ?=$? !=$^ERRNAME
			xxxign call work 0
			echo outer 2, ?=$? !=$^ERRNAME, could be error if xxxign non-empty
			call work 1
			echo outer 3, ?=$? !=$^ERRNAME
			echo this is definitely an error
			__EOT

      < "${BODY}" ${MAILX} ${ARGS} -X'commandalias xxxign ignerr' \
         -Snomemdebug > "${MBOX}" 2>&1
      check 2 0 "${MBOX}" '3900716531 4200'

      < "${BODY}" ${MAILX} ${ARGS} -X'commandalias xxxign " "' \
         -Snomemdebug > "${MBOX}" 2>&1
      check 3 1 "${MBOX}" '1006776201 2799'
   else
      t_echoskip '2-3:[!UISTRINGS]'
   fi

   t_epilog "${@}"
}

t_vpospar() {
   t_prolog "${@}"

   ${cat} <<- '__EOT' | ${MAILX} ${ARGS} > "${MBOX}" 2>&1
   vpospar set hey, "'you    ", world!
   echo $?/$^ERRNAME/$#: $* / "$@" / <$1><$2><$3><$4>
   vput vpospar x quote; echo x<$x>
   vpospar clear;echo $?/$^ERRNAME/$#: $* / "$@" / <$1><$2><$3><$4>
   vput vpospar y quote;echo y<$y>
   eval vpospar set ${x};echo $?/$^ERRNAME/$#: $* / "$@" / <$1><$2><$3><$4>
   eval vpospar set ${y};echo $?/$^ERRNAME/$#: $* / "$@" / <$1><$2><$3><$4>
   eval vpospar set ${x};echo $?/$^ERRNAME/$#: $* / "$@" / <$1><$2><$3><$4>

   define infun2 {
      echo infun2:$?/$^ERRNAME/$#:$*/"$@"/<$1><$2><$3><$4>
      vput vpospar z quote;echo infun2:z<$z>
   }

   define infun {
      echo infun:$?/$^ERRNAME/$#:$*/"$@"/<$1><$2><$3><$4>
      vput vpospar y quote;echo infun:y<$y>
      eval vpospar set ${x};echo infun:$?/$^ERRNAME/$#:$*/"$@"/<$1><$2><$3><$4>
      vpospar clear;echo infun:$?/$^ERRNAME/$#:$*/"$@"/<$1><$2><$3><$4>
      eval call infun2 $x
      echo infun:$?/$^ERRNAME/$#:$*/"$@"/<$1><$2><$3><$4>
      eval vpospar set ${y};echo infun:$?/$^ERRNAME/$#:$*/"$@"/<$1><$2><$3><$4>
   }

   call infun This "in a" fun
   echo $?/$^ERRNAME/$#: $* / "$@" / <$1><$2><$3><$4>
   vpospar clear;echo $?/$^ERRNAME/$#: $* / "$@" / <$1><$2><$3><$4>
	__EOT
   check 1 0 "${MBOX}" '155175639 866'

   #
   ${cat} <<- '__EOT' | ${MAILX} ${ARGS} > "${MBOX}" 2>&1
   set ifs=\'
   echo ifs<$ifs> ifs-ws<$ifs-ws>
   vpospar set hey, "'you    ", world!
   echo $?/$^ERRNAME/$#: $* / "$@" / <$1><$2><$3><$4>
   vput vpospar x quote; echo x<$x>
   vpospar clear;echo $?/$^ERRNAME/$#: $* / "$@" / <$1><$2><$3><$4>
   eval vpospar set ${x};echo $?/$^ERRNAME/$#: $* / "$@" / <$1><$2><$3><$4>

   set ifs=,
   echo ifs<$ifs> ifs-ws<$ifs-ws>
   vpospar set hey, "'you    ", world!
   unset ifs;echo $?/$^ERRNAME/$#: $* / "$@" / <$1><$2><$3><$4>
   set ifs=,
   vput vpospar x quote; echo x<$x>
   vpospar clear;echo $?/$^ERRNAME/$#: $* / "$@" / <$1><$2><$3><$4>
   eval vpospar set ${x};\
      unset ifs;echo $?/$^ERRNAME/$#: $* / "$@" / <$1><$2><$3><$4>

   wysh set ifs=$',\t'
   echo ifs<$ifs> ifs-ws<$ifs-ws>
   vpospar set hey, "'you    ", world!
   unset ifs; echo $?/$^ERRNAME/$#: $* / "$@" / <$1><$2><$3><$4>
   wysh set ifs=$',\t'
   vput vpospar x quote; echo x<$x>
   vpospar clear;echo $?/$^ERRNAME/$#: $* / "$@" / <$1><$2><$3><$4>
   eval vpospar set ${x};\
   unset ifs;echo $?/$^ERRNAME/$#: $* / "$@" / <$1><$2><$3><$4>
	__EOT
   check ifs 0 "${MBOX}" '2015927702 706'

   t_epilog "${@}"
}

t_atxplode() {
   t_prolog "${@}"

   ${cat} > ./.t.sh <<- '___'; ${cat} > ./.t.rc <<- '___'
	x() { echo $#; }
	xxx() {
	  printf " (1/$#: <$1>)"
	  shift
	  if [ $# -gt 0 ]; then
	    xxx "$@"
	  else
	    echo
	  fi
	}
	yyy() {
	  eval "$@ ' ball"
	}
	set --
	x "$@"
	x "$@"''
	x " $@"
	x "$@ "
	printf yyy;yyy 'xxx' "b\$'\t'u ' "
	printf xxx;xxx arg ,b      u.
	printf xxx;xxx arg ,  .
	printf xxx;xxx arg ,ball.
	___
	define x {
	  echo $#
	}
	define xxx {
	  echon " (1/$#: <$1>)"
	  shift
	  if [ $# -gt 0 ]
	    \xcall xxx "$@"
	  endif
     echo
	}
	define yyy {
	  eval "$@ ' ball"
	}
	vpospar set
	call x "$@"
	call x "$@"''
	call x " $@"
	call x "$@ "
	echon yyy;call yyy '\call xxx' "b\$'\t'u ' "
	echon xxx;call xxx arg ,b      u.
	echon xxx;call xxx arg ,  .
	echon xxx;call xxx arg ,ball.
	___

   ${MAILX} ${ARGS} -X'source ./.t.rc' -Xx > "${MBOX}" 2>&1
   check 1 0 "${MBOX}" '41566293 164'

   #${SHELL} ./.t.sh > ./.tshout 2>&1
   #check disproof-1 0 ./.tshout '41566293 164'

   t_epilog "${@}"
}

t_read() {
   t_prolog "${@}"

   ${cat} <<- '__EOT' > .tin
   hey1, "'you    ", world!
   hey2, "'you    ", bugs bunny!
   hey3, "'you    ",     
   hey4, "'you    "
	__EOT

   ${cat} <<- '__EOT' |\
      ${MAILX} ${ARGS} -X'readctl create ./.tin' > "${MBOX}" 2>&1
	commandalias x echo '$?/$^ERRNAME / <$a><$b><$c>'
   read a b c;x
   read a b c;x
   read a b c;x
   read a b c;x
   unset a b c;read a b c;x
   readctl remove ./.tin;echo readctl remove:$?/$^ERRNAME
	__EOT
   check 1 0 "${MBOX}" '1527910147 173'

   ${cat} <<- '__EOT' > .tin2
   hey2.0,:"'you    ",:world!:mars.:
   hey2.1,:"'you    ",:world!
   hey2.2,:"'you    ",:bugs bunny!
   hey2.3,:"'you    ",:    
   hey2.4,:"'you    ":
   :
	__EOT

   ${cat} <<- '__EOT' |\
      6< .tin2 ${MAILX} ${ARGS} -X 'readctl create 6' > "${MBOX}" 2>&1
	commandalias x echo '$?/$^ERRNAME / <$a><$b><$c>'
   set ifs=:
   read a b c;x
   read a b c;x
   read a b c;x
   read a b c;x
   read a b c;x
   read a b c;x
   unset a b c;read a b c;x
   read a b c;x
   readctl remove 6;echo readctl remove:$?/$^ERRNAME
	__EOT
   check ifs 0 "${MBOX}" '890153490 298'

   ${cat} <<- '__EOT' | ${MAILX} ${ARGS} > "${MBOX}" 2>&1
	commandalias x echo '$?/$^ERRNAME / <$d>'
   readctl create .tin
   readall d;x
   wysh set d;readall d;x
   readctl create .tin2
   readall d;x
   wysh set d;readall d;x
   readctl remove .tin;echo $?/$^ERRNAME;\
      readctl remove .tin2;echo $?/$^ERRNAME
   echo '### now with empty lines'
   ! printf 'one line\n\ntwo line\n\n' > ./.temptynl
   readctl create .temptynl;echo $?/$^ERRNAME
   readall d;x
   readctl remove .temptynl;echo $?/$^ERRNAME
	__EOT
   check readall 0 "${MBOX}" '4113506527 405'

   t_epilog "${@}"
}

t_headerpick() {
   t_prolog "${@}"

   t__x1_msg > ./.tmbox

   #
   </dev/null ${MAILX} ${ARGS} -Rf -Y '# Do not care much on error UISTRINGS
\echo --- 1
\headerpick
\echo --- $?/$^ERRNAME, 2
\type
\echo --- $?/$^ERRNAME, 3
\if "$features" !% +uistrings,
   \echoerr reproducible_build: Invalid field name cannot be ignored: ba:l
\endif
\headerpick type ignore \
   from_ mail-followup-to in-reply-to DATE MESSAGE-ID STATUS ba:l
\echo --- $?/$^ERRNAME, 4
\if "$features" !% +uistrings,
   \echo "#headerpick type retain currently covers no fields"
\endif
\headerpick
\echo --- $?/$^ERRNAME, 5
\type
\echo --- $?/$^ERRNAME, 6
\unheaderpick type ignore from_ DATE STATUS
\echo --- $?/$^ERRNAME, 7
\if "$features" !% +uistrings,
   \echo "#headerpick type retain currently covers no fields"
\endif
\headerpick
\echo --- $?/$^ERRNAME, 8
\type
\echo --- $?/$^ERRNAME, 9
\if "$features" =% +uistrings,
   \unheaderpick type ignore from_ ba:l
   \wysh set x=$? y=$^ERRNAME
\else
   \echoerr reproducible_build: Field not ignored: from_
   \echoerr reproducible_build: Field not ignored: ba:l
   \set x=1 y=INVAL
\endif
\echo --- $x/$y, 10
\unheaderpick type ignore *
\echo --- $?/$^ERRNAME, 11
\if "$features" !% +uistrings,
   \echo "#headerpick type retain currently covers no fields"
   \echo "#headerpick type ignore currently covers no fields"
\endif
\headerpick
\echo --- $?/$^ERRNAME, 12
\type
\echo --- $?/$^ERRNAME, 13 ---
#  ' ./.tmbox >./.tall 2>&1
   check 1 0 ./.tall '2481904228 2273'

   #
   if have_feat uistrings; then
      </dev/null ${MAILX} ${ARGS} -Y '#
\headerpick type retain \
   bcc cc date from sender subject to \
   message-id mail-followup-to reply-to user-agent
\echo --- $?/$^ERRNAME, 1
\headerpick forward retain \
   cc date from message-id list-id sender subject to \
   mail-followup-to reply-to
\echo --- $?/$^ERRNAME, 2
\headerpick save ignore ^Original-.*$ ^X-.*$ ^DKIM.*$
\echo --- $?/$^ERRNAME, 3
\headerpick top retain To Cc
\echo --- $?/$^ERRNAME, 4 ---
\headerpick
\echo --- $?/$^ERRNAME, 5
\headerpick type
\echo --- $?/$^ERRNAME, 6
\headerpick forward
\echo --- $?/$^ERRNAME, 7
\headerpick save
\echo --- $?/$^ERRNAME, 8
\headerpick top
\echo --- $?/$^ERRNAME, 9 ---
\unheaderpick type retain message-id mail-followup-to reply-to user-agent
\echo --- $?/$^ERRNAME, 10
\unheaderpick save ignore ^X-.*$ ^DKIM.*$
\echo --- $?/$^ERRNAME, 11
\unheaderpick forward retain *
\echo --- $?/$^ERRNAME, 12 ---
\headerpick
\echo --- $?/$^ERRNAME, 13
\headerpick type
\echo --- $?/$^ERRNAME, 14
\headerpick save
\echo --- $?/$^ERRNAME, 15 --
\unheaderpick type retain *
\echo --- $?/$^ERRNAME, 16
\unheaderpick forward retain *
\echo --- $?/$^ERRNAME, 17
\unheaderpick save ignore *
\echo --- $?/$^ERRNAME, 18
\unheaderpick top retain *
\echo --- $?/$^ERRNAME, 19 --
\headerpick
\echo --- $?/$^ERRNAME, 20
#  ' >./.tall 2>&1
      check 2 0 ./.tall '3515512395 2378'
   else
      t_echoskip '2:[!UISTRINGS]'
   fi

   t_epilog "${@}"
}
# }}}

# Send/RFC absolute basics {{{
t_can_send_rfc() { # {{{
   t_prolog "${@}"

   </dev/null ${MAILX} ${ARGS} -Smta=test://"$MBOX" -s Sub.1 \
      receiver@number.1 \
      > ./.terr 2>&1
   check 1 0 "${MBOX}" '550126528 126'
   check 1-err - .terr '4294967295 0'

   </dev/null ${MAILX} ${ARGS} -Smta=test://"$MBOX" -s Sub.2 \
      -b bcc@no.1 -b bcc@no.2 -b bcc@no.3 \
      -c cc@no.1 -c cc@no.2 -c cc@no.3 \
      to@no.1 to@no.2 to@no.3 \
      > ./.terr 2>&1
   check 2 0 "${MBOX}" '3259888945 324'
   check 2-err - .terr '4294967295 0'

   </dev/null ${MAILX} ${ARGS} -Smta=test://"$MBOX" -s Sub.2no \
      -b bcc@no.1\ \ bcc@no.2 -b bcc@no.3 \
      -c cc@no.1,cc@no.2 -c cc@no.3 \
      to@no.1,to@no.2 to@no.3 \
      > ./.terr 2>&1
   check 2no 4 "${MBOX}" '3350946897 468'
   if have_feat uistrings; then
      check 2no-err - .terr '3397557940 190'
   else
      check 2no-err - .terr '4294967295 0'
   fi

   # XXX NOTE we cannot test "cc@no1 <cc@no.2>" because our stupid parser
   # XXX would not treat that as a list but look for "," as a separator
   </dev/null ${MAILX} ${ARGS} -Smta=test://"$MBOX" -Sfullnames -s Sub.3 \
      -T 'bcc?single: bcc@no.1, <bcc@no.2>' -T bcc:\ bcc@no.3 \
      -T cc?si\ \ :\ \ 'cc@no.1, <cc@no.2>' -T cc:\ cc@no.3 \
      -T to?:\ to@no.1,'<to@no.2>' -T to:\ to@no.3 \
      > ./.terr 2>&1
   check 3 0 "${MBOX}" '1453534480 678'
   check 3-err - .terr '4294967295 0'

   </dev/null ${MAILX} ${ARGS} -Smta=test://"$MBOX" -Sfullnames -s Sub.4 \
      -T 'bcc: bcc@no.1, <bcc@no.2>' -T bcc:\ bcc@no.3 \
      -T cc:\ 'cc@no.1, <cc@no.2>' -T cc\ \ :\ \ cc@no.3 \
      -T to\ :to@no.1,'<to@no.2>' -T to:\ to@no.3 \
      > ./.terr 2>&1
   check 4 0 "${MBOX}" '535767201 882'
   check 4-err - .terr '4294967295 0'

   # Two test with a file-based MTA
   "${cat}" <<-_EOT > .tmta.sh
		#!${SHELL} -
		(echo 'From reproducible_build Wed Oct  2 01:50:07 1996' &&
			"${cat}" && echo pardauz && echo) > "${MBOX}"
	_EOT
   chmod 0755 .tmta.sh

   </dev/null ${MAILX} ${ARGS} -Smta=./.tmta.sh -s Sub.mta-1 \
      receiver@number.1 > ./.terr 2>&1
   check 5 0 "${MBOX}" '2384401657 138'
   check 5-err - .terr '4294967295 0'

   </dev/null ${MAILX} ${ARGS} -Smta=file://./.tmta.sh -s Sub.mta-2 \
      receiver@number.1 > ./.terr 2>&1
   check 6 0 "${MBOX}" '3006460737 138'
   check 6-err - .terr '4294967295 0'

   # Command
   </dev/null ${MAILX} ${ARGS} -Smta=test \
      -Y '#
mail hey@exam.ple
~s Subject 1
Body1
~.
echo $?/$^ERRNAME
xit
# '   > ./.tall 2>&1
   check 7 0 ./.tall '951018449 138'

   t_epilog "${@}"
} # }}}

t_reply() { # {{{
   # Alternates and ML related address massage etc. somewhere else
   t_prolog "${@}"
   XARGS=${ARGS} # TODO v15-compat
   ARGS="${ARGS} -Sv15-compat=y"

   t__gen_msg subject reply from 1 to 2 cc 2 > "${MBOX}"

   ## Base (does not test "recipient record")
   t_it() {
      </dev/null ${MAILX} ${ARGS} -Rf \
         -Y "${2}${1}"'
r1
~.
      echo 1:$?/$^ERRNAME
      set fullnames escape=!; '${1}'
r2 fullnames
!.
      echo 2:$?/$^ERRNAME
      set recipients-in-cc nofullnames; '${1}'
r3 recipients-in-cc
!.
      echo 3:$?/$^ERRNAME
      unset recipients-in-cc; '${1}'
r4
!.
      echo 4:$?/$^ERRNAME
      #' \
         "${MBOX}" > ./.tall 2>&1
      return ${?}
   }

   t_it reply
   check 1 0 ./.tall '4164251531 851'
   t_it Reply
   check 2 0 ./.tall '3034955332 591'
   t_it reply 'set flipr;'
   check 3 0 ./.tall '3034955332 591'
   t_it Reply 'set flipr;'
   check 4 0 ./.tall '4164251531 851'

   ## Dig the errors
   t__gen_msg subject reply-no-addr > ./.tnoaddr

   # MBOX will deduce addressee from From_ line..
   </dev/null ${MAILX} ${ARGS} -R -Sescape=! \
      -Y '#
   File ./.tnoaddr; reply # Takes addressee from From_ line :(
body1
!.
   echo 1:$?/$^ERRNAME
   File '"${MBOX}"'; set ea=$expandaddr expandaddr=-all; reply
body2
!.
   echo 2:$?/$^ERRNAME; set expandaddr=$ea; reply 10 # BADMSG
   echo 3:$?/$^ERRNAME; reply # cannot test IO,NOTSUP,INVAL
body3
!.
   echo 4:$?/$^ERRNAME
   #' \
      > ./.tall 2>./.terr
   check 5 0 ./.tall '3088217220 382'
   if have_feat uistrings; then
      check 6 - ./.terr '2514745519 544'
   else
      t_echoskip '6:[!UISTRINGS]'
   fi

   # ..but Maildir will not
   if have_feat maildir; then
      ${mkdir} -p .tdir .tdir/tmp .tdir/cur .tdir/new
      ${sed} 1d < ./.tnoaddr > .tdir/new/sillyname

      </dev/null ${MAILX} ${ARGS} -R -Sescape=! \
         -Y '#
      File ./.tdir; reply
body1
!.
      echo 1:$?/$^ERRNAME
      File '"${MBOX}"'; set ea=$expandaddr expandaddr=-all; reply
body2
!.
      echo 2:$?/$^ERRNAME; set expandaddr=$ea; reply 10 # BADMSG
      echo 3:$?/$^ERRNAME;reply # cannot test IO,NOTSUP,INVAL
body3
!.
      echo 4:$?/$^ERRNAME
      #' \
         > ./.tall 2>./.terr
      check 7 0 ./.tall '3631170341 244'
      if have_feat uistrings; then
         check 8 - ./.terr '1074346767 629'
      else
         t_echoskip '8:[!UISTRINGS]'
      fi
   fi

   ## Ensure action on multiple messages
   t__gen_msg subject reply2 from from2@exam.ple body body2 >> "${MBOX}"

   t_it() {
      </dev/null ${MAILX} ${ARGS} -Rf -Sescape=! \
      -Y '#
      '${1}' 1 2
repbody1
!.
repbody2
!.
      echo 1:$?/$^ERRNAME; '${2}' 1 2
Repbody1
!.
      echo 2:$?/$^ERRNAME
      #' \
         "${MBOX}" > ./.tall 2>&1
      check ${3} 0 ./.tall '283309820 502'
      if [ ${#} -eq 4 ]; then
         echo * > ./.tlst
         check ${3}-1 - ./.tlst '1649520021 12'
         check ${3}-2 - ./from1 '1501109193 347'
         check ${3}-3 - ./from2 '2154231432 137'
      fi
   }

   t_it reply Reply 9
   t_it respond Respond 10
   t_it followup Followup 11 yes
   ${rm} -f from1 from2

   ## *record*, *outfolder* (reuses $MBOX)
   ${mkdir} .tfolder

   t_it() {
      </dev/null ${MAILX} ${ARGS} -Rf -Sescape=! -Sfolder=`${pwd}`/.tfolder \
      -Y '#
      '${1}' 1 2
repbody1
!.
repbody2
!.
      echo 1:$?/$^ERRNAME; '${2}' 1 2
Repbody3
!.
      echo 2:$?/$^ERRNAME; set record=.trec'${4}'; '${1}' 1 2
repbody4
!.
repbody5
!.
      echo 3:$?/$^ERRNAME; '${2}' 1 2
Repbody6
!.
      echo 4:$?/$^ERRNAME; set outfolder norecord
      '${1}' 1 2
repbody1
!.
repbody2
!.
      echo 1:$?/$^ERRNAME; '${2}' 1 2
Repbody3
!.
      echo 2:$?/$^ERRNAME; set record=.trec'${4}'; '${1}' 1 2
repbody4
!.
repbody5
!.
      echo 3:$?/$^ERRNAME; '${2}' 1 2
Repbody6
!.
      echo 4:$?/$^ERRNAME
      #' \
         "${MBOX}" > ./.tall 2>&1
      check ${3} 0 ./.tall '3410330303 2008'
      if [ ${#} -ne 5 ]; then
         check ${4} - ./.trec${4} '3044885336 484'
         check ${4}-1 - ./.tfolder/.trec${4} '3044885336 484'
      else
         [ -f ./.trec${4} ]; check_exn0 ${4}
         echo * > ./.tlst
         check ${4}-1 - ./.tlst '1649520021 12'
         check ${4}-2 - ./from1 '2668975631 694'
         check ${4}-3 - ./from2 '225462887 274'
         [ -f ./.tfolder/.trec${4} ]; check_exn0 ${4}-4
         ( cd .tfolder && echo * > ./.tlst )
         check ${4}-5 - ./.tfolder/.tlst '1649520021 12'
         check ${4}-6 - ./.tfolder/from1 '2668975631 694'
         check ${4}-7 - ./.tfolder/from2 '225462887 274'
      fi
   }

   t_it reply Reply 12 13
   t_it respond Respond 14 15
   t_it followup Followup 16 17 yes
   #${rm} -f from1 from2

   ## Quoting (if not cmd_escapes related)
   ${rm} -f "${MBOX}"
   t__x2_msg > ./.tmbox

   printf '#
      set indentprefix=" |" quote
      reply
b1
!.
      set quote=noheading quote-inject-head
      reply
b2
!.
      headerpick type retain cc date from message-id reply-to subject to
      set quote=headers
      reply
b3
!.
      set quote=allheaders
      reply
b4
!.
      set quote-inject-head=%% quote-inject-tail=%% quote=headers
      reply
b5
!.
      set quote \\
         quote-inject-head='"\$'"'\\
            (%%%%a=%%a %%%%d=%%d %%%%f=%%f %%%%i=%%i %%%%n=%%n %%%%r=%%r)\\
            \\n'"'"' \\
         quote-inject-tail='"\$'"'\\
            (%%%%a=%%a %%%%d=%%d %%%%f=%%f %%%%i=%%i %%%%n=%%n %%%%r=%%r)\\
            \\n'"'"'
      reply
b6
!.
      set showname datefield=%%y nodatefield-markout-older indentprefix=\\ :
      reply
b7
!.
   ' | ${MAILX} ${ARGS} -Smta=test://"$MBOX" -Rf \
         -Sescape=! -Sindentprefix=' >' \
         ./.tmbox >./.tall 2>&1
   check_ex0 18-estat
   ${cat} ./.tall >> "${MBOX}"
   check 18 - "${MBOX}" '4192298831 3932'

   # quote-as-attachment, fullnames
   </dev/null ${MAILX} ${ARGS} -Rf \
         -Sescape=! \
         -S quote-as-attachment \
         -Y reply -Y yb1 -Y !. \
         -Y 'unset quote-as-attachment' \
         -Y 'reply;yb2' -Y !. \
         -Y 'set quote-as-attachment fullnames' \
         -Y ';reply;yb3' -Y !. \
         ./.tmbox >./.tall 2>&1
   check 19 0 ./.tall '2774517283 2571'

   ARGS=${XARGS} # TODO v15-compat
   t_epilog "${@}"
} # }}}

t_forward() { # {{{
   t_prolog "${@}"
   XARGS=${ARGS}
   ARGS="${ARGS} -Sv15-compat=y"

   t__gen_msg subject fwd1 body origb1 from 1 to 2 > "${MBOX}"
   t__gen_msg subject fwd2 body origb2 from 1 to 1 >> "${MBOX}"

   ## Base (does not test "recipient record")
   t_it() {
      </dev/null ${MAILX} ${ARGS} -Rf \
         -Y ${1}' . "du <ex1@am.ple>"
b1
~.
      echo 1:$?/$^ERRNAME; echoerr 1:done
      set fullnames escape=!
      '${1}' 1 "du <ex2@am.ple>"
b2 fullnames
!.
      echo 2:$?/$^ERRNAME; echoerr 2:done
      # Some errors
      set nofullnames ea=$expandaddr expandaddr=-all
      '${1}' ` "du <ex3@am.ple>"
b3
!.
      echo 3:$?/$^ERRNAME; echoerr 3:done
      set expandaddr=$ea
      '${1}' ` ex4-nono@am.ple ex4@am.ple # the first is a non-match msglist
b4
!.
      echo 4:$?/$^ERRNAME; echoerr 4:done
      '${1}' # TODO not yet possible b5 !.
      echo 5:$?/$^ERRNAME; echoerr 5:done
      set expandaddr=$ea
      '${1}' 1 2 ex6@am.ple
b6-1
!.
b6-2
!.
      echo 6:$?/$^ERRNAME; echoerr 6:done
      set forward-add-cc fullnames
      '${1}' . ex7@am.ple
b7
!.
      echo 7:$?/$^ERRNAME; echoerr 7:done
      set nofullnames
      '${1}' . ex8@am.ple
b8
!.
      echo 8:$?/$^ERRNAME; echoerr 8:done
      #' \
         "${MBOX}" > ./.tall 2>./.terr
      return ${?}
   }

   t_it forward
   check 1 0 ./.tall '2356713156 2219'
   if have_feat uistrings; then
      check 2 - ./.terr '693399532 265'
   else
      t_echoskip '2:[!UISTRINGS]'
   fi

   t_it Forward
   check 3 0 ./.tall '2356713156 2219'
   if have_feat uistrings; then
      check 4 - ./.terr '693399532 265'
   else
      t_echoskip '4:[!UISTRINGS]'
   fi
   ${rm} -f ex*

   ## *record*, *outfolder* (reuses $MBOX)
   ${mkdir} .tfolder

   t_it() {
      </dev/null ${MAILX} ${ARGS} -Rf -Sescape=! -Sfolder=`${pwd}`/.tfolder \
      -Y '#
      '${1}' 1 ex1@am.ple
b1
!.
      echo 1:$?/$^ERRNAME; set record=.trec'${2}'; '${1}' 1 ex2@am.ple
b2
!.
      echo 2:$?/$^ERRNAME; set outfolder norecord; '${1}' 2 ex1@am.ple
b3
!.
      echo 3:$?/$^ERRNAME; set record=.trec'${2}'; '${1}' 2 ex2@am.ple
b4
!.
      echo 4:$?/$^ERRNAME
      #' \
         "${MBOX}" > ./.tall 2>&1
      check ${2} 0 ./.tall '3180366037 1212'
      if [ ${#} -ne 4 ]; then
         check ${3}-1 - ./.trec${2} '1769129556 304'
         check ${3}-2 - ./.tfolder/.trec${2} '2335391111 284'
      else
         [ -f ./.trec${2} ]; check_exn0 ${3}
         echo * > ./.tlst
         check ${3}-1 - ./.tlst '2020171298 8'
         check ${3}-2 - ./ex1 '1512529673 304'
         check ${3}-3 - ./ex2 '1769129556 304'
         [ -f ./.tfolder/.trec${2} ]; check_exn0 ${3}-4
         ( cd .tfolder && echo * > ./.tlst )
         check ${3}-5 - ./.tfolder/.tlst '2020171298 8'
         check ${3}-6 - ./.tfolder/ex1 '2016773910 284'
         check ${3}-7 - ./.tfolder/ex2 '2335391111 284'
      fi
   }

   t_it forward 5 6
   t_it Forward 7 8 yes
   #${rm} -f ex*

   ## Injections, headerpick selection
   ${rm} -f "${MBOX}"
   t__x2_msg > ./.tmbox

   printf '#
      set quote=noheading forward-inject-head
      forward 1 ex1@am.ple
b1
!.
      headerpick forward retain cc from subject to
      forward 1 ex1@am.ple
b2
!.
      unheaderpick forward retain *
      forward 1 ex1@am.ple
b3
!.
      headerpick forward ignore in-reply-to reply-to message-id status
      set forward-inject-head=%% forward-inject-tail=%%
      forward 1 ex1@am.ple
b4
!.
      set forward-inject-head='"\$'"'\\
            (%%%%a=%%a %%%%d=%%d %%%%f=%%f %%%%i=%%i %%%%n=%%n %%%%r=%%r)\\
            \\n'"'"' \\
         forward-inject-tail='"\$'"'\\
            (%%%%a=%%a %%%%d=%%d %%%%f=%%f %%%%i=%%i %%%%n=%%n %%%%r=%%r)\\
            \\n'"'"'
      forward 1 ex1@am.ple
b5
!.
      set showname datefield=%%y nodatefield-markout-older
      forward 1 ex1@am.ple
b6
!.
   ' | ${MAILX} ${ARGS} -Smta=test://"$MBOX" -Rf \
         -Sescape=! \
         ./.tmbox >./.tall 2>&1
   check_ex0 9-estat
   ${cat} ./.tall >> "${MBOX}"
   check 9 - "${MBOX}" '2976943913 2916'

   # forward-as-attachment
   </dev/null ${MAILX} ${ARGS} -Rf \
         -Sescape=! \
         -S forward-inject-head=.head. \
         -S forward-inject-tail=.tail. \
         -S forward-as-attachment \
         -Y 'headerpick forward retain subject to from' \
         -Y 'forward ex1@am.ple' -Y b1 -Y !. \
         -Y 'unset forward-as-attachment' \
         -Y 'forward ex1@am.ple;b2' -Y !. \
         ./.tmbox >./.tall 2>&1
   check 10 0 ./.tall '799103633 1250'

   ARGS=${XARGS}
   t_epilog "${@}"
} # }}}

t_resend() { # {{{
   t_prolog "${@}"
   XARGS=${ARGS}
   ARGS="${ARGS} -Sv15-compat=y"

   t__gen_msg subject fwd1 body origb1 from 1 to 2 > "${MBOX}"
   t__gen_msg subject fwd2 body origb2 from 1 to 1 >> "${MBOX}"

   ## Base
   t_it() {
      </dev/null ${MAILX} ${ARGS} -Rf \
         -Y ${1}' . "du <ex1@am.ple>"
      echo 1:$?/$^ERRNAME; echoerr 1:done
      set fullnames escape=!
      '${1}' 1 "du , da <ex2@am.ple>"
      echo 2:$?/$^ERRNAME; echoerr 2:done
      # Some errors
      set nofullnames ea=$expandaddr expandaddr=-all
      '${1}' ` "du <ex3@am.ple>"
      echo 3:$?/$^ERRNAME; echoerr 3:done
      set expandaddr=$ea
      '${1}' ` ex4-nono@am.ple ex4@am.ple # the first is a non-match msglist
      echo 4:$?/$^ERRNAME; echoerr 4:done
      '${1}' # TODO not yet possible b5 !.
      echo 5:$?/$^ERRNAME; echoerr 5:done
      set expandaddr=$ea
      '${1}' 1 2 ex6@am.ple
      echo 6:$?/$^ERRNAME; echoerr 6:done
      #' \
         "${MBOX}" > ./.tall 2>./.terr
      return ${?}
   }

   t_it resend
   check 1 0 ./.tall '1461006932 1305'
   if have_feat uistrings; then
      check 2 - ./.terr '138360532 210'
   else
      t_echoskip '2:[!UISTRINGS]'
   fi

   t_it Resend
   check 3 0 ./.tall '3674535444 958'
   if have_feat uistrings; then
      check 4 - ./.terr '138360532 210'
   else
      t_echoskip '4:[!UISTRINGS]'
   fi

   ## *record*, *outfolder* (reuses $MBOX)
   ${mkdir} .tfolder

   t_it() {
      </dev/null ${MAILX} ${ARGS} -Rf -Sescape=! -Sfolder=`${pwd}`/.tfolder \
      -Y '#
      set record=.trec'${2}'; '${1}' 1 ex1@am.ple
      echo 1:$?/$^ERRNAME; set record-resent; '${1}' 1 ex2@am.ple
      echo 2:$?/$^ERRNAME; set outfolder norecord-resent; '${1}' 2 ex1@am.ple
      echo 3:$?/$^ERRNAME; set record-resent; '${1}' 2 ex2@am.ple
      echo 4:$?/$^ERRNAME
      #' \
         "${MBOX}" > ./.tall 2>&1
      check_ex0 ${2}
      if [ ${#} -ne 3 ]; then
         check ${2} - ./.tall '1711347390 992'
         check ${3}-1 - ./.trec${2} '2840978700 249'
         check ${3}-2 - ./.tfolder/.trec${2} '3219997964 229'
      else
         check ${2} - ./.tall '1391418931 724'
         check ${3}-1 - ./.trec${2} '473817710 182'
         check ${3}-2 - ./.tfolder/.trec${2} '2174632404 162'
      fi
   }

   t_it resend 5 6 yes
   t_it Resend 7 8

   ARGS=${XARGS}
   t_epilog "${@}"
} # }}}
# }}}

# VFS {{{
t_copy() { # {{{
   t_prolog "${@}"

   t__gen_msg subject Copy1 from 1 to 1 body 'Body1' > "${MBOX}"
   t__gen_msg subject Copy2 from 1 to 1 body 'Body2' >> "${MBOX}"
   check 1 - "${MBOX}" '137107341 324' # for flag test

   ##
   </dev/null ${MAILX} ${ARGS} -f \
      -Y '#
   headers
   copy 10 .tf1
   echo 0:$?/$^ERRNAME
   headers
   copy .tf1
   echo 1:$?/$^ERRNAME
   headers
   copy .tf1 # no auto-advance
   echo 2:$?/$^ERRNAME
   headers
   copy 2 .tf2
   echo 3:$?/$^ERRNAME
   headers
   copy 1 2 .tf3
   echo 4:$?/$^ERRNAME
   headers
   !chmod 0444 .tf3
   copy 1 2 .tf3
   echo 5:$?/$^ERRNAME
   #' \
      "${MBOX}" > ./.tallx 2>./.terr
   check_ex0 2

   ${sed} -e '$bP' -e d -e :P < ./.tallx >> "${ERR}" # strip "FLD updated" TODO
   ${sed} '$d' < ./.tallx > ./.tall # strip "FOLDER updated." TODO
   check 2-1 - ./.tall '1913702840 1121'
   check 2-2 - ./.tf1 '686654461 334'
   check 2-3 - ./.tf2 '1931512953 162'
   check 2-4 - ./.tf3 '3642131968 344'
   if have_feat uistrings; then
      check 2-5 - ./.terr '2590372641 91'
   else
      t_echoskip '2-5:[!UISTRINGS]'
   fi

   ##
   check 3 - "${MBOX}" '1477662071 346'

   ##
   t_it() {
      t__gen_msg subject Copy1 from 1 to 1 body 'Body1' > "${MBOX}"
      t__gen_msg subject Copy2 from 1 to 1 body 'Body2' >> "${MBOX}"
      t__gen_msg subject Copy3 from ex@am.ple to 1 body 'Body3' >> "${MBOX}"
      check ${1} - "${MBOX}" '2667292819 473' # for flag test

      </dev/null ${MAILX} ${ARGS} -f \
         -Y "${3}"'
      '"${2}"'
      Copy
      echo 1:$?/$^ERRNAME
      '"${2}"'
      Copy
      echo 2:$?/$^ERRNAME
      '"${2}"'
      Copy 2
      echo 3:$?/$^ERRNAME
      '"${2}"'
      Copy 3
      echo 4:$?/$^ERRNAME
      '"${2}"'
      Copy *
      echo 5:$?/$^ERRNAME
      '"${2}"'
      #' \
         "${MBOX}" > ./.tallx 2>&1
      return ${?}
   }

   t_it 5 headers '#'
   check_ex0 5-1
   ${sed} -e '$bP' -e d -e :P < ./.tallx >> "${ERR}" # strip "FLD updated" TODO
   ${sed} '$d' < ./.tallx > ./.tall # strip "FOLDER updated." TODO
   echo * > ./.tlst
   check 5-2 - ./.tlst '1058655452 9'
   check 5-3 - ./.tall '1543702808 1617'
   check 5-4 - ./from1 '1031912635 999'
   check 5-5 - ./ex '2400630246 149'
   ${rm} -f ./.tlst ./.tall ./from1 ./ex

   ${mkdir} .tfolder
   t_it 6 '#' 'set outfolder folder='"`${pwd}`"'/.tfolder'
   check_ex0 6-1
   ${sed} -e '$bP' -e d -e :P < ./.tallx >> "${ERR}" # strip "FLD updated" TODO
   ${sed} '$d' < ./.tallx > ./.tall # strip "FOLDER updated." TODO
   echo * .tfolder/* > ./.tlst
   check 6-2 - ./.tlst '1865898363 29'
   ${cat} ./.tall >> ${ERR} #check 6-3 - ./.tall # TODO due to folder echoes
   check 6-4 - .tfolder/from1 '1031912635 999'
   check 6-5 - .tfolder/ex '2400630246 149'

   ##
   t__x2_msg > ./.tmbox

   t_it() {
      printf '#
         '"${1}"'
         echo 1:$?/$^ERRNAME
         headerpick save retain cc date from subject to
         '"${1}"'
         echo 2:$?/$^ERRNAME
         unheaderpick save retain *
         '"${1}"'
         echo 3:$?/$^ERRNAME
         headerpick save ignore status in-reply-to
         '"${1}"'
         echo 4:$?/$^ERRNAME
      #' | ${MAILX} ${ARGS} -Rf ./.tmbox > ./.tall 2>&1
      return ${?}
   }

   t_it 'copy ./.tout'
   check_ex0 7-estat
   check 7-1 - ./.tall '3805176908 152'
   check 7-2 - ./.tout '2447734879 1316'

   t_it Copy
   check_ex0 8-estat
   echo * > ./.tlst
   check 8-1 - ./.tall '1044700686 136'
   check 8-2 - ./mr2 '2447734879 1316'
   check 8-3 - ./.tlst '3190056903 4'

   t_epilog "${@}"
} # }}}

t_save() { # {{{
   t_prolog "${@}"

   t__gen_msg subject Save1 from 1 to 1 body 'Body1' > "${MBOX}"
   t__gen_msg subject Save2 from 1 to 1 body 'Body2' >> "${MBOX}"
   check 1 - "${MBOX}" '3634443864 324' # for flag test

   ##
   </dev/null ${MAILX} ${ARGS} -f \
      -Y '#
   headers
   save 10 .tf1
   echo 0:$?/$^ERRNAME
   headers
   save .tf1
   echo 1:$?/$^ERRNAME
   headers
   save .tf1 # no auto-advance
   echo 2:$?/$^ERRNAME
   headers
   save 2 .tf2
   echo 3:$?/$^ERRNAME
   headers
   save 1 2 .tf3
   echo 4:$?/$^ERRNAME
   headers
   !chmod 0444 .tf3
   save 1 2 .tf3
   echo 5:$?/$^ERRNAME
   #' \
      "${MBOX}" > ./.tallx 2>./.terr
   check_ex0 2

   ${sed} -e '$bP' -e d -e :P < ./.tallx >> "${ERR}" # strip "FLD updated" TODO
   ${sed} '$d' < ./.tallx > ./.tall # strip "FOLDER updated." TODO
   check 2-1 - ./.tall '2335843514 1121'
   check 2-2 - ./.tf1 '2435434321 334'
   check 2-3 - ./.tf2 '920652966 162'
   check 2-4 - ./.tf3 '970407001 344'
   if have_feat uistrings; then
      check 2-5 - ./.terr '2590372641 91'
   else
      t_echoskip '2-5:[!UISTRINGS]'
   fi

   ##
   check 3 - "${MBOX}" '1219692400 346'

   ##
   t_it() {
      t__gen_msg subject Save1 from 1 to 1 body 'Body1' > "${MBOX}"
      t__gen_msg subject Save2 from 1 to 1 body 'Body2' >> "${MBOX}"
      t__gen_msg subject Save3 from ex@am.ple to 1 body 'Body3' >> "${MBOX}"
      check ${1} - "${MBOX}" '1391391227 473' # for flag test

      </dev/null ${MAILX} ${ARGS} -f \
         -Y "${3}"'
      '"${2}"'
      Save
      echo 1:$?/$^ERRNAME
      '"${2}"'
      Save
      echo 2:$?/$^ERRNAME
      '"${2}"'
      Save 2
      echo 3:$?/$^ERRNAME
      '"${2}"'
      Save 3
      echo 4:$?/$^ERRNAME
      '"${2}"'
      Save *
      echo 5:$?/$^ERRNAME
      '"${2}"'
      #' \
         "${MBOX}" > ./.tallx 2>&1
      return ${?}
   }

   t_it 5 headers '#'
   check_ex0 5-1
   ${sed} -e '$bP' -e d -e :P < ./.tallx >> "${ERR}" # strip "FLD updated" TODO
   ${sed} '$d' < ./.tallx > ./.tall # strip "FOLDER updated." TODO
   echo * > ./.tlst
   check 5-2 - ./.tlst '1058655452 9'
   check 5-3 - ./.tall '3418590770 1617'
   check 5-4 - ./from1 '1462882526 999'
   check 5-5 - ./ex '2153575326 149'
   ${rm} -f ./.tlst ./.tall ./from1 ./ex

   ${mkdir} .tfolder
   t_it 6 '#' 'set outfolder folder='"`${pwd}`"'/.tfolder'
   check_ex0 6-1
   ${sed} -e '$bP' -e d -e :P < ./.tallx >> "${ERR}" # strip "FLD updated" TODO
   ${sed} '$d' < ./.tallx > ./.tall # strip "FOLDER updated." TODO
   echo * .tfolder/* > ./.tlst
   check 6-2 - ./.tlst '1865898363 29'
   ${cat} ./.tall >> ${ERR} #check 6-3 - ./.tall # TODO due to folder echoes
   check 6-4 - .tfolder/from1 '1462882526 999'
   check 6-5 - .tfolder/ex '2153575326 149'

   ##

   t_it() {
      t__x2_msg > ./.tmbox
      check ${1} - ./.tmbox '561523988 397'

      a='-Rf'
      [ ${#} -gt 2 ] && a='-S MBOX=./.tmboxx'
      [ ${#} -gt 3 ] && a="${a}"' -S inbox=./.tmbox'
      printf '#
         headers
         '"${2}"'
         echo 1:$?/$^ERRNAME
         headers
         headerpick save retain cc date from subject to
         '"${2}"'
         echo 2:$?/$^ERRNAME
         unheaderpick save retain *
         '"${2}"'
         echo 3:$?/$^ERRNAME
         headerpick save ignore status in-reply-to
         '"${2}"'
         echo 4:$?/$^ERRNAME
      #' | ${MAILX} ${ARGS} -f ${a} ./.tmbox > ./.tall 2>&1
      return ${?}
   }

   t_it 7 'save ./.tout'
   check_ex0 7-estat
   check 7-1 - ./.tall '4190949581 312'
   check 7-2 - ./.tout '2447734879 1316'
   check 7-3 - ./.tmbox '561523988 397'

   t_it 8 Save
   check_ex0 8-estat
   echo * > ./.tlst
   check 8-1 - ./.tall '2109832180 296'
   check 8-2 - ./mr2 '2447734879 1316'
   check 8-3 - ./.tlst '3190056903 4'
   check 8-3 - ./.tmbox '561523988 397'

   # saves in $MBOX without argument
   t_it 9 save yes
   check_ex0 9-estat
   check 9-1 - ./.tall '652005824 320'
   check 9-2 - ./.tmboxx '2447734879 1316'
   check 9-3 - ./.tmbox '561523988 397'

   # and deletes if editing a primary mailbox
   ${rm} -f ./.tmboxx
   t_it 10 save yes yes
   check_ex0 10-estat
   check 10-1 - ./.tall '652005824 320'
   check 10-2 - ./.tmboxx '2447734879 1316'
   [ -f ./.tmbox ]; check_exn0 10-3

   t_epilog "${@}"
} # }}}

t_move() { # {{{
   t_prolog "${@}"

   t__gen_msg subject Move1 from 1 to 1 body 'Body1' > "${MBOX}"
   t__gen_msg subject Move2 from 1 to 1 body 'Body2' >> "${MBOX}"
   check 1 - "${MBOX}" '2967134193 324' # for flag test

   ##
   </dev/null ${MAILX} ${ARGS} -f \
      -Y '#
   headers
   move 10 .tf1
   echo 0:$?/$^ERRNAME
   headers
   move .tf1
   echo 1:$?/$^ERRNAME
   headers
   !touch .tf2; chmod 0444 .tf2
   move 2 .tf2
   echo 2:$?/$^ERRNAME
   !chmod 0644 .tf2
   move 2 .tf2
   echo 3:$?/$^ERRNAME
   headers
   #' \
      "${MBOX}" > ./.tallx 2>./.terr
   check_ex0 2

   ${sed} -e '$bP' -e d -e :P < ./.tallx >> "${ERR}" # strip "FLD updated" TODO
   ${sed} '$d' < ./.tallx > ./.tall # strip "FOLDER updated." TODO
   check 2-1 - ./.tall '1641443074 491'
   check 2-2 - ./.tf1 '1473857906 162'
   check 2-3 - ./.tf2 '331229810 162'
   if have_feat uistrings; then
      check 2-4 - ./.terr '1243633205 134'
   else
      t_echoskip '2-4:[!UISTRINGS]'
   fi

   ##
   check 3 - "${MBOX}" '4294967295 0'

   ##
   t_it() {
      t__gen_msg subject Move1 from 1 to 1 body 'Body1' > "${MBOX}"
      t__gen_msg subject Move2 from 1 to 1 body 'Body2' >> "${MBOX}"
      t__gen_msg subject Move3 from ex@am.ple to 1 body 'Body3' >> "${MBOX}"
      check ${1} - "${MBOX}" '2826896131 473' # for flag test

      </dev/null ${MAILX} ${ARGS} -f \
         -Y "${3}"'
      '"${2}"'
      Move
      echo 1:$?/$^ERRNAME
      '"${2}"'
      Move 2
      echo 2:$?/$^ERRNAME
      '"${2}"'
      Move 3
      echo 3:$?/$^ERRNAME
      '"${2}"'
      undelete *
      echo 4:$?/$^ERRNAME
      '"${2}"'
      Move *
      echo 5:$?/$^ERRNAME
      '"${2}"'
      #' \
         "${MBOX}" > ./.tallx 2>./.terr
      return ${?}
   }

   t_it 5 headers '#'
   check_ex0 5-1
   ${sed} -e '$bP' -e d -e :P < ./.tallx >> "${ERR}" # strip "FLD updated" TODO
   ${sed} '$d' < ./.tallx > ./.tall # strip "FOLDER updated." TODO
   echo * > ./.tlst
   check 5-2 - ./.tlst '1058655452 9'
   check 5-3 - ./.tall '419037676 870'
   check 5-4 - ./.terr '1383646464 86'
   check 5-5 - ./from1 '3719268580 827'
   check 5-6 - ./ex '4262925856 149'
   ${rm} -f ./.tlst ./.tall ./.terr ./from1 ./ex

   ${mkdir} .tfolder
   t_it 6 '#' 'set outfolder folder='"`${pwd}`"'/.tfolder'
   check_ex0 6-1
   ${sed} -e '$bP' -e d -e :P < ./.tallx >> "${ERR}" # strip "FLD updated" TODO
   ${sed} '$d' < ./.tallx > ./.tall # strip "FOLDER updated." TODO
   echo * .tfolder/* > ./.tlst
   check 6-2 - ./.tlst '1865898363 29'
   ${cat} ./.tall >> ${ERR} #check 6-3 - ./.tall # TODO due to folder echoes
   check 6-4 - .tfolder/from1 '3719268580 827'
   check 6-5 - .tfolder/ex '4262925856 149'

   ##
   t__x2_msg > ./.tmbox

   t_it() {
      printf '#
         '"${1}"'
         echo 1:$?/$^ERRNAME
         headerpick save retain cc date from subject to
         '"${1}"'
         echo 2:$?/$^ERRNAME
         unheaderpick save retain *
         '"${1}"'
         echo 3:$?/$^ERRNAME
         headerpick save ignore status in-reply-to
         '"${1}"'
         echo 4:$?/$^ERRNAME
      #' | ${MAILX} ${ARGS} -Rf ./.tmbox > ./.tall 2>&1
      return ${?}
   }

   t_it 'move ./.tout'
   check_ex0 7-estat
   check 7-1 - ./.tall '3805176908 152'
   check 7-2 - ./.tout '2447734879 1316'

   t_it Move
   check_ex0 8-estat
   echo * > ./.tlst
   check 8-1 - ./.tall '1044700686 136'
   check 8-2 - ./mr2 '2447734879 1316'
   check 8-3 - ./.tlst '3190056903 4'

   t_epilog "${@}"
} # }}}

t_mbox() { # {{{
   t_prolog "${@}"

   (
      i=1
      while [ ${i} -lt 113 ]; do
         printf 'm file://%s\n~s Subject %s\nHello %s!\n~.\n' \
            "${MBOX}" "${i}" "${i}"
         i=`add ${i} 1`
      done
   ) | ${MAILX} ${ARGS} > .tall 2>&1
   check 1 0 "${MBOX}" '1785801373 13336'
   check 1-outerr - ./.tall '4294967295 0' # empty file

   printf 'File "%s"\ncopy * "%s"\nFile "%s"\nfrom*' "${MBOX}" .tmbox1 .tmbox1 |
      ${MAILX} ${ARGS} -Sshowlast > .tall 2>&1
   check 2 0 .tall '3467540956 8991'

   printf 'File "%s"\ncopy * "file://%s"\nFile "file://%s"\nfrom*' \
      "${MBOX}" .tmbox2 .tmbox2 | ${MAILX} ${ARGS} -Sshowlast > .tall 2>&1
   check 3 0 .tall '2410946529 8998'

   # copy only the odd (but the first), move the even
   (
      printf 'File "file://%s"\ncopy ' .tmbox2
      i=1
      while [ ${i} -lt 113 ]; do
         printf '%s ' "${i}"
         i=`add ${i} 2`
      done
      printf 'file://%s\nFile "file://%s"\nfrom*' .tmbox3 .tmbox3
   ) | ${MAILX} ${ARGS} -Sshowlast > .tall 2>&1
   check 4 0 .tmbox3 '2554734733 6666'
   check 5 - .tall '2062382804 4517'
   # ...
   (
      printf 'file "file://%s"\nmove ' .tmbox2
      i=2
      while [ ${i} -lt 113 ]; do
         printf '%s ' "${i}"
         i=`add ${i} 2`
      done
      printf 'file://%s\nFile "file://%s"\nfrom*\nFile "file://%s"\nfrom*' \
         .tmbox3 .tmbox3 .tmbox2
   ) | ${MAILX} ${ARGS} -Sshowlast > .tall 2>>${ERR}
   check 6 0 .tmbox3 '1429216753 13336'
   if have_feat uistrings; then
      ${sed} 2d < .tall > .tallx
   else
      ${cp} .tall .tallx
   fi
   check 7 - .tallx '169518319 13477'

   # Invalid MBOXes (after [f4db93b3])
   echo > .tinvmbox
   printf 'copy 1 ./.tinvmbox' | ${MAILX} ${ARGS} -Rf "${MBOX}" > .tall 2>&1
   check 8 0 .tinvmbox '2848412822 118'
   check 9 - ./.tall '461280182 33'

   echo ' ' > .tinvmbox
   printf 'copy 1 ./.tinvmbox' | ${MAILX} ${ARGS} -Rf "${MBOX}" > .tall 2>&1
   check 10 0 .tinvmbox '624770486 120'
   check 11 - ./.tall '461280182 33'

   { echo; echo; } > .tinvmbox # (not invalid)
   printf 'copy 1 ./.tinvmbox' | ${MAILX} ${ARGS} -Rf "${MBOX}" > .tall 2>&1
   check 12 0 .tinvmbox '1485640875 119'
   check 13 - ./.tall '461280182 33'

   # *mbox-rfc4155*, plus
   ${cat} <<-_EOT > ./.tinv1
		 
		
		From MAILER-DAEMON-1 Wed Oct  2 01:50:07 1996
		Date: Wed, 02 Oct 1996 01:50:07 +0000
		To:
		Subject: Bad bad message 1
		
		From me to you, blinde Kuh!
		
		From MAILER-DAEMON-2 Wed Oct  2 01:50:07 1996
		Date: Wed, 02 Oct 1996 01:50:07 +0000
		To:
		Subject: Bad bad message 2
		
		From me to you, blindes Kalb!
		_EOT
   ${cp} ./.tinv1 ./.tinv2

   printf \
      'define mboxfix {
         \\localopts yes; \\wysh set mbox-rfc4155;\\wysh File "${1}";\\
            \\eval copy * "${2}"
      }
      call mboxfix ./.tinv1 ./.tok' | ${MAILX} ${ARGS} > .tall 2>&1
   check_ex0 14-estat
   ${cat} ./.tinv1 ./.tok >> .tall
   check 14 - ./.tall '739301109 616'

   printf \
      'wysh file ./.tinv1 # ^From not repaired, but missing trailing NL is
      wysh File ./.tok # Just move away to nowhere
      set mbox-rfc4155
      wysh file ./.tinv2 # Fully repaired
      File ./.tok' | ${MAILX} ${ARGS} >>${ERR} 2>&1
   check_ex0 15-estat
   # Equal since [Auto-fix when MBOX had From_ errors on read (Dr. Werner
   # Fink).]
   check 15-1 - ./.tinv1 '4151504442 314'
   check 15-2 - ./.tinv2 '4151504442 314'

   # *mbox-fcc-and-pcc*
   ${cat} > ./.ttmpl <<-'_EOT'
	Fcc: ./.tfcc1
	Bcc: | cat >> ./.tpcc1
	Fcc:        ./.tfcc2           
	Subject: fcc and pcc, and *mbox-fcc-and-pcc*
	
	one line body
	_EOT

   < ./.ttmpl ${MAILX} ${ARGS} -t > "${MBOX}" 2>&1
   check 16 0 "${MBOX}" '4294967295 0'
   check 17 - ./.tfcc1 '2301294938 148'
   check 18 - ./.tfcc2 '2301294938 148'
   check 19 - ./.tpcc1 '2301294938 148'

   < ./.ttmpl ${MAILX} ${ARGS} -t -Snombox-fcc-and-pcc > "${MBOX}" 2>&1
   check 20 0 "${MBOX}" '4294967295 0'
   check 21 - ./.tfcc1 '3629108107 98'
   check 22 - ./.tfcc2 '3629108107 98'
   check 23 - ./.tpcc1 '2373220256 246'

   # More invalid: since in "copy * X" messages will be copied in `sort' order,
   # reordering may happen, and before ([f5db11fe] (a_cwrite_save1(): FIX:
   # ensure pre-v15 MBOX separation "in between" messages.., 2019-08-07) that
   # could still have created invalid MBOX files!
   ${cat} <<-_EOT > ./.tinv1
		 
		
		From MAILER-DAEMON-4 Sun Oct  4 01:50:07 1998
		Date: Sun, 04 Oct 1998 01:50:07 +0000
		Subject: h4
		
		B4
		
		From MAILER-DAEMON-0 Fri Oct 28 21:02:21 2147483649
		Date: Nix, 01 Oct BAD 01:50:07 +0000
		Subject: hinvalid
		
		BINV
		
		From MAILER-DAEMON-3 Fri Oct  3 01:50:07 1997
		Date: Fri, 03 Oct 1997 01:50:07 +0000
		Subject: h3
		
		B3
		
		From MAILER-DAEMON-1 Sun Oct  1 01:50:07 1995
		Date: Sun, 01 Oct 1995 01:50:07 +0000
		Subject:h1
		
		B1
		
		
		From MAILER-DAEMON-2 Wed Oct  2 01:50:07 1996
		Date: Wed, 02 Oct 1996 01:50:07 +0000
		Subject: h2
		
		b2
		_EOT

   printf \
      'File ./.tinv1
      sort date
      remove ./.tinv2
      copy * ./.tinv2
      file ./.tinv1' | ${MAILX} ${ARGS} >>${ERR} 2>&1
   check 24 0 ./.tinv1 '104184185 560'
   check 25 - ./.tinv2 '853754737 510'

   t_epilog "${@}"
} # }}}

t_maildir() { # {{{
   t_prolog "${@}"

   if have_feat maildir; then :; else
      t_echoskip '[!MAILDIR]'
      t_epilog "${@}"
      return
   fi

   (
      i=0
      while [ ${i} -lt 112 ]; do
         printf 'm file://%s\n~s Subject %s\nHello %s!\n~.\n' \
            "${MBOX}" "${i}" "${i}"
         i=`add ${i} 1`
      done
   ) | ${MAILX} ${ARGS}
   check 1 0 "${MBOX}" '2366902811 13332'

   printf 'File "%s"
         copy * "%s"
         File "%s"
         from*
      ' "${MBOX}" .tmdir1 .tmdir1 |
      ${MAILX} ${ARGS} -Snewfolders=maildir -Sshowlast > .tlst
   check 2 0 .tlst '3442251309 8991'

   printf 'File "%s"
         copy * "maildir://%s"
         File "maildir://%s"
         from*
      ' "${MBOX}" .tmdir2 .tmdir2 |
      ${MAILX} ${ARGS} -Sshowlast > .tlst
   check 3 0 .tlst '3524806062 9001'

   printf 'File "maildir://%s"
         copy * "file://%s"
         File "file://%s"
         from*
      ' .tmdir2 .tmbox1 .tmbox1 |
      ${MAILX} ${ARGS} -Sshowlast > .tlst
   check 4 0 .tmbox1 '4096198846 12772'
   check 5 - .tlst '1262452287 8998'

   # only the odd (even)
   (
      printf 'File "maildir://%s"
            copy ' .tmdir2
      i=0
      while [ ${i} -lt 112 ]; do
         j=`modulo ${i} 2`
         [ ${j} -eq 1 ] && printf '%s ' "${i}"
         i=`add ${i} 1`
      done
      printf ' file://%s
            File "file://%s"
            from*
         ' .tmbox2 .tmbox2
   ) | ${MAILX} ${ARGS} -Sshowlast > .tlst
   check 6 0 .tmbox2 '4228337024 6386'
   check 7 - .tlst '2078821439 4517'
   # ...
   (
      printf 'file "maildir://%s"
            move ' .tmdir2
      i=0
      while [ ${i} -lt 112 ]; do
         j=`modulo ${i} 2`
         [ ${j} -eq 0 ] && [ ${i} -ne 0 ] && printf '%s ' "${i}"
         i=`add ${i} 1`
      done
      printf ' file://%s
            File "file://%s"
            from*
            File "maildir://%s"
            from*
         ' .tmbox2 .tmbox2 .tmdir2
   ) | ${MAILX} ${ARGS} -Sshowlast > .tlst
   check 8 0 .tmbox2 '978751761 12656'
   ${sed} 2d < .tlst > .tlstx
   check 9 - .tlstx '2172297531 13477'

   # More invalid: since in "copy * X" messages will be copied in `sort' order,
   # reordering may happen, and before ([f5db11fe] (a_cwrite_save1(): FIX:
   # ensure pre-v15 MBOX separation "in between" messages.., 2019-08-07) that
   # could still have created invalid MBOX files!
   ${cat} <<-_EOT > ./.tinv1
		 
		
		From MAILER-DAEMON-4 Sun Oct  4 01:50:07 1998
		Date: Sun, 04 Oct 1998 01:50:07 +0000
		Subject: h4
		
		B4
		
		From MAILER-DAEMON-0 Fri Oct 28 21:02:21 2147483649
		Date: Nix, 01 Oct BAD 01:50:07 +0000
		Subject: hinvalid
		
		BINV
		
		From MAILER-DAEMON-3 Fri Oct  3 01:50:07 1997
		Date: Fri, 03 Oct 1997 01:50:07 +0000
		Subject: h3
		
		B3
		
		From MAILER-DAEMON-1 Sun Oct  1 01:50:07 1995
		Date: Sun, 01 Oct 1995 01:50:07 +0000
		Subject:h1
		
		B1
		
		
		From MAILER-DAEMON-2 Wed Oct  2 01:50:07 1996
		Date: Wed, 02 Oct 1996 01:50:07 +0000
		Subject: h2
		
		b2
		_EOT

   printf \
      'File ./.tinv1
      sort date
      copy * maildir://./.tmdir10
      !{ for f in ./.tmdir10/new/*; do echo ===; %s $f; done; } > ./.t11
      File ./.tmdir10
      sort date
      copy * ./.t10warp
   ' "${cat}" | ${MAILX} ${ARGS} >>${ERR} 2>&1
   # Note that substdate() fixes all but one From_ line to $SOURCE_DATE_EPOCH!
   check 10 0 ./.t10warp '3551111321 502'
   check 11 - ./.t11 '642719592 302'

   t_epilog "${@}"
} # }}}
# }}}

# MIME and RFC basics {{{
t_mime_if_not_ascii() {
   t_prolog "${@}"

   </dev/null ${MAILX} ${ARGS} -s Subject "${MBOX}" >> "${MBOX}" 2>&1
   check 1 0 "${MBOX}" '3647956381 106'

   </dev/null ${MAILX} ${ARGS} -Scharset-7bit=not-ascii -s Subject "${MBOX}" \
      >> "${MBOX}" 2>&1
   check 2 0 "${MBOX}" '3964303752 274'

   t_epilog "${@}"
}

t_mime_encoding() {
   t_prolog "${@}"

   # 8B
   printf 'Hey, you.\nFrom me to you\nCiao\n' |
      ${MAILX} ${ARGS} -s Subject -Smime-encoding=8b "${MBOX}" \
         >> "${MBOX}" 2>&1
   check 1 0 "${MBOX}" '3835153597 136'
   printf 'Hey, you.\n\nFrom me to you\nCiao.\n' |
      ${MAILX} ${ARGS} -s Subject -Smime-encoding=8b "${MBOX}" \
         >> "${MBOX}" 2>&1
   check 2 0 "${MBOX}" '63875210 275'

   # QP
   printf 'Hey, you.\n From me to you\nCiao\n' |
      ${MAILX} ${ARGS} -s Subject -Smime-encoding=qp "${MBOX}" \
         >> "${MBOX}" 2>&1
   check 3 0 "${MBOX}" '465798521 412'
   printf 'Hey, you.\nFrom me to you\nCiao\n' |
      ${MAILX} ${ARGS} -s Subject -Smime-encoding=qp "${MBOX}" \
         >> "${MBOX}" 2>&1
   check 4 0 "${MBOX}" '2075263697 655'

   # B64
   printf 'Hey, you.\n From me to you\nCiao\n' |
      ${MAILX} ${ARGS} -s Subject -Smime-encoding=b64 "${MBOX}" \
         >> "${MBOX}" 2>&1
   check 5 0 "${MBOX}" '601672771 792'
   printf 'Hey, you.\nFrom me to you\nCiao\n' |
      ${MAILX} ${ARGS} -s Subject -Smime-encoding=b64 "${MBOX}" \
         >> "${MBOX}" 2>&1
   check 6 0 "${MBOX}" '3926760595 1034'

   t_epilog "${@}"
}

t_xxxheads_rfc2047() {
   t_prolog "${@}"

   echo | ${MAILX} ${ARGS} ${ADDARG_UNI} \
      -s 'a̲b̲c̲d̲e̲f̲h̲i̲k̲l̲m̲n̲o̲r̲s̲t̲u̲v̲w̲x̲z̲a̲b̲c̲d̲e̲f̲h̲i̲k̲l̲m̲n̲o̲r̲s̲t̲u̲v̲w̲x̲z̲' \
      "${MBOX}"
   check 1 0 "${MBOX}" '3422562347 371'

   # Single word (overlong line split -- bad standard! Requires injection of
   # artificial data!!  But can be prevented by using RFC 2047 encoding)
   ${rm} "${MBOX}"
   i=`${awk} 'BEGIN{for(i=0; i<92; ++i) printf "0123456789_"}'`
   echo | ${MAILX} ${ARGS} -s "${i}" "${MBOX}"
   check 2 0 "${MBOX}" '3317256266 1714'

   # Combination of encoded words, space and tabs of varying sort
   ${rm} "${MBOX}"
   echo | ${MAILX} ${ARGS} ${ADDARG_UNI} \
      -s "1Abrä Kaspas1 2Abra Katä	b_kaspas2  \
3Abrä Kaspas3   4Abrä Kaspas4    5Abrä Kaspas5     \
6Abra Kaspas6      7Abrä Kaspas7       8Abra Kaspas8        \
9Abra Kaspastäb4-3 	 	 	 10Abra Kaspas1 _ 11Abra Katäb1	\
12Abra Kadabrä1 After	Tab	after	Täb	this	is	NUTS" \
      "${MBOX}"
   check 3 0 "${MBOX}" '786672837 587'

   # Overlong multibyte sequence that must be forcefully split
   # todo This works even before v15.0, but only by accident
   ${rm} "${MBOX}"
   echo | ${MAILX} ${ARGS} ${ADDARG_UNI} \
      -s "✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄\
✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄\
✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄✄" \
      "${MBOX}"
   check 4 0 "${MBOX}" '2889557767 655'

   # Trailing WS
   ${rm} "${MBOX}"
   echo | ${MAILX} ${ARGS} \
      -s "1-1 	 B2 	 B3 	 B4 	 B5 	 B6 	 B\
1-2 	 B2 	 B3 	 B4 	 B5 	 B6 	 B\
1-3 	 B2 	 B3 	 B4 	 B5 	 B6 	 B\
1-4 	 B2 	 B3 	 B4 	 B5 	 B6 	 B\
1-5 	 B2 	 B3 	 B4 	 B5 	 B6 	 B\
1-6 	 B2 	 B3 	 B4 	 B5 	 B6 	 " \
      "${MBOX}"
   check 5 0 "${MBOX}" '3135161683 293'

   # Leading and trailing WS
   ${rm} "${MBOX}"
   echo | ${MAILX} ${ARGS} \
      -s "	 	 2-1 	 B2 	 B3 	 B4 	 B5 	 B6 	 B\
1-2 	 B2 	 B3 	 B4 	 B5 	 B6 	 B\
1-3 	 B2 	 B3 	 B4 	 B5 	 B6 	 B\
1-4 	 B2 	 B3 	 B4 	 B5 	 B6 	 " \
      "${MBOX}"
   check 6 0 "${MBOX}" '3221845405 232'

   # RFC 2047 in an address field!  (Missing test caused v14.9.6!)
   ${rm} "${MBOX}"
   echo "Dat Früchtchen riecht häußlich" |
      ${MAILX} ${ARGS} ${ADDARG_UNI} -Sfullnames -Smta=test://"$MBOX" \
         -s Hühöttchen \
         'Schnödes "Früchtchen" <do@du> (Hä!)'
   check 7 0 "${MBOX}" '3681801246 373'

   # RFC 2047 in an address field, and iconv involved
   if have_feat iconv; then
      ${rm} "${MBOX}"
      ${cat} > ./.trebox <<_EOT
From zaza@exam.ple  Fri Mar  2 21:31:56 2018
Date: Fri, 2 Mar 2018 20:31:45 +0000
From: z=?iso-8859-1?Q?=E1?=za <zaza@exam.ple>
To: dude <dude@exam.ple>
Subject: houston(...)
Message-ID: <abra@1>
MIME-Version: 1.0
Content-Type: text/plain; charset=iso-8859-1
Content-Disposition: inline
Content-Transfer-Encoding: 8bit

_EOT
      echo reply | ${MAILX} ${ARGS} ${ADDARG_UNI} \
         -Sfullnames -Sreply-in-same-charset \
         -Smta=test://"$MBOX" -Rf ./.trebox
      check 8 0 "${MBOX}" '3499372945 285'
   else
      t_echoskip '8:[!ICONV]'
   fi

   t_epilog "${@}"
}

t_iconv_mbyte_base64() { # TODO uses sed(1) and special *headline*!!
   t_prolog "${@}"

   if [ -n "${UTF8_LOCALE}" ] && have_feat iconv; then
      if (</dev/null iconv -f ascii -t iso-2022-jp) >/dev/null 2>&1 ||
            (</dev/null iconv -f ascii -t euc-jp) >/dev/null 2>&1; then
         :
      else
         t_echoskip '[ICONV/iconv(1):missing conversion(s)]'
         t_epilog "${@}"
         return
      fi
   else
      t_echoskip '[no UTF-8 locale or !ICONV]'
      t_epilog "${@}"
      return
   fi

   if (</dev/null iconv -f ascii -t iso-2022-jp) >/dev/null 2>&1; then
      ${cat} <<-'_EOT' | LC_ALL=${UTF8_LOCALE} ${MAILX} ${ARGS} \
            -Smta=test://"$MBOX" \
            -Sescape=! -Smime-encoding=base64 2>./.terr
         set ttycharset=utf-8 sendcharsets=iso-2022-jp
         m t1@exam.ple
!s Japanese from UTF-8 to ISO-2022-JP
シジュウカラ科（シジュウカラか、学名 Paridae）は、鳥類スズメ目の科である。シジュウカラ（四十雀）と総称されるが、狭義にはこの1種をシジュウカラと呼ぶ。

カンムリガラ（学名Parus cristatus）は、スズメ目シジュウカラ科に分類される鳥類の一種。


カンムリガラ（学名Parus cristatus）は、スズメ目シジュウカラ科に分類される鳥類の一種。

シジュウカラ科（シジュウカラか、学名 Paridae）は、鳥類スズメ目の科である。シジュウカラ（四十雀）と総称されるが、狭義にはこの1種をシジュウカラと呼ぶ。
!.

         set ttycharset=iso-2022-jp charset-7bit=iso-2022-jp sendcharsets=utf-8
         m t2@exam.ple
!s Japanese from ISO-2022-JP to UTF-8, eh, no, also ISO-2022-JP
$B%7%8%e%&%+%i2J!J%7%8%e%&%+%i$+!"3XL>(B Paridae$B!K$O!"D;N`%9%:%aL\$N2J$G$"$k!#%7%8%e%&%+%i!J;M==?}!K$HAm>N$5$l$k$,!"695A$K$O$3$N(B1$B<o$r%7%8%e%&%+%i$H8F$V!#(B

$B%+%s%`%j%,%i!J3XL>(BParus cristatus$B!K$O!"%9%:%aL\%7%8%e%&%+%i2J$KJ,N`$5$l$kD;N`$N0l<o!#(B


$B%+%s%`%j%,%i!J3XL>(BParus cristatus$B!K$O!"%9%:%aL\%7%8%e%&%+%i2J$KJ,N`$5$l$kD;N`$N0l<o!#(B

$B%7%8%e%&%+%i2J!J%7%8%e%&%+%i$+!"3XL>(B Paridae$B!K$O!"D;N`%9%:%aL\$N2J$G$"$k!#%7%8%e%&%+%i!J;M==?}!K$HAm>N$5$l$k$,!"695A$K$O$3$N(B1$B<o$r%7%8%e%&%+%i$H8F$V!#(B
!.
		_EOT
      # May not presume iconv output as long as roundtrip possible [489a7122]
      check_ex0 1-estat
      ${awk} 'BEGIN{h=1}/^$/{++h;next}{if(h % 2 == 1)print}' \
         < "${MBOX}" > ./.tcksum
      check 1 - ./.tcksum '3314001564 516'
      check 2 - ./.terr '4294967295 0'

      printf 'eval f 1; eval write ./.twrite; eval type 1; eval type 2\n' |
         LC_ALL=${UTF8_LOCALE} ${MAILX} ${ARGS} \
            -S headline="%>%a%m %-18f %-16d %i%-s" \
            -Rf "${MBOX}" >./.tlog 2>&1
      check 3 0 ./.twrite '1259742080 686'
      #check 4 - ./.tlog '3214068822 2123'
      ${sed} -e '/^\[-- M/d' < ./.tlog > ./.txlog
      check 4 - ./.txlog '4083300132 2030'
   else
      t_echoskip '1-4:[ICONV/iconv(1):ISO-2022-JP unsupported]'
   fi

   if (</dev/null iconv -f ascii -t euc-jp) >/dev/null 2>&1; then
      ${rm} -f "${MBOX}" ./.twrite
      ${cat} <<-'_EOT' | LC_ALL=${UTF8_LOCALE} ${MAILX} ${ARGS} \
            -Smta=test://"$MBOX" \
            -Sescape=! -Smime-encoding=base64 2>./.terr
         set ttycharset=utf-8 sendcharsets=euc-jp
         m t1@exam.ple
!s Japanese from UTF-8 to EUC-JP
シジュウカラ科（シジュウカラか、学名 Paridae）は、鳥類スズメ目の科である。シジュウカラ（四十雀）と総称されるが、狭義にはこの1種をシジュウカラと呼ぶ。

カンムリガラ（学名Parus cristatus）は、スズメ目シジュウカラ科に分類される鳥類の一種。


カンムリガラ（学名Parus cristatus）は、スズメ目シジュウカラ科に分類される鳥類の一種。

シジュウカラ科（シジュウカラか、学名 Paridae）は、鳥類スズメ目の科である。シジュウカラ（四十雀）と総称されるが、狭義にはこの1種をシジュウカラと呼ぶ。
!.

         set ttycharset=EUC-JP sendcharsets=utf-8
         m t2@exam.ple
!s Japanese from EUC-JP to UTF-8
�����奦����ʡʥ����奦���餫����̾ Paridae�ˤϡ�Ļ�ॹ�����ܤβʤǤ��롣�����奦����ʻͽ����ˤ����Τ���뤬�������ˤϤ���1��򥷥��奦����ȸƤ֡�

�����ꥬ��ʳ�̾Parus cristatus�ˤϡ��������ܥ����奦����ʤ�ʬ�व���Ļ��ΰ�


�����ꥬ��ʳ�̾Parus cristatus�ˤϡ��������ܥ����奦����ʤ�ʬ�व���Ļ��ΰ�

�����奦����ʡʥ����奦���餫����̾ Paridae�ˤϡ�Ļ�ॹ�����ܤβʤǤ��롣�����奦����ʻͽ����ˤ����Τ���뤬�������ˤϤ���1��򥷥��奦����ȸƤ֡�
!.
		_EOT
      check_ex0 5-estat
      ${awk} 'BEGIN{h=1}/^$/{++h;next}{if(h % 2 == 1)print}' \
         < "${MBOX}" > ./.tcksum
      check 5 - ./.tcksum '1754179361 469'
      check 6 - ./.terr '4294967295 0'

      printf 'eval f 1; eval write ./.twrite; eval type 1; eval type 2\n' |
         LC_ALL=${UTF8_LOCALE} ${MAILX} ${ARGS} \
            -S headline="%>%a%m %-18f %-16d %i%-s" \
            -Rf "${MBOX}" >./.tlog 2>&1
      check 7 0 ./.twrite '1259742080 686'
      #check 8 - ./.tlog '2506063395 2075'
      ${sed} -e '/^\[-- M/d' < ./.tlog > ./.txlog
      check 8 - ./.txlog '3192017734 1983'
   else
      t_echoskip '5-8:[ICONV/iconv(1):EUC-JP unsupported]'
   fi

   t_epilog "${@}"
}

t_iconv_mainbody() {
   t_prolog "${@}"

   if [ -n "${UTF8_LOCALE}" ] && have_feat iconv; then :; else
      t_echoskip '[no UTF-8 locale or !ICONV]'
      t_epilog "${@}"
      return
   fi

   printf '–' | ${MAILX} ${ARGS} ${ADDARG_UNI} -Smta=test://"$MBOX" \
      -S charset-7bit=us-ascii -S charset-8bit=utf-8 \
      -s '–' over-the@rain.bow 2>./.terr
   check 1 0 "${MBOX}" '3559538297 250'
   check 2 - ./.terr '4294967295 0'

   printf '–' | ${MAILX} ${ARGS} ${ADDARG_UNI} -Smta=test://"$MBOX" \
      -S charset-7bit=us-ascii -S charset-8bit=us-ascii \
      -s '–' over-the@rain.bow 2>./.terr
   check_exn0 3
   check 3 - "${MBOX}" '3559538297 250'
   if have_feat uistrings; then
      if have_feat docstrings; then # xxx should not be like that
         check 4 - ./.terr '2579894983 148'
      else
         check 4 - ./.terr '271380835 121'
      fi
   else
      t_echoskip '4:[!UISTRINGS]'
   fi

   # The different iconv(3) implementations use different replacement sequence
   # types (character-wise, byte-wise, and the character(s) used differ)
   i="${MAILX_ICONV_MODE}"
   if [ -n "${i}" ]; then
      printf 'p\nx\n' | ${MAILX} ${ARGS} -Rf "${MBOX}" >./.tout 2>./.terr
      j=${?}
      check_ex0 5-1-estat ${j}
      check 5-1 - ./.terr '4294967295 0'
      if [ ${i} -eq 13 ]; then
         check 5-2 - ./.tout '189327996 283' # XXX old (before test MTA)
      elif [ ${i} -eq 12 ]; then
         check 5-3 - ./.tout '1959197095 283' # XXX old (before test MTA)
      elif [ ${i} -eq 3 ]; then
         check 5-4 - ./.tout '3544755786 278'
      else
         check 5-5 - ./.tout '2381160335 278'
      fi
   else
      t_echoskip '5:[test unsupported]'
   fi

   t_epilog "${@}"
}

t_binary_mainbody() {
   t_prolog "${@}"

   printf 'abra\0\nka\r\ndabra' |
      ${MAILX} ${ARGS} ${ADDARG_UNI} -s 'binary with carriage-return!' \
      "${MBOX}" 2>./.terr
   check 1 0 "${MBOX}" '1629827 239'
   check 2 - ./.terr '4294967295 0'

   printf 'p\necho\necho writing now\nwrite ./.twrite\n' |
      ${MAILX} ${ARGS} -Rf \
         -Spipe-application/octet-stream="@* ${cat} > ./.tcat" \
         "${MBOX}" >./.tall 2>&1
   check 3 0 ./.tall '733582513 319'
   check 4 - ./.tcat '3817108933 15'
   check 5 - ./.twrite '3817108933 15'

   t_epilog "${@}"
}

t_mime_force_sendout() {
   t_prolog "${@}"

   if have_feat iconv; then :; else
      t_echoskip '[!ICONV]'
      t_epilog "${@}"
      return
   fi

   printf '\150\303\274' > ./.tmba
   printf 'ha' > ./.tsba
   printf '' > "${MBOX}"

   printf '\150\303\244' | ${MAILX} ${ARGS} -Smta=test://"$MBOX" \
      -s nogo \
      over-the@rain.bow 2>>${ERR}
   check 1 4 "${MBOX}" '4294967295 0'

   printf '\150\303\244' | ${MAILX} ${ARGS} -Smta=test://"$MBOX" \
      -s go -Smime-force-sendout \
      over-the@rain.bow 2>>${ERR}
   check 2 0 "${MBOX}" '1866273282 219'

   printf ha | ${MAILX} ${ARGS} -Smta=test://"$MBOX" \
      -s nogo \
      -a ./.tmba over-the@rain.bow 2>>${ERR}
   check 3 4 "${MBOX}" '1866273282 219'

   printf ha | ${MAILX} ${ARGS} -Smta=test://"$MBOX" \
      -s go -Smime-force-sendout \
      -a ./.tmba over-the@rain.bow 2>>${ERR}
   check 4 0 "${MBOX}" '644433809 880'

   printf ha | ${MAILX} ${ARGS} -Smta=test://"$MBOX" \
      -s nogo \
      -a ./.tsba -a ./.tmba over-the@rain.bow 2>>${ERR}
   check 5 4 "${MBOX}" '644433809 880'

   printf ha | ${MAILX} ${ARGS} -Smta=test://"$MBOX" \
      -s go -Smime-force-sendout \
      -a ./.tsba -a ./.tmba over-the@rain.bow 2>>${ERR}
   check 6 0 "${MBOX}" '3172365123 1729'

   printf '\150\303\244' | ${MAILX} ${ARGS} -Smta=test://"$MBOX" \
      -s nogo \
      -a ./.tsba -a ./.tmba over-the@rain.bow 2>>${ERR}
   check 7 4 "${MBOX}" '3172365123 1729'

   printf '\150\303\244' | ${MAILX} ${ARGS} -Smta=test://"$MBOX" \
      -s go -Smime-force-sendout \
      -a ./.tsba -a ./.tmba over-the@rain.bow 2>>${ERR}
   check 8 0 "${MBOX}" '4002905306 2565'

   t_epilog "${@}"
}

t_C_opt_customhdr() {
   t_prolog "${@}"

   echo bla |
   ${MAILX} ${ARGS} -Smta=test://"$MBOX" \
      -C 'C-One  :  Custom One Body' \
      -C 'C-Two:CustomTwoBody' \
      -C 'C-Three:      CustomThreeBody   ' \
      -S customhdr='chdr1:  chdr1 body, chdr2:chdr2 body, chdr3: chdr3 body ' \
      this-goes@nowhere >./.tall 2>&1
   check_ex0 1-estat
   ${cat} ./.tall >> "${MBOX}"
   check 1 0 "${MBOX}" '2535463301 238'

   ${rm} "${MBOX}"
   printf 'm this-goes@nowhere\nbody\n!.
      unset customhdr
      m this-goes2@nowhere\nbody2\n!.
      set customhdr=%ccustom1 :  custom1  body%c
      m this-goes3@nowhere\nbody3\n!.
      set customhdr=%ccustom1 :  custom1\\,  body  ,  \\
            custom2: custom2  body ,  custom-3 : custom3 body ,\\
            custom-4:custom4-body     %c
      m this-goes4@nowhere\nbody4\n!.
   ' "'" "'" "'" "'" |
   ${MAILX} ${ARGS} -Smta=test://"$MBOX" -Sescape=! \
      -C 'C-One  :  Custom One Body' \
      -C 'C-Two:CustomTwoBody' \
      -C 'C-Three:                   CustomThreeBody  ' \
      -C '   C-Four:CustomFourBody  ' \
      -C 'C-Five:CustomFiveBody' \
      -S customhdr='ch1:  b1 , ch2:b2, ch3:b3 ,ch4:b4,  ch5: b5 ' \
      >./.tall 2>&1
   check_ex0 2-estat
   ${cat} ./.tall >> "${MBOX}"
   check 2 0 "${MBOX}" '544085062 1086'

   t_epilog "${@}"
}
# }}}

# Operational basics with trivial tests {{{
t_alias() {
   t_prolog "${@}"

   ${cat} <<- '__EOT' | ${MAILX} ${ARGS} -Smta=test://"$MBOX" > ./.tall 2>&1
   alias a1 ex1@a1.ple
   alias a1 ex2@a1.ple "EX3 <ex3@a1.ple>"
   alias a1 ex4@a1.ple
   alias a2 ex1@a2.ple ex2@a2.ple ex3@a2.ple ex4@a2.ple
   alias a3 a4
   alias a4 a5 ex1@a4.ple
   alias a5 a6
   alias a6 a7 ex1@a6.ple
   alias a7 a8
   alias a8 ex1@a8.ple
   alias a1
   alias a2
   alias a3
   m a1
	~c a2
	~b a3
	~r - '_EOT'
   This body is!
   This also body is!!
_EOT
	__EOT
   check 1 0 "${MBOX}" '139467786 277'
   check 2 - .tall '1598893942 133'

   if have_feat uistrings; then
      ${cat} <<- '__EOT' | ${MAILX} ${ARGS} > "${MBOX}" 2>&1
		commandalias x echo '$?/$^ERRNAME'
		echo 1
		alias a:bra!  ha@m beb@ra ha@m '' zeb@ra ha@m; x
		alias a:bra!; x
		alias ha@m  ham-expansion  ha@m '';x
		alias ha@m;x
		alias beb@ra  ceb@ra beb@ra1;x
		alias beb@ra;x
		alias ceb@ra  ceb@ra1;x
		alias ceb@ra;x
		alias deb@ris   '';x
		alias deb@ris;x
		echo 2
		alias - a:bra!;x
		alias - ha@m;x
		alias - beb@ra;x
		alias - ceb@ra;x
		alias - deb@ris;x
		echo 3
		unalias ha@m;x
		alias - a:bra!;x
		unalias beb@ra;x
		alias - a:bra!;x
		echo 4
		unalias*;x;alias;x
		echo 5
		\alias noexpa@and this@error1;x
		\alias ha@m '\noexp@and' expa@and \\noexp@and2;x
		\alias ha@m;x
		\alias - ha@m;x
		\alias noexpa@and2 this@error2;x
		\alias expa1@and this@error3;x
		\alias expa@and \\expa1@and;x
		\alias expa@and;x
		\alias - ha@m;x
		\alias - expa@and;x
		__EOT
      check 3 0 "${MBOX}" '1788149870 789'
   else
      t_echoskip '3:[!UISTRINGS]'
   fi

   # TODO t_alias: n_ALIAS_MAXEXP is compile-time constant,
   # TODO need to somehow provide its contents to the test, then test

   t_epilog "${@}"
}

t_charsetalias() {
   t_prolog "${@}"

   ${cat} <<- '__EOT' | ${MAILX} ${ARGS} > "${MBOX}" 2>&1
   commandalias x echo '$?/$^ERRNAME'
	echo 1
	charsetalias latin1 latin15;x
	charsetalias latin1;x
	charsetalias - latin1;x
	echo 2
	charsetalias cp1252 latin1  latin15 utf8  utf8 utf16;x
	charsetalias cp1252;x
	charsetalias latin15;x
	charsetalias utf8;x
	echo 3
	charsetalias - cp1252;x
	charsetalias - latin15;x
	charsetalias - utf8;x
	echo 4
	charsetalias latin1;x
	charsetalias - latin1;x
	uncharsetalias latin15;x
	charsetalias latin1;x
	charsetalias - latin1;x
	__EOT
   check 1 0 "${MBOX}" '3551595280 433'

   t_epilog "${@}"
}

t_shortcut() {
   t_prolog "${@}"

   ${cat} <<- '__EOT' | ${MAILX} ${ARGS} > "${MBOX}" 2>&1
   commandalias x echo '$?/$^ERRNAME'
	echo 1
	shortcut file1 expansion-of-file1;x
	shortcut file2 expansion-of-file2;x
	shortcut file3 expansion-of-file3;x
	shortcut   file4   'expansion of file4'  'file 5' 'expansion of file5';x
	echo 2
	shortcut file1;x
	shortcut file2;x
	shortcut file3;x
	shortcut file4;x
	shortcut 'file 5';x
	echo 3
	shortcut;x
	__EOT
   check 1 0 "${MBOX}" '1970515669 430'

   t_epilog "${@}"
}
# }}}

# Operational basics with easy tests {{{
t_expandaddr() {
   # after: t_alias
   # MTA alias specific part in t_mta_aliases()
   # This only tests from command line, rest later on (iff any)
   t_prolog "${@}"

   if have_feat uistrings; then :; else
      t_echoskip '[!UISTRINGS]'
      t_epilog "${@}"
      return
   fi

   echo "${cat}" > ./.tcat
   chmod 0755 ./.tcat

   #
   </dev/null ${MAILX} ${ARGS} -Snoexpandaddr -Smta=test://"$MBOX" -ssub \
      -X'alias talias talias@exam.ple' \
      './.tfile' '  |  ./.tcat > ./.tpipe' 'talias' 'taddr@exam.ple' \
      > ./.tall 2>&1
   check 1 4 "${MBOX}" '1216011460 138'
   check 2 - .tall '4169590008 162'

   #
   </dev/null ${MAILX} ${ARGS} -Snoexpandaddr -Smta=test://"$MBOX" -ssub \
      -Sexpandaddr \
      -X'alias talias talias@exam.ple' \
      './.tfile' '  |  ./.tcat >./.tpipe' 'talias' 'taddr@exam.ple' \
      > ./.tall 2>&1
   check 3 0 "${MBOX}" '847567042 276'
   check 4 - .tall '4294967295 0'
   check 5 - .tfile '1216011460 138'
   check 6 - .tpipe '1216011460 138'

   #
   </dev/null ${MAILX} ${ARGS} -Snoexpandaddr -Smta=test://"$MBOX" -ssub \
      -Sexpandaddr=-all,+file,+pipe,+name,+addr \
      -X'alias talias talias@exam.ple' \
      './.tfile' '  |  ./.tcat >./.tpipe' 'talias' 'taddr@exam.ple' \
      > ./.tall 2>&1
   check 7 0 "${MBOX}" '3682360102 414'
   check 8 - .tall '4294967295 0'
   check 9 - .tfile '847567042 276'
   check 10 - .tpipe '1216011460 138'

   #
   </dev/null ${MAILX} ${ARGS} -Snoexpandaddr -Smta=test://"$MBOX" -ssub \
      -Sexpandaddr=-all,+file,-file,+pipe,+name,+addr \
      -X'alias talias talias@exam.ple' \
      './.tfile' '  |  ./.tcat >./.tpipe' 'talias' 'taddr@exam.ple' \
      > ./.tall 2>&1
   check 11 4 "${MBOX}" '1010907786 552'
   check 12 - .tall '673208446 70'
   check 13 - .tfile '847567042 276'
   check 14 - .tpipe '1216011460 138'

   printf '' > ./.tpipe
   </dev/null ${MAILX} ${ARGS} -Snoexpandaddr -Smta=test://"$MBOX" -ssub \
      -Sexpandaddr=fail,-all,+file,-file,+pipe,+name,+addr \
      -X'alias talias talias@exam.ple' \
      './.tfile' '  |  ./.tcat >./.tpipe' 'talias' 'taddr@exam.ple' \
      > ./.tall 2>&1
   check 15 4 "${MBOX}" '1010907786 552'
   check 16 - .tall '3280630252 179'
   check 17 - .tfile '847567042 276'
   check 18 - .tpipe '4294967295 0'

   #
   </dev/null ${MAILX} ${ARGS} -Snoexpandaddr -Smta=test://"$MBOX" -ssub \
      -Sexpandaddr=-all,+file,+pipe,-pipe,+name,+addr \
      -X'alias talias talias@exam.ple' \
      './.tfile' '  |  ./.tcat >./.tpipe' 'talias' 'taddr@exam.ple' \
      > ./.tall 2>&1
   check 19 4 "${MBOX}" '3359494254 690'
   check 20 - .tall '4052857227 91'
   check 21 - .tfile '3682360102 414'
   check 22 - .tpipe '4294967295 0'

   </dev/null ${MAILX} ${ARGS} -Snoexpandaddr -Smta=test://"$MBOX" -ssub \
      -Sexpandaddr=fail,-all,+file,+pipe,-pipe,+name,+addr \
      -X'alias talias talias@exam.ple' \
      './.tfile' '  |  ./.tcat >./.tpipe' 'talias' 'taddr@exam.ple' \
      > ./.tall 2>&1
   check 23 4 "${MBOX}" '3359494254 690'
   check 24 - .tall '2168069102 200'
   check 25 - .tfile '3682360102 414'
   check 26 - .tpipe '4294967295 0'

   #
   </dev/null ${MAILX} ${ARGS} -Snoexpandaddr -Smta=test://"$MBOX" -ssub \
      -Sexpandaddr=-all,+file,+pipe,+name,-name,+addr \
      -X'alias talias talias@exam.ple' \
      './.tfile' '  |  ./.tcat >./.tpipe' 'talias' 'taddr@exam.ple' \
      > ./.tall 2>&1
   check 27 0 "${MBOX}" '3735108703 828'
   check 28 - .tall '4294967295 0'
   check 29 - .tfile '1010907786 552'
   check 30 - .tpipe '1216011460 138'

   </dev/null ${MAILX} ${ARGS} -Snoexpandaddr -Smta=test://"$MBOX" -ssub \
      -Sexpandaddr=-all,+file,+pipe,+name,-name,+addr \
      './.tfile' '  |  ./.tcat >./.tpipe' 'talias' 'taddr@exam.ple' \
      > ./.tall 2>&1
   check 31 4 "${MBOX}" '4225234603 949'
   check 32 - .tall '3486613973 73'
   check 33 - .tfile '452731060 673'
   check 34 - .tpipe '1905076731 121'

   printf '' > ./.tpipe
   </dev/null ${MAILX} ${ARGS} -Snoexpandaddr -Smta=test://"$MBOX" -ssub \
      -Sexpandaddr=fail,-all,+file,+pipe,+name,-name,+addr \
      './.tfile' '  |  ./.tcat >./.tpipe' 'talias' 'taddr@exam.ple' \
      > ./.tall 2>&1
   check 35 4 "${MBOX}" '4225234603 949'
   check 36 - .tall '3032065285 182'
   check 37 - .tfile '452731060 673'
   check 38 - .tpipe '4294967295 0'

   #
   </dev/null ${MAILX} ${ARGS} -Snoexpandaddr -Smta=test://"$MBOX" -ssub \
      -Sexpandaddr=-all,+file,+pipe,+name,+addr,-addr \
      -X'alias talias talias@exam.ple' \
      './.tfile' '  |  ./.tcat >./.tpipe' 'talias' 'taddr@exam.ple' \
      > ./.tall 2>&1
   check 39 4 "${MBOX}" '4225234603 949'
   check 40 - .tall '3863610168 169'
   check 41 - .tfile '1975297706 775'
   check 42 - .tpipe '130065764 102'

   </dev/null ${MAILX} ${ARGS} -Snoexpandaddr -Smta=test://"$MBOX" -ssub \
      -Sexpandaddr=-all,+file,+pipe,+name,+addr,-addr \
      -Sadd-file-recipients \
      -X'alias talias talias@exam.ple' \
      './.tfile' '  |  ./.tcat >./.tpipe' 'talias' 'taddr@exam.ple' \
      > ./.tall 2>&1
   check 43 4 "${MBOX}" '4225234603 949'
   check 44 - .tall '3863610168 169'
   check 45 - .tfile '3291831864 911'
   check 46 - .tpipe '4072000848 136'

   printf '' > ./.tpipe
   </dev/null ${MAILX} ${ARGS} -Snoexpandaddr -Smta=test://"$MBOX" -ssub \
      -Sexpandaddr=fail,-all,+file,+pipe,+name,+addr,-addr \
      -Sadd-file-recipients \
      -X'alias talias talias@exam.ple' \
      './.tfile' '  |  ./.tcat >./.tpipe' 'talias' 'taddr@exam.ple' \
      > ./.tall 2>&1
   check 47 4 "${MBOX}" '4225234603 949'
   check 48 - .tall '851041772 278'
   check 49 - .tfile '3291831864 911'
   check 50 - .tpipe '4294967295 0'

   #
   </dev/null ${MAILX} ${ARGS} -Snoexpandaddr -Smta=test://"$MBOX" -ssub \
      -Sexpandaddr=-all,+addr \
      'taddr@exam.ple' 'this@@c.example' \
      > ./.tall 2>&1
   check 51 4 "${MBOX}" '473729143 1070'
   check 52 - .tall '2646392129 66'

   </dev/null ${MAILX} ${ARGS} -Snoexpandaddr -Smta=test://"$MBOX" -ssub \
      -Sexpandaddr=-all,failinvaddr \
      'taddr@exam.ple' 'this@@c.example' \
      > ./.tall 2>&1
   check 53 4 "${MBOX}" '473729143 1070'
   check 54 - .tall '887391555 175'

   #
   </dev/null ${MAILX} ${ARGS} -Snoexpandaddr -Smta=test://"$MBOX" -ssub \
      -Sthis=taddr@exam.ple -Sexpandaddr \
      -c '\$this' -b '\$this' '\$this' \
      > ./.tall 2>&1
   check 55 4 "${MBOX}" '473729143 1070'
   check 56 - .tall '1144578880 139'

   </dev/null ${MAILX} ${ARGS} -Snoexpandaddr -Smta=test://"$MBOX" -ssub \
      -Sthis=taddr@exam.ple -Sexpandaddr=shquote \
      -c '\$this' -b '\$this' '\$this' \
      > ./.tall 2>&1
   check 57 0 "${MBOX}" '398243793 1191'
   check 58 - .tall '4294967295 0'

   #
   printf '' > "${MBOX}"
   ${cat} <<-_EOT |\
      ${MAILX} ${ARGS} -Snoexpandaddr -Smta=test://"$MBOX" -t -ssub \
         -Sadd-file-recipients \
         -Sexpandaddr=-all,+fcc \
         > ./.tall 2>&1
	Fcc: .tfile1
	Fcc: .tfile2
	_EOT
   check 59 0 "${MBOX}" '4294967295 0'
   check 60 - .tall '4294967295 0'
   check 61 - .tfile1 '1067276522 124'
   check 62 - .tfile2 '1067276522 124'

   printf '' > "${MBOX}"
   ${cat} <<-_EOT |\
      ${MAILX} ${ARGS} -Snoexpandaddr -Smta=test://"$MBOX" -t -ssub \
         -Sadd-file-recipients \
         -Sexpandaddr=-all,+file \
         > ./.tall 2>&1
	Fcc: .tfile1
	Fcc: .tfile2
	_EOT
   check 63 0 "${MBOX}" '4294967295 0'
   check 64 - .tall '4294967295 0'
   check 65 - .tfile1 '2677253527 248'
   check 66 - .tfile2 '2677253527 248'

   printf '' > "${MBOX}"
   ${cat} <<-_EOT |\
      ${MAILX} ${ARGS} -Snoexpandaddr -Smta=test://"$MBOX" -t -ssub \
         -Sadd-file-recipients \
         -Sexpandaddr=-all,+file,-fcc \
         > ./.tall 2>&1
	Fcc: .tfile1
	Fcc: .tfile2
	_EOT
   check 67 0 "${MBOX}" '4294967295 0'
   check 68 - .tall '4294967295 0'
   check 69 - .tfile1 '3493511004 372'
   check 70 - .tfile2 '3493511004 372'

   printf '' > "${MBOX}"
   ${cat} <<-_EOT |\
      ${MAILX} ${ARGS} -Snoexpandaddr -Smta=test://"$MBOX" -t -ssub \
         -Sadd-file-recipients \
         -Sexpandaddr=-all,+fcc,-file \
         > ./.tall 2>&1
	Fcc: .tfile1
	Fcc: .tfile2
	_EOT
   check 71 4 "${MBOX}" '4294967295 0'
   check 72 - .tall '203687556 223'
   check 73 - .tfile1 '3493511004 372'
   check 74 - .tfile2 '3493511004 372'

   printf '' > "${MBOX}"
   ${cat} <<-_EOT |\
      ${MAILX} ${ARGS} -Snoexpandaddr -Smta=test://"$MBOX" -t -ssub \
         -Sadd-file-recipients \
         -Sexpandaddr=-all,fail,+addr \
         > ./.tall 2>&1
	Fcc: .tfile1
	Fcc: .tfile2
	To: never@exam.ple
	_EOT
   check 75 4 "${MBOX}" '4294967295 0'
   check 76 - .tall '4060426468 247'
   check 77 - .tfile1 '3493511004 372'
   check 78 - .tfile2 '3493511004 372'

   #
   printf '' > "${MBOX}"
   ${cat} <<-_EOT |\
      ${MAILX} ${ARGS} -Snoexpandaddr -Smta=test://"$MBOX" -t -ssub \
         -Sexpandaddr=fail,domaincheck \
         > ./.tall 2>&1
	To: one@localhost
	_EOT
   check 79 0 "${MBOX}" '171635532 120'
   check 80 - .tall '4294967295 0'

   ${cat} <<-_EOT |\
      ${MAILX} ${ARGS} -Snoexpandaddr -Smta=test://"$MBOX" -t -ssub \
         -Sexpandaddr=domaincheck \
         > ./.tall 2>&1
	To: one@localhost  ,    Hey two <two@exam.ple>, Trouble <three@tro.uble>
	_EOT
   check 81 4 "${MBOX}" '2659464839 240'
   check 82 - .tall '1119895397 158'

   ${cat} <<-_EOT |\
      ${MAILX} ${ARGS} -Snoexpandaddr -Smta=test://"$MBOX" -t -ssub \
         -Sexpandaddr=fail,domaincheck \
         > ./.tall 2>&1
	To: one@localhost  ,    Hey two <two@exam.ple>, Trouble <three@tro.uble>
	_EOT
   check 83 4 "${MBOX}" '2659464839 240'
   check 84 - .tall '1577313789 267'

   ${cat} <<-_EOT |\
      ${MAILX} ${ARGS} -Snoexpandaddr -Smta=test://"$MBOX" -t -ssub \
         -Sexpandaddr=fail,domaincheck \
         -Sexpandaddr-domaincheck=exam.ple,tro.uble \
         > ./.tall 2>&1
	To: one@localhost  ,    Hey two <two@exam.ple>, Trouble <three@tro.uble>
	_EOT
   check 85 0 "${MBOX}" '1670655701 410'
   check 86 - .tall '4294967295 0'

   t_epilog "${@}"
}

t_mta_aliases() {
   # after: t_expandaddr
   t_prolog "${@}"

   if have_feat mta-aliases; then :; else
      t_echoskip '[!MTA_ALIASES]'
      t_epilog "${@}"
      return
   fi

   ${cat} > ./.tali <<- '__EOT'
	
	   # Comment
	
	
	a1: ex1@a1.ple  , 
	  ex2@a1.ple, <ex3@a1.ple> ,
	  ex4@a1.ple    
	a2:     ex1@a2.ple  ,   ex2@a2.ple,a2_2
	a2_2:ex3@a2.ple,ex4@a2.ple
	a3: a4
	a4: a5,
	# Comment
	      # More comment
	   ex1@a4.ple
	# Comment
	a5: a6
	a6: a7  , ex1@a6.ple
	a7: a8,a9
	a8: ex1@a8.ple
	__EOT

   echo | ${MAILX} ${ARGS} -Smta=test://"$MBOX" \
      -Smta-aliases=./.tali \
      -b a3 -c a2 a1 > ./.tall 2>&1
   check 1 0 "${MBOX}" '1172368381 238'
   check 2 - .tall '4294967295 0'

   ## xxx The following are actually *expandaddr* tests!!

   # May not send plain names over SMTP!
   mtaali=
   if have_feat smtp; then
      echo | ${MAILX} ${ARGS} \
         -Smta=smtp://laber.backe -Ssmtp-auth=none \
         -Smta-aliases=./.tali \
         -b a3 -c a2 a1 > ./.tall 2>&1
      check_exn0 3
      check 4 - "${MBOX}" '1172368381 238'
      mtaali=1
   fi
   if [ -n "${mtaali}" ] && have_feat uistrings; then
      check 5 - .tall '771616226 179'
   else
      t_echoskip '5:[!SMTP/!UISTRINGS]'
   fi

   # xxx for false-positive SMTP test we would need some mocking
   echo | ${MAILX} ${ARGS} -Smta=test://"$MBOX" \
      -Sexpandaddr=fail,-name \
      -Smta-aliases=./.tali \
      -b a3 -c a2 a1 > ./.tall 2>&1
   check_exn0 6
   check 7 - "${MBOX}" '1172368381 238'
   if have_feat uistrings; then
      check 8 - .tall '2834389894 178'
   else
      t_echoskip '8:[!UISTRINGS]'
   fi

   echo | ${MAILX} ${ARGS} -Smta=test://"$MBOX" \
      -Sexpandaddr=-name \
      -Smta-aliases=./.tali \
      -b a3 -c a2 a1 > ./.tall 2>&1
   check 9 4 "${MBOX}" '2322273994 472'
   if have_feat uistrings; then
      check 10 - .tall '2136559508 69'
   else
      t_echoskip '10:[!UISTRINGS]'
   fi

   echo 'a9:nine@nine.nine' >> ./.tali

   echo | ${MAILX} ${ARGS} -Smta=test://"$MBOX" \
      -Sexpandaddr=fail,-name \
      -Smta-aliases=./.tali \
      -b a3 -c a2 a1 > ./.tall 2>&1
   check 11 0 "${MBOX}" '2422268299 722'
   check 12 - .tall '4294967295 0'

   printf '#
   set expandaddr=-name
   mail a1
!c a2
!:echo $?/$^ERRNAME
!^header insert bcc a3
!:echo $?/$^ERRNAME
!:set expandaddr
!t a1
!c a2
!:echo $?/$^ERRNAME
!^header insert bcc a3
!:echo $?/$^ERRNAME
!.
   echo and, once again, check that cache is updated
   # Enclose one pipe in quotes: immense stress for our stupid address parser:(
   !echo "a10:./.tf1,|%s>./.tp1,\\"|%s > ./.tp2\\",./.tf2" >> ./.tali
   mail a1
!c a2
!:echo $?/$^ERRNAME
!^header insert bcc a3
!:echo $?/$^ERRNAME
!.
   echo trigger happiness
   mail a1
!c a2
!:echo $?/$^ERRNAME
!^header insert bcc a3 a10
!:echo $?/$^ERRNAME
!.
   ' "${cat}" "${cat}" | ${MAILX} ${ARGS} -Smta=test://"$MBOX" -Sescape=! \
      -Smta-aliases=./.tali \
      > ./.tall 2>&1
   check 13 0 "${MBOX}" '550955032 1469'
   if have_feat uistrings; then
      check 14 - .tall '1795496020 473'
   else
      t_echoskip '14:[!UISTRINGS]'
   fi
   check 15 - .tf1 '3056269950 249'
   check 16 - .tp1 '3056269950 249'
   check 17 - .tp2 '3056269950 249'
   check 18 - .tf2 '3056269950 249'

   # TODO t_mta_aliases: n_ALIAS_MAXEXP is compile-time constant,
   # TODO need to somehow provide its contents to the test, then test

   t_epilog "${@}"
}

t_filetype() {
   t_prolog "${@}"

   printf 'm m1@e.t\nL1\nHy1\n~.\nm m2@e.t\nL2\nHy2\n~@ %s\n~.\n' \
      "${TOPDIR}snailmail.jpg" | ${MAILX} ${ARGS} -Smta=test://"$MBOX"
   check 1 0 "${MBOX}" '1314354444 13536'

   if (echo | gzip -c) >/dev/null 2>&1; then
      {
         printf 'File "%s"\ncopy 1 ./.t.mbox.gz\ncopy 2 ./.t.mbox.gz' \
            "${MBOX}" | ${MAILX} ${ARGS} \
               -X'filetype gz gzip\ -dc gzip\ -c'
         printf 'File ./.t.mbox.gz\ncopy * ./.t.mbox\n' |
            ${MAILX} ${ARGS} -X'filetype gz gzip\ -dc gzip\ -c'
      } > ./.t.out 2>&1
      check 2 - ./.t.mbox '1314354444 13536'
      check 3 - ./.t.out '635961640 103'
   else
      t_echoskip '2:[missing gzip(1)]'
      t_echoskip '3:[missing gzip(1)]'
   fi

   {
      ${rm} ./.t.mbox*
      printf 'File "%s"\ncopy 1 ./.t.mbox.gz
            copy 2 ./.t.mbox.gz
            copy 1 ./.t.mbox.gz
            copy 2 ./.t.mbox.gz
            ' "${MBOX}" |
         ${MAILX} ${ARGS} \
            -X'filetype gz gzip\ -dc gzip\ -c' \
            -X'filetype mbox.gz "${sed} 1,3d|${cat}" \
            "echo eins;echo zwei;echo und mit ${sed} bist Du dabei;${cat}"'
      printf 'File ./.t.mbox.gz\ncopy * ./.t.mbox\n' |
         ${MAILX} ${ARGS} \
            -X'filetype gz gzip\ -dc gzip\ -c' \
            -X'filetype mbox.gz "${sed} 1,3d|${cat}" kill\ 0'
   } > ./.t.out 2>&1
   check 4 - ./.t.mbox '2687765142 27092'
   check 5 - ./.t.out '2230192693 173'

   t_epilog "${@}"
}

t_e_H_L_opts() {
   t_prolog "${@}"

   touch ./.t.mbox
   ${MAILX} ${ARGS} -ef ./.t.mbox
   echo ${?} > "${MBOX}"

   printf 'm me@exam.ple\nLine 1.\nHello.\n~.\n' |
   ${MAILX} ${ARGS} -Smta=test://./.t.mbox
   printf 'm you@exam.ple\nLine 1.\nBye.\n~.\n' |
   ${MAILX} ${ARGS} -Smta=test://./.t.mbox

   ${MAILX} ${ARGS} -ef ./.t.mbox 2>> "${MBOX}"
   echo ${?} >> "${MBOX}"
   ${MAILX} ${ARGS} -efL @t@me ./.t.mbox 2>> "${MBOX}"
   echo ${?} >> "${MBOX}"
   ${MAILX} ${ARGS} -efL @t@you ./.t.mbox 2>> "${MBOX}"
   echo ${?} >> "${MBOX}"
   ${MAILX} ${ARGS} -efL '@>@Line 1' ./.t.mbox 2>> "${MBOX}"
   echo ${?} >> "${MBOX}"
   ${MAILX} ${ARGS} -efL '@>@Hello.' ./.t.mbox 2>> "${MBOX}"
   echo ${?} >> "${MBOX}"
   ${MAILX} ${ARGS} -efL '@>@Bye.' ./.t.mbox 2>> "${MBOX}"
   echo ${?} >> "${MBOX}"
   ${MAILX} ${ARGS} -efL '@>@Good bye.' ./.t.mbox 2>> "${MBOX}"
   echo ${?} >> "${MBOX}"

   ${MAILX} ${ARGS} -fH ./.t.mbox >> "${MBOX}" 2>&1
   echo ${?} >> "${MBOX}"
   ${MAILX} ${ARGS} -fL @t@me ./.t.mbox >> "${MBOX}" 2>&1
   echo ${?} >> "${MBOX}"
   ${MAILX} ${ARGS} -fL @t@you ./.t.mbox >> "${MBOX}" 2>&1
   echo ${?} >> "${MBOX}"
   ${MAILX} ${ARGS} -fL '@>@Line 1' ./.t.mbox >> "${MBOX}" 2>&1
   echo ${?} >> "${MBOX}"
   ${MAILX} ${ARGS} -fL '@>@Hello.' ./.t.mbox >> "${MBOX}" 2>&1
   echo ${?} >> "${MBOX}"
   ${MAILX} ${ARGS} -fL '@>@Bye.' ./.t.mbox >> "${MBOX}" 2>&1
   echo ${?} >> "${MBOX}"
   ${MAILX} ${ARGS} -fL '@>@Good bye.' ./.t.mbox >> "${MBOX}" 2>>${ERR}
   echo ${?} >> "${MBOX}"

   check 1 - "${MBOX}" '1369201287 670'

   ##

   printf 'm me1@exam.ple\n~s subject cab\nLine 1.\n~.\n' |
   ${MAILX} ${ARGS} -Smta=test://./.t.mbox \
      -r '' -X 'wysh set from=pony1@$LOGNAME'
   printf 'm me2@exam.ple\n~s subject bac\nLine 12.\n~.\n' |
   ${MAILX} ${ARGS} -Smta=test://./.t.mbox \
      -r '' -X 'wysh set from=pony2@$LOGNAME'
   printf 'm me3@exam.ple\n~s subject abc\nLine 123.\n~.\n' |
   ${MAILX} ${ARGS} -Smta=test://./.t.mbox \
      -r '' -X 'wysh set from=pony3@$LOGNAME'

   ${MAILX} ${ARGS} -S folder-hook=fh-test -X 'define fh-test {
         echo fh-test size; set autosort=size showname showto
      }' -fH ./.t.mbox > "${MBOX}" 2>&1
   check 2 0 "${MBOX}" '4286438644 413'

   ${MAILX} ${ARGS} -S folder-hook=fh-test -X 'define fh-test {
         echo fh-test subject; set autosort=subject showname showto
      }' -fH ./.t.mbox > "${MBOX}" 2>&1
   check 3 0 "${MBOX}" '3208053922 416'

   ${MAILX} ${ARGS} -S folder-hook=fh-test -X 'define fh-test {
         echo fh-test from; set autosort=from showto
      }' -fH ./.t.mbox > "${MBOX}" 2>&1
   check 4 0 "${MBOX}" '4209767839 413'

   ${MAILX} ${ARGS} -S folder-hook=fh-test -X 'define fh-test {
         echo fh-test to; set autosort=to showto
      }' -fH ./.t.mbox > "${MBOX}" 2>&1
   check 5 0 "${MBOX}" '2785342736 411'

   t_epilog "${@}"
}

t_q_t_etc_opts() {
   # Simple, if we need more here, place in a later vim fold!
   t_prolog "${@}"

   # Three tests for MIME encoding and (a bit) content classification.
   # At the same time testing -q FILE, < FILE and -t FILE
   t__put_body > ./.tin

   < ./.tin ${MAILX} ${ARGS} ${ADDARG_UNI} \
      -a ./.tin -s "`t__put_subject`" "${MBOX}"
   check 1 0 "${MBOX}" '1088822685 6642'

   ${rm} "${MBOX}"
   < /dev/null ${MAILX} ${ARGS} ${ADDARG_UNI} \
      -a ./.tin -s "`t__put_subject`" -q ./.tin "${MBOX}"
   check 2 0 "${MBOX}" '1088822685 6642'

   ${rm} "${MBOX}"
   (  echo "To: ${MBOX}" && echo "Subject: `t__put_subject`" && echo &&
      ${cat} ./.tin
   ) | ${MAILX} ${ARGS} ${ADDARG_UNI} -Snodot -a ./.tin -t
   check 3 0 "${MBOX}" '1088822685 6642'

   # Check comments in the header
   ${rm} "${MBOX}"
   ${cat} <<-_EOT | ${MAILX} ${ARGS} -Snodot -t "${MBOX}"
		# Ein Kommentar
		From: du@da
		# Noch ein Kommentar
		Subject    :       hey you
		# Nachgestelltes Kommentar
		
		BOOOM
		_EOT
   check 4 0 "${MBOX}" '4161555890 124'

   # ?MODifier suffix
   printf '' > "${MBOX}"
   (  echo 'To?single    : ./.tout1 .tout2  ' &&
      echo 'CC: ./.tcc1 ./.tcc2' &&
      echo 'BcC?sin  : ./.tbcc1 .tbcc2 ' &&
      echo 'To?    : ./.tout3 .tout4  ' &&
      echo &&
      echo body
   ) | ${MAILX} ${ARGS} ${ADDARG_UNI} -Snodot -t -Smta=test://"$MBOX"
   check 5 0 './.tout1 .tout2' '2948857341 94'
   check 6 - ./.tcc1 '2948857341 94'
   check 7 - ./.tcc2 '2948857341 94'
   check 8 - './.tbcc1 .tbcc2' '2948857341 94'
   check 9 - './.tout3 .tout4' '2948857341 94'
   check 10 - "${MBOX}" '4294967295 0'

   t_epilog "${@}"
}

t_message_injections() {
   # Simple, if we need more here, place in a later vim fold!
   t_prolog "${@}"

   echo mysig > ./.tmysig

   echo some-body | ${MAILX} ${ARGS} -Smta=test://"$MBOX" \
      -Smessage-inject-head=head-inject \
      -Smessage-inject-tail="`${cat} ./.tmysig`"'\ntail-inject' \
      ex@am.ple > ./.tall 2>&1
   check 1 0 "${MBOX}" '701778583 143'
   check 2 - .tall '4294967295 0' # empty file

   ${rm} "${MBOX}"
   ${cat} <<-_EOT > ./.template
	From: me
	To: ex1@am.ple
	Cc: ex2@am.ple
	Subject: This subject is

   Body, body, body me.
	_EOT
   < ./.template ${MAILX} ${ARGS} -t -Smta=test://"$MBOX" \
      -Smessage-inject-head=head-inject \
      -Smessage-inject-tail="`${cat} ./.tmysig`\n"'tail-inject' \
      > ./.tall 2>&1
   check 3 0 "${MBOX}" '2189109479 207'
   check 4 - .tall '4294967295 0' # empty file

   t_epilog "${@}"
}

t_attachments() {
   # TODO More should be in compose mode stuff aka digmsg
   t_prolog "${@}"

   ${cat} <<-_EOT  > ./.tx
	From steffen Sun Feb 18 02:48:40 2018
	Date: Sun, 18 Feb 2018 02:48:40 +0100
	To:
	Subject: m1
	User-Agent: s-nail v14.9.7
	
	
	From steffen Sun Feb 18 02:48:42 2018
	Date: Sun, 18 Feb 2018 02:48:42 +0100
	To:
	Subject: m2
	User-Agent: s-nail v14.9.7
	
	
	_EOT
   echo att1 > ./.t1
   printf 'att2-1\natt2-2\natt2-4\n' > ./'.t 2'
   printf 'att3-1\natt3-2\natt3-4\n' > ./.t3
   printf 'att4-1\natt4-2\natt4-4\n' > './.t 4'

   printf \
'!@  ./.t3              "./.t 4"             ""
!p
!@
   ./.t3
 "./.t 2"

!p
!.' \
   | ${MAILX} ${ARGS} -Sescape=! -Smta=test://"$MBOX" \
      -a ./.t1 -a './.t 2' \
      -s attachment-test \
      ex@am.ple > ./.tall 2>&1
   check 1 0 "${MBOX}" '2484200149 644'
   if have_feat uistrings; then
      check 2 - .tall '1928331872 720'
   else
      t_echoskip '2:[!UISTRINGS]'
   fi

   ${rm} "${MBOX}"
   printf \
'mail ex@amp.ple
!s This the subject is
!@  ./.t3        "#2"      "./.t 4"          "#1"   ""
!p
!@
   "./.t 4"
 "#2"

!p
!.
      mail ex@amp.ple
!s Subject two
!@  ./.t3        "#2"      "./.t 4"          "#1"   ""
!p
!@

!p
!.
      mail ex@amp.ple
!s Subject three
!@  ./.t3     ""   "#2"    ""  "./.t 4"   ""       "#1"   ""
!p
!@
 ./.t3

!p
!.
      mail ex@amp.ple
!s Subject Four
!@  ./.t3     ""   "#2"    ""  "./.t 4"   ""       "#1"   ""
!p
!@
 "#1"

!p
!.
      mail ex@amp.ple
!s Subject Five
!@
 "#2"

!p
!.' \
   | ${MAILX} ${ARGS} -Sescape=! -Smta=test://"$MBOX" -Rf ./.tx \
         > ./.tall 2>&1
   check 3 0 "${MBOX}" '3637385058 2335'
   if have_feat uistrings; then
      check 4 - .tall '2526106274 1910'
   else
      t_echoskip '4:[!UISTRINGS]'
   fi

   ${rm} "${MBOX}"
   printf \
'mail ex@amp.ple
!s Subject One
!@ "#."
Body one.
!p
!.
from 2
mail ex@amp.ple
!s Subject Two
!@
      "#."

Body two.
!p
!.
reply 1 2
!@ "#."
!p
!.
!@
"#."

!p
!.' \
   | ${MAILX} ${ARGS} -Sescape=! -Smta=test://"$MBOX" -Rf ./.tx \
         > ./.tall 2>&1
   check 5 0 "${MBOX}" '1604688179 2316'
   if have_feat uistrings; then
      check 6 - .tall '1210753005 508'
   else
      t_echoskip '6:[!UISTRINGS]'
   fi

   ##

   # Content-ID:
   </dev/null ${MAILX} ${ARGS} -Smta=test \
      -Sstealthmua=noagent -Shostname \
      -a ./.t1 -a './.t 2' \
      -a ./.t3 -a './.t 4' \
      -s Y \
      ex@am.ple > ./.tall 2>&1
   check 7 0 .tall '1003537919 1262'

   # input charset
   </dev/null ${MAILX} ${ARGS} -Smta=test -Sttycharset=utf8 \
      -a ./.t1=ascii -a './.t 2'=LATin1 \
      -a ./.t3=UTF-8 -a './.t 4'=- \
      -s Y \
      ex@am.ple > ./.tall 2>&1
   check 8 0 .tall '361641281 921'

   # input+output charset, no iconv
   </dev/null ${MAILX} ${ARGS} -Smta=test \
      -a ./.t1=ascii#- -a './.t 2'=LATin1#- \
      -a ./.t3=UTF-8#- -a './.t 4'=utf8#- \
      -s Y \
      ex@am.ple > ./.tall 2>&1
   check 9 0 .tall '1357456844 933'

   if have_feat iconv; then
      printf 'ein \303\244ffchen und ein pferd\n' > .t10-f1
      if (< .t10-f1 iconv -f ascii -t utf8) >/dev/null 2>&1; then
         </dev/null ${MAILX} ${ARGS} --set mta=test \
            --set stealthmua=noagent --set hostname \
            --attach ./.t1=-#utf8 \
            --attach ./.t10-f1=utf8#latin1 \
            --subject Y \
            ex@am.ple > ./.tall 2>&1
         check 10 0 .tall '1257664842 877'
      else
         t_echoskip '10:[ICONV/iconv(1):missing conversion(1)]'
      fi
   else
      t_echoskip '10:[!ICONV]'
   fi

   t_epilog "${@}"
}

t_rfc2231() {
   # (after attachments) 
   t_prolog "${@}"

   (
      mkdir ./.ttt || exit 1
      cd ./.ttt || exit 2
      : > "ma'ger.txt"
      : > "mä'ger.txt"
      : > 'diet\ is \curd.txt'
      : > 'diet "is" curd.txt'
      : > höde-tröge.txt
      : > höde__tröge__müde__dätte__hätte__vülle__gülle__äse__äße__säuerliche__kräuter__österliche__grüße__mäh.txt
      : > höde__tröge__müde__dätte__hätte__vuelle__guelle__aese__aesse__sauerliche__kräuter__österliche__grüße__mäh.txt
      : > hööööööööööööööööö_nöööööööööööööööööööööö_düüüüüüüüüüüüüüüüüüü_bäääääääääääääääääääääääh.txt
      : > ✆✆✆✆✆✆✆✆✆✆✆✆✆✆✆✆✆✆✆✆✆✆✆✆.txt
   )
   echo bla | ${MAILX} ${ARGS} ${ADDARG_UNI} \
      -a "./.ttt/ma'ger.txt" -a "./.ttt/mä'ger.txt" \
      -a './.ttt/diet\ is \curd.txt' -a './.ttt/diet "is" curd.txt' \
      -a ./.ttt/höde-tröge.txt \
      -a ./.ttt/höde__tröge__müde__dätte__hätte__vülle__gülle__äse__äße__säuerliche__kräuter__österliche__grüße__mäh.txt \
      -a ./.ttt/höde__tröge__müde__dätte__hätte__vuelle__guelle__aese__aesse__sauerliche__kräuter__österliche__grüße__mäh.txt \
      -a ./.ttt/hööööööööööööööööö_nöööööööööööööööööööööö_düüüüüüüüüüüüüüüüüüü_bäääääääääääääääääääääääh.txt \
      -a ./.ttt/✆✆✆✆✆✆✆✆✆✆✆✆✆✆✆✆✆✆✆✆✆✆✆✆.txt \
      "${MBOX}"
   check 1 0 "${MBOX}" '3720896054 3088'

   # `resend' test, reusing $MBOX
   printf "Resend ./.t2\nx\n" | ${MAILX} ${ARGS} -Rf "${MBOX}"
   check 2 0 ./.t2 '3720896054 3088'

   printf "resend ./.t3\nx\n" | ${MAILX} ${ARGS} -Rf "${MBOX}"
   check 3 0 ./.t3 '3979736592 3133'

   # And a primitive test for reading messages with invalid parameters
   ${cat} <<-_EOT > ./.tinv
	From a@b.invalid Wed May 15 12:43:00 2018
	MIME-Version: 1.0
	Content-Type: multipart/mixed; boundary="1"
	
	This is a multi-part message in MIME format.
	--1
	Content-Type: text/plain; charset=UTF-8
	Content-Transfer-Encoding: quoted-printable
	
	foo
	--1
	Content-Type: text/plain; name*17="na"; name*18="me-c-t"
	Content-Transfer-Encoding: 7bit
	Content-Disposition: inline
	
	bar
	--1--
	
	From a@b.invalid Wed May 15 12:43:00 2018
	MIME-Version: 1.0
	Content-Type: multipart/mixed; boundary="2"
	
	This is a multi-part message in MIME format.
	--2
	Content-Type: text/plain; charset=UTF-8
	Content-Transfer-Encoding: quoted-printable
	
	foo
	--2
	Content-Type: text/plain; name*17="na"; name*18="me-c-t"
	Content-Transfer-Encoding: 7bit
	Content-Disposition: inline;
	        filename*0="na";
	        filename*998999999999999999999999999999="me-c-d"
	
	bar
	--2--
	
	From a@b.invalid Wed May 15 12:43:00 2018
	MIME-Version: 1.0
	Content-Type: multipart/mixed; boundary="3"
	
	This is a multi-part message in MIME format.
	--3
	Content-Type: text/plain; charset=UTF-8
	Content-Transfer-Encoding: quoted-printable
	
	foo
	--3
	Content-Type: text/plain; name*17="na"; name*18="me-c-t"
	Content-Transfer-Encoding: 7bit
	Content-Disposition: inline;
	        filename*0="na"; filename*998="me-c-d"
	
	bar
	--3--
	_EOT

   printf '\\#
   \\headerpick type ignore Content-Type Content-Disposition
   \\type 1 2 3
   \\xit
   ' | ${MAILX} ${ARGS} -Rf ./.tinv > ./.tall 2> ./.terr
   check 4 0 ./.tall '1842050412 902'
   if have_feat uistrings; then
      check 5 - ./.terr '3713266499 473'
   else
      t_echoskip '5:[!UISTRINGS]'
   fi

   t_epilog "${@}"
}

t_mime_types_load_control() {
   t_prolog "${@}"

   if have_feat uistrings; then :; else
      t_echoskip '[!UISTRINGS]'
      t_epilog "${@}"
      return
   fi

   ${cat} <<-_EOT > ./.tmts1
   ? application/mathml+xml mathml
	_EOT
   ${cat} <<-_EOT > ./.tmts2
   ? x-conference/x-cooltalk ice
   ?t aga-aga aga
   ? application/aga-aga aga
	_EOT

   ${cat} <<-_EOT > ./.tmts1.mathml
   <head>nonsense ML</head>
	_EOT
   ${cat} <<-_EOT > ./.tmts2.ice
   Icy, icy road.
	_EOT
   printf 'of which the crack is coming soon' > ./.tmtsx.doom
   printf 'of which the crack is coming soon' > ./.tmtsx.aga

   printf '
         m %s
         Schub-di-du
~@ ./.tmts1.mathml
~@ ./.tmts2.ice
~@ ./.tmtsx.doom
~@ ./.tmtsx.aga
~.
         File %s
         from*
         type
         xit
      ' "${MBOX}" "${MBOX}" |
      ${MAILX} ${ARGS} \
         -Smimetypes-load-control=f=./.tmts1,f=./.tmts2 \
         > ./.tout 2>&1
   check_ex0 1-estat
   ${cat} "${MBOX}" >> ./.tout
   check 1 - ./.tout '919615295 2440'

   echo type | ${MAILX} ${ARGS} -R \
      -Smimetypes-load-control=f=./.tmts1,f=./.tmts3 \
      -f "${MBOX}" >> ./.tout 2>&1
   check 2 0 ./.tout '3998003232 3633'

   t_epilog "${@}"
}
# }}}

# Around state machine, after basics {{{
t_alternates() {
   t_prolog "${@}"

   ${cat} <<- '__EOT' | ${MAILX} ${ARGS} -Smta=test://"$MBOX" > ./.tall 2>&1
   commandalias x echo '$?/$^ERRNAME'
   commandalias y echo '$?/$^ERRNAME <$rv>'
   echo --0
   alternates;x
   alternates a1@b1 a2@b2 a3@b3;x
   alternates;x
   vput alternates rv;y

   echo --1
   unalternates a2@b2
   vput alternates rv;y
   unalternates a3@b3
   vput alternates rv;y
   unalternates a1@b1
   vput alternates rv;y

   echo --2
   unalternates *
   alternates a1@b1 a2@b2 a3@b3
   unalternates a3@b3
   vput alternates rv;y
   unalternates a2@b2
   vput alternates rv;y
   unalternates a1@b1
   vput alternates rv;y

   echo --3
   alternates a1@b1 a2@b2 a3@b3
   unalternates a1@b1
   vput alternates rv;y
   unalternates a2@b2
   vput alternates rv;y
   unalternates a3@b3
   vput alternates rv;y

   echo --4
   unalternates *
   alternates a1@b1 a2@b2 a3@b3
   unalternates *
   vput alternates rv;y

   echo --5
   unalternates *
   alternates a1@b1 a1@c1 a1@d1 a2@b2 a3@b3 a3@c3 a3@d3
   m a1@b1 a1@c1 a1@d1
	~s all alternates, only a1@b1 remains
	~c a2@b2
	~b a3@b3 a3@c3 a3@d3
	~r - '_EOT'
   This body is!
   This also body is!!
_EOT
	~.

   echo --6
   unalternates *
   alternates a1@b1 a1@c1 a2@b2 a3@b3
   m a1@b1 a1@c1 a1@d1
	~s a1@b1 a1@d1, and a3@c3 a3@d3 remain
	~c a2@b2
	~b a3@b3 a3@c3 a3@d3
	~r - '_EOT'
   This body2 is!
_EOT
	~.

   echo --7
   alternates a1@b1 a2@b2 a3; set allnet
   m a1@b1 a1@c1 a1@d1
	~s all alternates via allnet, only a1@b1 remains
	~c a2@b2
	~b a3@b3 a3@c3 a3@d3
	~r - '_EOT'
   This body3 is!
_EOT
	~.

   echo --10
   unalternates *
   alternates a1@b1;x
   vput alternates rv;y
   alternates a2@b2;x
   vput alternates rv;y
   alternates a3@b3;x
   vput alternates rv;y
   alternates a4@b4;x
   vput alternates rv;y

   unalternates *
   vput alternates rv;y

   echo --11
   set posix
   alternates a1@b1 a2@b2;x
   vput alternates rv;y
   alternates a3@b3 a4@b4;x
   vput alternates rv;y
	__EOT

   check 1 0 "${MBOX}" '3901995195 542'
   if have_feat uistrings; then
      check 2 - .tall '1878598364 505'
   else
      t_echoskip '2:[!UISTRINGS]'
   fi

   # Automatic alternates, also from command line (freezing etc.)
   ${rm} "${MBOX}"
   ${cat} <<- __EOT > ./.tin
	From trouble-report@desy  Wed Jun  6 20:19:28 2018
	Date: Wed, 06 Jun 2018 19:58:02 +0200
	From: a@b.org, b@b.org, c@c.org
	Sender: a@b.org
	To: b@b.org
	Cc: a@b.org, c@c.org
	Subject: test
	Message-ID: <20180606175802.dw-cn%a@b.org>
	
	sultry
	
	__EOT

   printf '#
   reply
!^header remove to
!^header remove cc
!^header remove subject
!^header insert to b@b.org
!^header insert cc a@b.org  b@b.org c@c.org
my body
!.
   ' | ${MAILX} ${ARGS} -Smta=test://"$MBOX" -Sescape=! \
         -S from=a@b.org,b@b.org,c@c.org -S sender=a@b.org \
         -Rf ./.tin > ./.tall 2>&1
   check 3 0 "${MBOX}" '3184203976 265'
   check 4 - .tall '3604001424 44'

   # same, per command
   printf '#
   set from=a@b.org,b@b.org,c@c.org sender=a@b.org
   reply
!^header remove to
!^header remove cc
!^header remove subject
!^header insert to b@b.org
!^header insert cc a@b.org  b@b.org c@c.org
my body
!.
   ' | ${MAILX} ${ARGS} -Smta=test://"$MBOX" -Sescape=! \
         -Rf ./.tin > ./.tall 2>&1
   check 5 0 "${MBOX}" '98184290 530'
   check 6 - .tall '3604001424 44'

   # And more, with/out -r
   # TODO -r should be the Sender:, which should automatically propagate to
   # TODO From: if possible and/or necessary.  It should be possible to
   # TODO suppres -r stuff from From: and Sender:, but fallback to special -r
   # TODO arg as appropriate.
   # TODO For now we are a bit messy

   ${rm} "${MBOX}"
   </dev/null ${MAILX} ${ARGS} -Smta=test://"$MBOX" -s '-Sfrom + -r ++ test' \
      -c a@b.example -c b@b.example -c c@c.example \
      -S from=a@b.example,b@b.example,c@c.example \
      -S sender=a@b.example \
      -r a@b.example b@b.example ./.tout >./.tall 2>&1
   check 7 0 "${MBOX}" '2052716617 201'
   check 8 - .tout '2052716617 201'
   check 9 - .tall '4294967295 0'

   </dev/null ${MAILX} ${ARGS} -Smta=test://"$MBOX" -s '-Sfrom + -r ++ test' \
      -c a@b.example -c b@b.example -c c@c.example \
      -S from=a@b.example,b@b.example,c@c.example \
      -r a@b.example b@b.example ./.tout >./.tall 2>&1
   check 10 0 "${MBOX}" '3213404599 382'
   check 11 - .tout '3213404599 382'
   check 12 - .tall '4294967295 0'

   </dev/null ${MAILX} ${ARGS} -Smta=test://"$MBOX" -s '-Sfrom + -r ++ test' \
      -c a@b.example -c b@b.example -c c@c.example \
      -S from=a@b.example,b@b.example,c@c.example \
      -S sender=a@b.example \
      b@b.example >./.tall 2>&1
   check 13 0 "${MBOX}" '337984804 609'
   check 14 - .tall '4294967295 0'

   t_epilog "${@}"
}

t_cmd_escapes() {
   # quote and cmd escapes because this (since Mail times) is worked in the
   # big collect() monster of functions
   t_prolog "${@}"

   echo 'included file' > ./.ttxt
   { t__x1_msg && t__x2_msg && t__x3_msg &&
      t__gen_msg from 'ex4@am.ple' subject sub4 &&
      t__gen_msg from 'eximan <ex5@am.ple>' subject sub5; } > ./.tmbox

   # ~@ is tested with other attachment stuff, ~^ is in compose_hooks; we also
   # have some in compose_edits and digmsg
   printf '#
      set Sign=SignVar sign=signvar DEAD=./.ttxt
      headerpick type retain Subject
      headerpick forward retain Subject To
      reply 2
!!1 Not escaped.  And shell test last, right before !..
!:echo 1
!:   echo 2 only echoed via colon
!:echo 2:$?/$^ERRNAME
!_  echo 3 only echoed via underscore
!:echo 3:$?/$^ERRNAME
!< ./.ttxt
!:echo 4:$?/$^ERRNAME
!<! echo 5 shell echo included
!:echo 5:$?/$^ERRNAME
!| echo 6 pipecmd-pre; cat; echo 6 pipecmd-post
!:echo 6:$?/$^ERRNAME
7 and 8 are ~A and ~a:
!A
!:echo 7:$?/$^ERRNAME
!a
!:echo 8:$?/$^ERRNAME
!b 9 added ~b cc <ex1@am.ple>
!:echo 9:$?/$^ERRNAME
!c 10 added ~c c <ex2@am.ple>
!:echo 10:$?/$^ERRNAME
11 next ~d / $DEAD
!d
!:echo 11:$?/$^ERRNAME
12: ~F
!F
!:echo 12:$?/$^ERRNAME
13: ~F 1 3
!F 1 3
!:echo 13:$?/$^ERRNAME
!F 1000
!:echo 13-1:$?/$^ERRNAME; set posix
14: ~f (headerpick: subject)
!f
!:echo 14:$?/$^ERRNAME; unset posix
14.1: ~f (!posix: headerpick: subject to)
!f
!:echo 14.1:$?/$^ERRNAME; set forward-add-cc
14.2: ~f (!posix: headerpick: subject to; forward-add-cc adds mr3)
!f 3
!:echo 14.2:$?/$^ERRNAME; set fullnames
14.3: ~f (!posix: headerpick: subject to; forward-add-cc adds mr1 fullname)
!f 1
!:echo 14.3:$?/$^ERRNAME; set nofullnames noforward-add-cc posix
15: ~f 1
!f 1
!:echo 15:$?/$^ERRNAME
15.5: nono: ~H, ~h
!H
!:echo 15.5-1:$?/$^ERRNAME
!h
!:echo 15.5-2:$?/$^ERRNAME
16, 17: ~I Sign, ~i Sign
!I Sign
!:echo 16:$?/$^ERRNAME
!i Sign
!:echo 17:$?/$^ERRNAME
18: ~M
!M
!:echo 18:$?/$^ERRNAME # XXX forward-add-cc: not expl. tested
19: ~M 1
!M 1
!:echo 19:$?/$^ERRNAME
20: ~m
!m
!:echo 20:$?/$^ERRNAME # XXX forward-add-cc: not expl. tested
21: ~m 3
!m 3
!:echo 21:$?/$^ERRNAME
28-34: ~Q; 28: ~Q
!Q
!:echo 28:$?/$^ERRNAME
29: ~Q 1 3
!Q 1 3
!:echo 29:$?/$^ERRNAME
set quote
!:set quote
30: ~Q
!Q
!:echo 30:$?/$^ERRNAME
31: ~Q 1 3
!Q 1 3
!:echo 31:$?/$^ERRNAME
set quote-inject-head quote-inject-tail indentprefix
!:wysh set quote-inject-head=%%a quote-inject-tail=--%%r
32: ~Q
!Q
!:echo 32:$?/$^ERRNAME
set noquote-inject-head noquote-inject-tail quote-add-cc
!:set noquote-inject-head noquote-inject-tail quote-add-cc
33: ~Q 4
!Q 4
!:echo 33:$?/$^ERRNAME
set fullnames
!:set fullnames
34: ~Q 5
!Q 5
!:echo 34:$?/$^ERRNAME
unset fullnames, quote stuff
!:unset quote quote-add-cc fullnames
22: ~R ./.ttxt
!R ./.ttxt
!:echo 22:$?/$^ERRNAME
23: ~r ./.ttxt
!r ./.ttxt
!:echo 23:$?/$^ERRNAME
24: ~s this new subject
!s 24 did new ~s ubject
!:echo 24:$?/$^ERRNAME
!t 25 added ~t o <ex3@am.ple>
!:echo 25:$?/$^ERRNAME
26.1: ~U
!U
!:echo 26.1:$?/$^ERRNAME
26.2: ~U 1
!U 1
!:echo 26.2:$?/$^ERRNAME # XXX forward-add-cc: not expl. tested
27.1: ~u
!u
!:echo 27.1:$?/$^ERRNAME
27.2: ~u 1
!u 1
!:echo 27.2:$?/$^ERRNAME # XXX forward-add-cc: not expl. tested
and i ~w rite this out to ./.tmsg
!w ./.tmsg
!:echo i ~w:$?/$^ERRNAME
!:wysh set x=$escape;set escape=~
~!echo shell command output
~:echo shell:$?/$^ERRNAME
~:wysh set escape=$x
!.
   ' | ${MAILX} ${ARGS} -Smta=test://"$MBOX" -Rf \
         -Sescape=! -Sindentprefix=' |' \
         ./.tmbox >./.tall 2>./.terr
   check_ex0 2-estat
   ${cat} ./.tall >> "${MBOX}"
   check 2 - "${MBOX}" '1742333334 5604'
   if have_feat uistrings; then
      check 2-err - ./.terr '3575876476 49'
   else
      t_echoskip '2-err:[!UISTRINGS]'
   fi
   check 3 - ./.tmsg '1237056298 4035'

   # Simple return/error value after *expandaddr* failure test
   printf 'body
!:echo --one
!s This a new subject is
!:set expandaddr=-name
!t two@to.invalid
!:echo $?/$^ERRNAME
!:echo --two
!c no-name-allowed
!:echo $?/$^ERRNAME
!c one@cc.invalid
!:echo $?/$^ERRNAME
!:echo --three
!:alias abcc one@bcc.invalid
!b abcc
!:echo $?/$^ERRNAME
!:set expandaddr=+addr
!b abcc
!:echo $!/$?/$^ERRNAME
!.
   ' | ${MAILX} ${ARGS} -Smta=test://"$MBOX" \
         -Sescape=! \
         -s testsub one@to.invalid >./.tall 2>&1
   check 4 0 "${MBOX}" '430234709 5805'
   if have_feat uistrings; then
      check 5 - ./.tall '2336041127 212'
   else
      check 5 - ./.tall '1818580177 59'
   fi

   t_epilog "${@}"
}

t_compose_edits() { # XXX very rudimentary
   # after: t_cmd_escapes
   t_prolog "${@}"

   ${cat} <<-_EOT > ./.ted.sh
	#!${SHELL}
	${cat} <<-__EOT > \${1}
	Fcc: .tout1
	To:
	Fcc: .tout2
	Subject: Fcc test 1
	Fcc: .tout3

	A body
	__EOT
	exit 0
	_EOT
   chmod 0755 .ted.sh

   # > All these are in-a-row!

   printf 'mail ./.tout\n~s This subject is\nThis body is\n~.' |
      ${MAILX} ${ARGS} -Seditheaders >./.tall 2>&1
   check 1 0 ./.tout '3993703854 127'
   check 2 - ./.tall '4294967295 0'

   ${mv} ./.tall ./.tout
   printf 'mail ./.tout\n~s This subject is\nThis body is\n~e\n~.' |
      ${MAILX} ${ARGS} -Seditheaders -SEDITOR=./.ted.sh >./.tall 2>&1
   check 3 0 ./.tout1 '285981670 116'
   check 4 - ./.tout2 '285981670 116'
   check 5 - ./.tout3 '285981670 116'
   check 6 - ./.tout '4294967295 0'
   check 7 - ./.tall '4294967295 0'
   ${rm} ./.tout1 ./.tout2 ./.tout3

   # t_compose_hooks will test ~^ at edge
   ${mv} ./.tout ./.tout1
   ${mv} ./.tall ./.tout2
   printf '#
   mail ./.tout\n!s This subject is\nThis body is
!^header list
!^header list fcc
!^header show fcc
!^header remove to
!^header insert fcc            ./.tout
!^header insert fcc      .tout1
!^header insert fcc   ./.tout2
!^header list
!^header show fcc
!^header remove-at fcc 2
!^header remove-at fcc 2
!^header show fcc
!^head remove fcc
!^header show fcc
!^header insert fcc ./.tout
!^header show fcc
!^header list
!.
      ' | ${MAILX} ${ARGS} -Sescape=! >./.tall 2>&1
   check 8 0 ./.tout '3993703854 127'
   check 9 - ./.tout1 '4294967295 0'
   check 10 - ./.tout2 '4294967295 0'
   check 11 - ./.tall '4280910245 300'

   # < No longer in-a-row

   ${cat} <<-_EOT | ${MAILX} ${ARGS} -t >./.tall 2>&1
	Fcc: .ttout
	Subject: Fcc via -t test

	My body
	_EOT
   check 12 0 ./.ttout '1289478830 122'
   check 13 - ./.tall '4294967295 0'

   # This test assumes code of `^' and `digmsg' is shared: see t_digmsg()

   t_epilog "${@}"
}

t_digmsg() { # XXX rudimentary
   t_prolog "${@}"

   printf '#
   mail ./.tout\n!s This subject is\nThis body is
!:echo --one
!:digmsg create - -
!:digmsg - header list
!:digmsg - header show subject
!:digmsg - header show to
!:digmsg - header remove to
!:digmsg - header list
!:digmsg - header show to
!:digmsg remove -
!:echo --two
!:digmsg create -
!:digmsg - header list;   readall x;   echon "<$x>";
!:digmsg - header show subject;readall x;echon "<$x>";;
!:digmsg remove -
!:echo --three
!:    # nothing here as is comment
!^header insert fcc   ./.tbox
!:echo --four
!:digmsg create - -
!:digmsg - header list
!:digmsg - header show fcc
!:echo --five
!^head remove fcc
!:echo --six
!:digmsg - header list
!:digmsg - header show fcc
!:digmsg - header insert fcc ./.tfcc
!:echo --seven
!:digmsg remove -
!:echo bye
!.
   echo --hello again
   File ./.tfcc
   echo --one
   digmsg create 1 -
   digmsg 1 header list
   digmsg 1 header show subject
   echo --two
   ! : > ./.tempty
   File ./.tempty
   echo --three
   digmsg 1 header list; echo $?/$^ERRNAME
   digmsg create -; echo $?/$^ERRNAME
   echo ==========
   ! %s ./.tfcc > ./.tcat
   ! %s "s/This subject is/There subject was/" < ./.tfcc >> ./.tcat
   File ./.tcat
   mail nowhere@exam.ple
!:echo ===1
!:digmsg create -; echo $?/$^ERRNAME;\\
   digmsg create 1; echo $?/$^ERRNAME;\\
   digmsg create 2; echo $?/$^ERRNAME
!:echo ===2.1
!:digmsg - h l;echo $?/$^ERRNAME;readall d;echo "$?/$^ERRNAME <$d>"
!:echo =2.2
!:digmsg 1 h l;echo $?/$^ERRNAME;readall d;echo "$?/$^ERRNAME <$d>"
!:echo =2.3
!^ h l
!:echo =2.4
!:digmsg 2 h l;echo $?/$^ERRNAME;readall d;echo "$?/$^ERRNAME <$d>"
!:echo ===3.1
!:digmsg - h s to;echo $?/$^ERRNAME;readall d;echo "$?/$^ERRNAME <$d>"
!:echo =3.2
!:digmsg 1 h s subject;echo $?/$^ERRNAME;readall d;echo "$?/$^ERRNAME <$d>"
!:echo =3.3
!^ h s to
!:echo =3.4
!:digmsg 2 h s subject;echo $?/$^ERRNAME;readall d;echo "$?/$^ERRNAME <$d>"
!:echo ==4.1
!:digmsg remove -; echo $?/$^ERRNAME;\\
   digmsg remove 1; echo $?/$^ERRNAME;\\
   digmsg remove 2; echo $?/$^ERRNAME;
!x
   echo ======= new game new fun!
   mail one@to.invalid
!s hossa
!:set expandaddr=-name
!:echo -oneo
!^ header insert to two@to.invalid
!:echo $?/$^ERRNAME
!:echo --two
!^ header insert cc no-name-allowed
!:echo $?/$^ERRNAME
!^ header insert cc one@cc.invalid
!:echo $?/$^ERRNAME
!:echo --three
!:alias abcc one@bcc.invalid
!^ header insert bcc abcc
!:echo $?/$^ERRNAME
!:set expandaddr=+addr
!^ header insert bcc abcc
!:echo $!/$?/$^ERRNAME
!.
   echo --bye
      ' "${cat}" "${sed}" |
      ${MAILX} ${ARGS} -Smta=test://"$MBOX" -Sescape=! >./.tall 2>&1
   check 1 0 "$MBOX" '665881681 179'
   if have_feat uistrings; then
      check 2 - ./.tall '2554217728 1366'
   else
      check 2 - ./.tall '121327235 1093'
   fi
   check 3 - ./.tfcc '3993703854 127'
   check 4 - ./.tempty '4294967295 0'
   check 5 - ./.tcat '2157992522 256'

   t_epilog "${@}"
}

t_on_main_loop_tick() {
   t_prolog "${@}"

   if have_feat cmd-vexpr; then :; else
      t_echoskip '[!CMD_VEXPR]'
      t_epilog "${@}"
      return
   fi

   printf '#
   echo hello; set i=1
define bla {
   echo bla1
   echo bla2
}
define omlt {
   echo in omlt: $i
   vput vexpr i + 1 $i
}
   echo one
   set on-main-loop-tick=omlt
   echo two
   echo three
   echo calling bla;call bla
   echo four
   echo --bye;xit' |
      ${MAILX} ${ARGS} -Smta=test://"$MBOX" -Sescape=! >./.tall 2>&1
   check 1 0 ./.tall '367031402 108'

   t_epilog "${@}"
}

t_on_program_exit() {
   t_prolog "${@}"

   ${MAILX} ${ARGS} \
      -X 'define x {' -X 'echo jay' -X '}' -X x -Son-program-exit=x \
      > ./.tall 2>&1
   check 1 0 ./.tall '2820891503 4'

   ${MAILX} ${ARGS} \
      -X 'define x {' -X 'echo jay' -X '}' -X q -Son-program-exit=x \
      > ./.tall 2>&1
   check 2 0 ./.tall '2820891503 4'

   </dev/null ${MAILX} ${ARGS} \
      -X 'define x {' -X 'echo jay' -X '}' -Son-program-exit=x \
      > ./.tall 2>&1
   check 3 0 ./.tall '2820891503 4'

   </dev/null ${MAILX} ${ARGS} -Smta=test://"$MBOX" \
      -X 'define x {' -X 'echo jay' -X '}' -Son-program-exit=x \
      -s subject -. hey@you \
      > ./.tall 2>&1
   check 4 0 ./.tall '2820891503 4'
   check 5 - "$MBOX" '561900352 118'

   t_epilog "${@}"
}
# }}}

# Heavy use of/rely on state machine (behaviour) and basics {{{
t_compose_hooks() { # {{{ TODO monster
   t_prolog "${@}"

   if have_feat uistrings &&
         have_feat cmd-csop && have_feat cmd-vexpr; then :; else
      t_echoskip '[!UISTRINGS/!CMD_CSOP/!CMD_VEXPR]'
      t_epilog "${@}"
      return
   fi

   (echo line one&&echo line two&&echo line three) > ./.treadctl
   (echo echo four&&echo echo five&&echo echo six) > ./.tattach

   ${cat} <<'__EOT__' > ./.trc
   define bail {
      echoerr "Failed: $1.  Bailing out"; echo "~x"; xit
   }
   define xerr {
      vput csop es substr "$1" 0 1
      if [ "$es" != 2 ]
         xcall bail "$2"
      end
   }
   define read_mline_res {
      read hl; wysh set len=$? es=$! en=$^ERRNAME;\
         echo $len/$es/$^ERRNAME: $hl
      if [ $es -ne $^ERR-NONE ]
         xcall bail read_mline_res
      elif [ $len -ne 0 ]
         \xcall read_mline_res
      end
   }
   define ins_addr {
      wysh set xh=$1
      echo "~^header list"; read hl; echo $hl;\
         call xerr "$hl" "in_addr ($xh) 0-1"

      echo "~^header insert $xh diet <$xh@exam.ple> spliced";\
         read es; echo $es; call xerr "$es" "ins_addr $xh 1-1"
      echo "~^header insert $xh <${xh}2@exam.ple>";\
         read es; echo $es; call xerr "$es" "ins_addr $xh 1-2"
      echo "~^header insert $xh ${xh}3@exam.ple";\
         read es; echo $es; call xerr "$es" "ins_addr $xh 1-3"
      echo "~^header list $xh"; read hl; echo $hl;\
         call xerr "$hl" "ins_addr $xh 1-4"
      echo "~^header show $xh"; read es; call xerr $es "ins_addr $xh 1-5"
      call read_mline_res

      if [ "$t_remove" == "" ]
         return
      end

      echo "~^header remove $xh"; read es; call xerr $es "ins_addr $xh 2-1"
      echo "~^header remove $xh"; read es; vput csop es substr $es 0 3
      if [ $es != 501 ]
         xcall bail "ins_addr $xh 2-2"
      end
      echo "~^header list $xh"; read es; vput csop es substr $es 0 3
      if [ $es != 501 ]
         xcall bail "ins_addr $xh 2-3"
      end
      echo "~^header show $xh"; read es; vput csop es substr $es 0 3
      if [ $es != 501 ]
         xcall bail "ins_addr $xh 2-4"
      end

      #
      echo "~^header insert $xh diet <$xh@exam.ple> spliced";\
         read es; echo $es; call xerr "$es" "ins_addr $xh 3-1"
      echo "~^header insert $xh <${xh}2@exam.ple>";\
         read es; echo $es; call xerr "$es" "ins_addr $xh 3-2"
      echo "~^header insert $xh ${xh}3@exam.ple";\
         read es; echo $es; call xerr "$es" "ins_addr $xh 3-3"
      echo "~^header list $xh"; read hl; echo $hl;\
         call xerr "$hl" "ins_addr $xh 3-4"
      echo "~^header show $xh"; read es; call xerr $es "ins_addr $xh 3-5"
      call read_mline_res

      echo "~^header remove-at $xh 1"; read es;\
         call xerr $es "ins_addr $xh 3-6"
      echo "~^header remove-at $xh 1"; read es;\
         call xerr $es "ins_addr $xh 3-7"
      echo "~^header remove-at $xh 1"; read es;\
         call xerr $es "ins_addr $xh 3-8"
      echo "~^header remove-at $xh 1"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 501 ]
         xcall bail "ins_addr $xh 3-9"
      end
      echo "~^header remove-at $xh T"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 505 ]
         xcall bail "ins_addr $xh 3-10"
      end
      echo "~^header list $xh"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 501 ]
         xcall bail "ins_addr $xh 3-11"
      end
      echo "~^header show $xh"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 501 ]
         xcall bail "ins_addr $xh 3-12"
      end

      #
      echo "~^header insert $xh diet <$xh@exam.ple> spliced";\
         read es; echo $es; call xerr "$es" "ins_addr $xh 4-1"
      echo "~^header insert $xh <${xh}2@exam.ple> (comment) \"Quot(e)d\"";\
         read es; echo $es; call xerr "$es" "ins_addr $xh 4-2"
      echo "~^header insert $xh ${xh}3@exam.ple";\
         read es; echo $es; call xerr "$es" "ins_addr $xh 4-3"
      echo "~^header list $xh"; read hl; echo $hl;\
         call xerr "$hl" "header list $xh 3-4"
      echo "~^header show $xh"; read es; call xerr $es "ins_addr $xh 4-5"
      call read_mline_res

      echo "~^header remove-at $xh 3"; read es;\
         call xerr $es "ins_addr $xh 4-6"
      echo "~^header remove-at $xh 2"; read es;\
         call xerr $es "ins_addr $xh 4-7"
      echo "~^header remove-at $xh 1"; read es;\
         call xerr $es "ins_addr $xh 4-8"
      echo "~^header remove-at $xh 1"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 501 ]
         xcall bail "ins_addr $xh 4-9"
      end
      echo "~^header remove-at $xh T"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 505 ]
         xcall bail "ins_addr $xh 4-10"
      end
      echo "~^header list $xh"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 501 ]
         xcall bail "ins_addr $xh 4-11"
      end
      echo "~^header show $xh"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 501 ]
         xcall bail "ins_addr $xh 4-12"
      end
   }
   define ins_ref {
      wysh set xh=$1 mult=$2
      echo "~^header list"; read hl; echo $hl;\
         call xerr "$hl" "ins_ref ($xh) 0-1"

      echo "~^header insert $xh <$xh@exam.ple>";\
         read es; echo $es; call xerr "$es" "ins_ref $xh 1-1"
      if [ $mult -ne 0 ]
         echo "~^header insert $xh <${xh}2@exam.ple>";\
            read es; echo $es; call xerr "$es" "ins_ref $xh 1-2"
         echo "~^header insert $xh ${xh}3@exam.ple";\
            read es; echo $es; call xerr "$es" "ins_ref $xh 1-3"
      else
         echo "~^header insert $xh <${xh}2@exam.ple>"; read es;\
            vput csop es substr $es 0 3
         if [ $es != 506 ]
            xcall bail "ins_ref $xh 1-4"
         end
      end

      echo "~^header list $xh"; read hl; echo $hl;\
         call xerr "$hl" "ins_ref $xh 1-5"
      echo "~^header show $xh"; read es; call xerr $es "ins_ref $xh 1-6"
      call read_mline_res

      if [ "$t_remove" == "" ]
         return
      end

      echo "~^header remove $xh"; read es;\
         call xerr $es "ins_ref $xh 2-1"
      echo "~^header remove $xh"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 501 ]
         xcall bail "ins_ref $xh 2-2"
      end
      echo "~^header list $xh"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 501 ]
         xcall bail "$es ins_ref $xh 2-3"
      end
      echo "~^header show $xh"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 501 ]
         xcall bail "ins_ref $xh 2-4"
      end

      #
      echo "~^header insert $xh <$xh@exam.ple>";\
         read es; echo $es; call xerr "$es" "ins_ref $xh 3-1"
      if [ $mult -ne 0 ]
         echo "~^header insert $xh <${xh}2@exam.ple>";\
            read es; echo $es; call xerr "$es" "ins_ref $xh 3-2"
         echo "~^header insert $xh ${xh}3@exam.ple";\
            read es; echo $es; call xerr "$es" "ins_ref $xh 3-3"
      end
      echo "~^header list $xh";\
         read hl; echo $hl; call xerr "$hl" "ins_ref $xh 3-4"
      echo "~^header show $xh";\
         read es; call xerr $es "ins_ref $xh 3-5"
      call read_mline_res

      echo "~^header remove-at $xh 1"; read es;\
         call xerr $es "ins_ref $xh 3-6"
      if [ $mult -ne 0 ] && [ $xh != subject ]
         echo "~^header remove-at $xh 1"; read es;\
            call xerr $es "ins_ref $xh 3-7"
         echo "~^header remove-at $xh 1"; read es;\
            call xerr $es "ins_ref $xh 3-8"
      end
      echo "~^header remove-at $xh 1"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 501 ]
         xcall bail "ins_ref $xh 3-9"
      end
      echo "~^header remove-at $xh T"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 505 ]
         xcall bail "ins_ref $xh 3-10"
      end
      echo "~^header show $xh"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 501 ]
         xcall bail "ins_ref $xh 3-11"
      end

      #
      echo "~^header insert $xh <$xh@exam.ple> ";\
         read es; echo $es; call xerr "$es" "ins_ref $xh 4-1"
      if [ $mult -ne 0 ]
         echo "~^header insert $xh <${xh}2@exam.ple> ";\
            read es; echo $es; call xerr "$es" "ins_ref $xh 4-2"
         echo "~^header insert $xh ${xh}3@exam.ple";\
            read es; echo $es; call xerr "$es" "ins_ref $xh 4-3"
      end
      echo "~^header list $xh"; read hl; echo $hl;\
         call xerr "$hl" "ins_ref $xh 4-4"
      echo "~^header show $xh"; read es; call xerr $es "ins_ref $xh 4-5"
      call read_mline_res

      if [ $mult -ne 0 ] && [ $xh != subject ]
         echo "~^header remove-at $xh 3"; read es;\
            call xerr $es "ins_ref $xh 4-6"
         echo "~^header remove-at $xh 2"; read es;\
            call xerr $es "ins_ref $xh 4-7"
      end
      echo "~^header remove-at $xh 1"; read es;\
         call xerr $es "ins_ref $xh 4-8"
      echo "~^header remove-at $xh 1"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 501 ]
         xcall bail "ins_ref $xh 4-9"
      end
      echo "~^header remove-at $xh T"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 505 ]
         xcall bail "ins_ref $xh 4-10"
      end
      echo "~^header show $xh"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 501 ]
         xcall bail "ins_ref $xh 4-11"
      end
   }
   define t_header {
      echo t_header ENTER
      # In collect.c order
      call ins_addr from
      call ins_ref sender 0 # Not a "ref", but works
      call ins_addr To
      call ins_addr cC
      call ins_addr bCc
      call ins_addr reply-To
      call ins_addr mail-Followup-to
      call ins_ref messAge-id 0
      call ins_ref rEfErEncEs 1
      call ins_ref in-Reply-to 1
      call ins_ref subject 1 # Not a "ref", but works (with tweaks)
      call ins_addr freeForm1
      call ins_addr freeform2

      echo "~^header show MAILX-Command"; read es; call xerr $es "t_header 1000"
      call read_mline_res
      echo "~^header show MAILX-raw-TO"; read es; call xerr $es "t_header 1001"
      call read_mline_res

      echo t_header LEAVE
   }
   define t_attach {
      echo t_attach ENTER

      echo "~^attachment";\
         read hl; echo $hl; vput csop es substr "$hl" 0 3
      if [ "$es" != 501 ]
         xcall bail "attach 0-1"
      end

      echo "~^attach attribute ./.treadctl";\
         read hl; echo $hl; vput csop es substr "$hl" 0 3
      if [ "$es" != 501 ]
         xcall bail "attach 0-2"
      end
      echo "~^attachment attribute-at 1";\
         read hl; echo $hl; vput csop es substr "$hl" 0 3
      if [ "$es" != 501 ]
         xcall bail "attach 0-3"
      end

      echo "~^attachment insert ./.treadctl=ascii";\
         read hl; echo $hl; call xerr "$hl" "attach 1-1"
      echo "~^attachment list";\
         read es; echo $es;call xerr "$es" "attach 1-2"
      call read_mline_res
      echo "~^attachment attribute ./.treadctl";\
         read es; echo $es;call xerr "$es" "attach 1-3"
      call read_mline_res
      echo "~^attachment attribute .treadctl";\
         read es; echo $es;call xerr "$es" "attach 1-4"
      call read_mline_res
      echo "~^attachment attribute-at 1";\
         read es; echo $es;call xerr "$es" "attach 1-5"
      call read_mline_res

      echo "~^attachment attribute-set ./.treadctl filename rctl";\
         read es; echo $es;call xerr "$es" "attach 1-6"
      echo "~^attachment attribute-set .treadctl content-description Au";\
         read es; echo $es;call xerr "$es" "attach 1-7"
      echo "~^attachment attribute-set-at 1 content-id <10.du@ich>";\
         read es; echo $es;call xerr "$es" "attach 1-8"

      echo "~^attachment attribute ./.treadctl";\
         read es; echo $es;call xerr "$es" "attach 1-9"
      call read_mline_res
      echo "~^attachment attribute .treadctl";\
         read es; echo $es;call xerr "$es" "attach 1-10"
      call read_mline_res
      echo "~^attachment attribute rctl";\
         read es; echo $es;call xerr "$es" "attach 1-11"
      call read_mline_res
      echo "~^attachment attribute-at 1";\
         read es; echo $es;call xerr "$es" "attach 1-12"
      call read_mline_res

      #
      echo "~^attachment insert ./.tattach=latin1";\
         read hl; echo $hl; call xerr "$hl" "attach 2-1"
      echo "~^attachment list";\
         read es; echo $es;call xerr "$es" "attach 2-2"
      call read_mline_res
      echo "~^attachment attribute ./.tattach";\
         read es; echo $es;call xerr "$es" "attach 2-3"
      call read_mline_res
      echo "~^attachment attribute .tattach";\
         read es; echo $es;call xerr "$es" "attach 2-4"
      call read_mline_res
      echo "~^attachment attribute-at 2";\
         read es; echo $es;call xerr "$es" "attach 2-5"
      call read_mline_res

      echo "~^attachment attribute-set ./.tattach filename tat";\
         read es; echo $es;call xerr "$es" "attach 2-6"
      echo \
      "~^attachment attribute-set .tattach content-description Au2";\
         read es; echo $es;call xerr "$es" "attach 2-7"
      echo "~^attachment attribute-set-at 2 content-id <20.du@wir>";\
         read es; echo $es;call xerr "$es" "attach 2-8"
      echo \
         "~^attachment attribute-set-at 2 content-type application/x-sh";\
        read es; echo $es;call xerr "$es" "attach 2-9"

      echo "~^attachment attribute ./.tattach";\
         read es; echo $es;call xerr "$es" "attach 2-10"
      call read_mline_res
      echo "~^attachment attribute .tattach";\
         read es; echo $es;call xerr "$es" "attach 2-11"
      call read_mline_res
      echo "~^attachment attribute tat";\
         read es; echo $es;call xerr "$es" "attach 2-12"
      call read_mline_res
      echo "~^attachment attribute-at 2";\
         read es; echo $es;call xerr "$es" "attach 2-13"
      call read_mline_res

      #
      if [ "$t_remove" == "" ]
         return
      end

      echo "~^attachment remove ./.treadctl"; read es;\
         call xerr $es "attach 3-1"
      echo "~^attachment remove ./.tattach"; read es;\
         call xerr $es "attach 3-2"
      echo "~^   attachment     remove     ./.treadctl"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 501 ]
         xcall bail "attach 3-3"
      end
      echo "~^   attachment     remove     ./.tattach"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 501 ]
         xcall bail "attach 3-4"
      end
      echo "~^attachment list"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 501 ]
         xcall bail "attach 3-5"
      end

      #
      echo "~^attachment insert ./.tattach=latin1";\
         read hl; echo $hl; call xerr "$hl" "attach 4-1"
      echo "~^attachment insert ./.tattach=latin1";\
         read hl; echo $hl; call xerr "$hl" "attach 4-2"
      echo "~^attachment list";\
         read es; echo $es;call xerr "$es" "attach 4-3"
      call read_mline_res
      echo "~^   attachment     remove     .tattach"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 506 ]
         xcall bail "attach 4-4 $es"
      end
      echo "~^attachment remove-at T"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 505 ]
         xcall bail "attach 4-5"
      end
      echo "~^attachment remove ./.tattach"; read es;\
         call xerr $es "attach 4-6"
      echo "~^attachment remove ./.tattach"; read es;\
         call xerr $es "attach 4-7"
      echo "~^   attachment     remove     ./.tattach"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 501 ]
         xcall bail "attach 4-8 $es"
      end
      echo "~^attachment list"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 501 ]
         xcall bail "attach 4-9"
      end

      #
      echo "~^attachment insert ./.tattach=latin1";\
         read hl; echo $hl; call xerr "$hl" "attach 5-1"
      echo "~^attachment insert ./.tattach=latin1";\
         read hl; echo $hl; call xerr "$hl" "attach 5-2"
      echo "~^attachment insert ./.tattach=latin1";\
         read hl; echo $hl; call xerr "$hl" "attach 5-3"
      echo "~^attachment list";\
         read es; echo $es;call xerr "$es" "attach 5-4"
      call read_mline_res

      echo "~^attachment remove-at 3"; read es;\
         call xerr $es "attach 5-5"
      echo "~^attachment remove-at 3"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 501 ]
         xcall bail "attach 5-6"
      end
      echo "~^attachment remove-at 2"; read es;\
         call xerr $es "attach 5-7"
      echo "~^attachment remove-at 2"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 501 ]
         xcall bail "attach 5-8"
      end
      echo "~^attachment remove-at 1"; read es;\
         call xerr $es "attach 5-9"
      echo "~^attachment remove-at 1"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 501 ]
         xcall bail "attach 5-10"
      end

      echo "~^attachment list"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 501 ]
         xcall bail "attach 5-11"
      end

      #
      echo "~^attachment insert ./.tattach=latin1";\
         read hl; echo $hl; call xerr "$hl" "attach 6-1"
      echo "~^attachment insert ./.tattach=latin1";\
         read hl; echo $hl; call xerr "$hl" "attach 6-2"
      echo "~^attachment insert ./.tattach=latin1";\
         read hl; echo $hl; call xerr "$hl" "attach 6-3"
      echo "~^attachment list";\
         read es; echo $es;call xerr "$es" "attach 6-4"
      call read_mline_res

      echo "~^attachment remove-at 1"; read es;\
         call xerr $es "attach 6-5"
      echo "~^attachment remove-at 1"; read es;\
         call xerr $es "attach 6-6"
      echo "~^attachment remove-at 1"; read es;\
         call xerr $es "attach 6-7"
      echo "~^attachment remove-at 1"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 501 ]
         xcall bail "attach 6-8"
      end

      echo "~^attachment list"; read es;\
         vput csop es substr $es 0 3
      if [ $es != 501 ]
         xcall bail "attach 6-9"
      end

      echo t_attach LEAVE
   }
   define t_ocs {
      read ver
      echo t_ocs
      call t_header
      call t_attach
   }
   define t_oce {
      echo on-compose-enter, mailx-command<$mailx-command>
      alternates alter1@exam.ple alter2@exam.ple
      alternates
      set autocc='alter1@exam.ple alter2@exam.ple'
      echo mailx-from<$mailx-from> mailx-sender<$mailx-sender>
      echo mailx-subject<$mailx-subject>
      echo mailx-to<$mailx-to> mailx-cc<$mailx-cc> mailx-bcc<$mailx-bcc>
      echo mailx-raw-to<$mailx-raw-to> mailx-raw-cc<$mailx-raw-cc> \
         mailx-raw-bcc<$mailx-raw-bcc>
      echo mailx-orig-from<$mailx-orig-from> mailx-orig-to<$mailx-orig-to> \
         mailx-orig-cc<$mailx-orig-cc> mailx-orig-bcc<$mailx-orig-bcc>
      digmsg create - -;echo $?/$!/$^ERRNAME;\
         digmsg - header list;\
         digmsg remove -;echo $?/$!/$^ERRNAME
      digmsg create -;echo $?/$!/$^ERRNAME;\
         digmsg - header list;readall x;echon $x;\
         digmsg remove -;echo $?/$!/$^ERRNAME
   }
   define t_ocl {
      echo on-compose-leave, mailx-command<$mailx-command>
      vput alternates al
      eval alternates $al alter3@exam.ple alter4@exam.ple
      alternates
      set autobcc='alter3@exam.ple alter4@exam.ple'
      echo mailx-from<$mailx-from> mailx-sender<$mailx-sender>
      echo mailx-subject<$mailx-subject>
      echo mailx-to<$mailx-to> mailx-cc<$mailx-cc> mailx-bcc<$mailx-bcc>
      echo mailx-raw-to<$mailx-raw-to> mailx-raw-cc<$mailx-raw-cc> \
         mailx-raw-bcc<$mailx-raw-bcc>
      echo mailx-orig-from<$mailx-orig-from> mailx-orig-to<$mailx-orig-to> \
         mailx-orig-cc<$mailx-orig-cc> mailx-orig-bcc<$mailx-orig-bcc>
      digmsg create - -;echo $?/$!/$^ERRNAME;\
         digmsg - header list;\
         digmsg remove -;echo $?/$!/$^ERRNAME
      digmsg create -;echo $?/$!/$^ERRNAME;\
         digmsg - header list;readall x;echon $x;\
         digmsg remove -;echo $?/$!/$^ERRNAME
   }
   define t_occ {
      echo on-compose-cleanup, mailx-command<$mailx-command>
      unalternates *
      alternates
      echo mailx-from<$mailx-from> mailx-sender<$mailx-sender>
      echo mailx-subject<$mailx-subject>
      echo mailx-to<$mailx-to> mailx-cc<$mailx-cc> mailx-bcc<$mailx-bcc>
      echo mailx-raw-to<$mailx-raw-to> mailx-raw-cc<$mailx-raw-cc> \
         mailx-raw-bcc<$mailx-raw-bcc>
      echo mailx-orig-from<$mailx-orig-from> mailx-orig-to<$mailx-orig-to> \
         mailx-orig-cc<$mailx-orig-cc> mailx-orig-bcc<$mailx-orig-bcc>
      # XXX error message variable digmsg create - -;echo $?/$!/$^ERRNAME;\
         digmsg - header list;\
         digmsg remove -;echo $?/$!/$^ERRNAME
      # ditto digmsg create -;echo $?/$!/$^ERRNAME;\
         digmsg - header list;readall x;echon $x;\
         digmsg remove -;echo $?/$!/$^ERRNAME
   }
   wysh set on-compose-splice=t_ocs \
      on-compose-enter=t_oce on-compose-leave=t_ocl \
         on-compose-cleanup=t_occ
__EOT__

   printf 'm this-goes@nowhere\nbody\n!.\n' |
   ${MAILX} ${ARGS} -Snomemdebug -Sescape=! -Sstealthmua=noagent \
      -X'source ./.trc' -Smta=test://"$MBOX" \
      >./.tall 2>&1
   ${cat} ./.tall >> "${MBOX}"
   check 1 0 "${MBOX}" '3199865751 10529'

   ${rm} "${MBOX}"
   printf 'm this-goes@nowhere\nbody\n!.\n' |
   ${MAILX} ${ARGS} -Snomemdebug -Sescape=! -Sstealthmua=noagent \
      -St_remove=1 -X'source ./.trc' -Smta=test://"$MBOX" \
      >./.tall 2>&1
   ${cat} ./.tall >> "${MBOX}"
   check 2 0 "${MBOX}" '473642362 12743'

   ##

   # Some state machine stress, shell compose hook, localopts for hook, etc.
   # readctl in child. ~r as HERE document
   ${rm} "${MBOX}"
   printf 'm ex@am.ple\nbody\n!.
      echon ${mailx-command}${mailx-subject}
      echon ${mailx-from}${mailx-sender}
      echon ${mailx-to}${mailx-cc}${mailx-bcc}
      echon ${mailx-raw-to}${mailx-raw-cc}${mailx-raw-bcc}
      echon ${mailx-orig-from}${mailx-orig-to}${mailx-orig-gcc}${mailx-orig-bcc}
      var t_oce t_ocs t_ocs_sh t_ocl t_occ autocc
   ' | ${MAILX} ${ARGS} -Snomemdebug -Sescape=! \
      -Smta=test://"$MBOX" \
      -X'
         define bail {
            echoerr "Failed: $1.  Bailing out"; echo "~x"; xit
         }
         define xerr {
            vput csop es substr "$1" 0 1
            if [ "$es" != 2 ]
               xcall bail "$2"
            end
         }
         define read_mline_res {
            read hl; wysh set len=$? es=$! en=$^ERRNAME;\
               echo $len/$es/$^ERRNAME: $hl
            if [ $es -ne $^ERR-NONE ]
               xcall bail read_mline_res
            elif [ $len -ne 0 ]
               \xcall read_mline_res
            end
         }
         define _work {
            vput vexpr i + 1 "$2"
            if [ $i -lt 111 ]
               vput vexpr j % $i 10
               if [ $j -ne 0 ]
                  set j=xcall
               else
                  echon "$i.. "
                  set j=call
               end
               eval \\$j _work $1 $i
               return $?
            end
            vput vexpr i + $i "$1"
            return $i
         }
         define _read {
            wysh set line; read line;wysh set es=$? en=$^ERRNAME ;\
               echo read:$es/$en: $line
            if [ "${es}" -ne -1 ]
               xcall _read
            end
            readctl remove $cwd/.treadctl; echo readctl remove:$?/$^ERRNAME
         }
         define t_ocs {
            read ver
            echo t_ocs
            echo "~^header list"; read hl; echo $hl;\
               vput csop es substr "$hl" 0 1
            if [ "$es" != 2 ]
               xcall bail "header list"
            endif
            #
            call _work 1; echo $?
            echo "~^header insert cc splicy diet <splice@exam.ple> spliced";\
               read es; echo $es; vput csop es substr "$es" 0 1
            if [ "$es" != 2 ]
               xcall bail "be diet"
            endif
            echo "~^header insert cc <splice2@exam.ple>";\
               read es; echo $es; vput csop es substr "$es" 0 1
            if [ "$es" != 2 ]
               xcall bail "be diet2"
            endif
            #
            call _work 2; echo $?
            echo "~^header insert bcc juicy juice <juice@exam.ple> spliced";\
               read es; echo $es;vput csop es substr "$es" 0 1
            if [ "$es" != 2 ]
               xcall bail "be juicy"
            endif
            echo "~^header insert bcc juice2@exam.ple";\
               read es; echo $es;vput csop es substr "$es" 0 1
            if [ "$es" != 2 ]
               xcall bail "be juicy2"
            endif
            echo "~^header insert bcc juice3 <juice3@exam.ple>";\
               read es; echo $es;vput csop es substr "$es" 0 1
            if [ "$es" != 2 ]
               xcall bail "be juicy3"
            endif
            echo "~^header insert bcc juice4@exam.ple";\
               read es; echo $es;vput csop es substr "$es" 0 1
            if [ "$es" != 2 ]
               xcall bail "be juicy4"
            endif
            #
            echo "~^header remove-at bcc 3";\
               read es; echo $es;vput csop es substr "$es" 0 1
            if [ "$es" != 2 ]
               xcall bail "remove juicy5"
            endif
            echo "~^header remove-at bcc 2";\
               read es; echo $es;vput csop es substr "$es" 0 1
            if [ "$es" != 2 ]
               xcall bail "remove juicy6"
            endif
            echo "~^header remove-at bcc 3";\
               read es; echo $es;vput csop es substr "$es" 0 3
            if [ "$es" != 501 ]
               xcall bail "failed to remove-at"
            endif
            # Add duplicates which ought to be removed!
            echo "~^header insert bcc juice4@exam.ple";\
               read es; echo $es;vput csop es substr "$es" 0 1
            if [ "$es" != 2 ]
               xcall bail "be juicy4-1"
            endif
            echo "~^header insert bcc juice4@exam.ple";\
               read es; echo $es;vput csop es substr "$es" 0 1
            if [ "$es" != 2 ]
               xcall bail "be juicy4-2"
            endif
            echo "~^header insert bcc juice4@exam.ple";\
               read es; echo $es;vput csop es substr "$es" 0 1
            if [ "$es" != 2 ]
               xcall bail "be juicy4-3"
            endif
            echo "~:set t_ocs"

            #
            call _work 3; echo $?
            echo "~r - '__EOT'"
            vput ! i echo just knock if you can hear me;\
               i=0;\
               while [ $i -lt 24 ]; do printf "%s " $i; i=`expr $i + 1`; done;\
               echo relax
            echon shell-cmd says $?/$^ERRNAME: $i
            echo "~x  will not become interpreted, we are reading until __EOT"
            echo "__EOT"
            read r_status; echo "~~r status output: $r_status"
            echo "~:echo $? $! $^ERRNAME"
            read r_status
            echo "~~r status from parent: $r_status"

            #
            call _work 4; echo $?
            vput cwd cwd;echo cwd:$?
            readctl create $cwd/.treadctl     ;echo readctl:$?/$^ERRNAME;\
            call _read

            #
            call _work 5; echo $?
            echo "~^header show MAILX-Command"; read es;\
               call xerr $es "t_header 1000"; call read_mline_res
            echo "~^header show MAILX-raw-TO"; read es;\
               call xerr $es "t_header 1001"; xcall read_mline_res

            echoerr IT IS WRONG IF YOU SEE THIS
         }
         define t_oce {
            echo on-compose-enter, mailx-command<$mailx-command>
            set t_oce autobcc=oce@exam.ple
            alternates alter1@exam.ple alter2@exam.ple
            alternates
            echo mailx-from<$mailx-from> mailx-sender<$mailx-sender>
            echo mailx-subject<$mailx-subject>
            echo mailx-to<$mailx-to> mailx-cc<$mailx-cc> mailx-bcc<$mailx-bcc>
            echo mailx-raw-to<$mailx-raw-to> mailx-raw-cc<$mailx-raw-cc> \
               mailx-raw-bcc<$mailx-raw-bcc>
            echo mailx-orig-from<$mailx-orig-from> \
               mailx-orig-to<$mailx-orig-to> \
               mailx-orig-cc<$mailx-orig-cc> mailx-orig-bcc<$mailx-orig-bcc>
         }
         define t_ocl {
            echo on-compose-leave, mailx-command<$mailx-command>
            set t_ocl autocc=ocl@exam.ple
            unalternates *
            alternates alter3@exam.ple alter4@exam.ple
            alternates
            echo mailx-from<$mailx-from> mailx-sender<$mailx-sender>
            echo mailx-subject<$mailx-subject>
            echo mailx-to<$mailx-to> mailx-cc<$mailx-cc> mailx-bcc<$mailx-bcc>
            echo mailx-raw-to<$mailx-raw-to> mailx-raw-cc<$mailx-raw-cc> \
               mailx-raw-bcc<$mailx-raw-bcc>
            echo mailx-orig-from<$mailx-orig-from> \
               mailx-orig-to<$mailx-orig-to> \
               mailx-orig-cc<$mailx-orig-cc> mailx-orig-bcc<$mailx-orig-bcc>
         }
         define t_occ {
            echo on-compose-cleanup, mailx-command<$mailx-command>
            set t_occ autocc=occ@exam.ple
            unalternates *
            alternates
            echo mailx-from<$mailx-from> mailx-sender<$mailx-sender>
            echo mailx-subject<$mailx-subject>
            echo mailx-to<$mailx-to> mailx-cc<$mailx-cc> mailx-bcc<$mailx-bcc>
            echo mailx-raw-to<$mailx-raw-to> mailx-raw-cc<$mailx-raw-cc> \
               mailx-raw-bcc<$mailx-raw-bcc>
            echo mailx-orig-from<$mailx-orig-from> \
               mailx-orig-to<$mailx-orig-to> \
               mailx-orig-cc<$mailx-orig-cc> mailx-orig-bcc<$mailx-orig-bcc>
         }
         wysh set on-compose-splice=t_ocs \
            on-compose-splice-shell="read ver;echo t_ocs-shell;\
               echo \"~t shell@exam.ple\"; echo \"~:set t_ocs_sh\"" \
            on-compose-enter=t_oce on-compose-leave=t_ocl \
            on-compose-cleanup=t_occ
      ' > ./.tnotes 2>&1
   check_ex0 3-estat
   ${cat} ./.tnotes >> "${MBOX}"
   check 3 - "${MBOX}" '3986011319 2437'

   # Reply, forward, resend, Resend

   ${rm} "${MBOX}"
   printf '#
      set from="f1@z"
      m t1@z
b1
!.
      set from="du <f2@z>" stealthmua=noagent
      m t2@z
b2
!.
      ' | ${MAILX} ${ARGS} -Smta=test://"$MBOX" -Snomemdebug -Sescape=! \
         > ./.tnotes 2>&1
   check_ex0 4-intro-estat

   printf '
      echo start: $? $! $^ERRNAME
      File %s
      echo File: $? $! $^ERRNAME;echo;echo
      reply 1
this is content of reply 1
!.
      echo reply 1: $? $! $^ERRNAME;echo;echo
      Reply 1 2
this is content of Reply 1 2
!.
      echo Reply 1 2: $? $! $^ERRNAME;echo;echo
      forward 1 fwdex@am.ple
this is content of forward 1
!.
      echo forward 1: $? $! $^ERRNAME;echo;echo
      wysh set forward-inject-head=$'"'"'-- \\
         forward (%%a)(%%d)(%%f)(%%i)(%%n)(%%r) --\\n'"'"'
      wysh set forward-inject-tail=$'"'"'-- \\
         end of forward (%%i) --\\n'"'"'
      forward 2 fwdex@am.ple
this is content of forward 2
!.
      echo forward 2: $? $! $^ERRNAME;echo;echo
      set showname
      forward 2 fwdex2@am.ple
this is content of forward 2, 2nd, with showname set
!.
      echo forward 2, 2nd: $? $! $^ERRNAME;echo;echo
      resend 1 2 resendex@am.ple
      echo resend 1 2: $? $! $^ERRNAME;echo;echo
      Resend 1 2 Resendex@am.ple
      echo Resend 1 2: $? $! $^ERRNAME;echo;echo
   ' "${MBOX}" |
   ${MAILX} ${ARGS} -Snomemdebug -Sescape=! -Sfullnames \
      -Smta=test://"$MBOX" \
      -X'
         define bail {
            echoerr "Failed: $1.  Bailing out"; echo "~x"; xit
         }
         define xerr {
            vput csop es substr "$1" 0 1
            if [ "$es" != 2 ]
               xcall bail "$2"
            end
         }
         define read_mline_res {
            read hl; wysh set len=$? es=$! en=$^ERRNAME;\
               echo mline_res:$len/$es/$^ERRNAME: $hl
            if [ $es -ne $^ERR-NONE ]
               xcall bail read_mline_res
            elif [ $len -ne 0 ]
               \xcall read_mline_res
            end
         }
         define work_hl {
            echo "~^header show $1"; read es;\
               call xerr $es "work_hl $1"; echo $1; call read_mline_res
            if [ $# -gt 1 ]
               shift
               xcall work_hl "$@"
            end
         }
         define t_ocs {
            read ver
            echo t_ocs version $ver
            echo "~^header list"; read hl; echo $hl;\
            echoerr the header list is $hl;\
               call xerr "$hl" "header list"
            eval vpospar set $hl
            shift
            xcall work_hl "$@"
            echoerr IT IS WRONG IF YOU SEE THIS
         }
         define t_oce {
            echo on-XY-enter, mailx-command<$mailx-command>
            set t_oce autobcc=oce@exam.ple
            echo mailx-from<$mailx-from> mailx-sender<$mailx-sender>
            echo mailx-subject<$mailx-subject>
            echo mailx-to<$mailx-to> mailx-cc<$mailx-cc> mailx-bcc<$mailx-bcc>
            echo mailx-raw-to<$mailx-raw-to> mailx-raw-cc<$mailx-raw-cc> \
               mailx-raw-bcc<$mailx-raw-bcc>
            echo mailx-orig-from<$mailx-orig-from> \
               mailx-orig-to<$mailx-orig-to> \
               mailx-orig-cc<$mailx-orig-cc> mailx-orig-bcc<$mailx-orig-bcc>
         }
         define t_ocl {
            echo on-XY-leave, mailx-command<$mailx-command>
            set t_ocl autocc=ocl@exam.ple
            echo mailx-from<$mailx-from> mailx-sender<$mailx-sender>
            echo mailx-subject<$mailx-subject>
            echo mailx-to<$mailx-to> mailx-cc<$mailx-cc> mailx-bcc<$mailx-bcc>
            echo mailx-raw-to<$mailx-raw-to> mailx-raw-cc<$mailx-raw-cc> \
               mailx-raw-bcc<$mailx-raw-bcc>
            echo mailx-orig-from<$mailx-orig-from> \
               mailx-orig-to<$mailx-orig-to> \
               mailx-orig-cc<$mailx-orig-cc> mailx-orig-bcc<$mailx-orig-bcc>
         }
         define t_occ {
            echo on-XY-cleanup, mailx-command<$mailx-command>
            set t_occ autocc=occ@exam.ple
            echo mailx-from<$mailx-from> mailx-sender<$mailx-sender>
            echo mailx-subject<$mailx-subject>
            echo mailx-to<$mailx-to> mailx-cc<$mailx-cc> mailx-bcc<$mailx-bcc>
            echo mailx-raw-to<$mailx-raw-to> mailx-raw-cc<$mailx-raw-cc> \
               mailx-raw-bcc<$mailx-raw-bcc>
            echo mailx-orig-from<$mailx-orig-from> \
               mailx-orig-to<$mailx-orig-to> \
               mailx-orig-cc<$mailx-orig-cc> mailx-orig-bcc<$mailx-orig-bcc>
         }
         wysh set on-compose-splice=t_ocs \
            on-compose-enter=t_oce on-compose-leave=t_ocl \
               on-compose-cleanup=t_occ \
            on-resend-enter=t_oce on-resend-cleanup=t_occ
      ' >> ./.tnotes 2>&1
   check_ex0 4-estat
   ${cat} ./.tnotes >> "${MBOX}"
   check 4 - "${MBOX}" '1818661134 11250'

   t_epilog "${@}"
} # }}}

t_mass_recipients() {
   t_prolog "${@}"

   if have_feat cmd-vexpr; then :; else
      t_echoskip '[!CMD_VEXPR]'
      t_epilog "${@}"
      return
   fi

   ${cat} <<'__EOT__' > ./.trc
   define bail {
      echoerr "Failed: $1.  Bailing out"; echo "~x"; xit
   }
   define ins_addr {
      wysh set nr=$1 hn=$2
      echo "~$hn $hn$nr@$hn"; echo '~:echo $?'; read es
      if [ "$es" -ne 0 ]
        xcall bail "ins_addr $hn 1-$nr"
      end
      vput vexpr nr + $nr 1
      if [ "$nr" -le "$maximum" ]
         xcall ins_addr $nr $hn
      end
   }
   define bld_alter {
      wysh set nr=$1 hn=$2
      alternates $hn$nr@$hn
      vput vexpr nr + $nr 2
      if [ "$nr" -le "$maximum" ]
         xcall bld_alter $nr $hn
      end
   }
   define t_ocs {
      read ver
      call ins_addr 1 t
      call ins_addr 1 c
      call ins_addr 1 b
   }
   define t_ocl {
      if [ "$t_remove" != '' ]
         call bld_alter 1 t
         call bld_alter 2 c
      end
   }
   set on-compose-splice=t_ocs on-compose-leave=t_ocl
__EOT__

   printf 'm this-goes@nowhere\nbody\n!.\n' |
   ${MAILX} ${ARGS} -Snomemdebug -Sescape=! -Sstealthmua=noagent \
      -X'source ./.trc' -Smta=test://"$MBOX" -Smaximum=${LOOPS_MAX} \
      >./.tall 2>&1
   check_ex0 1-estat
   ${cat} ./.tall >> "${MBOX}"
   if [ ${LOOPS_MAX} -eq ${LOOPS_BIG} ]; then
      check 1-${LOOPS_BIG} - "${MBOX}" '3835365533 51534'
   elif [ ${LOOPS_MAX} -eq ${LOOPS_SMALL} ]; then
      check 1-${LOOPS_SMALL} - "${MBOX}" '3647549277 4686'
   fi

   ${rm} "${MBOX}"
   printf 'm this-goes@nowhere\nbody\n!.\n' |
   ${MAILX} ${ARGS} -Snomemdebug -Sescape=! -Sstealthmua=noagent \
      -St_remove=1 -X'source ./.trc' -Smta=test://"$MBOX" \
      -Smaximum=${LOOPS_MAX} \
      >./.tall 2>&1
   check_ex0 2-estat
   ${cat} ./.tall >> "${MBOX}"
   if [ ${LOOPS_MAX} -eq ${LOOPS_BIG} ]; then
      check 2-${LOOPS_BIG} - "${MBOX}" '3768249992 34402'
   elif [ $LOOPS_MAX -eq ${LOOPS_SMALL} ]; then
      check 2-${LOOPS_SMALL} - "${MBOX}" '4042568441 3170'
   fi

   t_epilog "${@}"
}

t_lreply_futh_rth_etc() {
   t_prolog "${@}"

   ${cat} <<-_EOT > ./.tmbox
	From neverneverland  Sun Jul 23 13:46:25 2017
	Subject: Bugstop: five miles out 1
	Reply-To: mister originator2 <mr2@originator>, bugstop@five.miles.out
	From: mister originator <mr@originator>
	To: bugstop-commit@five.miles.out, laber@backe.eu
	Cc: is@a.list
	Mail-Followup-To: bugstop@five.miles.out, laber@backe.eu, is@a.list
	In-reply-to: <20170719111113.bkcMz%laber@backe.eu>
	Date: Wed, 19 Jul 2017 09:22:57 -0400
	Message-Id: <20170719132257.766AF781267@originator>
	Status: RO
	
	 >  |Sorry, I think I misunderstand something.  I would think that
	
	That's appalling.
	
	From neverneverland  Fri Jul  7 22:39:11 2017
	Subject: Bugstop: five miles out 2
	Reply-To: mister originator2<mr2@originator>,bugstop@five.miles.out,is@a.list
	Content-Transfer-Encoding: 7bit
	From: mister originator <mr@originator>
	To: bugstop-commit@five.miles.out
	Cc: is@a.list
	Message-ID: <149945963975.28888.6950788126957753723.reportbug@five.miles.out>
	Date: Fri, 07 Jul 2017 16:33:59 -0400
	Status: R
	
	capable of changing back.
	
	From neverneverland  Fri Jul  7 22:42:00 2017
	Subject: Bugstop: five miles out 3
	Reply-To: mister originator2 <mr2@originator>, bugstop@five.miles.out
	Content-Transfer-Encoding: 7bit
	From: mister originator <mr@originator>
	To: bugstop-commit@five.miles.out
	Cc: is@a.list
	Message-ID: <149945963975.28888.6950788126957753746.reportbug@five.miles.out>
	Date: Fri, 07 Jul 2017 16:33:59 -0400
	List-Post: <mailto:bugstop@five.miles.out>
	Status: R
	
	are you ready, boots?
	
	From neverneverland  Sat Aug 19 23:15:00 2017
	Subject: Bugstop: five miles out 4
	Reply-To: mister originator2 <mr2@originator>, bugstop@five.miles.out
	Content-Transfer-Encoding: 7bit
	From: mister originator <mr@originator>
	To: bugstop@five.miles.out
	Cc: is@a.list
	Message-ID: <149945963975.28888.6950788126qtewrqwer.reportbug@five.miles.out>
	Date: Fri, 07 Jul 2017 16:33:59 -0400
	List-Post: <mailto:bugstop@five.miles.out>
	Status: R
	
	are you ready, boots?
	_EOT

   #

   ${cat} <<-'_EOT' | ${MAILX} ${ARGS} -Sescape=! -Smta=test://"$MBOX" \
         -Rf ./.tmbox >> "${MBOX}" 2>&1
	define r {
	   wysh set m="This is text of \"reply ${1}."
	   reply 1 2 3
	!I m
	1".
	!.
	!I m
	2".
	!.
	!I m
	3".
	!.
	   echo -----After reply $1.1 - $1.3: $?/$^ERRNAME
	}
	define R {
	   wysh set m="This is text of \"Reply ${1}."
	   eval Reply $2
	!I m
	!I 2
	".
	!.
	   echo -----After Reply $1.$2: $?/$^ERRNAME
	}
	define _Lh {
	   read protover
	   echo '~I m'
	   echo '~I n'
	   echo '".'
	}
	define _Ls {
	   wysh set m="This is text of \"Lreply ${1}." on-compose-splice=_Lh n=$2
	   eval Lreply $2
	}
	define L {
	   # We need two indirections for this test: one for the case that Lreply
	   # fails because of missing recipients: we need to read EOF next, thus
	   # place this in _Ls last; and second for the succeeding cases EOF is
	   # not what these should read, so go over the backside and splice it in!
	   # (A shame we do not have redirection++ as a Bourne/K/POSIX shell!)
	   call _Ls "$@"
	   echo -----After Lreply $1.$2: $?/$^ERRNAME
	}
	define x {
	   localopts call-fixate yes
	   call r $1
	   call R $1 1; call R $1 2; call R $1 3; call R $1 4
	   call L $1 1; call L $1 2; call L $1 3
	}
	define tweak {
	   echo;echo '===== CHANGING === '"$*"' =====';echo
	   eval "$@"
	}
	#
	set from=laber@backe.eu
	mlist is@a.list
	call x 1
	call tweak set reply-to-honour
	call x 2
	call tweak set followup-to
	call x 3
	call tweak set followup-to-honour
	call x 4
	call tweak mlist bugstop@five.miles.out
	call x 5
	call tweak mlsubscribe bugstop@five.miles.out
	call x 6
	call tweak set recipients-in-cc
	call x 7
	# While here, test that *fullnames* works (also here)
	call tweak set fullnames
	reply 1
	This message should have *fullnames* in the header.
	!.
	# Revert
	call tweak unmlsubscribe bugstop@five.miles.out';' \
		set followup-to-add-cc nofullnames
	call x 8
	call tweak mlsubscribe bugstop@five.miles.out
	call x 9
	_EOT

   check_ex0 1-estat
   if have_feat uistrings; then
      check 1 - "${MBOX}" '2954356452 39829'
   else
      t_echoskip '1:[!UISTRINGS]'
   fi

   ##

   ${cat} <<-_EOT > ./.tmbox
	From tom@i-i.example Thu Oct 26 03:15:55 2017
	Date: Wed, 25 Oct 2017 21:15:46 -0400
	From: tom <tom@i-i.example>
	To: Steffen Nurpmeso <steffen@sdaoden.eu>
	Cc: tom <tom@i-i.example>
	Subject: Re: xxxx yyyyyyyy configure does not really like a missing zzzzz
	Message-ID: <20171026011546.GA11643@i-i.example>
	Reply-To: tom@i-i.example
	References: <20171025214601.T2pNd%steffen@sdaoden.eu>
	In-Reply-To: <20171025214601.T2pNd%steffen@sdaoden.eu>
	Status: R
	
	The report's useful :-)
	_EOT

   # Let us test In-Reply-To: removal starts a new thread..
   # This needs adjustment of *stealthmua*
   argadd='-Sstealthmua=noagent -Shostname'

   ${rm} "${MBOX}"
   printf 'reply 1\nthread\n!.\n' |
      ${MAILX} ${ARGS} -Sescape=! -Smta=test://"$MBOX" -Sreply-to-honour \
         ${argadd} -Rf ./.tmbox > .tall 2>&1
   check 2 0 "${MBOX}" '841868335 433'
   check 3 - .tall '4294967295 0'

   printf 'reply 1\nnew <- thread!\n!||%s -e "%s"\n!.\n' \
         "${sed}" '/^In-Reply-To:/d' |
      ${MAILX} ${ARGS} -Sescape=! -Smta=test://"$MBOX" -Sreply-to-honour \
         ${argadd} -Rf "${MBOX}" > .tall 2>&1
   check 4 0 "${MBOX}" '3136957908 771'
   check 5 - .tall '4294967295 0'

   printf 'reply 2\nold <- new <- thread!\n!.\n' |
      ${MAILX} ${ARGS} -Sescape=! -Smta=test://"$MBOX" -Sreply-to-honour \
         ${argadd} -Rf "${MBOX}" > .tall 2>&1
   check 6 0 "${MBOX}" '3036449053 1231'
   check 7 - .tall '4294967295 0'

   printf 'reply 3\nnew <- old <- new <- thread!\n!|| %s -e "%s"\n!.\n' \
         "${sed}" '/^In-Reply-To:/d' |
      ${MAILX} ${ARGS} -Sescape=! -Smta=test://"$MBOX" -Sreply-to-honour \
         ${argadd} -Rf "${MBOX}" > .tall 2>&1
   check 8 0 "${MBOX}" '2069841383 1583'
   check 9 - .tall '4294967295 0'

   # And follow-up testing whether changing In-Reply-To: to - starts a new
   # thread with only the message being replied-to.

   printf 'reply 1\nthread with only one ref!\n!||%s -e "%s"\n!.\n' \
         "${sed}" 's/^In-Reply-To:.*$/In-Reply-To:-/' |
      ${MAILX} ${ARGS} -Sescape=! -Smta=test://"$MBOX" -Sreply-to-honour \
         ${argadd} -Rf "${MBOX}" > .tall 2>&1
   check 10 0 "${MBOX}" '3155846378 2047'
   check 11 - .tall '4294967295 0'

   t_epilog "${@}"
}

t_pipe_handlers() {
   t_prolog "${@}"

   if have_feat cmd-vexpr; then :; else
      t_echoskip '[!CMD_VEXPR]'
      t_epilog "${@}"
      return
   fi

   # "Test for" [d6f316a] (Gavin Troy)
   printf "m ${MBOX}\n~s subject1\nEmail body\n~.\nfi ${MBOX}\np\nx\n" |
   ${MAILX} ${ARGS} ${ADDARG_UNI} -Spipe-text/plain="?* ${cat}" > "${BODY}"
   check 1 0 "${MBOX}" '3942990636 118'
   check 2 - "${BODY}" '3951695530 170'

   ${rm} "${MBOX}"
   printf "m %s\n~s subject2\n~@%s\nBody2\n~.\nFi %s\nmimeview\nx\n" \
         "${MBOX}" "${TOPDIR}snailmail.jpg" "${MBOX}" |
      ${MAILX} ${ARGS} ${ADDARG_UNI} \
         -S 'pipe-text/plain=?' \
         -S 'pipe-image/jpeg=?=&?'\
'trap \"'"${rm}"' -f '\ '\\"${MAILX_FILENAME_TEMPORARY}\\"\" EXIT;'\
'trap \"trap \\\"\\\" INT QUIT TERM; exit 1\" INT QUIT TERM;'\
'{ echo C=$MAILX_CONTENT;'\
'echo C-E=$MAILX_CONTENT_EVIDENCE;'\
'echo E-B-U=$MAILX_EXTERNAL_BODY_URL;'\
'echo F=$MAILX_FILENAME;'\
'echo F-G=not testable MAILX_FILENAME_GENERATED;'\
'echo F-T=not testable MAILX_FILENAME_TEMPORARY;'\
''"${cksum}"' < \"${MAILX_FILENAME_TEMPORARY}\" |'\
''"${sed}"' -e "s/[ 	]\{1,\}/ /g"; } > ./.tax 2>&1;'"${mv}"' ./.tax ./.tay' \
            > "${BODY}" 2>&1
   check 3 0 "${MBOX}" '1933681911 13435'
   check 4 - "${BODY}" '2275717813 469'
   check 4-hdl - ./.tay '144517347 151' async

   # Keep $MBOX..
   if [ -z "${ln}" ]; then
      t_echoskip '5:[ln(1) not found]'
   else
      # Let us fill in tmpfile, test auto-deletion
      printf 'Fi %s\nmimeview\nvput vexpr v file-stat .t.one-link\n'\
'eval wysh set $v;echo should be $st_nlink link\nx\n' "${MBOX}" |
         ${MAILX} ${ARGS} ${ADDARG_UNI} \
            -S 'pipe-text/plain=?' \
            -S 'pipe-image/jpeg=?=++?'\
'echo C=$MAILX_CONTENT;'\
'echo C-E=$MAILX_CONTENT_EVIDENCE;'\
'echo E-B-U=$MAILX_EXTERNAL_BODY_URL;'\
'echo F=$MAILX_FILENAME;'\
'echo F-G=not testable MAILX_FILENAME_GENERATED;'\
'echo F-T=not testable MAILX_FILENAME_TEMPORARY;'\
"${ln}"' -f $MAILX_FILENAME_TEMPORARY .t.one-link;'\
''"${cksum}"' < \"${MAILX_FILENAME_TEMPORARY}\" |'\
''"${sed}"' -e "s/[ 	]\{1,\}/ /g"' \
               > "${BODY}" 2>&1
      check 5 0 "${BODY}" '79260249 637'

      # Fill in ourselfs, test auto-deletion
      printf 'Fi %s\nmimeview\nvput vexpr v file-stat .t.one-link\n'\
'eval wysh set $v;echo should be $st_nlink link\nx\n' "${MBOX}" |
         ${MAILX} ${ARGS} ${ADDARG_UNI} \
            -S 'pipe-text/plain=?' \
            -S 'pipe-image/jpeg=?++?'\
"${cat}"' > $MAILX_FILENAME_TEMPORARY;'\
'echo C=$MAILX_CONTENT;'\
'echo C-E=$MAILX_CONTENT_EVIDENCE;'\
'echo E-B-U=$MAILX_EXTERNAL_BODY_URL;'\
'echo F=$MAILX_FILENAME;'\
'echo F-G=not testable MAILX_FILENAME_GENERATED;'\
'echo F-T=not testable MAILX_FILENAME_TEMPORARY;'\
''"${cksum}"' < \"${MAILX_FILENAME_TEMPORARY}\" |'\
''"${sed}"' -e "s/[ 	]\{1,\}/ /g"' \
               > "${BODY}" 2>&1
      check 6 0 "${BODY}" '79260249 637'

      # And the same, via copiousoutput (fake)
      printf 'Fi %s\np\nvput vexpr v file-stat .t.one-link\n'\
'eval wysh set $v;echo should be $st_nlink link\nx\n' "${MBOX}" |
         ${MAILX} ${ARGS} ${ADDARG_UNI} \
            -S 'pipe-text/plain=?' \
            -S 'pipe-image/jpeg=?*++?'\
"${cat}"' > $MAILX_FILENAME_TEMPORARY;'\
'echo C=$MAILX_CONTENT;'\
'echo C-E=$MAILX_CONTENT_EVIDENCE;'\
'echo E-B-U=$MAILX_EXTERNAL_BODY_URL;'\
'echo F=$MAILX_FILENAME;'\
'echo F-G=not testable MAILX_FILENAME_GENERATED;'\
'echo F-T=not testable MAILX_FILENAME_TEMPORARY;'\
"${ln}"' -f $MAILX_FILENAME_TEMPORARY .t.one-link;'\
''"${cksum}"' < \"${MAILX_FILENAME_TEMPORARY}\" |'\
''"${sed}"' -e "s/[ 	]\{1,\}/ /g"' \
               > "${BODY}" 2>&1
      check 7 0 "${BODY}" '686281717 676'
   fi

   t_epilog "${@}"
}
# }}}

# Unclassified rest {{{
t_top() {
   t_prolog "${@}"

   t__gen_msg subject top1 to 1 from 1 cc 1 body 'body1-1
body1-2

body1-3
body1-4


body1-5
'     > "${MBOX}"
   t__gen_msg subject top2 to 1 from 1 cc 1 body 'body2-1
body2-2


body2-3


body2-4
body2-5
'     >> "${MBOX}"

   ${MAILX} ${ARGS} -Rf -Y '#
\top 1
\echo --- $?/$^ERRNAME, 1; \set toplines=10
\top 1
\echo --- $?/$^ERRNAME, 2; \set toplines=5
\headerpick top retain subject # For top
\headerpick type retain to subject # For Top
\top 1
\echo --- $?/$^ERRNAME, 3; \set topsqueeze
\top 1 2
\echo --- $?/$^ERRNAME, 4
\Top 1
\echo --- $?/$^ERRNAME, 5
#  ' "${MBOX}" > ./.tall 2>&1
   check 1 0 ./.tall '2556125754 705'

   t_epilog "${@}"
}

t_s_mime() {
   t_prolog "${@}"

   if have_feat smime; then :; else
      t_echoskip '[!SMIME]'
      t_epilog "${@}"
      return
   fi

   ${cat} <<-_EOT > ./.t.conf
		[req]
		default_bits = 1024
		default_keyfile = keyfile.pem
		distinguished_name = req_distinguished_name
		attributes = req_attributes
		prompt = no
		output_password =

		[req_distinguished_name]
		C = GB
		ST = Over the
		L = rainbow
		O = S-nail
		OU = S-nail.smime
		CN = S-nail.test
		emailAddress = test@localhost

		[req_attributes]
		challengePassword =
	_EOT
   openssl req -x509 -nodes -days 3650 -config ./.t.conf \
      -newkey rsa:1024 -keyout ./.tkey.pem -out ./.tcert.pem >>${ERR} 2>&1
   check_ex0 0
   ${cat} ./.tkey.pem ./.tcert.pem > ./.tpair.pem

   # Sign/verify
   echo bla | ${MAILX} ${ARGS} \
      -Ssmime-sign -Ssmime-sign-cert=./.tpair.pem -Sfrom=test@localhost \
      -Ssmime-sign-digest=sha1 \
      -s 'S/MIME test' ./.VERIFY
   check_ex0 1-estat
   ${awk} '
      BEGIN{ skip=0 }
      /^Content-Description: /{ skip = 2; print; next }
      /^$/{ if(skip) --skip }
      { if(!skip) print }
   ' \
      < ./.VERIFY > "${MBOX}"
   check 1 - "${MBOX}" '335634014 644'

   printf 'verify\nx\n' |
   ${MAILX} ${ARGS} -Ssmime-ca-file=./.tcert.pem -Serrexit \
      -R -f ./.VERIFY >>${ERR} 2>&1
   check_ex0 2

   openssl smime -verify -CAfile ./.tcert.pem -in ./.VERIFY >>${ERR} 2>&1
   check_ex0 3

   # (signing +) encryption / decryption

   echo bla |
   ${MAILX} ${ARGS} \
      -Smta=test://./.ENCRYPT \
      -Ssmime-force-encryption -Ssmime-encrypt-recei@ver.com=./.tpair.pem \
      -Ssmime-sign-digest=sha1 \
      -Ssmime-sign -Ssmime-sign-cert=./.tpair.pem -Sfrom=test@localhost \
      -s 'S/MIME test' recei@ver.com
   check_ex0 4-estat
   ${sed} -e '/^$/,$d' < ./.ENCRYPT > "${MBOX}"
   check 4 - "${MBOX}" '2359655411 336'

   printf 'decrypt ./.DECRYPT\nfi ./.DECRYPT\nverify\nx\n' |
   ${MAILX} ${ARGS} \
      -Smta=test://./.ENCRYPT \
      -Ssmime-ca-file=./.tcert.pem \
      -Ssmime-sign-cert=./.tpair.pem \
      -Serrexit -R -f ./.ENCRYPT >>${ERR} 2>&1
   check_ex0 5-estat
   ${awk} '
      BEGIN{ skip=0 }
      /^Content-Description: /{ skip = 2; print; next }
      /^$/{ if(skip) --skip }
      { if(!skip) print }
   ' \
      < ./.DECRYPT > "${MBOX}"
   check 5 - "${MBOX}" '2602978204 940'

   (openssl smime -decrypt -inkey ./.tkey.pem -in ./.ENCRYPT |
         openssl smime -verify -CAfile ./.tcert.pem) >>${ERR} 2>&1
   check_ex0 6

   ${rm} ./.ENCRYPT
   echo bla | ${MAILX} ${ARGS} \
      -Smta=test://./.ENCRYPT \
      -Ssmime-force-encryption -Ssmime-encrypt-recei@ver.com=./.tpair.pem \
      -Sfrom=test@localhost \
      -s 'S/MIME test' recei@ver.com
   check_ex0 7-estat
   ${sed} -e '/^$/,$d' < ./.ENCRYPT > "${MBOX}"
   check 7 - "${MBOX}" '2359655411 336'

   ${rm} ./.DECRYPT
   printf 'decrypt ./.DECRYPT\nx\n' | ${MAILX} ${ARGS} \
      -Smta=test://./.ENCRYPT \
      -Ssmime-sign-cert=./.tpair.pem \
      -Serrexit -R -f ./.ENCRYPT >>${ERR} 2>&1
   check 8 0 ./.DECRYPT '2453471323 431'

   openssl smime -decrypt -inkey ./.tkey.pem -in ./.ENCRYPT >>${ERR} 2>&1
   check_ex0 9

   t_epilog "${@}"
}
# }}}

# xxx Note: t_z() was the first test (series) written.  Today many
# xxx aspects are (better) covered by other tests above, some are not.
# xxx At some future date and time, convert the last remains not covered
# xxx elsewhere to a real t_* test and drop it
t_z() {
   t_prolog "${@}"

   # Test for [260e19d] (Juergen Daubert)
   echo body | ${MAILX} ${ARGS} "${MBOX}"
   check 4 0 "${MBOX}" '2948857341 94'

   # "Test for" [c299c45] (Peter Hofmann) TODO shouldn't end up QP-encoded?
   ${rm} "${MBOX}"
   ${awk} 'BEGIN{
      for(i = 0; i < 10000; ++i)
         printf "\xC3\xBC"
         #printf "\xF0\x90\x87\x90"
      }' | ${MAILX} ${ARGS} ${ADDARG_UNI} -s TestSubject "${MBOX}"
   check 7 0 "${MBOX}" '1707496413 61812'

   t_epilog "${@}"
}

# Test support {{{
t__gen_msg() {
   t___header() {
      printf '%s: ' ${1}
      case "${3}" in
      [0-9]*)
         ___hi=1
         while [ ${___hi} -le ${3} ]; do
            [ ${___hi} -gt 1 ] && printf ', '
            printf '%s%s <%s%s@exam.ple>' ${1} ${___hi} ${2} ${___hi}
            ___hi=`add ${___hi} 1`
         done
         ;;
      *)
         printf '%s' "${3}"
         ;;
      esac
      printf '\n'
   }

   printf 'From reproducible_build Wed Oct  2 01:50:07 1996
Date: Wed, 02 Oct 1996 01:50:07 +0000
'

   body=Body
   while [ ${#} -ge 2 ]; do
      case "${1}" in
      from) t___header From from "${2}";;
      to) t___header To to "${2}";;
      cc) t___header Cc cc "${2}";;
      bcc) t___header Bcc bcc "${2}";;
      subject) printf 'Subject: %s\n' "${2}";;
      body) body="${2}";;
      esac
      shift 2
   done

   printf '\n%s\n\n' "${body}"
}

t__x1_msg() {
   ${cat} <<-_EOT
	From neverneverland  Sun Jul 23 13:46:25 2017
	Subject: Bugstop: five miles out 1
	Reply-To: mister originator1 <mr1@originator>
	From: mister originator1 <mr1@originator>
	To: bugstop-commit@five.miles.out
	Cc: is1@a.list
	In-reply-to: <20170719111113.bkcMz%laber1@backe.eu>
	Date: Wed, 19 Jul 2017 09:22:57 -0400
	Message-Id: <20170719132257.766AF781267-1@originator>
	Mail-Followup-To: bugstop@five.miles.out, laber@backe.eu, is@a.list
	Status: RO
	
	That's appalling, I.
	
	_EOT
}

t__x2_msg() {
   ${cat} <<-_EOT
	From neverneverland  Sun Jul 23 13:47:25 2017
	Subject: Bugstop: five miles out 2
	Reply-To: mister originator2 <mr2@originator>
	From: mister originator2 <mr2@originator>
	To: bugstop-commit@five.miles.out
	Cc: is2@a.list
	In-reply-to: <20170719111113.bkcMz%laber2@backe.eu>
	Date: Wed, 19 Jul 2017 09:23:57 -0400
	Message-Id: <20170719132257.766AF781267-2@originator>
	Status: RO
	
	That's appalling, II.
	
	_EOT
}

t__x3_msg() {
   ${cat} <<-_EOT
	From neverneverland  Sun Jul 23 13:48:25 2017
	Subject: Bugstop: five miles out 3
	Reply-To: mister originator3 <mr3@originator>
	From: mister originator3 <mr3@originator>
	To: bugstop-commit@five.miles.out
	Cc: is3@a.list
	In-reply-to: <20170719111113.bkcMz%laber3@backe.eu>
	Date: Wed, 19 Jul 2017 09:24:57 -0400
	Message-Id: <20170719132257.766AF781267-3@originator>
	Status: RO
	
	That's appalling, III.
	
	_EOT
}

t__put_subject() {
   # MIME encoding (QP) stress message subject
   printf 'Äbrä  Kä?dä=brö 	 Fü?di=bus? '\
'adadaddsssssssddddddddddddddddddddd'\
'ddddddddddddddddddddddddddddddddddd'\
'ddddddddddddddddddddddddddddddddddd'\
'dddddddddddddddddddd Hallelulja? Od'\
'er?? eeeeeeeeeeeeeeeeeeeeeeeeeeeeee'\
'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'\
'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee f'\
'fffffffffffffffffffffffffffffffffff'\
'fffffffffffffffffffff ggggggggggggg'\
'ggggggggggggggggggggggggggggggggggg'\
'ggggggggggggggggggggggggggggggggggg'\
'ggggggggggggggggggggggggggggggggggg'\
'gggggggggggggggg'
}

t__put_body() {
   # MIME encoding (QP) stress message body
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
"QP am Zeilenende über soft-nl hinweg\n"\
"Ich bin eine ziemlich lange, steile, scharfe Zeile mit Unix Zeilenende."\
"ö123\n"\
"Ich bin eine ziemlich lange, steile, scharfe Zeile mit Unix Zeilenende."\
"1ö23\n"\
"Ich bin eine ziemlich lange, steile, scharfe Zeile mit Unix Zeilenende."\
"12ö3\n"\
"Ich bin eine ziemlich lange, steile, scharfe Zeile mit Unix Zeilenende."\
"123ö\n"\
"=VIER = EQUAL SIGNS=ON A LINE=\n"\
" \n"\
"Die letzte Zeile war ein Leerschritt.\n"\
' '
}
# }}}

# cc_all_configs() {{{
# Test all configs TODO doesn't cover all *combinations*, stupid!
cc_all_configs() {
   if [ ${MAXJOBS} -gt 1 ]; then
      MAXJOBS='-j '${MAXJOBS}
   else
      MAXJOBS=
   fi

   < ${CONF} ${awk} '
      BEGIN{
         ALWAYS = "OPT_AUTOCC=1 OPT_AMALGAMATION=1"
         NOTME["OPT_AUTOCC_STACKPROT"] = 1
         NOTME["OPT_ALWAYS_UNICODE_LOCALE"] = 1
         NOTME["OPT_CROSS_BUILD"] = 1
         NOTME["OPT_AUTOCC"] = 1
         NOTME["OPT_AMALGAMATION"] = 1
         NOTME["OPT_DEBUG"] = 1
         NOTME["OPT_DEVEL"] = 1
         NOTME["OPT_ASAN_ADDRESS"] = 1
         NOTME["OPT_ASAN_MEMORY"] = 1
         NOTME["OPT_NOMEMDBG"] = 1

         #OPTVALS
         OPTNO = 0

         MULCHOICE["OPT_IDNA"] = "VAL_IDNA"
            MULVALS["VAL_IDNA"] = 1

         #VALKEYS[0] = "VAL_RANDOM"
            VALVALS["VAL_RANDOM"] = 1
         VALNO = 0
      }
      /^[ 	]*OPT_/{
         sub(/^[ 	]*/, "")
         # This bails for UnixWare 7.1.4 awk(1), but preceeding = with \
         # does not seem to be a compliant escape for =
         #sub(/=.*$/, "")
         $1 = substr($1, 1, index($1, "=") - 1)
         if(!NOTME[$1])
            OPTVALS[OPTNO++] = $1
         next
      }
      /^[ 	]*VAL_/{
         sub(/^[ 	]*/, "")
         val = substr($0, index($0, "=") + 1)
         if(val ~ /^"/){
            val = substr(val, 2)
            val = substr(val, 1, length(val) - 1)
         }
         $1 = substr($1, 1, index($1, "=") - 1)
         if(MULVALS[$1])
            MULVALS[$1] = val
         else if(VALVALS[$1]){
            VALKEYS[VALNO++] = $1
            VALVALS[$1] = val
         }
         next
      }
      function onepass(addons){
         a_onepass__worker(addons, "1", "0")
         a_onepass__worker(addons, "0", "1")
      }
      function a_onepass__worker(addons, b0, b1){
         # Doing this completely sequentially and not doing make distclean in
         # between runs should effectively result in lesser compilations.
         # It is completely dumb nonetheless... TODO
         for(ono = 0; ono < OPTNO; ++ono){
            myconf = mula = ""
            for(i = 0; i < ono; ++i){
               myconf = myconf " " OPTVALS[i] "=" b0 " "
               if(b0 == "1"){
                  j = MULCHOICE[OPTVALS[i]]
                  if(j){
                     if(i + 1 == ono)
                        mula = j
                     else
                        myconf = myconf " " MULCHOICE[OPTVALS[i]] "=any "
                  }
               }
            }
            for(i = ono; i < OPTNO; ++i){
               myconf = myconf " " OPTVALS[i] "=" b1 " "
               if(b1 == "1"){
                  j = MULCHOICE[OPTVALS[i]]
                  if(j){
                     if(i + 1 == OPTNO)
                        mula = j;
                     else
                        myconf = myconf " " MULCHOICE[OPTVALS[i]] "=any "
                  }
               }
            }

            for(i in VALKEYS)
               myconf = VALKEYS[i] "=any " myconf

            myconf = myconf " " ALWAYS " " addons

            if(mula == "")
               print myconf
            else{
               i = split(MULVALS[mula], ia)
               j = "any"
               while(i >= 1){
                  j = ia[i--] " " j
                  print mula "=\"" j "\" " myconf
               }
            }
         }
      }
      END{
         # We cannot test NULL because of missing UI strings, which will end
         # up with different checksums
         print "CONFIG=NULLI OPT_AUTOCC=1"
            for(i in VALKEYS){
               j = split(VALVALS[VALKEYS[i]], ia)
               k = "any"
               while(j >= 1){
                  k = ia[j--] " " k
                  print VALKEYS[i] "=\"" k "\" CONFIG=NULLI OPT_AUTOCC=1"
               }
            }
         print "CONFIG=MINIMAL OPT_AUTOCC=1"
         print "CONFIG=NETSEND OPT_AUTOCC=1"
         print "CONFIG=MAXIMAL OPT_AUTOCC=1"
            for(i in VALKEYS){
               j = split(VALVALS[VALKEYS[i]], ia)
               k = "any"
               while(j >= 1){
                  k = ia[j--] " " k
                  print VALKEYS[i] "=\"" k "\" CONFIG=MAXIMAL OPT_AUTOCC=1"
               }
            }
         print "CONFIG=DEVEL OPT_AUTOCC=1"
         print "CONFIG=ODEVEL OPT_AUTOCC=1"

         print split_here

         onepass("OPT_DEBUG=1")
         onepass("")
      }
   ' | while read c; do
      if [ "$c" = split_here ]; then
         printf 'Predefined configs done, now OPT_ combinations\n'
         printf 'Predefined configs done, now OPT_ combinations\n' >&2
         ${SHELL} -c "cd ../ && ${MAKE} distclean"
         continue
      fi
      [ -f mk-config.h ] && ${cp} mk-config.h .ccac.h
      printf "\n\n##########\n${MAKE} config $c\n"
      printf "\n\n##########\n${MAKE} config $c\n" >&2
      ${SHELL} -c "cd .. && ${MAKE} config ${c}"
      if [ -f .ccac.h ] && ${cmp} mk-config.h .ccac.h; then
         printf 'Skipping after config, nothing changed\n'
         printf 'Skipping after config, nothing changed\n' >&2
         continue
      fi
      ${SHELL} -c "cd ../ && ${MAKE} ${MAXJOBS} build test"
   done
   ${rm} -f .ccac.h
   cd .. && ${MAKE} distclean
}
# }}}

ssec=$SECONDS
if [ -z "${CHECK_ONLY}${RUN_TEST}" ]; then
   jobs_max
   cc_all_configs
else
   if have_feat debug; then
      if have_feat devel; then
         JOBSYNC=1
         DUMPERR=y
         ARGS="${ARGS} -Smemdebug"
      fi
   elif have_feat devel; then
      LOOPS_MAX=${LOOPS_BIG}
   fi
   color_init

   if [ -z "${RUN_TEST}" ] || [ ${#} -eq 0 ]; then
      jobs_max
      printf 'Will do up to %s tests in parallel, with a %s second timeout\n' \
         ${MAXJOBS} ${JOBWAIT}
      jobreaper_start
      t_all
      jobreaper_stop
   else
      MAXJOBS=1
      #jobreaper_start
      while [ ${#} -gt 0 ]; do
         jspawn ${1}
         shift
      done
      #jobreaper_stop
   fi

fi
esec=$SECONDS

printf '%u tests: %s%u ok%s, %s%u failure(s)%s.  %s%u test(s) skipped%s\n' \
   "${TESTS_PERFORMED}" "${COLOR_OK_ON}" "${TESTS_OK}" "${COLOR_OK_OFF}" \
   "${COLOR_ERR_ON}" "${TESTS_FAILED}" "${COLOR_ERR_OFF}" \
   "${COLOR_WARN_ON}" "${TESTS_SKIPPED}" "${COLOR_WARN_OFF}"
if [ -n "${ssec}" ] && [ -n "${esec}" ]; then
   ( echo 'Elapsed seconds: '`$awk 'BEGIN{print '"${esec}"' - '"${ssec}"'}'` )
fi

exit ${ESTAT}
# s-sh-mode