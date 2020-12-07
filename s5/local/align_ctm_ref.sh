#!/bin/bash

. ./path.sh
. ./cmd.sh

nj=10
cmd=run.pl

. ./utils/parse_options.sh
if [ $# -ne 3 ]; then
  echo "Usage: ./local/align_ctm_ref.sh <ctm> <ref> <odir>" 
  exit 1;
fi

ctm=$1
ref=$2
odir=$3

mkdir -p ${odir}/log

$cmd JOB=1:${nj} ${odir}/log/get_ctm.JOB.log \
  ./local/make_segments_from_ctm_and_ref_text.sh $nj JOB $ctm $ref ${odir}/segments.JOB

rm ${odir}/segments.*.ctm
cat ${odir}/segments.* | LC_ALL=C sort > ${odir}/segments
rm ${odir}/segments.*
