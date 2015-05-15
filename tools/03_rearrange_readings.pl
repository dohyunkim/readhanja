
use strict;
use warnings;

my @lines  = ();
my %hanjas = ();

open my $fh, "hanja2hangul.lua" or die;
while(<$fh>) {
  push @lines, $_;
  if(/\[(\d+)\]={(.+)},/) {
    @{ $hanjas{$1} } = split ",", $2;
  }
}
close $fh;

my %varseq = ();

open $fh, "hanja2varseq.lua" or die;
while(<$fh>) {
  if(/\[(\d+)\]={(.+)},/) {
    my $hanja = $1;
    for my $var (split ",", $2) {
      push @{ $varseq{$hanja} }, @{ $hanjas{$var} };
    }
  }
}
close $fh;

for my $hanja (keys %hanjas) {
  my @hanguls = ();
  for my $hangul (@{ $hanjas{$hanja} }) {
    my $seen = 0;
    for my $var (@{ $varseq{$hanja} }) {
      $seen = 1 if $hangul == $var;
    }
    push @hanguls, $hangul unless $seen;
  }
  my $first = shift @hanguls;
  unshift @hanguls, @{ $varseq{$hanja} };
  unshift @hanguls, $first;
  @{ $hanjas{$hanja} } = @hanguls;
}

for (@lines) {
  s/\[(\d+)\]={.+},/"[".$1."]={".join(',',@{ $hanjas{$1} })."},"/e;
  print;
}
