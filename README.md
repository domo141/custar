
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
tried such a case. (`custar.sh` is mainly used as output comparison tool)

custar.pl is BSD (2-clause) licensed (pure) perl program, which can be
(easily?) edited should a need arise.

The tar format these utilities know, POSIX 1003.1-1988 ("Unix Standard TAR")
has some limitations (link targets max len 100 octets, file/dir pathname
max len 255 octets (when subdir length matches 155 octets)) -- usually
these limits are far enough but be prepared...

Related utilities
-----------------

### custarlist.pl

Lists ustar archive contents, the subset of file information chosen
by `flags` argument.

### custardiff.pl

List differences of two ustar archives. This has reasonably good usage,
may help use of `custarlist.pl` too (in addition to reading the code).
