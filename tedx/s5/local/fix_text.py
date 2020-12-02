#!/usr/bin/env python
#-*- coding: utf-8 -*-
# Copyright 2019  Johns Hopkins University (Author: Matthew Wiesner)
# Apache 2.0

from __future__ import print_function
import argparse
import sys
import os
import re


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('text')
    args = parser.parse_args()

    with open(args.text, encoding='utf-8') as f:
        for l in f:
            if re.match(r"^\w+ *(<[^>]*> *)+$", l, re.UNICODE):
                print(l.strip())
            elif "<" in l or ">" in l:
                continue;
            else:
                print(l.strip())                       

if __name__ == "__main__":
    main()

