#!/usr/bin/perl
# gms-security-graceful: in the method containing ANCHOR, make the SecurityException catch handler
# jump to the graceful failure path instead of rethrowing. Reads smali on stdin, writes to stdout.
# Labels are apktool-generated, so they're found by structure, not name.
use strict;
use warnings;

my $anchor = $ENV{ANCHOR} or die "ANCHOR not set\n";
my $id     = $ENV{ID}     or die "ID not set\n";

local $/;
my $smali = <STDIN>;

my @methods = split /(?=^\.method )/m, $smali;
my $hits = grep { index($_, $anchor) >= 0 } @methods;
die "[$id] anchor in $hits methods, expected 1\n" unless $hits == 1;

for my $method (@methods) {
    next if index($method, $anchor) < 0;

    my ($handler) = $method =~ /\.catch Ljava\/lang\/SecurityException; \{[^\}]*\} :(\w+)/
        or die "[$id] no SecurityException handler\n";

    # The graceful path is the last label before the first use of the anchor string.
    my $before = substr($method, 0, index($method, $anchor));
    my @labels = $before =~ /^\s*:(\w+)\s*$/mg or die "[$id] no graceful label\n";
    my $graceful = $labels[-1];

    # Handler shape: ":<handler>  move-exception vN  [.line/blank lines]  throw vN"
    $method =~ s/(^[ \t]*:\Q$handler\E[ \t]*\n[ \t]*move-exception (\w+)[ \t]*\n(?:[ \t]*(?:\.line \d+)?[ \t]*\n)*)([ \t]*)throw \2\b/$1$3# PATCH $id\n$3goto :$graceful/m
        or die "[$id] handler shape changed\n";
}

print join '', @methods;
