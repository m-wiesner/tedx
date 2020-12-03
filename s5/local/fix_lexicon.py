#!/usr/bin/env python
#-*- coding: utf-8 -*-
# Copyright 2019  Johns Hopkins University (Author: Matthew Wiesner)
# Apache 2.0

from __future__ import print_function
import argparse
import sys
import os
import re


def _any_numeric(s):
    for c in s:
        if c.isnumeric():
            return True
    return False


def process_lexicon(f, noise, unk, number):
    for l in f:
        try:
            word, pron = l.strip().split(None, 1)
        except ValueError:
            word = l.strip().split(None, 1)[0]
            pron = '<empty>'
        
        if pron == '<empty>':
            if _any_numeric(word):
                pron = number
            else:
                pron = unk.split()[1]
            print('{} {}'.format(word, pron))
            continue;
        if pron.strip() == '':
            print('{} {}'.format(word, unk.split()[1]).strip())
            continue;
        if word.strip() == noise.strip().split()[0]:
            print(noise.strip())
            continue;

        word_parts = re.split(r'[0-9]*', word)
        # We assume word_parts has only 2 elements ('', word) or (word, '')
        # if word_parts has 3 elements, then alignment between each part and
        # subsequences of the pron are needed and we don't have that so
        # we ignore this case which is relatively rare anyway.
        if len(word_parts) == 1:
            print('{} {}'.format(word, pron).strip())
        elif len(word_parts) == 2:
            if word_parts[0].strip() == '':
                print('{} {}'.format(word, ' '.join([number, pron])).strip()) 
            elif word_parts[1].strip() == '':
                print('{} {}'.format(word, ' '.join([pron, number])).strip()) 
            else:
                pron_parts = pron.split()
                for i in range(1, len(pron_parts)+1):
                    print(
                        '{} {}'.format(word,
                            ' '.join([
                                    ' '.join(pron_parts[0:i]),
                                    number,
                                    ' '.join(pron_parts[i:-1]),
                                ]
                            )
                        ).strip()
                    )
        else:
            pron_parts = pron.split()
            for i in range(0, len(pron_parts)+1):
                try:
                    print('{} {}'.format(word,
                        ' '.join(
                            [' '.join(pron_parts[0:i]), number, ' '.join(pron_parts[i:-1])]
                            )
                        ).strip()
                    )
                except ValueError:
                    print('{} {}'.format(word, ' '.join([pron, number])).strip())  

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('lexicon')
    parser.add_argument('--noise', default='<noise> <noise>')
    parser.add_argument('--unk', default='<unk> <oov>')
    parser.add_argument('--silence', default='<silence> SIL')
    parser.add_argument('--number', default='<number>')
    args = parser.parse_args()

    print('<silence> SIL')
    print(args.unk)
    with open(args.lexicon, encoding='utf-8') as f:
        process_lexicon(f, args.noise, args.unk, args.number)

if __name__ == "__main__":
    main()

