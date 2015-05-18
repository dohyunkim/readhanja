
all:
	perl 01_unihan_libhangul.pl > hanja2hangul.lua
	perl 02_std_var_seq.pl > hanja2varseq.lua
	perl 03_rearrange_readings.pl > newhanja2hangul.lua
	mv newhanja2hangul.lua hanja2hangul.lua

clean:
	rm -f hanja2hangul.lua hanja2varseq.lua
