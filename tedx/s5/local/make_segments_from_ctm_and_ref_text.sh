#!/bin/bash

if [ $# -ne 5 ]; then
  echo "Usage: ./local/make_segments_from_ctm_and_ref_text.sh <nj> <JOB> <ctm> <text> <segments>"
  exit 1;
fi

nj=$1
job=$2
ctm=$3
text=$4
segments=$5

./utils/split_scp.pl -j $nj $job --one-based \
  <(awk '{print $1}' ${ctm} | LC_ALL=C sort -u) |\
  grep -Ff - ${ctm} > ${segments}.ctm 

LC_ALL= python local/make_segments_from_ctm_and_ref_text.py $text ${segments}.ctm $segments
