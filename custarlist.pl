#!/usr/bin/perl
# -*- mode: cperl; cperl-indent-level: 4 -*-
# $ custarlist.pl $
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#	Copyright (c) 2020 Tomi Ollila
#	    All rights reserved
#
# Created: Sat 24 Oct 2020 17:20:10 EEST too
# Last modified: Tue 10 Nov 2020 21:51:38 +0200 too

# SPDX-License-Identifier: BSD 2-Clause "Simplified" License

use 5.14.1; # for tr/.../.../r (used in two (2) lines)
use strict;
use warnings;

my @res;
my ($seek, $cf) = (0, undef);

my %zo = ( 'tar', => '', 'bzip2' => 'bzip2',
	   'gz' => 'gzip', 'gzip' => 'gzip',
	   'xz' => 'xz', '.txz' => 'xz',
	   'lz' => 'lzip', '.tlz' => 'lzip' );

sub xseekarg($)
{
    foreach (split /,/, $_[0]) {
	$seek = $1, next if /^(\d+)$/;
	next unless $_;
	$cf = $zo{$_};
	die "'$_': not in (", join(', ',sort keys %zo),"\n" unless defined $cf;
    }
}

sub needarg() { die "No value for '$_'\n" unless @ARGV }

my $tarf;
my $care;

while (@ARGV) {
    shift, last if $ARGV[0] eq '--';
    unless ($ARGV[0] =~ /^-/) {
	$care = $ARGV[0], shift, next unless defined $care;
	$tarf = $ARGV[0], shift, next unless defined $tarf;
	die "$0: '$ARGV[0]': too many arguments\n"
    }
    $_ = shift;

    needarg, xseekarg(shift), next if $_ eq '-x';
    xseekarg($1), next if $_ =~ /^-x[,=](.*)/;

    die "'$_': unknown option\n"
}
die "Usage: $0 [-x seek,ffmt] flags tarchive1\n" unless defined $tarf;

die "'$tarf': no such file\n" unless -f $tarf;

my $care_f = ($care =~ tr/f//d); # file type flag
my $care_p = ($care =~ tr/p//d); # perm
my $care_u = ($care =~ tr/u//d); # user
my $care_g = ($care =~ tr/g//d); # group
my $care_s = ($care =~ tr/s//d); # size / devmajor/minor
my $care_t = ($care =~ tr/t//d); # (mod.) time
my $care_n = ($care =~ tr/n//d); # file name
my $care_h = ($care =~ tr/h//d); # hard link
my $care_l = ($care =~ tr/l//d); # sym. link
my $care_o = ($care =~ tr/o//d); # sort order
$care =~ tr/-//d;
die "'$care': unknown interest flags\n" if $care;

my %zc = ( '.tar' => '', '.tar.bzip2' => 'bzip2',
	   '.tar.gz' => 'gzip', '.tgz' => 'gzip',
	   '.tar.xz' => 'xz', '.txz' => 'xz',
	   '.tar.lz' => 'lzip', '.tlz' => 'lzip' );

sub fmz($$$) {
    $_[0] = $_[2], return if defined $_[2];
    $_[1] =~ /\S((?:[.]tar)?[.]?[.]\w+)$/;
    die "Unknown format in '$_[1]': not in (fn" . join(', fn', sort keys %zc) .
  ")\n" unless defined $1 and defined ($_[0] = $zc{$1});
}
my  $zc;
fmz $zc, $tarf, $cf;

sub opn($$$$) {
    if ($_[1]) {
	# with decompressor
	if ($_[2] == 0) {
	    # no seek
	    open $_[0], '-|', $_[1], '-dc', $_[3] or die $!;
	    return
	}
	# decompressor and seek
	# temp stdin replace. simplest!
	open my $oldin, '<&', \*STDIN or die $!;
	open STDIN, '<', $_[3] or die $!;
	seek STDIN, $_[2], 0;
	open $_[0], '-|', $_[1], '-dc' or die $!;
	open STDIN, '<&', $oldin or die $!;
    }
    else {
	# plain tar
	open $_[0], '<', $_[3] or die $!;
	seek $_[0], $_[2], 0 if $_[2] > 0
    }
}
my  $fh;
opn $fh, $zc, $seek, $tarf;

sub unpack_ustar_hdr($$) {
    my @l = unpack('A100 A8 A8 A8 A12 A12 A8 A1 A100 a8 A32 A32 A8 A8 A155',
		   $_[0]);
    if ($l[14]) {
	$l[14] =~ s:/*$:/:;
	$l[0] = $l[14] . $l[0];
    }
    xforms $l[0] if @res;
    die "$_[1]: '$l[9]': not 'ustar{\\0}00'\n" unless $l[9] eq "ustar\00000";
    return ($l[0], $l[1]+0, $l[2]+0, $l[3]+0, oct($l[4]), oct($l[5]),
	    $l[7], $l[8], $l[10], $l[11], $l[12]+0, $l[13]+0, 1);
}

my @h;
my $z512 = "\0" x 512;
my $buf;

sub read_hdr($$$) {
    while (1) {
	my $l = read $_[0], $buf, 512;
	die $! unless defined $l;
	if ($l == 512) {
	    next if $buf eq $z512;
	    last;
	}
	die "fixme" unless $l == 0;
	@h = ("\377\377", 0, 0, 0, 0, 0, '9', '', '', '', 0, 0, 0);
	return
    }
    @h = unpack_ustar_hdr $buf, $_[2];
    my $n = ($h[0] =~ tr[/]/\0/r);
    if ($_[1] ge $n and $care_o) {
	print "-- ^ -- file name sort order discontinuity -- v --\n";
	unless ($care_n) {
	    $_[1] =~ tr/\0/\//;
	    my $o = ($n =~ tr/\0/\//r);
	    print "\\-- $_[1] <=> $o\n"
	}
    }
    $_[1] = $n;
    return @h;
}

sub dt($)
{
    my @d = gmtime $_[0];
    sprintf "%d-%02d-%02d %02d:%02d:%02d",
      $d[5] + 1900, $d[4]+1, $d[3], $d[2], $d[1], $d[0]
}
my @ftypes = qw/ f h l c b d p /;
my $pname = '';

while (1) {
    read_hdr $fh, $pname, $tarf;
    last unless $h[12];
    my @o;
    push @o, $ftypes[$h[6]] if $care_f; # file type (from flag)
    push @o, sprintf('%03s', $h[1]) if $care_p; # perm
    push @o, sprintf('%6s', $h[8]) if $care_u;  # user
    push @o, sprintf('%6s', $h[9]) if $care_g;  # group
    if ($care_s) {
	if ($h[6] == 3 or $h[6] == 4) {
	    my ($ma, $mi) = (oct($h[10]), oct($h[11]));
	    push @o, sprintf('%8s', "$ma,$mi"); # devmajor/minor
	}
	else {
	    push @o, sprintf('%8d', $h[4]) # size
	}
    }
    push @o, dt $h[5] if $care_t; # mod.time
    push @o, $h[0] if $care_n;  # file name
    push @o, '=>', $h[7] if $care_h and $h[6] == 1; # show hard link target
    push @o, '->', $h[7] if $care_l and $h[6] == 2; # show sym. link target
    print "@o\n" if @o;

    my $left = $h[4];
    while ($left > 1024 * 1024) {
	# xxx check read length (readfully?, check other perl code)
	read $fh, $buf, 1024 * 1024;
	$left -= 1024 * 1024
    }
    if ($left > 0) {
	# ditto
	read $fh, $buf, $left;
    }
    $left = $left & 511;
    read $fh, $buf, 512 - $left if $left;
}

close $fh; # or warn $!;
