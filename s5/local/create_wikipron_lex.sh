#!/bin/bash

. ./path.sh
. ./cmd.sh
 
. ./utils/parse_options.sh
if [ $# -ne 5 ]; then
  echo "Usage: ./create_wikipron_lex.sh <words> <lex> <g2p> <wdir> <olex>"
  exit 1;
fi

words=$1
lex=$2
g2p=$3
wdir=$4
olex=$5

./local/apply_g2p.sh ${words} ${g2p} ${wdir}
LC_ALL= python ./local/create_wikipron_lex.py <(cut -f1,3 ${wdir}/lexicon_out.1) ${lex} ${olex} 
