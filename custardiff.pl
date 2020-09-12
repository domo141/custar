#!/usr/bin/perl
# -*- mode: cperl; cperl-indent-level: 4 -*-
# $ custardiff.pl $
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#	Copyright (c) 2020 Tomi Ollila
#	    All rights reserved
#
# Created: Fri 11 Sep 2020 21:24:10 EEST too
# Last modified: Sat 12 Sep 2020 19:56:03 +0300 too

# SPDX-License-Identifier: BSD 2-Clause "Simplified" License

# hint: LC_ALL=C sh -c './custar.sh archive.tar.gz 2020-02-02 *'
# for archiving with shell wildcard (w/ custar.pl . gets close)

use 5.8.1;
use strict;
use warnings;

# arg scanning here

die "Usage: $0 [wip add options] tarchive1 tarchive2\n"
  unless @ARGV == 2;

die "'$ARGV[0]': no such file\n" unless -f $ARGV[0];
die "'$ARGV[1]': no such file\n" unless -f $ARGV[1];

my %zc = ( '.tar' => '', '.tar.bzip2' => 'bzip2',
	   '.tar.gz' => 'gzip', '.tgz' => 'gzip',
	   '.tar.xz' => 'xz', '.txz' => 'xz',
	   '.tar.lz' => 'lzip', '.tlz' => 'lzip' );

sub fmz($$) {
    $_[1] =~ /\S((?:[.]tar)?[.]?[.]\w+)$/;
    die "Unknown format in '$_[1]': not in (fn" . join(', fn', sort keys %zc) .
  ")\n" unless defined $1 and defined ($_[0] = $zc{$1});
}
my ($zc0, $zc1);
fmz $zc0, $ARGV[0];
fmz $zc1, $ARGV[1];

sub opn($$$) {
    if ($_[1]) { open $_[0], '-|', $_[1], '-dc', $_[2] or die $! }
    else       { open $_[0], '<', $_[2] or die $! }
}
my ($fh0, $fh1);
opn $fh0, $zc0, $ARGV[0];
opn $fh1, $zc1, $ARGV[1];

sub unpack_ustar_hdr($$) {
    my @l = unpack('A100 A8 A8 A8 A12 A12 A8 A1 A100 a8 A32 A32 A8 A8 A155',
		   $_[0]);
    if ($l[14]) {
	$l[14] =~ s:/*$:/:;
	$l[0] = $l[14] . $l[0];
    }
    die "$_[1]: '$l[9]': not 'ustar{\\0}00'\n" unless $l[9] eq "ustar\00000";
    return ($l[0], $l[1]+0, $l[2]+0, $l[3]+0, oct($l[4]), oct($l[5]),
	    $l[7], $l[8], $l[10], $l[11], $l[12]+0, $l[13]+0, 1);
}

my (@h0, @h1);

sub chkdiffer($$) {
    if ($h0[$_[0]] ne $h1[$_[0]]) {
	print "$h0[0]: $_[1] differ ($h0[$_[0]] != $h1[$_[0]])\n";
	return 1
    }
    return 0
}

# return for filename / file content ....
sub hdrdiffer() {
    my $cmp = 1;
    chkdiffer  1, "file mode (perms)";
    chkdiffer  2, "user id";
    chkdiffer  3, "group id";
    chkdiffer  4, "file size" or $cmp = 0; # no point compare, but visual diff
    chkdiffer  5, "mod. time";
    chkdiffer  6, "file type" or $cmp = -1; # -1: no point ever diff
    chkdiffer  7, "link name" or $cmp = -1;
    chkdiffer  8, "user name";
    chkdiffer  9, "group name";
    chkdiffer 10, "device major";
    chkdiffer 11, "device minor";
    return -1 if $h0[6] != '0';
    return $cmp;
}

my ($pname0, $pname1) = ('', '');
my $z512 = "\0" x 512;

sub read_hdr($$$) {
    my $buf;
    while (1) {
	my $l = read $_[0], $buf, 512;
	die $! unless defined $l;
	if ($l == 512) {
	    next if $buf eq $z512;
	    last;
	}
	die "fixme" unless $l == 0;
	return ("\377\377", 0, 0, 0, 0, 0, '9', '', '', '', 0, 0, 0)
    }
    my @h = unpack_ustar_hdr $buf, $_[2];
    my $n = $h[0];
    die "order!: $_[2]: $_[1] > $n\n" unless $_[1] le $n;
    $_[1] = $n;
    return @h;
}

# btw: check/test if sysread is faster...
sub consume($$) {
    my $left = $_[1]; # could have used alias to list, but...
    $left = ($left + 511) & ~511;
    my $buf;
    while ($left > 1024 * 1024) {
	# xxx check read length (readfully?, check other perl code)
	read $_[0], $buf, 1024 * 1024;
	$left -= 1024 * 1024
    }
    if ($left > 0) {
	# ditto
	read $_[0], $buf, $left;
    }
}

sub compare() {
    my $left = ($h0[4] + 511) & ~511;
    my ($buf0, $buf1);
    my $diff = 0;
    while ($left > 1024 * 1024) {
	# xxx check read length (readfully?, check other perl code)
	read $fh0, $buf0, 1024 * 1024;
	read $fh1, $buf1, 1024 * 1024;
	$diff = $buf0 cmp $buf1 unless $diff;
    }
    if ($left > 0) {
	# ditto
	read $fh0, $buf0, $left;
	read $fh1, $buf1, $left;
	$diff = $buf0 cmp $buf1 unless $diff;
    }
    return $diff
}

T: while (1) {
    @h0 = read_hdr $fh0, $pname0, $ARGV[0];
    @h1 = read_hdr $fh1, $pname1, $ARGV[1];
    last unless $h0[12] and $h1[12];

    while (1) {
	my $n = $h0[0] cmp $h1[0];
	if ($n == 0) {
	    my $w = hdrdiffer;
	    if ($w <= 0) { # 0 and -1: diffing not implemented yet
		consume $fh0, $h0[4];
		consume $fh1, $h1[4];
	    }
	    else {
		print "$h0[0]: file content differ\n" if compare;
	    }
	    next T
	}
	if ($n < 0) {
	    # later, collect to list to be printed at the end
	    print "$h0[0]: only in $ARGV[0]\n"; # not in argv[1]
	    consume $fh0, $h0[4];
	    @h0 = read_hdr $fh0, $pname0, $ARGV[0];
	}
	else {
	    # later, collect to list to be printed at the end
	    print "$h1[0]: only in $ARGV[1]\n"; # not in argv[0]
	    consume $fh1, $h1[4];
	    @h1 = read_hdr $fh1, $pname1, $ARGV[1];
	}
    }
    last
}

close $fh0; # or warn $!;
close $fh1; # or warn $!;
