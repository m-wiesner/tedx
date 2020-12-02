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
html_tags = re.compile(r"(&[^ ;]*;)|(</?[iu]>)")
KEEP_LIST = [u'\u2019']

def _filter(s):
    return unicodedata.category(s) in VALID_CATEGORIES or s in KEEP_LIST 


def time2sec(time):
    hr, mn, sec = time.split(':')
    return int(hr) * 3600.0 + int(mn) * 60.0 + float(sec)


def _parse_time_segment(l):
    start, end = l.split(' --> ')
    start = time2sec(start)    
    end = time2sec(end)
    return start, end


#def strip_punc(c):
#    if c in ("'", "(", ")"):
#        return c
#    else:
#        return ""
#
#
def normalize_space(c):
    if unicodedata.category(c) == 'Zs':
        return " "
    else:
        return c


def _parse_vtt(f, noise):
    lines = f.read()
    blocks = lines.split('\n\n') 
    for i, b in enumerate(blocks, -1):
        if i > 0 and b.strip() != "":
            b_lines = b.split('\n')
            start, end = _parse_time_segment(b_lines[0])
            line = ' '.join(b_lines[1:])
            line_new = line
            if line.strip('- ') != '':
                line_parts = noise_pattern.sub(noise, line_new)
                line_parts = apostrophe_pattern.sub(r"\1\u2019\2", line_parts)
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
            #line = re.sub(r"\p{P}", lambda m: strip_punc(m.group(0)), line)
            #line = re.sub(r' +', ' ', line).strip().lower()
            yield start, end, line_new


def _format_uttid(recoid, start):
    start = '{0:08d}'.format(int(float(start)*100))
    return '_'.join([recoid, start])
 

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('speech', help='data directory', type=str)
    parser.add_argument('text', help='output kaldi text file', type=str)
    parser.add_argument('segments', help='output kaldi segments file', type=str)
    parser.add_argument('--noise', help='the symbol for noise token',
        type=str, default='(noise)'
    )
    args = parser.parse_args()

    srcname = os.path.basename(args.speech)
    vtt_files = glob.glob('{}/*/*{}.vtt'.format(args.speech, srcname))
    segments = {}
    text = {}
    for fname in vtt_files:
        recoid = os.path.basename(fname).split('.')[0]
        with open(fname, encoding='utf-8') as f:
            print("\r ", fname, end="")
            for start, end, line in _parse_vtt(f, args.noise):
                uttid = _format_uttid(recoid, start)
                segments[uttid] = '{} {} {:.2f} {:.2f}'.format(uttid, recoid, start, end)
                text[uttid] = '{} {}'.format(uttid, line)
    print()
    
    with open(args.text, 'w', encoding='utf-8') as f:
        for uttid in sorted(text):
            print(text[uttid], file=f)

    with open(args.segments, 'w', encoding='utf-8') as f:
        for uttid in sorted(segments):
            print(segments[uttid], file=f)
        

if __name__ == "__main__":
    main()

