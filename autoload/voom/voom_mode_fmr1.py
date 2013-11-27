# voom_mode_fmr1.py
# Last Modified: 2013-10-31
# VOoM -- Vim two-pane outliner, plugin for Python-enabled Vim 7.x
# Website: http://www.vim.org/scripts/script.php?script_id=2657
# Author: Vlad Irnov (vlad DOT irnov AT gmail DOT com)
# License: CC0, see http://creativecommons.org/publicdomain/zero/1.0/

"""
VOoM markup mode for start fold markers with levels.
Similar to the default mode, that is the :Voom command.
See |voom-mode-fmr|, ../../doc/voom.txt#*voom-mode-fmr*

headline level 1 {{{1
some text
headline level 2 {{{2
more text
"""

# Define this mode as an 'fmr' mode.
MTYPE = 0

# voom_vim.makeoutline() without char stripping
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
        head = bline[:m.start()].strip()
        tline = ' %s%s|%s' %(m.group(2) or ' ', '. '*(lev-1), head)
        tlines_add(tline)
        bnodes_add(i+1)
        levels_add(lev)
    return (tlines, bnodes, levels)


# same as voom_vim.newHeadline() but without ---
def hook_newHeadline(VO, level, blnum, ln):
    """Return (tree_head, bodyLines).
    tree_head is new headline string in Tree buffer (text after |).
    bodyLines is list of lines to insert in Body buffer.
    """
    tree_head = 'NewHeadline'
    #bodyLines = ['---%s--- %s%s' %(tree_head, VO.marker, level), '']
    bodyLines = ['%s %s%s' %(tree_head, VO.marker, level), '']
    return (tree_head, bodyLines)


