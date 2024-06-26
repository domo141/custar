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
# Last modified: Wed 19 Jun 2024 22:25:42 +0300 too

# SPDX-License-Identifier: BSD 2-Clause "Simplified" License

use 5.14.1; # for tr/.../.../r (used in one (1) line)
use strict;
use warnings;

my @res;
my ($seek1, $cf1, $seek2, $cf2) = (0, undef, 0, undef);
my @diffcmds;

my %zo = ( 'tar', => '', 'bzip2' => 'bzip2',
	   'gz' => 'gzip', 'gzip' => 'gzip', 'tgz' => 'gzip',
	   'xz' => 'xz', 'txz' => 'xz',
	   'lz' => 'lzip', 'tlz' => 'lzip',
	   'zst' => 'zstd', 'tzst' => 'zstd' );

sub xseekarg($$)
{
    my $a = $_[1];
    my $n;
    if ($_[0]) {
	# internal error if $_[0] not 1 nor 2 here...
	$n = $_[0];
    } else {
	$a =~ s/^([12]),// or die "'-x' arg $a does not start with 1, or 2,\n";
	$n = $1;
    }
    my ($s, $f) = (0, '');
    foreach (split /[,.]/, $a) {
	$s = $1, next if /^(\d+)$/;
	next unless $_;
	$f = $zo{$_};
	die "'$_': not in (", join(', ', sort keys %zo),"\n" unless defined $f;
    }
    (($n == 1)? ($seek1, $cf1): ($seek2, $cf2)) = ($s, $f);
}

sub needarg() { die "No value for '$_'\n" unless @ARGV }

my ($tarf1, $tarf2);
my $care = 'pugtd'; # perm user group time device

while (@ARGV) {
    shift, last if $ARGV[0] eq '--';
    unless ($ARGV[0] =~ /^-/) {
	$tarf1 = $ARGV[0], shift, next unless defined $tarf1;
	$tarf2 = $ARGV[0], shift, next unless defined $tarf2;
	die "$0: '$ARGV[0]': too many arguments\n"
    }
    $_ = shift;

    needarg, push(@res, shift), next if $_ eq '-s';
    needarg, @diffcmds = split(/\s*:\s*/, shift, 2), next if $_ eq '-d';
    needarg, xseekarg(1, shift), next if $_ eq '-x1';
    needarg, xseekarg(2, shift), next if $_ eq '-x2';
    needarg, xseekarg('', shift), next if $_ eq '-x';
    needarg, $care = shift, next if $_ eq '-c';

    push(@res, $1), next if $_ =~ /^-s(.*)/;
    needarg, @diffcmds = split(/\s*:\s*/, $1, 2), next if $_ =~ /^-d(.*)/;
    xseekarg(1, $1), next if $_ =~ /^-x1[,=](.*)/;
    xseekarg(2, $1), next if $_ =~ /^-x2[,=](.*)/;
    $care = $1, next if $_ =~ /^-c(.*)/;

    die "'$_': unknown option\n"
}

unless (defined $tarf2) {
    die <<EOF;

Usage: $0 [-options] ustarchive1 ustarchive2

Options:
    -s /regexp/replacement/  -- filename replacements (for filename matching)
    -d [tdiff]:[bdiff]       -- optional text/binary diff programs
    -c (pugtd)               -- for hdrcmp only: perm user group time device
    -x1 seek,ffmt            -- seek to position in file,file (compr.) fmt
    -x2 seek,ffmt            -- \\ first seek, then e.g. gunzip if fmt 'tgz'

Hints: -s,.*?/,,  can be used to drop first path component
       -cp        may give good information/noise balance

EOF
}

die "'$tarf1': no such file\n" unless -f $tarf1;
die "'$tarf2': no such file\n" unless -f $tarf2;

die "Will not run diff commands if stdout is not a tty...\n"
  if @diffcmds and ! -t STDOUT;

sub xforms($); # fn name from custar.pl...
if (@res) {
    my $eval = 'sub xforms($) {';
    #
    # Current solution is to "eval" replace script run time. Due to input
    # restrictions full perl regexp substitution interface is not available
    # (';'s dropped, separator must be non-word character).
    # Improvements welcome.
    #
    foreach (@res) {
	# early checks...
	die "'$_' does not start with non-word character\n" unless /^\W/;
	my $p = substr($_, 0, 1);
	tr/;//d;
	my $s = substr($_, -1, 1);
	die "'$_' not $p...$p...$p nor $s...$s...$s\n" unless $p eq $s;
	$eval .= "\n \$_[0] =~ s$_;";
    }
    $eval .= "\n}; 1";
    eval $eval or die "Unsupported/broken '-s ...' content\n";
}

my %zc = ( '.tar' => '', '.tar.bzip2' => 'bzip2',
	   '.tar.gz' => 'gzip', '.tgz' => 'gzip',
	   '.tar.xz' => 'xz', '.txz' => 'xz',
	   '.tar.lz' => 'lzip', '.tlz' => 'lzip',
	   '.tar.zst' => 'zstd', '.tzst' => 'zstd' );

sub fmz($$$) {
    $_[0] = $_[2], return if defined $_[2];
    $_[1] =~ /\S((?:[.]tar)?[.]?[.]\w+)$/;
    die "Unknown format in '$_[1]': not in (fn" . join(', fn', sort keys %zc) .
  ")\n" unless defined $1 and defined ($_[0] = $zc{$1});
}
my ($zc1, $zc2);
fmz $zc1, $tarf1, $cf1;
fmz $zc2, $tarf2, $cf2;

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
my ($fh1, $fh2);
opn $fh1, $zc1, $seek1, $tarf1;
opn $fh2, $zc2, $seek2, $tarf2;

sub unpack_ustar_hdr($$) {
    my @l = unpack('A100 A8 A8 A8 A12 A12 A8 A1 A100 a8 A32 A32 A8 A8 A155',
		   $_[0]);
    if ($l[14]) {
	$l[14] =~ s:/*$:/:;
	$l[0] = $l[14] . $l[0];
    }
    if (@res) {
	xforms $l[0];
	xforms $l[8] if $l[7] == 1; # hard link
    }
    die "$_[1]: '$l[9]': not 'ustar{\\0}00'\n" unless $l[9] eq "ustar\00000";
    return ($l[0], $l[1]+0, $l[2]+0, $l[3]+0, oct($l[4]), oct($l[5]),
	    $l[7], $l[8], $l[10], $l[11], ($l[12]||-1)+0, ($l[13]||-1)+0, 1);
}

my (@h0, @h1);

#my @differ_now; ...
sub chkdiffer($$;$) {
    if ($h0[$_[0]] ne $h1[$_[0]]) {
	if (defined $_[2]) {
	    return 1 if ((index $care, $_[2]) < 0);
	}
	print " $h0[0] :$_[1] differ ($h0[$_[0]] != $h1[$_[0]])\n";
	return 0
    }
    return 1
}

# return for filename / file content ....
sub hdrdiffer() {
    my $cmp = 1;
    chkdiffer  1, "file mode (perms)", 'p';
    chkdiffer  2, "user id", 'u';
    chkdiffer  3, "group id", 'g';
    chkdiffer  4, "file size" or $cmp = 0; # no point compare, but visual diff
    chkdiffer  5, "mod. time", 't';
    chkdiffer  6, "file type" or $cmp = -1; # -1: no point ever diff
    chkdiffer  7, "link name" or $cmp = -1;
    chkdiffer  8, "user name", 'u';
    chkdiffer  9, "group name", 'g';
    chkdiffer 10, "device major", 'd';
    chkdiffer 11, "device minor", 'd';
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
	$_[1] = "\377\377";
	return ("\377\377", 0, 0, 0, 0, 0, '9', '', '', '', 0, 0, 0)
    }
    my @h = unpack_ustar_hdr $buf, $_[2];
    my $n = ($h[0] =~ tr[/]/\n/r);
    unless ($_[1] le $n) {
	$_[1] =~ tr/\n/\//; $n =~ tr/\n/\//;
	die "order!: $_[2]: $_[1] > $n\n";
    }
    $_[1] = $n;
    return @h;
}

# a tmpdir creation fn, just for fun (less use's). good enough fail safe.
my $tmpd;
sub mktmpd ()
{
    my $t = time;
    my $salt = substr((sprintf "%2x", $$), -2);
    for (1..100) {
	my $dn = crypt $t, $salt; $dn =~ tr|/.||d;
	next unless length $dn >= 6;
	$dn = substr $dn, -6; $dn = "/tmp/ctd-$dn";
	if (mkdir $dn, 0700) {
	    $tmpd = $dn;
	    eval "END { unlink glob('$tmpd/*'); rmdir '$tmpd' }";
	    return
	}
	$t -= 11111;
    }
    die "Could not create temporary directory\n";
}

if (@diffcmds) {
    sub which($) {
	foreach (split /:/, $ENV{PATH}) {
	    my $p = "$_/$_[0]";
	    return $p if -x $p;
	}
	return '';
    }
    if ($diffcmds[0]) {
	$diffcmds[0] = [ split /\s+/, $diffcmds[0] ];
    }
    else {
	my @l; @l = qw/xxdiff kompare meld/ if ($ENV{DISPLAY} || '');
	#push @l, ...
	$diffcmds[0] = [ 'sh', '-c', 'diff -u "$0" "$1" | less' ];
	foreach (@l) {
	    my $p = which $_;
	    $diffcmds[0] = [ $p ], last if $p;
	}
    }
    if (@diffcmds == 2 and $diffcmds[1]) {
	$diffcmds[1] = [ split /\s+/, $diffcmds[1] ];
    }
    else {
	$diffcmds[1] = [ 'sh', '-c', 'cmp -b -l "$0" "$1" | less' ];
	foreach (qw/vbindiff/) {
	    my $p = which $_;
	    $diffcmds[1] = [ $p ], last if $p;
	}
    }
}
my $binary = 0;
$ENV{LESSSECURE} = '1';

sub rundiff($$)
{
    my $diffcmd = $binary? $diffcmds[1]: $diffcmds[0];
    #system qw/sh -c/, 'echo $# -- $0 -- $@', $diffcmd, $_[0], $_[1];
    print "Executing @{$diffcmd} $_[0] $_[1]\n";
    $ENV{LESS} = "iP%lt-%lb " . $h0[0]; # '.'s lost. good enough
    system @{$diffcmd}, $_[0], $_[1];
    unlink $_[0], $_[1];
    $binary = 0;
}

sub diffiles ()
{
    my $f = $h0[0]; $f =~ tr|/|,|;
    mktmpd unless defined $tmpd;
    return ("$tmpd/1-$f", "$tmpd/2-$f");
}

sub write_tmpfiles($$@)
{
    open O, '>', $_[0] or die $!;  print O $_[1];  close O or die $!;
    $binary = 1 if -B $_[0];
    return unless defined $_[2];
    open O, '>', $_[2] or die $!;  print O $_[3];  close O or die $!;
    $binary = 1 if -B $_[2];
}

# btw: check/test if sysread is faster... (what about global $buf ?)
sub consume($$$) {
    my $left = $_[1]; # could have used alias to list, but...
    my $buf;
    my $dowr = ($_[2])? 1: 0;
    while ($left > 1024 * 1024 + 1024) {
	# xxx check read length (readfully?, check other perl code)
	read $_[0], $buf, 1024 * 1024;
	write_tmpfiles($_[2], $buf), $dowr = 0 if $dowr;
	$left -= 1024 * 1024
    }
    if ($left > 0) {
	# ditto
	read $_[0], $buf, $left;
	write_tmpfiles($_[2], $buf), $dowr = 0 if $dowr;
    }
    $left = $left & 511;
    read $_[0], $buf, 512 - $left if $left;
}

sub compare() {
    my $left = $h0[4];
    my ($buf1, $buf2);
    my $diff = 0;
    my ($tf1, $tf2, $dowr, $rd) = @diffcmds ? (diffiles, 1, 1) : ('','', 0, 0);
    while ($left > 1024 * 1024 + 1024) {
	# xxx check read length (readfully?, check other perl code)
	read $fh1, $buf1, 1024 * 1024;
	read $fh2, $buf2, 1024 * 1024;
	$diff = $buf1 cmp $buf2 unless $diff;
	write_tmpfiles($tf1, $buf1, $tf2, $buf2), $dowr = 0 if $dowr and $diff;
	$left -= 1024 * 1024;
    }
    if ($left > 0) {
	# ditto
	read $fh1, $buf1, $left;
	read $fh2, $buf2, $left;
	$diff = $buf1 cmp $buf2 unless $diff;
	write_tmpfiles($tf1, $buf1, $tf2, $buf2), $dowr = 0 if $dowr and $diff;
    }
    $left = $left & 511;
    if ($left) {
	read $fh1, $buf1, 512 - $left;
	read $fh2, $buf2, 512 - $left;
    }
    rundiff $tf1, $tf2 if $diff and $rd;
    return $diff
}

my (@only1, @only2);

print "\n =-- File differences --=\n";

T: while (1) {
    @h0 = read_hdr $fh1, $pname0, $tarf1;
    @h1 = read_hdr $fh2, $pname1, $tarf2;
    last unless $h0[12] and $h1[12];

    while (1) {
	my $n = $pname0 cmp $pname1;
	if ($n == 0) {
	    my $w = hdrdiffer;
	    if ($w <= 0) { # 0 and -1: diffing not implemented yet
		my ($tf1, $tf2) = ($w == 0 && @diffcmds) ? diffiles : ('','');
		consume $fh1, $h0[4], $tf1;
		consume $fh2, $h1[4], $tf2;
		rundiff $tf1, $tf2 if $tf1;
	    }
	    else {
		print " $h0[0] :file content differ\n" if compare;
	    }
	    next T
	}
	if ($n < 0) {
	    push @only1, $h0[0]; # warn "<<< $h0[0]\n";
	    consume $fh1, $h0[4], '';
	    @h0 = read_hdr $fh1, $pname0, $tarf1;
	}
	else {
	    push @only2, $h1[0]; # warn ">>> $h0[0]\n";
	    consume $fh2, $h1[4], '';
	    @h1 = read_hdr $fh2, $pname1, $tarf2;
	}
    }
    last
}

close $fh1; # or warn $!;
close $fh2; # or warn $!;

print "\n<-- only in $tarf1 <--\n";
print ' ', $_, "\n" foreach (@only1);

print "\n--> only in $tarf2 -->\n";
print ' ', $_, "\n" foreach (@only2);
print "\n";
