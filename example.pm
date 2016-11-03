#!/usr/bin/perl
use strict;
use warnings;
use 5.14.1;
use lib qq($ENV{HOME}/Apps/Perl5/libs);
use IPC::SemGroup;
use Time::HiRes qw(sleep);

my $sg=IPC::SemGroup->new(qw(nif-nif nuf-nuf naf-naf),{'autodestroy'=>1});

my $nif=$sg->get_sem('nif-nif');
$nif->set(1);

my @children=(
  {
    'func'=>sub {
        my $pnum=shift;
        say "p${pnum}: $$";
        $nif->take();
        local $| = 1;
        for (0..9) {
          print '|'.$_; sleep 0.3;
        };
        say '|';
        $nif->release;
        exit;
    },
  },
  {
    'func'=>sub {
        my $pnum=shift;
        say "p${pnum}: $$";
        sleep 0.1;
        do {
          say "p${pnum}: cant take semaphore, exiting";
          exit;
        } unless $nif->take_nowait();
        say "p${pnum}: takes semaphore!";
        exit;
    },
  },
);

for my $pnum (0..$#children) {
  if (my $childPID=fork()) {
    $children[$pnum]{'pid'}=$childPID;
    next;
  }
  say "I am a child #${pnum} with pid=$$";
  $children[$pnum]{'func'}->($pnum);
  exit;
}

while ((my $childPID=wait())>0) {
  printf "Child with pid=%d exited. Status code: %d (%s)\n", $childPID, ${^CHILD_ERROR_NATIVE}, (${^CHILD_ERROR_NATIVE}?'ERROR':'SUCCESS');
}

say 'Main process finished';
undef $sg;
