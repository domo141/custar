#!/usr/bin/perl
# -*- mode: cperl; cperl-indent-level: 4 -*-
# $ custargrep.pl $
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#	Copyright (c) 2022 Tomi Ollila
#	    All rights reserved
#
# Created: Fri 04 Nov 2022 19:58:45 +0200 too (custarfilter)
# Created: Fri 06 Mar 2026 10:49:00 +0200 too (custargrep)
# Last modified: Sun 08 Mar 2026 13:11:17 +0200 too

# SPDX-License-Identifier: BSD 2-Clause "Simplified" License

use 5.8.1;
use strict;
use warnings;

my ($seek, $cf, $fixed, $lnrs) = (0, undef, 0, 0);

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
	die "'$_': not in (", join(', ',sort keys %zo),"\n" unless defined $cf
    }
}

sub needarg() { die "No value for '$_'\n" unless @ARGV }

my @pats;

while (@ARGV) {
    shift, last if $ARGV[0] eq '--';
    $_ = $ARGV[0];
    last unless /^-/;
    needarg, push(@pats, shift), shift, next if $_ eq '-e';
    needarg, xseekarg(shift), shift, next if $_ eq '-x';
    xseekarg($1), shift, next if /^-x[,=](.*)/;
    if (tr/-Fn//cd) {
	tr/-Fn//d;
	die "$ARGV[0]: unknown options: '$_'\n"
    }
    $fixed = 1 if /F/;
    $lnrs = 1 if /n/;
    shift
}
$0 =~ s:.*/::,
die "\nUsage: $0 [-x seek,ffmt] [-nF] [-e pattern...] [--] [pattern] ustarchives

" unless @ARGV;

unless (@pats) {
    push @pats, shift;
    die "No input ustar files\n" unless (@ARGV);
    die "Only one tarfile when -x is used\n" if $seek && @ARGV > 1
}

my %zc = ( '.tar' => '', '.tar.bzip2' => 'bzip2',
	   '.tar.gz' => 'gzip', '.tgz' => 'gzip',
	   '.tar.xz' => 'xz', '.txz' => 'xz',
	   '.tar.lz' => 'lzip', '.tlz' => 'lzip',
	   '.tar.zst' => 'zstd', '.tzst' => 'zstd' );
my $tarfn;

sub fmz() {
    $tarfn =~ /\S((?:[.]tar)?[.]?[.]\w+)$/;
    my $zc;
    warn "Unknown format in '$tarfn': not in (fn"
      . join(', fn', sort keys %zc) . ")\n"
      unless defined $1 and defined ($zc = $zc{$1});
    $zc
}

sub warn0(@) { warn "@_\n"; 0 }

sub opn($$$) {
    if ($_[1]) {
	# with decompressor
	if ($_[2] == 0) {
	    # no seek
	    open $_[0], '-|', $_[1], '-dc', $tarfn or return warn0 $!;
	    return 1
	}
	# decompressor and seek
	# temp stdin replace. simplest!
	open my $oldin, '<&', \*STDIN or return warn0 $!;
	open STDIN, '<', $tarfn or return warn0 $!;
	seek STDIN, $_[2], 0;
	open $_[0], '-|', $_[1], '-dc' or return warn0 $!;
	open STDIN, '<&', $oldin or return warn0 $!
    }
    else {
	# plain tar
	open $_[0], '<', $tarfn or return warn0 $!;
	seek $_[0], $_[2], 0 if $_[2] > 0
    }
    1
}

my @hdr;
sub unpack_ustar_hdr($) {
    @hdr = unpack('A100 A8 A8 A8 A12 A12 a8 A1 A100 a8 A32 A32 A8 A8 A155',
		  $_[0]);
    #print $hdr[9], "\n";
    # xxx could support old tar
    #die "$tarfn: '$hdr[9]': not 'ustar{\\0}00'\n"
    #  unless $hdr[9] eq "ustar\00000";
    my $n;
    if ($hdr[14]) {
	$n = $hdr[14];
	$n =~ s:/*$:/:;
	$n .= $hdr[0]
    }
    else {
	$n = $hdr[0]
    }
    return $n;
}

my $z512 = "\0" x 512;
my $buf;

sub read_hdr($) {
    while (1) {
	my $l = read $_[0], $buf, 512;
	die $! unless defined $l;
	if ($l == 512) {
	    next if $buf eq $z512;
	    last
	}
	die "fixme: $l" unless $l == 0;
	return ''
    }
    return unpack_ustar_hdr $buf;
}

unless ($fixed) { $_ = qr/$_/ for (@pats) }

for (@ARGV) {
    $tarfn = $_;
    warn("'$tarfn': no such file\n"), next unless -f $tarfn;

    my $zc = defined $cf? $cf: fmz;
    next unless defined $zc;

    my $fh; opn $fh, $zc, $seek or next;

    my $fsiz;
    while (1) {
	my $name = read_hdr $fh;
	last unless $name;

	my $left = oct($hdr[4]);
	next if $left == 0;
	$fsiz = $left;

	read $fh, $buf, ($left > 65536? 65536: $left);
	#read $fh, $buf, ($left > 2048? 2048: $left);
	$left -= length $buf;

	my ($fnn, $ln) = ($name, 0);
	my $binary = ((index $buf, "\0") >= 0);
	while (1) {
	    my $ll;
	    if ($binary) {
		if ($left) {
		    $ll = substr $buf, -1024;
		    substr($buf, -1024) = ''
		} else {
		    $ll = ''
		}
		if ($fnn) { for my $pat (@pats) {
		    if ($fixed) {
			if (index($buf, $pat) >= 0) {
			    print "$name: binary file matches\n";
			    $fnn = '';
			    last
			}
		    }
		    else {
			if ($buf =~ /$pat/) {
			    print "$name: binary file matches\n";
			    $fnn = '';
			    last
			}
		    }
		}}
	    }
	    else {
		my @lines = split /\n/, $buf;
		$ll = do {
		    if ($left > 0) {
			my $l = pop @lines;
			length $l > 65536? '': $l # long line unlikely
		    }
		    else { '' }
		};
		if ($fixed) {
		    for (@lines) {
			$ln++;
			for my $pat (@pats) {
			    if (index($_, $pat) >= 0) {
				$fnn = "$name:$ln" if $lnrs;
				print $fnn,':',$_,"\n";
				last
			    }
			}
		    }
		}
		else {
		    for (@lines) {
			$ln++;
			for my $pat (@pats) {
			    if (/$pat/) {
				$fnn = "$name:$ln" if $lnrs;
				print $fnn,':',$_,"\n";
				last
			    }
			}
		    }
		}
	    }
	    last unless $left > 0;
	    $buf = $ll;
	    my $l = read $fh, $buf, ($left > 65536? 65536: $left), length $buf;
	    warn("unexpected eof/error\n"), last unless defined $l and $l > 0;
	    $left -= $l
	}
	$fsiz = $fsiz & 511;
	read $fh, $buf, 512 - $fsiz if $fsiz
    }
    close $fh or warn $!
}
