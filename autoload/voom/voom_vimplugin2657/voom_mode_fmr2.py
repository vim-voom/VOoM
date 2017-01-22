# File: voom_mode_fmr2.py
# Last Modified: 2017-01-07
# Description: VOoM -- two-pane outliner plugin for Python-enabled Vim
# Website: http://www.vim.org/scripts/script.php?script_id=2657
# Author: Vlad Irnov (vlad DOT irnov AT gmail DOT com)
# License: CC0, see http://creativecommons.org/publicdomain/zero/1.0/

"""
VOoM markup mode for start fold markers with levels.
See |voom-mode-fmr2|, ../../../doc/voom.txt#*voom-mode-fmr2*

Headline text is after the start fold marker with level.

{{{1 headline level 1
some text
{{{2 headline level 2
more text
"""

import sys
if sys.version_info[0] > 2:
    xrange = range

# Define this mode as an 'fmr' mode.
MTYPE = 0


def hook_makeOutline(VO, blines):
    """Return (tlines, bnodes, levels) for Body lines blines.
    blines is either Vim buffer object (Body) or list of buffer lines.
    """
    marker = VO.marker
    marker_re_search = VO.marker_re.search
    Z = len(blines)
    tlines, bnodes, levels = [], [], []
    tlines_add, bnodes_add, levels_add = tlines.append, bnodes.append, levels.append
    #c = VO.rstrip_chars
    for i in xrange(Z):
        if not marker in blines[i]: continue
        bline = blines[i]
        m = marker_re_search(bline)
        if not m: continue
        lev = int(m.group(1))

        head = bline[m.end():] # part after the fold marker
        # strip optional special marks from left side: "o", "=", "o="
        #if head and head[0]=='o': head = head[1:]
        #if head and head[0]=='=': head = head[1:]
        # lstrip all xo= to avoid conflicts with commands that add or remove them
        head = head.lstrip('xo=')

        tline = ' %s%s|%s' %(m.group(2) or ' ', '. '*(lev-1), head.strip())
        tlines_add(tline)
        bnodes_add(i+1)
        levels_add(lev)
    return (tlines, bnodes, levels)


def hook_newHeadline(VO, level, blnum, ln):
    """Return (tree_head, bodyLines).
    tree_head is new headline string in Tree buffer (text after |).
    bodyLines is list of lines to insert in Body buffer.
    """
    tree_head = 'NewHeadline'
    bodyLines = ['%s%s %s' %(VO.marker, level, tree_head), '']
    return (tree_head, bodyLines)


