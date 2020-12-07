#!/usr/bin/env python
#-*- coding: utf-8 -*-
# Copyright 2019  Johns Hopkins University (Author: Matthew Wiesner)
# Apache 2.0

from __future__ import print_function
import argparse
import sys
import os
import epitran


def load_ref_lex(f):
    words = {}
    for l in f:
        try:
            w, pron, _ = l.strip().split('\t')
        except ValueError:
            w, pron = l.strip().split('\t')
        if w not in words:
            words[w] = []
        words[w].append(pron)
    return words


def load_hyp_lex(f):
    words = {}
    for l in f:
        try:
            w, pron = l.strip().split('\t')
        except ValueError:
            w = l.strip().split('\t')[0]
            pron = ''
        if w not in words:
            words[w] = []
        words[w].append(pron)
    return words



def make_lex(hyp, ref):
    prons = {}
    for w in hyp:
        if w not in prons:
            prons[w] = []
        if w in ref:
            prons[w].extend(ref[w])
        else:
            prons[w].extend(hyp[w])
    return prons


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('hyp_lex')
    parser.add_argument('ref_lex')
    parser.add_argument('olex')
    
    args = parser.parse_args()
    with open(args.hyp_lex, 'r', encoding='utf-8') as f:
        hyp = load_hyp_lex(f)
    with open(args.ref_lex, 'r', encoding='utf-8') as f:
        ref = load_ref_lex(f)
  
    xs = epitran.xsampa.XSampa()
    with open(args.olex, 'w', encoding='utf-8') as f: 
        for word, prons in sorted(make_lex(hyp, ref).items()):
            for pron in prons:
                pron_xsampa = u' '.join(map(xs.ipa2xs, pron.split()))
                print(u'{}\t{}'.format(word, pron_xsampa), file=f)
    
    args = parser.parse_args()


if __name__ == "__main__":
    main()

