#!/bin/sh
#
# $ gnutarsums.sh $
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#	Copyright (c) 2025 Tomi Ollila
#	    All rights reserved
#
# Created: Fri 05 Sep 2025 21:29:22 EEST too
# Last modified: Thu 25 Sep 2025 22:16:31 +0300 too

# SPDX-License-Identifier: BSD 2-Clause "Simplified" License

# A slow (and output unformatted) version of custarsums. Can handle
# all tar formats (which gnu tar knows).

case ${BASH_VERSION-} in *.*) set -o posix; shopt -s xpg_echo; esac
case ${ZSH_VERSION-} in *.*) emulate ksh; esac

set -euf  # hint: (z|ba|da|'')sh -x thisfile [args] to trace execution

die () { printf '%s\n' '' "$@" ''; exit 1; } >&2

# [-x seek,ffmt] tba (if anyone cared, ever)

test $# -ge 2 ||
 die "Usage: ${0##*/} (md5|sha1|sha256) tarfile [patterns]" '' \
   'For convenience (avoid shell wildcard expansion, as absolute paths rare)',\
   "leading '/' is replaced with '*', '//' '*/' and '///' '/', in patterns."

test -f "$2" || die "'$2': no such file"

command -v gtar >/dev/null || die "'gtar': command not found"

csum=
case $1 in md5)
	if command -v md5sum; then csum=md5sum
	elif command -v md5; then csum=md5
	fi
	;; sha1)
	if command -v sha1sum; then csum=sha1sum
	elif command -v sha1; then csum=sha1
	fi
	;; sha256)
	if command -v sha256sum; then csum=sha256sum
	elif command -v sha256; then csum=sha256
	fi
	;; *) die "'$1': unhandled digest command"
esac >/dev/null

test "$csum" || die "Cannot find command to do $1"

tf=$2
shift 2
for arg
do
	case $arg in ///*) arg=${arg#??}
		  ;; /*) arg=*${arg#?}
	esac
	shift; set -- "$@" "$arg"
done

exec gtar --to-command='printf "%s  " "$TAR_FILENAME"; exec '"$csum" \
     -xf "$tf" "$@"


# Local variables:
# mode: shell-script
# sh-basic-offset: 8
# tab-width: 8
# End:
# vi: set sw=8 ts=8
