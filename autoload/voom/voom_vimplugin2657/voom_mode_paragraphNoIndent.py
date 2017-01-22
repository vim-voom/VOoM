# File: voom_mode_paragraphNoIndent.py
# Last Modified: 2017-01-07
# Description: VOoM -- two-pane outliner plugin for Python-enabled Vim
# Website: http://www.vim.org/scripts/script.php?script_id=2657
# Author: Vlad Irnov (vlad DOT irnov AT gmail DOT com)
# License: CC0, see http://creativecommons.org/publicdomain/zero/1.0/

"""
VOoM markup mode for paragraphs identified by non-indented lines.
Any line that starts with a character other than space or tab is a headline.
Everything is at level 1. Levels >1 are not possible.

See |voom-mode-paragraphNoIndent|,  ../../../doc/voom.txt#*voom-mode-paragraphNoIndent*
"""

import sys
if sys.version_info[0] > 2:
        xrange = range

# Disable unsupported outline operations: special node marks, insert new headline as child, move right.
MTYPE = 2

whitespace = ('\t', ' ')

def hook_makeOutline(VO, blines):
    """Return (tlines, bnodes, levels) for Body lines blines.
    blines is either Vim buffer object (Body) or list of buffer lines.
    """
    # every line that doesn't start with a space or tab is level 1 headline
    Z = len(blines)
    tlines, bnodes, levels = [], [], []
    tlines_add, bnodes_add, levels_add = tlines.append, bnodes.append, levels.append
    for i in xrange(Z):
        bline = blines[i]
        if not bline or bline[0] in whitespace: # THE ONLY DIFFERENCE FROM voom_mode_paragraphIndent.py
            continue
        bline = bline.strip()
        if not bline:
            continue
        tlines_add('  |%s' %bline)
        bnodes_add(i+1)
        levels_add(1)
    return (tlines, bnodes, levels)


def hook_newHeadline(VO, level, blnum, tlnum):
    """Return (tree_head, bodyLines).
    tree_head is new headline string in Tree buffer (text after |).
    bodyLines is list of lines to insert in Body buffer.
    """
    return ('NewHeadline', ['NewHeadline'])


### DO NOT DEFINE THIS HOOK -- level never changes, it is always 1
#def hook_changeLevBodyHead(VO, h, levDelta):
#    """Increase of decrease level number of Body headline by levDelta."""
#    return h


