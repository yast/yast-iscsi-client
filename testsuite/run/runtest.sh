#! /bin/bash

# Run test on one ycp file
# Michal Svec <msvec@suse.cz>
#
# $1 = script.ycp
# $2 = stdout
# $3 = stderr
#
# These arguments may be preceded by options that will be passed to y2base
#
# $Id: runtest.sh 20547 2004-12-14 12:55:49Z mvidner $

while [ $# -gt 3 ]; do
    OPTIONS="$OPTIONS $1"
    shift
done

# but now y2base does not support them :-(
if [ "$OPTIONS" ]; then
    echo "Options not supported yet, discarding '$OPTIONS'" >&2
    OPTIONS=""
fi

unset LANG
unset LC_CTYPE
unset LC_NUMERIC
unset LC_TIME
unset LC_COLLATE
unset LC_MONETARY
unset LC_MESSAGES
unset LC_PAPER
unset LC_NAME
unset LC_ADDRESS
unset LC_TELEPHONE
unset LC_MEASUREMENT
unset LC_IDENTIFICATION
unset LC_ALL

unset Y2DEBUG
unset Y2DEBUGALL
# export Y2DEBUG=1
# export Y2DEBUGALL=1
export Y2ALLGLOBAL=1

ybindir=`pkg-config  --variable=ybindir  yast2-core`
yast2dir=`pkg-config --variable=yast2dir yast2-core`
Y2BASE=$ybindir/y2base
logconf="$yast2dir/data/testsuite/log.conf"

if [ ! -f "$logconf" ]; then
  logconf="../skel/log.conf"
fi

DUMMY_LOG_STRING="LOGTHIS_SECRET_314 "

files="$(grep '^[/*[:space:]]*testedfiles:' "$1"|sed 's/.*testedfiles:[[:space:]]*//g')"
if [ "$files" ]; then
  echo "$files" >> testsuite.log
  regex="[ /](testsuite\.ycp|Testsuite\.ycp|$(echo "$files"|sed 's|\.|\\.|g'|sed 's| |\||g')):"
fi
echo "$regex" >> testsuite.log

parse() {
  file="`mktemp /tmp/yast2-test.XXXXXX`"
  cat >"$file"
  if [ -z "$Y2TESTSUITE" ]; then
    # errors are OK if they come from YCP (or Perl, #41448),
    # mark them for output
    sed1="s/ <[2-5]> [^ ]\+ \[\(YCP\|Perl\)\] \([^ ]\+\) / <0> host [YCP] \2 ${DUMMY_LOG_STRING}Log	/"
    # leave only essential info
    sed2="s/^.*$DUMMY_LOG_STRING//g"
    ycp="\[YCP\].*$DUMMY_LOG_STRING"
    components="(agent-dummy|YCP)"
    cat "$file" | sed "$sed1" | grep -E "<[012]>[^]]*$components.*$regex.*$DUMMY_LOG_STRING" | sed "$sed2" # | cut -d" " -f7-
    # Y2PMrc: #38235
    cat "$file" | grep "<[345]>" | grep -v "\[\(YCP\|Perl\|Y2PMrc\)\]" >&2
  else
    echo "Y2TESTSUITE set to \"$Y2TESTSUITE\""
    echo
    cat "$file"
  fi
  rm -f "$file"
}

( $Y2BASE -l - -c "$logconf" $OPTIONS "$1" testsuite 2>&1 ) | parse >"$2" 2>"$3"

retcode="$PIPESTATUS"
if [ "$retcode" -gt 0 ]; then
  if [ "$retcode" -ge 128 ]; then
    sig=$[$retcode-128]
    echo -ne "\nCommand terminated on signal '$sig'"
    echo -e '!\n'
  else
    echo -e "\nReturn code: '$retcode'.\n"
  fi
fi

exit "$retcode"
# EOF
