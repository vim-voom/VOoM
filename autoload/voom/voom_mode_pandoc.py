# voom_mode_pandoc.py
# Last Modified: 2014-04-09
# VOoM -- Vim two-pane outliner, plugin for Python-enabled Vim 7.x
# Website: http://www.vim.org/scripts/script.php?script_id=2657
# Author: Vlad Irnov (vlad DOT irnov AT gmail DOT com)
# License: CC0, see http://creativecommons.org/publicdomain/zero/1.0/

"""
VOoM markup mode for Pandoc Markdown headers.
See |voom-mode-pandoc|,   ../../doc/voom.txt#*voom-mode-pandoc*
"""

### NOTES
# The code is identical to voom_mode_markdown.py except that the parser ignores
# headlines that:
#  - are not preceded by a blank line, or another headline, or an end of fenced block
#  - are inside fenced code blocks.

LEVELS_ADS = {1:'=', 2:'-'}
ADS_LEVELS = {'=':1, '-':2}

def hook_makeOutline(VO, blines):
    """Return (tlines, bnodes, levels) for Body lines blines.
    blines is either Vim buffer object (Body) or list of buffer lines.
    """
    Z = len(blines)
    tlines, bnodes, levels = [], [], []
    tlines_add, bnodes_add, levels_add = tlines.append, bnodes.append, levels.append

    # trailing whitespace is always removed with rstrip()
    #
    # underline-style, overrides hashes-style:
    #    head   L1, blines[i]    -- current line, title line, not blank
    #   ------  L2, blines[i+1]  -- any number of = or - only
    #
    # hashes-style:
    #   ## head L1, blines[i]    -- current line
    #   abcde   L2, blines[i+1]
    #

    # Set this once when headline with level 1 or 2 is encountered.
    # 0 or 1 -- False, use underline-style (default); 2 -- True, use hashes-style
    useHash = 0
    # Set this once when headline with hashes is encountered.
    # 0 or 1 -- True, use closing hashes (default); 2 -- False, do not use closing hashes
    useCloseHash = 0

    # Keep track of fenced code blocks where headlines are ignored.
    isFenced = ''
    # Set True on lines after which a new headline is allowed: blank line,
    # headline, end-of-fenced-block. Also applies to start-of-fenced-block.
    ok = 1
    L2 = blines[0].rstrip() # first Body line
    isHead = False
    for i in xrange(Z):
        L1 = L2
        j = i+1
        if j < Z:
            L2 = blines[j].rstrip()
        else:
            L2 = ''

        if not L1:
            ok = 1
            continue

        # ignore headlines inside fenced code block
        if isFenced:
            if L1.startswith(isFenced) and L1.lstrip(isFenced[0])=='':
                isFenced = ''
                ok = 1
            continue

        # Headline is allowed only after a blank line, another headline,
        # end-of-fenced block. Same for start-of-fenced-block.
        if not ok:
            continue

        # new fenced code block
        if L1.startswith('~~~') or L1.startswith('```'):
            ch = L1[0]
            isFenced = ch*(len(L1)-len(L1.lstrip(ch)))
            continue

        if L2 and (L2[0] in ADS_LEVELS) and not L2.lstrip(L2[0]):
            isHead = True
            lev = ADS_LEVELS[L2[0]]
            head = L1.strip()
            L2 = '' # this will set ok=1 on the next line (underline)
            if not useHash:
                useHash = 1
        elif L1.startswith('#') and not L1.startswith('#. '):
            ok = 1
            isHead = True
            lev = len(L1) - len(L1.lstrip('#'))
            head = L1.strip('#').strip()
            if not useHash and lev < 3:
                useHash = 2
            if not useCloseHash:
                if L1.endswith('#'): useCloseHash = 1
                else: useCloseHash = 2
        else:
            ok = 0
            continue

        if isHead:
            isHead = False
            tline = '  %s|%s' %('. '*(lev-1), head)
            tlines_add(tline)
            bnodes_add(j)
            levels_add(lev)

    # don't clobber these when parsing clipboard during Paste
    # which is the only time blines is not Body
    if blines is VO.Body:
        VO.useHash = useHash == 2
        VO.useCloseHash = useCloseHash < 2

    return (tlines, bnodes, levels)

#------ the rest is identical to voom_mode_markdown.py ------


def hook_newHeadline(VO, level, blnum, tlnum):
    """Return (tree_head, bodyLines).
    tree_head is new headline string in Tree buffer (text after |).
    bodyLines is list of lines to insert in Body buffer.
    """
    tree_head = 'NewHeadline'
    if level < 3 and not VO.useHash:
        bodyLines = [tree_head, LEVELS_ADS[level]*11, '']
    else:
        lev = '#'*level
        if VO.useCloseHash:
            bodyLines = ['%s %s %s' %(lev, tree_head, lev), '']
        else:
            bodyLines = ['%s %s' %(lev, tree_head), '']

    # Add blank line when inserting after non-blank Body line.
    if VO.Body[blnum-1].strip():
        bodyLines[0:0] = ['']

    return (tree_head, bodyLines)


#def hook_changeLevBodyHead(VO, h, levDelta):
#    DO NOT CREATE THIS HOOK


def hook_doBodyAfterOop(VO, oop, levDelta, blnum1, tlnum1, blnum2, tlnum2, blnumCut, tlnumCut):
    # this is instead of hook_changeLevBodyHead()

    # Based on reST mode function. Insert blank separator lines if missing,
    # even though they are not important for Markdown headlines.

    #print oop, levDelta, blnum1, tlnum1, blnum2, tlnum2, tlnumCut, blnumCut
    Body = VO.Body
    Z = len(Body)
    bnodes, levels = VO.bnodes, VO.levels
    ENC = VO.enc

    # blnum1 blnum2 is first and last lnums of Body region pasted, inserted
    # during up/down, or promoted/demoted.
    if blnum1:
        assert blnum1 == bnodes[tlnum1-1]
        if tlnum2 < len(bnodes):
            assert blnum2 == bnodes[tlnum2]-1
        else:
            assert blnum2 == Z

    # blnumCut is Body lnum after which a region was removed during 'cut',
    # 'up', 'down'. Need this to check if there is blank line between nodes
    # used to be separated by the cut/moved region.
    if blnumCut:
        if tlnumCut < len(bnodes):
            assert blnumCut == bnodes[tlnumCut]-1
        else:
            assert blnumCut == Z

    # Total number of added lines minus number of deleted lines.
    b_delta = 0

    ### After 'cut' or 'up': insert blank line if there is none
    # between the nodes used to be separated by the cut/moved region.
    if (oop=='cut' or oop=='up') and (0 < blnumCut < Z) and Body[blnumCut-1].strip():
        Body[blnumCut:blnumCut] = ['']
        update_bnodes(VO, tlnumCut+1 ,1)
        b_delta+=1

    if oop=='cut':
        return

    ### Make sure there is blank line after the last node in the region:
    # insert blank line after blnum2 if blnum2 is not blank, that is insert
    # blank line before bnode at tlnum2+1.
    if blnum2 < Z and Body[blnum2-1].strip():
        Body[blnum2:blnum2] = ['']
        update_bnodes(VO, tlnum2+1 ,1)
        b_delta+=1

    ### Change levels and/or formats of headlines in the affected region.
    # Always do this after Paste, even if level is unchanged -- format can
    # be different when pasting from other outlines.
    # Examine each headline, from bottom to top, and change level and/or format.
    # To change from hashes to underline-style:
    #   strip hashes, strip whitespace;
    #   insert underline.
    # To change from underline to hashes-style:
    #   delete underline or change it to blank if it is followed by another underline
    #   insert hashes.
    # Update bnodes after inserting or deleting a line.

    #   hash-style       underline-style (overrides hash-style)
    #
    #   ## head  L1      head  L1   <--bnode  Body[bln-1]
    #            L2      ----  L2             Body[bln]
    #            L3            L3             Body[bln+1]

    if levDelta or oop=='paste':
        for i in xrange(tlnum2, tlnum1-1, -1):
            # required level (VO.levels has been updated)
            lev = levels[i-1]
            # current level from which to change to lev
            lev_ = lev - levDelta

            # Body headline (bnode) and next line
            bln = bnodes[i-1]
            L1 = Body[bln-1].rstrip()
            if bln < len(Body):
                L2 = Body[bln].rstrip()
            else:
                L2 = ''

            # get the current headline format
            hasHash, hasCloseHash = True, VO.useCloseHash
            if L2 and (L2.lstrip('=')=='' or L2.lstrip('-')==''):
                hasHash = False
            else:
                if L1.endswith('#'):
                    hasCloseHash = True
                else:
                    hasCloseHash = False

            # get the desired headline format
            if oop=='paste':
                if lev > 2:
                    useHash = True
                else:
                    useHash = VO.useHash
                useCloseHash = VO.useCloseHash
            elif lev < 3 and lev_ < 3:
                useHash = hasHash
                useCloseHash = hasCloseHash
            elif lev > 2 and lev_ > 2:
                useHash = True
                useCloseHash = hasCloseHash
            elif lev < 3 and lev_ > 2:
                useHash = VO.useHash
                useCloseHash = VO.useCloseHash
            elif lev > 2 and lev_ < 3:
                useHash = True
                useCloseHash = hasCloseHash
            else:
                assert False
            #print 'useHash:', useHash, 'hasHash:', hasHash, 'useCloseHash:', useCloseHash, 'hasCloseHash:', hasCloseHash
            #print L1, L2

            # change headline level and/or format

            # underline-style unchanged, only adjust level of underline
            if not useHash and not hasHash:
                if not levDelta: continue
                Body[bln] = LEVELS_ADS[lev]*len(L2)
            # hashes-style unchanged, adjust level of hashes and add/remove closing hashes
            elif useHash and hasHash:
                # no format change, there are closing hashes
                if useCloseHash and hasCloseHash:
                    if not levDelta: continue
                    Body[bln-1] = '%s%s%s' %('#'*lev, L1.strip('#'), '#'*lev)
                # no format change, there are no closing hashes
                elif not useCloseHash and not hasCloseHash:
                    if not levDelta: continue
                    Body[bln-1] = '%s%s' %('#'*lev, L1.lstrip('#'))
                # add closing hashes
                elif useCloseHash and not hasCloseHash:
                    Body[bln-1] = '%s%s %s' %('#'*lev, L1.strip('#').rstrip(), '#'*lev)
                # remove closing hashes
                elif not useCloseHash and hasCloseHash:
                    Body[bln-1] = '%s%s' %('#'*lev, L1.strip('#').rstrip())
            # insert underline, remove hashes
            elif not useHash and hasHash:
                L = L1.strip('#').strip()
                Body[bln-1] = L
                # insert underline
                Body[bln:bln] = [LEVELS_ADS[lev]*len(L.decode(ENC,'replace'))]
                update_bnodes(VO, i+1, 1)
                b_delta+=1
            # remove underline, insert hashes
            elif useHash and not hasHash:
                if L1[0].isspace():
                    sp = ''
                else:
                    sp = ' '
                if useCloseHash:
                    Body[bln-1] = '%s%s%s %s' %('#'*lev, sp, L1, '#'*lev)
                else:
                    Body[bln-1] = '%s%s%s' %('#'*lev, sp, L1)
                # check if the next line after underline is another underline
                if bln+1 < len(Body):
                    L3 = Body[bln+1].rstrip()
                else:
                    L3 = ''
                #print L1, L2, L3
                # yes: do not delete underline, change it to a blank line
                if L3 and (L3.lstrip('=')=='' or L3.lstrip('-')==''):
                    Body[bln] = ''
                # no: delete underline
                else:
                    Body[bln:bln+1] = []
                    update_bnodes(VO, i+1, -1)
                    b_delta-=1

    ### Make sure first headline is preceded by a blank line.
    blnum1 = bnodes[tlnum1-1]
    if blnum1 > 1 and Body[blnum1-2].strip():
        Body[blnum1-1:blnum1-1] = ['']
        update_bnodes(VO, tlnum1 ,1)
        b_delta+=1

    ### After 'down' : insert blank line if there is none
    # between the nodes used to be separated by the moved region.
    if oop=='down' and (0 < blnumCut < Z) and Body[blnumCut-1].strip():
        Body[blnumCut:blnumCut] = ['']
        update_bnodes(VO, tlnumCut+1 ,1)
        b_delta+=1

    assert len(Body) == Z + b_delta


def update_bnodes(VO, tlnum, delta):
    """Update VO.bnodes by adding/substracting delta to each bnode
    starting with bnode at tlnum and to the end.
    """
    bnodes = VO.bnodes
    for i in xrange(tlnum, len(bnodes)+1):
        bnodes[i-1] += delta


