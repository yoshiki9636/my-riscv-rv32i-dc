#!/bin/perl

open (F0, ">test0.txt") or die "cannot open test0.txt";
open (F1, ">test1.txt") or die "cannot open test1.txt";
open (F2, ">test2.txt") or die "cannot open test2.txt";
open (F3, ">test3.txt") or die "cannot open test3.txt";
open (F4, ">test0.txt") or die "cannot open test0.txt";
open (F5, ">test1.txt") or die "cannot open test1.txt";
open (F6, ">test2.txt") or die "cannot open test2.txt";
open (F7, ">test3.txt") or die "cannot open test3.txt";
open (F8, ">test0.txt") or die "cannot open test0.txt";
open (F9, ">test1.txt") or die "cannot open test1.txt";
open (FA, ">test2.txt") or die "cannot open test2.txt";
open (FB, ">test3.txt") or die "cannot open test3.txt";
open (FC, ">test0.txt") or die "cannot open test0.txt";
open (FD, ">test1.txt") or die "cannot open test1.txt";
open (FE, ">test2.txt") or die "cannot open test2.txt";
open (FF, ">test3.txt") or die "cannot open test3.txt";

$phase = 0;

while (<>) {
	if (/^\s*(..)(..)(..)(..)$/) {
		if ($phase == 0) {
			print F0 "$4\n";
			print F1 "$3\n";
			print F2 "$2\n";
			print F3 "$1\n";
		}
		elsif ($phase == 1) {
			print F4 "$4\n";
			print F5 "$3\n";
			print F6 "$2\n";
			print F7 "$1\n";
		}
		elsif ($phase == 2) {
			print F8 "$4\n";
			print F9 "$3\n";
			print FA "$2\n";
			print FB "$1\n";
		}
		elsif ($phase == 3) {
			print FC "$4\n";
			print FD "$3\n";
			print FE "$2\n";
			print FF "$1\n";
		}
		$phase++;
		if ($phase >= 4) { $phase = 0; }
	}
}

close (F0);
close (F1);
close (F2);
close (F3);
close (F4);
close (F5);
close (F6);
close (F7);
close (F8);
close (F9);
close (FA);
close (FB);
close (FC);
close (FD);
close (FE);
close (FF);
