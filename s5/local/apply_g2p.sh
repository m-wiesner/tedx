#! /bin/bash

cmd=run.pl
encoding=utf-8
g2p_iters=6
stage=0
known_words=50
nbest=1

. ./utils/parse_options.sh
. ./path.sh

# To get the word list ...
# comm -23 <(grep -v '<.*>' hub4_words | grep -v 'SIL' | sort) \
#          <(awk '{print $1}' pron_lex | sort) > hub4_oov
#
# comm -23 <(grep -v '<.*>' lorelei_words | sort) \
#          <(awk '{print $1}' pron_lex | sort) > lorelei_oov
#
# cat hub4_oov lorelei_oov | sort -u > oov.txt
#
# comm -12 <(grep -v '<.*>' hub4_words | grep -v 'SIL' | sort) \
#          <(awk '{print $1}' pron_lex | sort) > hub4_words
#
# awk 'FNR==NR{a[$1]=$0; next}($1 in a)' pron_lex > hub4_pron_lex


if [ $# -eq 0 ]; then
  echo "Usage: ./local_/g2p/apply_g2p.sh <oov-wordlist> <g2p> <odir>"
  exit 1
fi

output=$3
g2p=$2
oovlist=$1

mkdir -p $output/log

echo "--------- Params ------"
echo "IV_LEX: $ivlex"
echo "oovlist: $oovlist"
echo "G2P: $g2p"
echo "output: $output"
echo "------------------------"

echo "$0: Producing graphemic forms for pronunciations..."
#$cmd JOB=1:$nj $output/log/g2p.JOB.log \  utils/split_scp.pl -j $nj \$\[JOB -1\] $oovlist \|\
#  utils/split_scp.pl -j $nj \$\[JOB -1\] $oovlist \|\
#  cut -f 1  \|\
#  phonetisaurus-g2pfst \
#    --model=$g2p/g2p.fst\
#    --wordlist=/dev/stdin \
#    --nbest=$nbest \> $output/lexicon_out.JOB \|\| true

phonetisaurus-g2pfst --model=$g2p/g2p.fst --wordlist=$oovlist --nbest=$nbest > $output/lexicon_out.1

exit 0
