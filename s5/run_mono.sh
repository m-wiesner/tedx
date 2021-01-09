#!/bin/bash
# This exists to make acoustic models for sentence alignment
# stages 0-X: train acoustic model with vtts
# stages 12-13: speech-to-text alignments
# line 148 is the meat; the rest is prep

. ./path.sh
. ./cmd.sh

speech=/export/c24/salesky/tedx/
text=/export/c24/salesky/tedx/text/

src=fr
stage=0

. ./utils/parse_options.sh

speech=${speech}/${src}

if [ $stage -le 0 ]; then
  ./local/prepare_data.sh --stage 0 $speech data/all
fi

# Make features
if [ $stage -le 1 ]; then
  ./utils/copy_data_dir.sh data/all data/all_mfcc
  steps/make_mfcc.sh --nj 80 --cmd "$train_cmd" data/all_mfcc
  utils/fix_data_dir.sh data/all_mfcc
  steps/compute_cmvn_stats.sh data/all_mfcc
  utils/fix_data_dir.sh data/all_mfcc
fi

#filter out data/dict/lexicon.txt -- filter eval/valid words
# Make Lang directory
if [ $stage -le 2 ]; then
  python local/prepare_dict.py \
    --silence-lexicon <(grep "^<" data/dict/lexicon.txt) \
    --extra-sil-phones "<number>" \
    data/dict/lexicon.txt data/dict

  ./utils/prepare_lang.sh --num-sil-states 10 --share-silence-phones true \
    data/dict "<unk>" data/dict/tmp.lang data/lang  
fi

# Subset data
if [ $stage -le 3 ]; then
  #subset with filter_scp instead of random, to only train. also make data/eval proper eval
  utils/subset_data_dir.sh --speakers data/all_mfcc 3000 data/eval #
  utils/copy_data_dir.sh data/all_mfcc data/train #
  utils/filter_scp.pl --exclude -f 1 data/eval/segments data/all_mfcc/segments > data/train/segments #
  utils/fix_data_dir.sh data/train
  utils/subset_data_dir.sh --shortest data/train 10000 data/train_10kshort
fi

if [ $stage -le 4 ]; then
  steps/train_mono.sh --nj 20 --cmd "$train_cmd" \
    data/train_10kshort data/lang exp/mono
fi

if [ $stage -le 5 ]; then
  steps/align_si.sh --nj 40 --cmd "$train_cmd" \
    data/train data/lang exp/mono exp/mono_ali
  steps/train_deltas.sh --cmd "$train_cmd" \
    2500 30000 data/train data/lang exp/mono_ali exp/tri1  
fi

if [ $stage -le 6 ]; then
  steps/align_si.sh --nj 40 --cmd "$train_cmd" \
    data/train data/lang exp/tri1 exp/tri1_ali
  
  steps/train_lda_mllt.sh --cmd "$train_cmd" \
    4000 50000 data/train data/lang exp/tri1_ali exp/tri2  
fi

if [ $stage -le 7 ]; then
  steps/align_si.sh --nj 40 --cmd "$train_cmd" \
    data/train data/lang exp/tri2 exp/tri2_ali
  
  steps/train_sat.sh --cmd "$train_cmd" \
    5000 100000 data/train data/lang exp/tri2_ali exp/tri3 
fi

# Decode to check ASR performance
if [ $stage -le 8 ]; then
  num_utts=`cat data/train/text | wc -l`
  num_valid_utts=$(($num_utts/10))
  num_train_utts=$(($num_utts - $num_valid_utts)) 
  
  mkdir -p data/lm
  shuf data/train/text > data/lm/text.shuf
  head -n $num_train_utts data/lm/text.shuf > data/lm/train_text
  tail -n $num_valid_utts data/lm/text.shuf > data/lm/dev_text
  
  ./local/train_lm.sh data/dict/lexicon.txt data/lm/train_text data/lm/dev_text data/lm
  ./utils/format_lm.sh data/lang data/lm/lm.gz data/dict/lexicon.txt data/lang

  ./utils/mkgraph.sh data/lang exp/tri3 exp/tri3/graph

  # Can only decode with 10 jobs because we only have 10 speakers
  ./steps/decode_fmllr_extra.sh --cmd "$decode_cmd" --nj 10 exp/tri3/graph data/eval exp/tri3/decode_eval
  ./steps/score_kaldi.sh --min-lmwt 6 --max-lmwt 18 --cmd "$decode_cmd" data/eval data/lang exp/tri3/decode_eval
  grep WER exp/tri3/decode_eval/wer* | ./utils/best_wer.sh
fi

if [ $stage -le 9 ]; then
  ./local/prepare_data.sh --stage 0 --filter false --skip-lang true $speech data/all_unfilt
fi

# Prepare features for all data (including segments we filtered out)
if [ $stage -le 10 ]; then
  ./utils/copy_data_dir.sh data/all_unfilt data/all_unfilt_mfcc
  steps/make_mfcc.sh --nj 80 --cmd "$train_cmd" data/all_unfilt_mfcc
  utils/fix_data_dir.sh data/all_unfilt_mfcc
  steps/compute_cmvn_stats.sh data/all_unfilt_mfcc
  utils/fix_data_dir.sh data/all_unfilt_mfcc
fi

# Align the data 
if [ $stage -le 11 ]; then
  train_cmd_="$train_cmd --mem 4G"
  ./steps/align_fmllr.sh \
    --beam 40 \
    --retry-beam 200 \
    --cmd "$train_cmd_" \
    --nj 40 \
    data/all_unfilt_mfcc data/lang exp/tri3 exp/tri3_ali_unfilt

  echo "Alignment failed for the following audio files ..."
  grep -o 'Did not successfully decode file [-_a-zA-Z0-9]*' exp/tri3_ali_unfilt/log/align_pass2.*.log
fi

if [ $stage -le 12 ]; then
  # Make ctm file
  awk '{print $2, $2, 1}' data/all_unfilt_mfcc/segments > data/all_unfilt_mfcc/reco2file_and_channel
  ./steps/get_train_ctm.sh --cmd "$train_cmd" data/all_unfilt_mfcc data/lang exp/tri3_ali_unfilt

  # Find all target languages
  tgt_translations=( `find ${text}/ -type d -name "*${src}-*"` )
  for tt in ${tgt_translations[@]}; do
    language_pair=`basename ${tt}`
    target_language=${language_pair##${src}-}
    datadir=data/all_sentence_${target_language}
    mkdir -p ${datadir}
    LC_ALL= python local/make_text_only.py --noise "<noise>" --keep-segments \
      ${tt} ${datadir}/text #tt = srclangdir

    segmentdir=exp/translate_ali_${target_language}
    ./local/align_ctm_ref.sh --nj 40 --cmd "$decode_cmd" \
      exp/tri3_ali_unfilt/ctm ${datadir}/text ${segmentdir}

    failed_ctm_files=( `awk '($4-$3 == 0.0){print $1}' ${segmentdir}/segments` )
    if [ ${#failed_ctm_files[@]} -ne 0 ]; then
      echo "CTM shows alignment issues in the following segments ..."
      for f in ${failed_ctm_files[@]}; do 
        echo ${f}
      done
    fi

    overlapped_segments=( `awk 'BEGIN{ prev_val=0; prev_line=""} 
    {
      if(prev_val > $3 && $2 == prev_reco) {
        print prev_line;
        print $1
      };
      prev_line=$1;
      prev_val=$4;
      prev_reco=$2
    }' ${segmentdir}/segments`
    )

    if [ ${#overlapped_segments[@]} -ne 0 ]; then
      echo "The following segments were overlapped."
      for f in ${overlapped_segments[@]}; do
        echo ${f}
      done
      echo ""
      echo "This may indicate missing translations,"
      echo "or that there are unaligned segments."
      echo "Try realigning unfiltered data with a larger retry-beam."
    fi 
    
    cp ${segmentdir}/segments ${datadir}
    awk '{print $1, $2}' ${datadir}/segments > ${datadir}/utt2spk
    ./utils/utt2spk_to_spk2utt.pl ${datadir}/utt2spk > ${datadir}/spk2utt
    cp data/all_unfilt/wav.scp ${datadir}/wav.scp    
 
    ./utils/fix_data_dir.sh ${datadir}
  done
fi

if [ $stage -le 13 ]; then
  tgt_translations=( `find ${text}/ -type d -name "*${src}-*"` )
  grep WER exp/*/decode*eval*/wer_* | ./utils/best_wer.sh > ${src}_statistics.txt
  for tt in ${tgt_translations[@]}; do
    language_pair=`basename ${tt}`
    target_language=${language_pair##${src}-}
    datadir=data/all_sentence_${target_language}
    echo "------------ ${target_language} Dataset Statistics: ----------------"
    num_segs=`cat ${datadir}/segments | wc -l`
    num_hrs=`awk '{sum+=$4-$3} END{print sum/3600}' ${datadir}/segments`
    num_talks=`cat ${datadir}/wav.scp | wc -l`
    num_src_words=`cat ${tt}/*.${src} | tr " " "\n" | grep -v '^\s*$' | wc -l`
    num_src_types=`cat ${tt}/*.${src} | tr " " "\n" | LC_ALL=C sort -u | grep -v '^\s*$' | wc -l`
    avg_src_len=`echo "${num_src_words} ${num_segs}" | awk '{print $1/$2}'`
    avg_src_dur=`echo "${num_hrs} ${num_segs}" | awk '{print $1*3600/$2}'` 
    echo "# Segments: ${num_segs}"
    echo "# Hours: ${num_hrs}"
    echo "# Talks: ${num_talks}"
    echo "# Src Tokens: ${num_src_words}"
    echo "# Src Types: ${num_src_types}"
    echo "Avg # Words / Segment in Src: ${avg_src_len}"
    echo "Avg Duration (s) / Segment in Src: ${avg_src_dur}"
    echo ""
    echo ""
  done >> ${src}_statistics.txt 
fi

