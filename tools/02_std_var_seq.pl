
use strict;
use warnings;

my %hanjas = ();

#[20415]={48320,54200},
open my $fd, "hanja2hangul.lua" or die;
while(<$fd>) {
  if(/\[(\d+)\]={.+},/) {
    $hanjas{$1} = 1;
  }
}
close $fd;

my %vars = ();

#4E0D FE00; CJK COMPATIBILITY IDEOGRAPH-F967;
open $fd, "StandardizedVariants.txt" or die;
while(<$fd>) {
  if(/^(.+?)\s(.+?);\sCJK COMPATIBILITY IDEOGRAPH-(.+?);/) {
    $vars{hex $1}{hex $2} = hex $3;
  }
}
close $fd;

print("return{\n");
for my $k (sort keys %vars) {
  next unless $hanjas{$k};
  my @compat = ();
  for my $kk (sort keys %{ $vars{$k} }) {
    my $var = $vars{$k}{$kk};
    next unless $hanjas{$var};
    push @compat, $var;
  }
  next unless @compat;
  printf("[%s]={%s},\n", $k, join ",",@compat);
}
print("}\n");
