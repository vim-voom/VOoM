# voom_mode_dokuwiki.py
# Last Modified: 2014-02-02
# VOoM -- Vim two-pane outliner, plugin for Python-enabled Vim 7.x
# Website: http://www.vim.org/scripts/script.php?script_id=2657
# Author: Vlad Irnov (vlad DOT irnov AT gmail DOT com)
# License: CC0, see http://creativecommons.org/publicdomain/zero/1.0/

"""
VOoM markup mode for DokuWiki sections.
See |voom-mode-dokuwiki|,  ../../doc/voom.txt#*voom-mode-dokuwiki*
"""
# based on voom_mode_inverseAtx.py

try:
    import vim
except ImportError:
    pass
import re

headline_match = re.compile(r'^( ?| \t[ \t]*)(={2,})(.+?)(={2,})[ \t]*$').match
# Marker character that denotes a headline in the regexp above.
CHAR = '='
# The maximum possible level.
# The number of leading marker characters for level 1 headline is MAX+1 or more.
MAX = 5

def hook_makeOutline(VO, blines):
    """Return (tlines, bnodes, levels) for Body lines blines.
    blines is either Vim buffer object (Body) or list of buffer lines.
    """
    Z = len(blines)
    tlines, bnodes, levels = [], [], []
    tlines_add, bnodes_add, levels_add = tlines.append, bnodes.append, levels.append
    for i in xrange(Z):
        if not blines[i].lstrip().startswith(CHAR):
            continue
        bline = blines[i]
        m = headline_match(bline)
        if not m:
            continue
        n = len(m.group(2))
        if n > MAX:
            lev = 1
        else:
            lev = MAX - n + 2
        head = m.group(3).strip()
        tline = '  %s|%s' %('. '*(lev-1), head)
        tlines_add(tline)
        bnodes_add(i+1)
        levels_add(lev)
    return (tlines, bnodes, levels)


def hook_newHeadline(VO, level, blnum, tlnum):
    """Return (tree_head, bodyLines).
    tree_head is new headline string in Tree buffer (text after |).
    bodyLines is list of lines to insert in Body buffer.
    """
    tree_head = 'NewHeadline'
    if level >= MAX:
        C = CHAR
    else:
        C = CHAR * (MAX - level + 1)
    bodyLines = ['=%s %s =%s' %(C, tree_head, C), '']
    return (tree_head, bodyLines)


#def hook_changeLevBodyHead(VO, h, levDelta):

def hook_doBodyAfterOop(VO, oop, levDelta, blnum1, tlnum1, blnum2, tlnum2, blnumCut, tlnumCut):
    # this is instead of hook_changeLevBodyHead()
    #print oop, levDelta, blnum1, tlnum1, blnum2, tlnum2, tlnumCut, blnumCut
    Body = VO.Body
    Z = len(Body)
    bnodes, levels = VO.bnodes, VO.levels

    # blnum1 blnum2 is first and last lnums of Body region pasted, inserted
    # during up/down, or promoted/demoted.
    if blnum1:
        assert blnum1 == bnodes[tlnum1-1]
        if tlnum2 < len(bnodes):
            assert blnum2 == bnodes[tlnum2]-1
        else:
            assert blnum2 == Z

    # blnumCut is Body lnum after which a region was removed during 'cut'
    if blnumCut:
        if tlnumCut < len(bnodes):
            assert blnumCut == bnodes[tlnumCut]-1
        else:
            assert blnumCut == Z

    ### Change levels and/or sections of headlines in the affected region.
    if not levDelta:
        return

    # Examine each headline in the affected region from top to bottom.
    # Change levels.
    # Correct levels that exceed the MAX: set them to MAX.
    invalid_levs = [] # tree lnums of nodes with level > MAX
    for i in xrange(tlnum1, tlnum2+1):
        # required level based on new VO.levels, can be disallowed
        lev_ = levels[i-1]
        # Body line
        bln = bnodes[i-1]
        L = Body[bln-1] # original Body headline line

        if lev_ <= MAX:
            n = MAX - lev_ + 1
        # MAX level exceeded
        else:
            n = 1
            invalid_levs.append(i)
            levels[i-1] = MAX # correct VO.levels
            # don't change Body line if level is already at MAX
            if lev_ - levDelta == MAX:
                continue
        m = headline_match(L)
        # set Body line
        # don't bother changing closing CHARs if there are too many of them
        if len(m.group(4)) <= MAX+1:
            Body[bln-1] = '%s=%s%s=%s' %(m.group(1), CHAR * n, m.group(3), CHAR * n)
        else:
            Body[bln-1] = '%s=%s%s' %(m.group(1), CHAR * n, L[m.end(2):])

    ### --- the end ---
    if invalid_levs:
        vim.command("call voom#ErrorMsg('VOoM (dokuwiki): Disallowed levels have been corrected after ''%s''')" %oop)
        invalid_levs = ', '.join(['%s' %i for i in invalid_levs])
        vim.command("call voom#ErrorMsg('     level set to maximum (%s) for nodes: %s')" %(MAX, invalid_levs))


