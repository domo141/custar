#!/usr/bin/perl
# -*- mode: cperl; cperl-indent-level: 4 -*-
# $ custarfilter.pl $
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#	Copyright (c) 2022 Tomi Ollila
#	    All rights reserved
#
# Created: Fri 04 Nov 2022 19:58:45 +0200 too
# Last modified: Thu 29 Dec 2022 20:02:28 +0200 too

# SPDX-License-Identifier: BSD 2-Clause "Simplified" License

use 5.10.1; # for \K
use strict;
use warnings;

my ($seek, $cf) = (0, undef);

my %zo = ( 'tar', => '', 'bzip2' => 'bzip2',
	   'gz' => 'gzip', 'gzip' => 'gzip', 'tgz' => 'gzip',
	   'xz' => 'xz', 'txz' => 'xz',
	   'lz' => 'lzip', 'tlz' => 'lzip',
	   'zst' => 'zstd', 'tzst' => 'zstd' );

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

my (@mats, @subs);

while (@ARGV) {
    shift, last if $ARGV[0] eq '--';
    $_ = $ARGV[0];
    push (@mats, [qr($1), 1]), shift, next if /^[+](.*)[+]$/;
    push (@mats, [qr($1), 0]), shift, next if /^[-](.*)[-]$/;
    push (@subs, $_), shift, next if /s(.).+\1.*\1$/;
    needarg, xseekarg(shift), next if $_ eq '-x';
    xseekarg($1), next if /^-x[,=](.*)/;
    last;
}
die "$0: '$ARGV[0]': too many arguments\n" if @ARGV > 1;

die "\nUsage: $0 [-x seek,ffmt] ([-rem-] [+keep+] [s:re:repl:]...) ustarchive

filenames matching regeps between -...- are removed from archive
filenames matching regeps between +...+ are kept in archive
- first match decides fate -- file kept if no match

s:re:regexp: modifies filename ( s/re/repl/, s(re)(repl), s're'repl'... )
- eval's in perl code: no silly input (noone to run silly code)

" unless @ARGV;

my $tarf = $ARGV[0];

die "'$tarf': no such file\n" unless -f $tarf;

my %zc = ( '.tar' => '', '.tar.bzip2' => 'bzip2',
	   '.tar.gz' => 'gzip', '.tgz' => 'gzip',
	   '.tar.xz' => 'xz', '.txz' => 'xz',
	   '.tar.lz' => 'lzip', '.tlz' => 'lzip',
	   '.tar.zst' => 'zstd', '.tzst' => 'zstd' );

sub fmz($$$) {
    $_[0] = $_[2], return if defined $_[2];
    $_[1] =~ /\S((?:[.]tar)?[.]?[.]\w+)$/;
    die "Unknown format in '$_[1]': not in (fn"
      . join(', fn', sort keys %zc) . ")\n"
      unless defined $1 and defined ($_[0] = $zc{$1});
}
my  $zc;
fmz $zc, $tarf, $cf;

#foreach (@mats) { print "$_->[1] : $_->[0]\n"; }
#foreach (@subs) { print "$_\n"; }
#__END__

die "stdout (fd 1) refers to a terminal (tty)\n" if -t 1;

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

my @hdr;
sub unpack_ustar_hdr($$) {
    @hdr = unpack('A100 A8 A8 A8 A12 A12 a8 A1 A100 a8 A32 A32 A8 A8 A155',
		  $_[0]);
    die "$_[1]: '$hdr[9]': not 'ustar{\\0}00'\n"
      unless $hdr[9] eq "ustar\00000";
    my $n;
    if ($hdr[14]) {
	$n = $hdr[14];
	$n =~ s:/*$:/:;
	$n .= $hdr[0]
    }
    else {
	$n = $hdr[0];
    }
    return $n;
}

my $z512 = "\0" x 512;
my $buf;

sub read_hdr($$) {
    while (1) {
	my $l = read $_[0], $buf, 512;
	die $! unless defined $l;
	if ($l == 512) {
	    next if $buf eq $z512;
	    last;
	}
	die "fixme" unless $l == 0;
	return '';
    }
    return unpack_ustar_hdr $buf, $_[1];
}

sub fate($)
{
    my $fn = $_[0];
    foreach (@mats) { return $_->[1] if $fn =~ /$_->[0]/ }
    return 1 # default keep
}

sub _tarlisted_nampfx($$) {
    local $_ = $_[0];
    my $n = '';
    while (s:/([^/]+)$::) {
	$n = $n? "$n/$1": $1;
	last if length $n > 100;
	next if length $_ > 155;
	$_[1] = $_;
	return $n
    }
    die "'$_[0]': does not fit in ustar header file name fields\n"
}

while (1) {
    my $n = read_hdr $fh, $tarf;
    last unless $n;

    my $fate = fate $n;
    my @o;
    push @o, $fate;
    my $left = oct($hdr[4]);
    unless ($fate) {
	# skip file #
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
	next;
    }
    my $nmod;
    if ($fate) {
	# FIXME: symbolic/hard links
	$nmod = $n;
	eval "\$n =~ $_" foreach (@subs);
	$nmod = ($nmod eq $n)? 0: 1
    }
    push @o, $n;
    push @o, '=>', $hdr[8] if $hdr[7] == 1; # show hard link target
    push @o, '->', $hdr[8] if $hdr[7] == 2; # show sym. link target
    warn "@o\n" if @o;

    if ($nmod) {
	my $name = $_[0];
	my $pfx;
	if (length($n) > 100) {
	    $n = _tarlisted_nampfx $n, $pfx
	}
	else { $pfx = '' }
	$hdr[0] = pack('a100', $n);
	$hdr[14] = pack('a155', $pfx);
	$hdr[6] = '        ';
	$buf = pack('a100 a8 a8 a8 a12 a12 a8 a1 a100 a8 a32 a32 a8 a8 a155 x12'
		    ,@hdr);
	my $sum = 0;
	$sum = $sum + ord $_ foreach (split //, $buf);
	$hdr[6] = sprintf "%06o\0 ", $sum;
	$buf = pack('a100 a8 a8 a8 a12 a12 a8 a1 a100 a8 a32 a32 a8 a8 a155 x12'
		    ,@hdr);
    }
    print $buf;

    while ($left > 1024 * 1024) {
	# xxx check read length (readfully?, check other perl code)
	read $fh, $buf, 1024 * 1024;
	print $buf;
	$left -= 1024 * 1024
    }
    if ($left > 0) {
	# ditto
	read $fh, $buf, $left;
	print $buf
    }
    $left = $left & 511;
    if ($left) {
	read $fh, $buf, 512 - $left;
	print $buf
    }
}

# end file, 2 zero 512 byte blocks (cannot know how to sync w/ 10240

print $z512 . $z512;

close $fh; # or warn $!;
