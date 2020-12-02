# tedx

This repository so far holds the recipes for ASR systems using the tedx data scraped from the web, as well as recipes segmenting the speech according to existing sentences,
such as those produced by an MT aligner. The recipes are meant to be run inside of Kaldi.

## Installation
1. Make sure Kaldi is installed somewhere (KALDI_ROOT)
2. Then in some directory run the following lines

  ``
  git clone https://github.com/m-wiesner/tedx.git
  mv tedx KALDI_ROOT/egs/
  ``
## Aligning the Audio to the MT sentences
1. Go to the tedx. direction

  ``cd KALDI_ROOT/egs/tedx/s5``

2. Train a basic acoustic model, decode a held-out evaluation set to compute WER, align the MT data

  ``./run.sh --src fr --tgt en``
