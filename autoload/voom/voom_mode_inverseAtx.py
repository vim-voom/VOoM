# voom_mode_inverseAtx.py
# Last Modified: 2013-11-07
# VOoM -- Vim two-pane outliner, plugin for Python-enabled Vim 7.x
# Website: http://www.vim.org/scripts/script.php?script_id=2657
# Author: Vlad Irnov (vlad DOT irnov AT gmail DOT com)
# License: CC0, see http://creativecommons.org/publicdomain/zero/1.0/

"""
VOoM markup mode for inverse Atx-style headers.
See |voom-mode-various|,  ../../doc/voom.txt#*voom-mode-various*

Headlines start with '@'. There is a maximum of 3 levels:

@@@ Headline level 1
@@ Headline level 2
@ Headline level 3

To change the character that denotes headlines and the maximum level, change
module-level constants CHAR and MAX below.
You can also change them by adding options to .vimrc:
    let g:voom_inverseAtx_char = '^'
    let g:voom_inverseAtx_max = 5

"""

# Marker character that denotes a headline. It can be any ASCII character.
CHAR = '@'
# The number of marker characters for level 1 headline. This is also the maximum possible level.
MAX = 3

try:
    import vim
    if vim.eval('exists("g:voom_inverseAtx_char")')=='1':
        CHAR = vim.eval("g:voom_inverseAtx_char")
    if vim.eval('exists("g:voom_inverseAtx_max")')=='1':
        MAX = int(vim.eval("g:voom_inverseAtx_max"))
except ImportError:
    pass

import re

# Use this if whitespace after marker chars is optional.
headline_match = re.compile(r'^(%s+)' %re.escape(CHAR)).match

# Use this if a whitespace is required after marker chars.
#headline_match = re.compile(r'^(%s+)\s' %re.escape(CHAR)).match


# based on voom_mode_hashes.py
def hook_makeOutline(VO, blines):
    """Return (tlines, bnodes, levels) for Body lines blines.
    blines is either Vim buffer object (Body) or list of buffer lines.
    """
    Z = len(blines)
    tlines, bnodes, levels = [], [], []
    tlines_add, bnodes_add, levels_add = tlines.append, bnodes.append, levels.append
    for i in xrange(Z):
        if not blines[i].startswith(CHAR):
            continue
        bline = blines[i]
        m = headline_match(bline)
        # Uncomment the next line if whitespace is required after marker chars.
        #if not m: continue
        n = len(m.group(1))
        if n >= MAX:
            lev = 1
        else:
            lev = MAX - n + 1
        head = bline.lstrip(CHAR).strip()
        # Do this instead if optional closing markers need to be stripped.
        #head = bline.rstrip().strip(CHAR).strip()
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
        n = 1
    else:
        n = MAX - level + 1
    bodyLines = ['%s %s' %(CHAR * n, tree_head), '']
    return (tree_head, bodyLines)


## This is not good enough: Body is always modified when move right fails
## because MAX level was exceeded, even if no changes to headlines were made.
#def hook_changeLevBodyHead(VO, h, levDelta):
#    """Increase of decrease level number of Body headline by levDelta."""
#    if levDelta==0: return h
#    m = headline_match(h)
#    n = len(m.group(1))
#    if n >= MAX:
#        lev = 1
#    else:
#        lev = MAX - n + 1
#    level = lev + levDelta
#    if level >= MAX:
#        n = 1
#    else:
#        n = MAX - level + 1
#    return '%s%s' %(CHAR * n, h[m.end(1):])


# based on voom_mode_latex.py
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
        Body[bln-1] ='%s%s' %(CHAR * n, L[m.end(1):])

    ### --- the end ---
    if invalid_levs:
        vim.command("call voom#ErrorMsg('VOoM (inverseAtx): Disallowed levels have been corrected after ''%s''')" %oop)
        invalid_levs = ', '.join(['%s' %i for i in invalid_levs])
        vim.command("call voom#ErrorMsg('     level set to maximum (%s) for nodes: %s')" %(MAX, invalid_levs))


