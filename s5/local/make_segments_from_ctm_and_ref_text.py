#!/usr/bin/env python
#-*- coding: utf-8 -*-
# Copyright 2019  Johns Hopkins University (Author: Matthew Wiesner)
# Apache 2.0

from __future__ import print_function
import argparse
import sys
import os


def _read_ctm_line(l):
    try:
        recoid, _, start, dur, word= l.strip().split()
    except ValueError:
        recoid, _, start, dur, word, _ = l.strip().split()
    return recoid, (float(start), float(dur), word)


def _read_text_line(l):
    uttid, text = l.strip().split(None, 1)
    recoid, sentence_num = uttid.rsplit('_', 1)
    return recoid, (
        uttid,
        text.split()
    )

def align(ctm, segments):
    '''
        Takes a representation of a ctm and segments file and returns a
        representation of the segmentation.
        
        Inputs: ctm -- [(recoid, (float(start), float(dur), word1)), ...]
                segments -- [(uttid1, [word1, word2, ...]), (uttid2, [word1, word2, ...]), ...]

        A dynamic program aligns the ctm file to a reference segmentation.
        The words from the segmentation are treated as reference where
        utterance boundary tokens are inserted to keep track of utterance
        boundaries. The reference segmentation starts with a sentinal (empty)
        utterance with end of utterance boundary symbol <s>,
        name <s> because it is the start of the reference segmentation of the
        speech recording with id=recoid.
        
        The reference are the columns in the dynamic programming table
        (row x col). The hypothesis words are from the ctm file. They are rows
        in the table. 
        
        There can be holes in both the ctm and/or the segmentation: holes in
        the ctm occur when there is text in the reference segmentation that
        does not occur in the ctm. This generally happens when there is speech
        that was not able to be aligned due to erroneous, or non-standard
        transcription practices.
        
        Holes in the reference segmentation occur when portions of audio data
        were also not properly transcribed, or if the translation for a portion
        of the audio file is missing.
        
        Holes in the reference segmentation:
        -------------------------------------
        There are two cases. The holes can be internal to a reference sentence
        or between reference segments. 
        
            Case 1: Internal holes
                This is a normal case and the insertion cost is 1.0
            Case 2: Holes between segments
                We want to align the ctm tokens to a sentence boundary token
                rather than substitute them. We allow for a lower insertion
                cost at sentence boundaries than elsewhere 

        Holes in the ctm (or extra text, e.g. sentence boundaries,
        in the reference segmentation):
        ------------------------------
        Extra text that doesn't occur in the ctm should always be aligned to a
        single word in the ctm. Since we know sentence boundary tokens never
        occur in the ctm, the cost of deleting these is set to 0.
        Otherwise the deletion cost is normal.
        
    '''
    ref_words = ['<s>']
    sentence_boundaries = set(['<s>'])
    for s in segments :
        for w in s[1]:
            ref_words.append(w)
        ref_words.append(s[0])
        sentence_boundaries.add(s[0])

    costs = [[0 for j in range(len(ref_words) + 1)] for i in range(len(ctm) + 1)]   
    costs[0] = [j for j in range(len(ref_words) + 1)]
    for i in range(len(ctm) + 1):
        costs[i][0] = i

    backtrace = [[0 for j in range(len(ref_words) + 1)] for i in range(len(ctm) + 1)]

    for i in range(1, len(ctm) + 1):
        for j in range(1, len(ref_words) + 1): 
            sub_cost = (ref_words[j-1] != ctm[i-1][2])
            ins_cost = 0.5 if ref_words[j-1] in sentence_boundaries else 1.0
            del_cost = 0.0 if ref_words[j-1] in sentence_boundaries else 1.0
            next_state_costs = [
                costs[i-1][j-1] + sub_cost,
                costs[i-1][j] + ins_cost,
                costs[i][j-1] + del_cost,
            ]
            costs[i][j] = min(next_state_costs)
            backtrace[i][j] = next_state_costs.index(costs[i][j])                
    
    # Do backtrace
    i, j = len(ctm), len(ref_words)
    segmentation = {}
    while j > 1 or i > 1:
        word = ref_words[j-1]
        if word in sentence_boundaries:
            sentence = word
        start, end = ctm[i-1][0], ctm[i-1][0] + ctm[i-1][1]
      
        if sentence not in segmentation:
            segmentation[sentence] = [99999999.0, 0.0]  
          
        best_transition = backtrace[i][j] 
        print(i, j, best_transition, start, end, segmentation[sentence], ref_words[j-1], ctm[i-1])
        # Substitution
        if best_transition == 0:
            i -= 1
            j -= 1
        # Insertion
        elif best_transition == 1:
            i -=1
        # Deletion
        elif best_transition == 2:
            j -= 1
        
        # Only look at the reference words that are not sentence boundaries
        # when updating timing information.
        if best_transition != 1 or word not in sentence_boundaries:
            if start < segmentation[sentence][0]:
                segmentation[sentence][0] = start
        
            if end > segmentation[sentence][1]:
                segmentation[sentence][1] = end 
    
    segmentation.pop('<s>', None)     
    return segmentation 


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('text',
        help='',
        type=str
    )
    parser.add_argument('ctm')
    parser.add_argument('segments')
    args = parser.parse_args()

    # Read in CTM
    recoid2element_list = {}
    print("Reading", args.ctm, "...")
    with open(args.ctm) as f_ctm:
        for l in f_ctm:
            recoid, el = _read_ctm_line(l) # el = (start, duration, word)
            if recoid not in recoid2element_list:
                recoid2element_list[recoid] = []
            recoid2element_list[recoid].append(el)
   
    # Sort CTM by time 
    for recoid in recoid2element_list:
        recoid2element_list[recoid] = sorted(recoid2element_list[recoid], key=lambda x: x[0])  

    # Read Text 
    recoid2verses = {}
    print("Reading", args.text, "...")
    with open(args.text) as f_text:
        for l in f_text:
            recoid, verses = _read_text_line(l)
            if recoid not in recoid2verses:
                recoid2verses[recoid] = []
            recoid2verses[recoid].append(verses)
    
    # Sort Text by verse number 
    for recoid in recoid2verses:
        recoid2verses[recoid] = sorted(recoid2verses[recoid], key=lambda x: x[0])
   
    segments_dict = {}
    print("Aligning", args.ctm, "to", args.text, "...") 
    num_recos = len(recoid2element_list.items())
    reco_idx = 1
    for recoid, ctm in sorted(recoid2element_list.items(), key=lambda x: x[0]):
        print('\r Audio file: ', recoid, reco_idx, ' of ', num_recos, end='')
        reco_idx += 1
        try:
            segments = recoid2verses[recoid]
        except:
            print()
            print('Missing ', recoid, ' from ctm')
            continue;
    
        segmentation = align(ctm, segments) 
        segments_dict.update(segmentation)    
    
    # Dump the segments to a file
    print("Dumping segments to", args.segments)
    with open(args.segments, 'w') as f_segments:
        for uttid, seg in sorted(segments_dict.items(), key=lambda x: x[0]):
            recoid = uttid.rsplit('_', 1)[0]
            segment_str = '{} {} {:.2f} {:.2f}'.format(uttid, recoid, seg[0], seg[1]) 
            print(segment_str, file=f_segments)

    
if __name__ == "__main__":
    main()

