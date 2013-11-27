# voom_mode_fmr2.py
# Last Modified: 2013-10-31
# VOoM -- Vim two-pane outliner, plugin for Python-enabled Vim 7.x
# Website: http://www.vim.org/scripts/script.php?script_id=2657
# Author: Vlad Irnov (vlad DOT irnov AT gmail DOT com)
# License: CC0, see http://creativecommons.org/publicdomain/zero/1.0/

"""
VOoM markup mode. Headline text is after the start fold marker with level.
See |voom-mode-fmr|, ../../doc/voom.txt#*voom-mode-fmr*

{{{1 headline level 1
some text
{{{2 headline level 2
more text
"""

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
        #head = bline[:m.start()].lstrip().rstrip(c).strip('-=~').strip()
        head = bline[m.end():]
        # strip special marks o=
        if head and head[0]=='o': head = head[1:]
        if head and head[0]=='=': head = head[1:]
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


