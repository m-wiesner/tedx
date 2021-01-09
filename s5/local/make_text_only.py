#!/usr/bin/env python
#-*- coding: utf-8 -*-
# Copyright 2020  Johns Hopkins University (Author: Matthew Wiesner)
# Apache 2.0

from __future__ import print_function
import argparse
import sys
import os
import glob
import regex as re
import unicodedata


# Keep Markings such as vowel signs, all letters, and decimal numbers 
VALID_CATEGORIES = ('Mc', 'Mn', 'Ll', 'Lm', 'Lo', 'Lt', 'Lu', 'Nd', 'Zs')
noise_pattern = re.compile(r'\([^)]*\)', re.UNICODE)
apostrophe_pattern = re.compile(r"(\w)'(\w)")
apostrophe_tokenizer_pattern = re.compile(r" *\u2019 *", re.UNICODE)
html_tags = re.compile(r"(& *[^ ;]* *;)|(< */?[iu] *>)")
KEEP_LIST = [u'\u2019']

def _filter(s):
    return unicodedata.category(s) in VALID_CATEGORIES or s in KEEP_LIST 


def normalize_space(c):
    if unicodedata.category(c) == 'Zs':
        return " "
    else:
        return c


def _parse_vtt(f, noise, keep_segments=False):
    lines = f.read()
    if not keep_segments:
        lines = lines.replace('\n', ' ')
    for l in lines.split('\n'): 
        if l.strip('- ') != '':
            line_parts = noise_pattern.sub(noise, l)
            line_parts = apostrophe_pattern.sub(r"\1\u2019\2", line_parts)
            line_parts = apostrophe_tokenizer_pattern.sub(r"\u2019", line_parts)
            line_parts = html_tags.sub('', line_parts)
            line_parts_new = []
            for lp in line_parts.split(noise):
                line_parts_new.append(
                    ''.join(
                        [i for i in filter(_filter, lp.strip().replace('-', ' '))] 
                    )
                )
            joiner = ' ' + noise + ' '
            line_new = joiner.join(line_parts_new)
            line_new = re.sub(r"\p{Zs}", lambda m: normalize_space(m.group(0)), line_new)
            line_new = re.sub(r' +', ' ', line_new).strip().lower()
            yield line_new


def _format_uttid(recoid, start):
    start = '{0:08d}'.format(int(float(start)*100))
    return '_'.join([recoid, start])
 

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('speech', help='data directory', type=str)
    parser.add_argument('text', help='output kaldi text file', type=str)
    parser.add_argument('--noise', help='the symbol for noise token',
        type=str, default='(noise)'
    )
    parser.add_argument('--keep-segments', action='store_true',
        help='keep line segments in input file'
    )
    args = parser.parse_args()

    srcname = os.path.basename(args.speech)
    srcname = srcname.split('-')[0]
    vtt_files = glob.glob('{}/*{}'.format(args.speech, srcname))
    text = {}
    for fname in vtt_files:
        recoid = os.path.basename(fname).split('.')[0]
        with open(fname, encoding='utf-8') as f:
            print("\r ", fname, end="")
            for i, line in enumerate(_parse_vtt(f, args.noise, args.keep_segments)):
                if args.keep_segments:
                    uttid = '{}_{:04d}'.format(recoid, i)
                    text[uttid] = '{} {}'.format(uttid, line)
                else:
                    uttid = recoid
                    text[uttid] = '{} {}'.format(uttid, line)

    print()
    
    with open(args.text, 'w', encoding='utf-8') as f:
        for uttid in sorted(text):
            print(text[uttid], file=f)

if __name__ == "__main__":
    main()
