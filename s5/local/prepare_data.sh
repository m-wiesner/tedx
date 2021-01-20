#!/bin/bash

. ./path.sh
. ./cmd.sh
. ./lang.conf

stage=0
filter=true
skip_lang=false

. ./utils/parse_options.sh

if [ $# -ne 2 ]; then
  echo "Usage: ./local/prepare_data.sh <speech> <data>"
  exit 1; 
fi

speech=$1
data=$2

src=`basename ${speech}`

mkdir -p ${data}
if [ $stage -le 0 ]; then
  # Make ${data}/wav.scp (recoid command to pipe into feature creation)
  files=( `find -L ${speech} -name "*.wav"` )
  
  for f in ${files[@]}; do
    fname=`basename ${f}`;
    channels=`soxi ${f} | grep Channels | awk '{print $3}'`
    if [ $channels -eq 2 ]; then
      echo "${fname%%.wav} sox ${f} -b 16 -r 16000 -t wav - remix 1,2 |"  
    else
      echo "${fname%%.wav} sox ${f} -c 1 -b 16 -r 16000 -t wav - |"  
    fi
  done | LC_ALL=C sort > ${data}/wav.scp
  
  # Make Text and segments file
  LC_ALL= python local/make_text_and_segments.py --noise "<noise>"\
    ${speech} ${data}/text ${data}/segments
  
  awk '{print $1, $2}' ${data}/segments > ${data}/utt2spk
  ./utils/utt2spk_to_spk2utt.pl ${data}/utt2spk > ${data}/spk2utt
  
  echo "The following audio files had no transcription:"
  comm -23 <(awk '{print $1}' ${data}/wav.scp | LC_ALL=C sort) \
           <(awk '{print $2}' ${data}/segments | LC_ALL=C sort)
  
  echo "Fixing data dir ..."
  ./utils/fix_data_dir.sh ${data}
  
  # Get vocab
  mkdir -p data/lm
  cut -d' ' -f2- ${data}/text | tr " " "\n" | LC_ALL=C sort -u > data/lm/vocab.tmp
  
  # Get graphemes
  if [ -z $graphemes ]; then
    LC_ALL= sed 's/./& /g' data/lm/vocab.tmp | LC_ALL= tr " " "\n" | LC_ALL=C sort -u |\
      LC_ALL= grep -v '^\s*$' > data/lm/graphemes
    graphemes=data/lm/graphemes
  fi
  
  if $filter; then
    # Filter vocab based on valid graphemes. By default we essentially use all of
    # them.
    LC_ALL= python local/filter.py data/lm/vocab.tmp ${graphemes} > data/lm/vocab.map
    mv ${data}/text ${data}/text.bk && \
      cat ${data}/text.bk | utils/apply_map.pl --permissive -f 2- data/lm/vocab.map 2>/dev/null \
      > ${data}/text
    
    # Clean text
    mv ${data}/text ${data}/text.unfilt
    LC_ALL= python local/fix_text.py ${data}/text.unfilt > ${data}/text
  fi

fi

if $skip_lang; then
  stage=2
fi

if [ $stage -le 1 ]; then
  # Make lexicon
  lexicon=${src}_lexicon
  mkdir -p data/dict
  [ ! -f ${!lexicon} ] && echo "Expected ${!lexicon} to exist" && exit 1; 
  ./local/train_g2p.sh <(cut -f 1,2 ${!lexicon}) data/g2p
  ./local/create_wikipron_lex.sh <(cut -d' ' -f2- data/lm/vocab.map) ${!lexicon} \
    data/g2p data/g2p/vocab data/dict/lexicon.tmp
  
  LC_ALL= python local/fix_lexicon.py data/dict/lexicon.tmp | LC_ALL=C sort -u > data/dict/lexicon.txt
fi

./utils/fix_data_dir.sh ${data}


hr_speech=`awk '{sum+=$4-$3} END{print sum/3600}' ${data}/segments`
num_utts=`cat ${data}/segments | wc -l`
avg_sentence_len=`awk '{words+=(NF-1)} END{print words/NR}' ${data}/text`
vocab_size=`cut -d' ' -f2- ${data}/text | tr " " "\n" | sort -u | grep -v '^\s*$' | wc -l`
avg_utt_dur=`echo $hr_speech $num_utts | awk '{print $1*3600/$2}'`

echo "Prepared ${data} with:"
echo "   ${hr_speech} hr of speech"
echo "   ${num_utts} utterances"
echo "   ${avg_sentence_len} average #words/utt"
echo "   ${avg_utt_dur} average utterance duration"
echo "   ${vocab_size} # unique words"
