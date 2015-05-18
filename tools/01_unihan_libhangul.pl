
use strict;
use warnings;
use charnames ();

my %hanjahangul = ();

open my $fh, "<:utf8", "hanja.txt" or die;
while(<$fh>) {
  if(/^(.):(.):/) {
    push @{ $hanjahangul{ord $2} }, $1;
  }
}
close $fh;

open $fh, "<:utf8", "Unihan_Readings.txt" or die;
while(<$fh>) {
  if(/^U\+(.*?)\s+kHangul\s+(.*)$/) {
    unshift @{ $hanjahangul{hex $1} }, split /\s+/,$2;
  }
  elsif(/^U\+(.*?)\s+kKorean\s+(.*)$/) {
    my $uni = hex $1;
    next if $uni >= 0xF900;
    my @kos = split /\s+/, $2;
    for (@kos) {
      s/PEY/BAE/g; # exception: 베 -> 배
      s/K(?!H)/G/g;
      s/T(?!H)/D/g;
      s/L(?!$)/R/g;
      s/P(?!H)/B/g;
      s/C(?!H)/J/g;
      s/CH/C/g;
      s/KH/K/g;
      s/TH/T/g;
      s/PH/P/g;
      s/(?<![YWA])E(?!Y)/EO/g;
      s/(?<![WY])U(?!Y)/EU/g;
      s/WU/U/g;
      s/(?<![YW])AY/AE/g;
      s/(?<![YW])EY/E/g;
      s/OY/OE/g;
      s/YE(?!Y)/YEO/g;
      s/YAY/YAE/g;
      s/YEY/YE/g;
      s/WAY/WAE/g;
      s/WE(?!Y)/WEO/g;
      s/WEY/WE/g;
      s/UY/YI/g;
      $_ = charnames::string_vianame("HANGUL SYLLABLE $_");
    }
    if( $uni == 0x6635 or $uni == 0x66B1 or $uni == 0x8D05 ) {
      unshift @{ $hanjahangul{$uni} }, @kos;
    }
    else {
      push @{ $hanjahangul{$uni} }, @kos;
    }
  }
}
close $fh;

print("return{\n");
for my $key (sort keys %hanjahangul) {
  my @hangul  = ();
  my %tmp     = ();
  for (@{ $hanjahangul{$key} }) {
    push @hangul, ord $_ unless $tmp{$_};
    $tmp{$_} = 1;
  }
  printf("[%s]={%s},\n", $key, join ",", @hangul);
}

print <<__EOS__;
}
--[[
Copyright (c) 2005,2006 Choe Hwanjin
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.
3. Neither the name of the author nor the names of its contributors
   may be used to endorse or promote products derived from this software
   without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
--]]
__EOS__

