export KALDI_ROOT=`pwd`/../../..
[ -f $KALDI_ROOT/tools/env.sh ] && . $KALDI_ROOT/tools/env.sh

#[ ! -f /export/babel/data/software/env.sh ] && echo >&2 "The file /export/babel/data/software/env.sh is not present -> Exit!" && exit 1
#. /export/babel/data/software/env.sh

export PATH=$PWD/utils/:$KALDI_ROOT/tools/openfst/bin:$KALDI_ROOT/tools/sph2pipe_v2.5/:/export/b09/mwiesner/LORELEI_2019_test/LORELEI/tools/kaldi/tools/srilm/lm/bin/i686-m64:$PWD:$PATH
#/export/a15/MStuDy/Matthew/KALDI_LORELEI/LORELEI/tools/kaldi_github/tools/phonetisaurus-g2p:$PATH

[ ! -f $KALDI_ROOT/tools/config/common_path.sh ] && echo >&2 "The standard file $KALDI_ROOT/tools/config/common_path.sh is not present -> Exit!" && exit 1
. $KALDI_ROOT/tools/config/common_path.sh

export VENV=/export/b09/mwiesner/LORELEI_2019_test/LORELEI/tools/venv_lorelei/bin/activate
#export ROOT=`pwd`/../../..
#export VENV=${ROOT}/tools/venv_lorelei/bin/activate
source ${VENV}

export LC_ALL=C
