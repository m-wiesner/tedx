#!/usr/bin/env python
#-*- coding: utf-8 -*-
# Copyright 2019  Johns Hopkins University (Author: Matthew Wiesner)
# Apache 2.0

from __future__ import print_function
import argparse
import sys
import os
import unicodedata
from functools import partial
import re


VALID_CATEGORIES = ('Mc', 'Mn', 'Ll', 'Lm', 'Lo', 'Lt', 'Lu', 'Nd', 'Zs')

def _filter(s, graphemes):
    for c in s:
        if unicodedata.category(c) not in VALID_CATEGORIES and c not in graphemes:
            return False
    return True

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('vocab')
    parser.add_argument('graphemes')
    args = parser.parse_args()

    graphemes = set()
    with open(args.graphemes, encoding='utf-8') as f:
        for l in f:
            graphemes.add(l.strip())
    
    filterfun = partial(_filter, graphemes=graphemes)

    with open(args.vocab, encoding='utf-8') as f:
        for l in f:
            line_text = l.strip()
            if re.match(r"^(\([^)]*\) *)+$", line_text):
                print(line_text, line_text)
            elif filterfun(line_text):
                print(line_text, line_text)
            else:
                print(line_text, "<unk>")


if __name__ == "__main__":
    main()

