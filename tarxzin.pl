#!/usr/bin/perl
# -*- mode: cperl; cperl-indent-level: 4 -*-
# $ tarxzin.pl $
#
# Author: Tomi Ollila -- too ät iki piste fi
#
# Created: Fri 21 Aug 2020 18:18:04 EEST too (custar.pl)
# Created: Thu 03 Apr 2025 23:10:17 EEST too (tarxzin.pl)
# Last modified: Mon 05 May 2025 21:36:18 +0300 too

# SPDX-License-Identifier: BSD 2-Clause "Simplified" License

# this reads filenames (of existing files) from stdin, archives
# those to an xz-compressed ustar formatted file.

# the following 4 arguments are required:
# 1. prefix (dir) to be added to all target paths
# 2. mtime as seconds from epoch
# 3. close archive by adding 1024 zero bytes if arg nonzero
# 4. perl code block to be eval'd as function body - to transform $_,
#    or return 0/undef to skip the current file in $_
# 5... optionally args to be used in that codeblock, left in @ARGV
#      (there are some cases where this is convenient)
# sample:
# find . -type f | ./tarxzin.pl tst 1734562890 1024 '
#    return if /[.]txz$/; s/..//; s/$ARGV[0]/watnot/' tarxzin > tst.txz

# after transformations the transformed filenames are sorted in ASCII
# order and then the files (accessed via their original names)
# are added to the archive.

# should one want to change compression that is very easy; should
# one want to add dirs or block/char devs, one can restore relevant
# code from custar.pl -- there is reason those are removed, but if
# not good enough for cases one may have...

# this code is not using record size of 10240 - it is  just simpler
# to end with two 512 byte blocks - in rare cases - when one writes
# uncompressed archive to some (obscure?) media that could cause
# problems (?) - anyway too unlikely to be currently handled here.

# one may want not to end output with 1024 bytes of zeroes, so
# that more content can be added later. xz(1) can  extract multiple
# xz-compressed parts from a file - one can then just execute
#   head -c 1024 /dev/zero | xz -0
# to create 80-byte xz block and # cat(1)enate that to the end of
# the created (unfinalized) archive (xz -1 ... xz -9 gave 84-bytes).

# hard links to files (already) collected, inodes in %hash is easy,
# so stored.
# symlinks are harder, so cross-directory (symlink target with '/'s)
# are followed and the file contents of symlink targets are stored.
# symlinks with targets without '/'s are stored as symlinks

use 5.8.1;
use strict;
use warnings;

die "\nUsage: $0 prefix mtime close filter-transform-codeblock [ftcb-args]\n\n"
  unless @ARGV >= 4;

$SIG{__DIE__} = sub { $0 =~ s,.*/,,; warn $0, ': ', @_; exit 1 };

die "stdin is on a tty\n" if -t 0;
die "stdout is on a tty\n" if -t 1;

# tune your checks...
die "'$ARGV[0]' starts with '.'\n" if ord $ARGV[0] == 46;
die "'$ARGV[0]' contains '/'s\n" if $ARGV[0] =~ m:/:;

my $pfx = shift;
my $gmtime = (shift) + 0;
my $close = (shift) + 0;

sub filter_transform;
eval 'sub filter_transform {' . (shift) . '; 1 }';
die $@ if $@;

my @files;
while (<STDIN>) {
    chomp;
    die "'$_': no such file\n" unless -f $_;
    my $f = $_;
    next unless filter_transform;
    tr[/][\0];
    push @files, [ $_, $f ]
}

unless (@files) {
    my $m = $close? ' - creating empty archive': '';
    warn "no files to be archived$m\n"
};
@files = sort { $a->[0] cmp $b->[0] } @files;

# declare tarlisted.pm functions #

#sub _tarlisted_mkhdr($$$$$$$$$$$$);
sub _tarlisted_mkhdr_rp($$$$$$);
sub _tarlisted_writehdr($);
sub _tarlisted_xsyswrite($);

sub tarlisted_open($@); # name following optional compression program & args
sub tarlisted_close0();
sub tarlisted_close();

tarlisted_open '-', 'xz', '-9';

#use Data::Dumper;

my $dotcount = 0;
my %links;
L: foreach (@files) {
    my $f = $_->[1];
    my @st = lstat $f;
    warn("lstat '$f' failed: $!\n"), next unless @st;
    $_->[0] =~ tr[\0][/];
    my $n = $pfx.'/'.$_->[0];
    if (-l _) {
	my $l = readlink $f;
	unless ($l =~ m,/,) {
	    # storing symlink when no path components
	    _tarlisted_writehdr
	      _tarlisted_mkhdr_rp $n, 0777, 0, $gmtime, '2', $l;
	    next
	}
	# else stat(2)ing -- the file content behind symlink stored
	@st = stat $f;
	warn("stat '$f' failed: $!\n"), next unless @st;
    }
    my $prm = $st[2] & 0777;
    print STDERR (((++$dotcount) % 72)? '.': "\n");
    # XXX could use die() to fail on (accidental) input...
    warn("skipping directory '$f'\n"), next if -d _;
    warn("skipping chardev '$f'\n"), next if -c _;
    warn("skipping blockdev '$f'\n"), next if -d _;
    # fixme: fifos not yet handled (or is it a feature)
    warn("hmm, '$f' not file (fifo?)\n"), next unless -f _;

    # hard links we do
    my ($size, $type, $lname) = ($st[7], '0', '');
    if ($st[3] > 1) {
	my $devino = "$st[0].$st[1]";
	$lname = $links{$devino};
	if (defined $lname) {
	    $type = '1';
	    $size = 0;
	}
	else {
	    $links{$devino} = $n;
	}
    }
    _tarlisted_writehdr
      _tarlisted_mkhdr_rp $n, $prm, $size, $gmtime, $type, $lname;

    next if $lname;

    open my $in, '<', $f or die "opening '$f': $!\n";
    my $buf; my $tlen = 0;
    while ( (my $len = sysread($in, $buf, 524288)) > 0) {
	_tarlisted_xsyswrite $buf;
	$tlen += $len;
	die "$n got larger while archiving\n" if $tlen > $size;
    }
    die "$n: Short read ($tlen != $size)!\n" if $tlen != $size;
    close $in; # fixme, check
    _tarlisted_xsyswrite "\0" x (512 - $size % 512) if $size % 512;
}
print STDERR "\n" if $dotcount % 72;

( $close? tarlisted_close: tarlisted_close0 )
  and die "Closing tar file failed: $!\n";

# exit #

# from tarlisted.pm #

my $_tarlisted_pid;

sub _tarlisted_pipetocmd(@)
{
    pipe PR, PW;
    $_tarlisted_pid = fork;
    die "fork() failed: $!\n" unless defined $_tarlisted_pid;
    unless ($_tarlisted_pid) {
	# child
	close PW;
	open STDOUT, '>&TARLISTED';
	open STDIN, '>&PR';
	close PR;
	close TARLISTED;
	exec @_;
	die "exec() failed: $!";
    }
    # parent
    close PR;
    open TARLISTED, '>&PW';
    close PW;
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

# IEEE Std 1003.1-1988 (“POSIX.1”) ustar format
# name perm uid gid size mtime type lname uname gname devmajor devminor
sub _tarlisted_mkhdr($$$$$$$$$$$$)
{
    if (length($_[7]) > 100) {
	die "Link name '$_[7]' too long\n";
    }
    my $name = $_[0];
    my $prefix;
    if (length($name) > 100) {
	$name = _tarlisted_nampfx $name, $prefix
    }
    else {
	$prefix = ''
    }
    $name = pack('a100', $name);
    $prefix = pack('a155', $prefix);

    my $mode = sprintf("%07o\0", $_[1]);
    my $uid = sprintf("%07o\0", $_[2]);
    my $gid = sprintf("%07o\0", $_[3]);
    my $size = sprintf("%011o\0", $_[4]);
    my $mtime = sprintf("%011o\0", $_[5]);
    my $checksum = '        ';
    my $typeflag = $_[6];
    my $linkname = pack('a100', $_[7]);
    my $magic = "ustar\0";
    my $version = '00';
    my $uname = pack('a32', $_[8]);
    my $gname = pack('a32', $_[9]);
    my $devmajor = $_[10] < 0? "\0" x 8: sprintf("%07o\0", $_[10]);
    my $devminor = $_[11] < 0? "\0" x 8: sprintf("%07o\0", $_[11]);
    my $pad = pack('a12', '');

    my $hdr = join '', $name, $mode, $uid, $gid, $size, $mtime,
      $checksum, $typeflag, $linkname, $magic, $version, $uname, $gname,
	$devmajor, $devminor, $prefix, $pad;

    my $sum = 0;
    foreach (split //, $hdr) {
	$sum = $sum + ord $_;
    }
    $checksum = sprintf "%06o\0 ", $sum;
    $hdr = join '', $name, $mode, $uid, $gid, $size, $mtime,
      $checksum, $typeflag, $linkname, $magic, $version, $uname, $gname,
	$devmajor, $devminor, $prefix, $pad;

    return $hdr;
}

# name perm size mtime type lname (no uid gid uname gname devmajor devminor)
sub _tarlisted_mkhdr_rp($$$$$$)
{
    return _tarlisted_mkhdr
      $_[0], $_[1], 0, 0, $_[2], $_[3], $_[4], $_[5], '','', -1, -1;
}

sub _tarlisted_xsyswrite($)
{
    my $len = syswrite TARLISTED, $_[0] or 0;
    my $l = length $_[0];
    while ($len < $l) {
	die "Short write!\n" if $len <= 0;
	my $nl = syswrite TARLISTED, $_[0], $l - $len, $len or 0;
	die "Short write!\n" if $nl <= 0;
	$len += $nl;
    }
}

sub _tarlisted_writehdr($)
{
    _tarlisted_xsyswrite $_[0];
}

sub tarlisted_open($@)
{
    die "tarlisted alreadly open\n" if defined $_tarlisted_pid;
    $_tarlisted_pid = 0;
    if ($_[0] eq '-') {
	open TARLISTED, '>&STDOUT' or die "dup stdout: $!\n";
    } else {
	open TARLISTED, '>', $_[0] or die "> $_[0]: $!\n";
    }
    shift;
    _tarlisted_pipetocmd @_ if @_;
}

sub tarlisted_close0()
{
    close TARLISTED; # fixme: need check here.
    $? = 0;
    waitpid $_tarlisted_pid, 0 if $_tarlisted_pid;
    undef $_tarlisted_pid;
    return $?;
}

sub tarlisted_close()
{
    # end archive
    _tarlisted_xsyswrite "\0" x 1024;
    return tarlisted_close0;
}
