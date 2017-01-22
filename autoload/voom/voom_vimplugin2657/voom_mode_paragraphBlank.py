# File: voom_mode_paragraphBlank.py
# Last Modified: 2017-01-07
# Description: VOoM -- two-pane outliner plugin for Python-enabled Vim
# Website: http://www.vim.org/scripts/script.php?script_id=2657
# Author: Vlad Irnov (vlad DOT irnov AT gmail DOT com)
# License: CC0, see http://creativecommons.org/publicdomain/zero/1.0/

"""
VOoM markup mode for paragraphs separated by blank lines. The first line of
each paragraph is level 1 headline. That is the first non-blank line and any
non-blank line preceded by a blank line is a headline.

See |voom-mode-paragraphBlank|,  ../../../doc/voom.txt#*voom-mode-paragraphBlank*

Everything is at level 1. Levels >1 are not possible.

There are must be a blank line after the last paragraph, that is end-of-file.
Otherwise there are will be errors when the last paragraph is moved.
"""

import sys
if sys.version_info[0] > 2:
    xrange = range

# Disable unsupported outline operations: special node marks, insert new headline as child, move right.
MTYPE = 2


def hook_makeOutline(VO, blines):
    """Return (tlines, bnodes, levels) for Body lines blines.
    blines is either Vim buffer object (Body) or list of buffer lines.
    """
    # A line is headline level 1 if it is: preceded by a blank line (or is
    # first buffer line) and is non-blank.
    Z = len(blines)
    tlines, bnodes, levels = [], [], []
    tlines_add, bnodes_add, levels_add = tlines.append, bnodes.append, levels.append
    bline_ = ''
    for i in xrange(Z):
        bline = blines[i].strip()
        if bline_ or not bline:
            bline_ = bline
            continue
        bline_ = bline
        tlines_add('  |%s' %bline)
        bnodes_add(i+1)
        levels_add(1)
    return (tlines, bnodes, levels)


def hook_newHeadline(VO, level, blnum, tlnum):
    """Return (tree_head, bodyLines).
    tree_head is new headline string in Tree buffer (text after |).
    bodyLines is list of lines to insert in Body buffer.
    """
    # Add blank line when inserting after non-blank Body line.
    if VO.Body[blnum-1].strip():
        return ('NewHeadline', ['', 'NewHeadline', ''])
    else:
        return ('NewHeadline', ['NewHeadline', ''])


### DO NOT DEFINE THIS HOOK -- level never changes, it is always 1
#def hook_changeLevBodyHead(VO, h, levDelta):
#    """Increase of decrease level number of Body headline by levDelta."""
#    return h


# This is needed to insert blank line missing from end-of-file. Code is from rest mode.
def hook_doBodyAfterOop(VO, oop, levDelta, blnum1, tlnum1, blnum2, tlnum2, blnumCut, tlnumCut):
    # this is instead of hook_changeLevBodyHead()
    #print('oop=%s levDelta=%s blnum1=%s tlnum1=%s blnum2=%s tlnum2=%s tlnumCut=%s blnumCut=%s' % (oop, levDelta, blnum1, tlnum1, blnum2, tlnum2, tlnumCut, blnumCut))
    Body = VO.Body
    Z = len(Body)
    bnodes = VO.bnodes

    # blnum1 blnum2 is first and last lnums of Body region pasted, inserted
    # during up/down, or promoted/demoted.
    if blnum1:
        assert blnum1 == bnodes[tlnum1-1]
        if tlnum2 < len(bnodes):
            assert blnum2 == bnodes[tlnum2]-1
        else:
            assert blnum2 == Z

    # blnumCut is Body lnum after which a region was removed during 'cut',
    # 'up', 'down'. We need to check if there is blank line between nodes
    # used to be separated by the cut/moved region to prevent headline loss.
    if blnumCut:
        if tlnumCut < len(bnodes):
            assert blnumCut == bnodes[tlnumCut]-1
        else:
            assert blnumCut == Z

    # Total number of added lines minus number of deleted lines.
    b_delta = 0

#    ### After 'cut' or 'up': insert blank line if there is none
#    # between the nodes used to be separated by the cut/moved region.
#    if (oop=='cut' or oop=='up') and (0 < blnumCut < Z) and Body[blnumCut-1].strip():
#        Body[blnumCut:blnumCut] = ['']
#        update_bnodes(VO, tlnumCut+1 ,1)
#        b_delta+=1

    if oop=='cut':
        return

    ### Prevent loss of headline after last node in the region:
    # insert blank line after blnum2 if blnum2 is not blank, that is insert
    # blank line before bnode at tlnum2+1.
    if blnum2 < Z and Body[blnum2-1].strip():
        Body[blnum2:blnum2] = ['']
        update_bnodes(VO, tlnum2+1 ,1)
        b_delta+=1

    ### Prevent loss of first headline: make sure it is preceded by a blank line
    blnum1 = bnodes[tlnum1-1]
    if blnum1 > 1 and Body[blnum1-2].strip():
        Body[blnum1-1:blnum1-1] = ['']
        update_bnodes(VO, tlnum1 ,1)
        b_delta+=1

#    ### After 'down' : insert blank line if there is none
#    # between the nodes used to be separated by the moved region.
#    if oop=='down' and (0 < blnumCut < Z) and Body[blnumCut-1].strip():
#        Body[blnumCut:blnumCut] = ['']
#        update_bnodes(VO, tlnumCut+1 ,1)
#        b_delta+=1

    assert len(Body) == Z + b_delta


def update_bnodes(VO, tlnum, delta):
    """Update VO.bnodes by adding/substracting delta to each bnode
    starting with bnode at tlnum and to the end.
    """
    bnodes = VO.bnodes
    for i in xrange(tlnum, len(bnodes)+1):
        bnodes[i-1] += delta



