
Create tar archives - ustar format - reproducibly
=================================================

Accompanied with related utilities.

All programs give usage information when run without arguments.

The program `custar.pl`, when given same arguments where *mtime*
is absolute time, creates exactly same archive when same content
is available in file system.

The program `custar.sh` does the same with almost identical arguments,
and uses (new enough) GNU tar to do the archiving. In many cases
the created archive is exactly same as with `custar.pl`.

I bet other tar archivers (e.g. `bsdtar`) can do the same, I just haven't
tried such a case. (`custar.sh` is mainly used as output comparison tool).

custar.pl is BSD (2-clause) licensed (pure) perl program, which can be
(easily?) edited should a need arise.

The tar format these utilities know, POSIX 1003.1-1988 ("Unix Standard TAR")
has some limitations (link targets max len 100 octets, file/dir pathname
max len 255 octets (when subdir length matches 155 octets)) -- usually
these limits are far enough but be prepared...


Other archive-creating commands
-------------------------------

### cpaxgtar.sh

Whenever ustar format is not enough, the Pax Interchange Format is used
to store the information. Whenever there is no need, cpaxgtar.sh usually
produces byte-exact arhives compared to custar.pl and custar.sh

Diff to custar.sh is --format=posix, some --pax-options (and --mode...).

### tarxzin.pl

Reads filenames to be archive from standard input, filters (removes if any)
and transforms (filenames) of those.
The (remaining, transformed) filenames are sorted, and the files accessed
using their original name are archived to xz-compressed ustar-formatted file.

The sorting of the filenames is none *after* filename transformations.


Related utilities
-----------------

These don't touch the input archive.

### custarlist.pl

Lists ustar archive contents, the subset of file information chosen
by `flags` argument.

### custardiff.pl

List differences of two ustar archives. This has reasonably good usage,
may help use of `custarlist.pl` too (in addition to reading the code).

### custarfilter.pl

Keep, remove, and rename files from/in a ustar archive, writing modified
archive to stdout (failing if stdout (fd 1) is referring to a tty).

### custarsums.pl

Calculate md5, sha1 or sha256 checksums of the files in the ustar archive.

### gnutarsums.sh

custarsums.pl, while being fast and produces nice output [sum  filename],
does not know much beyond ustar. gnutarsums.sh, while being slow and
produces somewhat unformatted output, can handle all tar formats.
gnutarsums.sh forks shell which execs the checksum program for every
file in the archive.
