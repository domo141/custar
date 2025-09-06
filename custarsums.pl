#!/usr/bin/perl
# -*- mode: cperl; cperl-indent-level: 4 -*-
# $ custarsums.pl $
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#	Copyright (c) 2022 Tomi Ollila
#	    All rights reserved
#
# Created: Wed 23 Apr 2025 21:23:43 +0300 too
# Last modified: Fri 05 Sep 2025 12:27:18 +0300 too

# SPDX-License-Identifier: BSD 2-Clause "Simplified" License

use 5.8.1;
use strict;
use warnings;

use Digest;

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

while (@ARGV) {
    shift, last if $ARGV[0] eq '--';
    $_ = $ARGV[0];
    needarg, xseekarg(shift), next if $_ eq '-x';
    xseekarg($1), next if /^-x[,=](.*)/;
    last;
}
die "$0: '$ARGV[2]...': too many arguments\n" if @ARGV > 2;
$0 =~ s:.*/::,
  die "\nUsage: $0 [-x seek,ffmt] (md5|sha1|sha256) ustarchive\n\n"
  unless @ARGV > 1;

my $dgst = do {
    my %h = qw/md5 MD5 sha1 SHA-1 sha256 SHA-256/; # compile- or runtime ?
    my $v = $h{$ARGV[0]};
    die "\n'$ARGV[0]' not any of '", (join "', '",keys %h), "'\n\n"
      unless defined $v;
    $v
};

my $tarf = $ARGV[1];

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
my $zc;
fmz $zc, $tarf, $cf;

my $zdgst = Digest->new($dgst)->hexdigest;
my $zdash = '-' x length $zdgst;

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
    unless ($hdr[9] eq "ustar\00000") {
	die "$_[1]: '$hdr[9]': not 'ustar{\\0}00' (magic + version\n"
	  unless ($hdr[9] eq "ustar  \0");
	print "GNU Tar header, info may be incorrect\n"
    }
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
    my $left = oct($hdr[4]);
    if ($left == 0) {
	my $z = $hdr[7] eq '0'? $zdgst: $zdash;
	print "$z  $n\n";
	next
    }
    my $ctx = Digest->new($dgst);
    while ($left > 1024 * 1024) {
	# xxx check read length (readfully?, check other perl code)
	read $fh, $buf, 1024 * 1024;
	$ctx->add($buf);
	$left -= 1024 * 1024
    }
    if ($left > 0) {
	# ditto
	read $fh, $buf, $left;
	$ctx->add($buf);
    }
    $left = $left & 511;
    if ($left) {
	read $fh, $buf, 512 - $left;
    }
    print $ctx->hexdigest, "  $n\n";
}

close $fh; # or warn $!;
