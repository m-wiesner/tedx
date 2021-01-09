#!/bin/bash
# Run ASR recipes

. ./path.sh
. ./cmd.sh

speech=/export/c24/salesky/tedx
text=/export/c24/salesky/tedx/text

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

# Make Lang directory
# filter out data/dict/lexicon.txt -- filter eval/valid words
if [ $stage -le 2 ]; then
  utils/copy_data_dir.sh data/all_mfcc data/train
  cat splits/*.${src} | utils/filter_scp.pl --exclude - data/all_mfcc/wav.scp > data/train/wav.scp
  utils/fix_data_dir.sh data/train
  cut -d' ' -f2- data/train/text | tr " " "\n" | LC_ALL=C sort -u | grep -v '^\s*$' > data/dict/vocab.train
  grep "^<" data/dict/lexicon.txt > data/dict/silence_lexicon.txt
  cat data/dict/vocab.train | grep -Ff - data/dict/lexicon.txt > data/dict/nonsilence_lexicon.txt
  cat data/dict/silence_lexicon.txt data/dict/nonsilence_lexicon.txt | LC_ALL=C sort -u > data/dict/lexicon.train
  mv data/dict/lexicon.{txt,all} && mv data/dict/lexicon.{train,txt}
  python local/prepare_dict.py \
    --silence-lexicon <(grep "^<" data/dict/lexicon.txt) \
    --extra-sil-phones "<number>" \
    data/dict/lexicon.txt data/dict
  
  ./utils/prepare_lang.sh --num-sil-states 10 --share-silence-phones true \
    data/dict "<unk>" data/dict/tmp.lang data/lang  
fi

# Subset data
if [ $stage -le 3 ]; then
  #subset to official eval sets with with filter_scp 
  utils/copy_data_dir.sh data/all_mfcc data/eval
  utils/filter_scp.pl -f 2 splits/eval.${src} data/all_mfcc/segments > data/eval/segments
  utils/fix_data_dir.sh data/eval

  utils/copy_data_dir.sh data/all_mfcc data/valid
  utils/filter_scp.pl -f 2 splits/valid.${src} data/all_mfcc/segments > data/valid/segments
  utils/fix_data_dir.sh data/valid

  utils/copy_data_dir.sh data/all_mfcc data/iwslt2021
  utils/filter_scp.pl -f 2 splits/iwslt2021.${src} data/all_mfcc/segments > data/iwslt2021/segments
  utils/fix_data_dir.sh data/iwslt2021

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

  ./steps/align_fmllr.sh \
    --nj 40 \
    data/train data/lang exp/tri3 exp/tri3_ali
fi

# Train chain 
if [ $stage -eq 8 ]; then
    local/run_chain.sh #--stage 16 --train-stage <last iternum that finished>
fi

# Decode to check ASR performance
if [ $stage -eq 9 ]; then
  num_utts=`cat data/train/text | wc -l`
  num_valid_utts=$(($num_utts/10))
  num_train_utts=$(($num_utts - $num_valid_utts)) 
  
  mkdir -p data/lm
  shuf data/train/text > data/lm/text.shuf
  head -n $num_train_utts data/lm/text.shuf > data/lm/train_text
  tail -n $num_valid_utts data/lm/text.shuf > data/lm/dev_text
  
  ./local/train_lm.sh data/dict/lexicon.txt data/lm/train_text data/lm/dev_text data/lm
  ./utils/format_lm.sh data/lang data/lm/lm.gz data/dict/lexicon.txt data/lang

  ./utils/mkgraph.sh --self-loop 1.0 data/lang exp/chain/tree_a_sp exp/chain/tree_a_sp/graph

  # Have more than 40 speakers, so nj can be greater than 40
  for data in valid eval iwslt2021; do
      ./steps/nnet3/decode.sh \
          --acwt 1.0 --post-decode-acwt 10.0 \
          --frames-per-chunk 140 \
          --nj 40 --cmd "$decode_cmd" \
          --online-ivector-dir exp/nnet3/ivectors_${data}_hires \
          exp/chain/tree_a_sp/graph data/${data}_hires exp/chain/cnn_tdnn1c_sp/decode_${data} || exit 1

      ./steps/score_kaldi.sh --min-lmwt 6 --max-lmwt 18 --cmd "$decode_cmd" data/${data}_hires data/lang exp/chain/cnn_tdnn1c_sp/decode_${data}
  done

  grep WER exp/chain/cnn_tdnn1c_sp/decode_valid/wer* | ./utils/best_wer.sh
  grep WER exp/chain/cnn_tdnn1c_sp/decode_eval/wer* | ./utils/best_wer.sh
  grep WER exp/chain/cnn_tdnn1c_sp/decode_iwslt2021/wer* | ./utils/best_wer.sh
fi

