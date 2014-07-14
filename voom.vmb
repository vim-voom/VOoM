" Vimball Archiver by Charles E. Campbell, Jr., Ph.D.
UseVimball
finish
autoload/voom/voom_mode_asciidoc.py	[[[1
435
# voom_mode_asciidoc.py
# Last Modified: 2014-05-21
# VOoM -- Vim two-pane outliner, plugin for Python-enabled Vim 7.x
# Website: http://www.vim.org/scripts/script.php?script_id=2657
# Author: Vlad Irnov (vlad DOT irnov AT gmail DOT com)
# License: CC0, see http://creativecommons.org/publicdomain/zero/1.0/

"""
VOoM markup mode for AsciiDoc document and section titles.
See |voom-mode-asciidoc|,   ../../doc/voom.txt#*voom-mode-asciidoc*
"""

### NOTES
#
# When outline operation changes level, it has to deal with two ambiguities:
#   a) Level 1-5 headline can use 2-style (underline) or 1-style (=).
#   b) 1-style can have or not have closing ='s.
# To determine current preferences: check first headline at level <6 and check
# first headline with =. This must be done in hook_makeOutline().
# (Save in VO, similar to reST mode.) Cannot be done during outline operation,
# that is in hook_doBodyAfterOop().
# Defaults: use underline, use closing ='s.

try:
    import vim
    if vim.eval('exists("g:voom_asciidoc_do_blanks")')=='1' and vim.eval("g:voom_asciidoc_do_blanks")=='0':
        DO_BLANKS = False
    else:
        DO_BLANKS = True
except ImportError:
    DO_BLANKS = True

import re

# regex for 1-style headline, assumes there is no trailing whitespace
HEAD_MATCH = re.compile(r'^(=+)(\s+\S.*?)(\s+\1)?$').match

#---------------------------------------------------------------------
# Characters used as underlines in two-line headlines.
ADS_LEVELS = {'=' : 1, '-' : 2, '~' : 3, '^' : 4, '+' : 5}
# Characters for Delimited Blocks. Headines are ignored inside such blocks.
BLOCK_CHARS = {'/' : 0, '+' : 0, '-' : 0, '.' : 0, '*' : 0, '_' : 0, '=' : 0}

#LEVELS_ADS = {1:'=', 2:'-', 3:'~', 4:'^', 5:'+'}
LEVELS_ADS = {}
for k in ADS_LEVELS:
    LEVELS_ADS[ADS_LEVELS[k]] = k
# Combine all signficant chars. Need one of these at start of line for a headline or DelimitedBlock to occur.
CHARS = {}
for k in ADS_LEVELS:
    CHARS[k] = 0
for k in BLOCK_CHARS:
    CHARS[k] = 0
#---------------------------------------------------------------------

def hook_makeOutline(VO, blines):
    """Return (tlines, bnodes, levels) for Body lines blines.
    blines is either Vim buffer object (Body) or list of buffer lines.
    """
    ENC = VO.enc
    Z = len(blines)
    tlines, bnodes, levels = [], [], []
    tlines_add, bnodes_add, levels_add = tlines.append, bnodes.append, levels.append

    # trailing whitespace is always removed with rstrip()
    # if headline is precedeed by [AAA] and/or [[AAA]], bnode is set to their lnum
    #
    # 1-style, overrides 2-style
    #  [[AAA]]       L3, blines[i-2]
    #  [yyy]         L2, blines[i-1]
    #  == head ==    L1, blines[i]   -- current line, closing = are optional
    #
    # 2-style (underline)
    #  [[AAA]]       L4, blines[i-3]
    #  [yyy]         L3, blines[i-2]
    #  head          L2, blines[i-1] -- title line, many restrictions on the format
    #  ----          L1, blines[i]   -- current line


    # Set this the first time a headline with level 1-5 is encountered.
    # 0 or 1 -- False, use 2-style (default); 2 -- True, use 1-style
    useOne = 0
    # Set this the first time headline in 1-style is encountered.
    # 0 or 1 -- True, use closing ='s (default); 2 -- False, do not use closing ='s
    useOneClose = 0

    isHead = False
    isFenced = False # True if inside DelimitedBlock, the value is the char
    headI = -2 # idx of the last line that is part of a headline
    blockI = -2 # idx of the last line where a DelimitedBlock ended
    m = None # match object for 1-style regex

    for i in xrange(Z):
        L1 = blines[i].rstrip()
        if not L1 or not L1[0] in CHARS:
            continue
        ch = L1[0]

        if isFenced:
            if isFenced==ch and len(L1)>3 and L1.lstrip(ch)=='':
                isFenced = False
                blockI = i
            continue

        # 1-style headline
        if ch == '=' and L1.strip('='):
            m = HEAD_MATCH(L1)
            if m:
                isHead = True
                headI_ = headI
                headI = i
                lev = len(m.group(1))
                head = m.group(2).strip()
                bnode = i+1

        # current line is an underline
        # the previous, underlined line (L2) is not a headline if it:
        #   is not exactly the length of underline +/- 2
        #   is already part of in the previous headline
        #   looks like an underline or a delimited block line
        #   is [[AAA]] or [AAA] (BlockID or Attribute List)
        #   starts with . (Block Title, they have no level)
        #   starts with // (comment line)
        #   starts with tab (don't know why, spaces are ok)
        #   is only 1 chars (avoids confusion with --, as in Vim syntax, not as in AsciiDoc)
        if not isHead and ch in ADS_LEVELS and L1.lstrip(ch)=='' and i > 0:
            L2 = blines[i-1].rstrip()
            z2 = len(L2.decode(ENC,'replace'))
            z1 = len(L1)
            if (L2 and
                  (-3 < z2 - z1 < 3) and z1 > 1 and z2 > 1 and
                  headI != i-1 and
                  not ((L2[0] in CHARS) and L2.lstrip(L2[0])=='') and
                  not (L2.startswith('[') and L2.endswith(']')) and
                  not L2.startswith('.') and
                  not L2.startswith('\t') and
                  not (L2.startswith('//') and not L2.startswith('///'))
                  ):
                isHead = True
                headI_ = headI
                headI = i
                lev = ADS_LEVELS[ch]
                head = L2.strip()
                bnode = i # lnum of previous line (L2)

        if isHead and bnode > 1:
            # decrement bnode if preceding lines are [[AAA]] or [AAA] lines
            # that is set bnode to the topmost [[AAA]] or [AAA] line number
            j_ = bnode-2 # idx of line before the title line
            L3 = blines[bnode-2].rstrip()
            while L3.startswith('[') and L3.endswith(']'):
                bnode -= 1
                if bnode > 1:
                    L3 = blines[bnode-2].rstrip()
                else:
                    break

            # headline must be preceded by a blank line unless:
            #   it's line 1 (j == -1)
            #   headline is preceded by [AAA] or [[AAA]] lines (j != j_)
            #   previous line is a headline (headI_ == j)
            #   previous line is the end of a DelimitedBlock (blockI == j)
            j = bnode-2
            if DO_BLANKS and j==j_ and j > -1:
                L3 = blines[j].rstrip()
                if L3 and headI_ != j and blockI != j:
                    # skip over any adjacent comment lines
                    while L3.startswith('//') and not L3.startswith('///'):
                        j -= 1
                        if j > -1:
                            L3 = blines[j].rstrip()
                        else:
                            L3 = ''
                    if L3 and headI_ != j and blockI != j:
                        isHead = False
                        headI = headI_

        # start of DelimitedBlock
        if not isHead and ch in BLOCK_CHARS and len(L1)>3 and L1.lstrip(ch)=='':
            isFenced = ch
            continue

        if isHead:
            isHead = False
            # save style info for first headline and first 1-style headline
            if not useOne and lev < 6:
                if m:
                    useOne = 2
                else:
                    useOne = 1
            if not useOneClose and m:
                if m.group(3):
                    useOneClose = 1
                else:
                    useOneClose = 2
            # make outline
            tline = '  %s|%s' %('. '*(lev-1), head)
            tlines_add(tline)
            bnodes_add(bnode)
            levels_add(lev)

    # don't clobber these when parsing clipboard during Paste
    # which is the only time blines is not Body
    if blines is VO.Body:
        VO.useOne = useOne == 2
        VO.useOneClose = useOneClose < 2

    return (tlines, bnodes, levels)


def hook_newHeadline(VO, level, blnum, tlnum):
    """Return (tree_head, bodyLines).
    tree_head is new headline string in Tree buffer (text after |).
    bodyLines is list of lines to insert in Body buffer.
    """
    tree_head = 'NewHeadline'
    if level < 6 and not VO.useOne:
        bodyLines = [tree_head, LEVELS_ADS[level]*11, '']
    else:
        lev = '='*level
        if VO.useOneClose:
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

    # Based on Markdown mode function.
    # Inserts blank separator lines if missing.

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
    if DO_BLANKS and (oop=='cut' or oop=='up') and (0 < blnumCut < Z) and Body[blnumCut-1].strip():
        Body[blnumCut:blnumCut] = ['']
        update_bnodes(VO, tlnumCut+1 ,1)
        b_delta+=1

    if oop=='cut':
        return

    ### Make sure there is blank line after the last node in the region:
    # insert blank line after blnum2 if blnum2 is not blank, that is insert
    # blank line before bnode at tlnum2+1.
    if DO_BLANKS and blnum2 < Z and Body[blnum2-1].strip():
        Body[blnum2:blnum2] = ['']
        update_bnodes(VO, tlnum2+1 ,1)
        b_delta+=1

    ### Change levels and/or formats of headlines in the affected region.
    # Always do this after Paste, even if level is unchanged -- format can
    # be different when pasting from other outlines.
    # Examine each headline, from bottom to top, and change level and/or format.
    # To change from 1-style to 2-style:
    #   strip ='s, strip whitespace;
    #   insert underline.
    # To change from 2-style to 1-style:
    #   delete underline;
    #   insert ='s.
    # Update bnodes after inserting or deleting a line.
    #
    # NOTE: bnode can be [[AAA]] or [AAA] line, we check for that and adjust it
    # to point to the headline text line
    #
    #   1-style          2-style
    #
    #            L0            L0             Body[bln-2]
    #   == head  L1      head  L1   <--bnode  Body[bln-1] (not always the actual bnode)
    #            L2      ----  L2             Body[bln]
    #            L3            L3             Body[bln+1]

    if levDelta or oop=='paste':
        for i in xrange(tlnum2, tlnum1-1, -1):
            # required level (VO.levels has been updated)
            lev = levels[i-1]
            # current level from which to change to lev
            lev_ = lev - levDelta

            # Body headline (bnode) and the next line
            bln = bnodes[i-1]
            L1 = Body[bln-1].rstrip()
            # bnode can point to the tompost [AAA] or [[AAA]] line
            # increment bln until the actual headline (title line) is found
            while L1.startswith('[') and L1.endswith(']'):
                bln += 1
                L1 = Body[bln-1].rstrip()
            # the underline line
            if bln < len(Body):
                L2 = Body[bln].rstrip()
            else:
                L2 = ''

            # get current headline format
            hasOne, hasOneClose = False, VO.useOneClose
            theHead = L1
            if L1.startswith('='):
                m = HEAD_MATCH(L1)
                if m:
                    hasOne = True
                    # headline without ='s but with whitespace around it preserved
                    theHead = m.group(2)
                    theclose = m.group(3)
                    if theclose:
                        hasOneClose = True
                        theHead += theclose.rstrip('=')
                    else:
                        hasOneClose = False

            # get desired headline format
            if oop=='paste':
                if lev > 5:
                    useOne = True
                else:
                    useOne = VO.useOne
                useOneClose = VO.useOneClose
            elif lev < 6 and lev_ < 6:
                useOne = hasOne
                useOneClose = hasOneClose
            elif lev > 5 and lev_ > 5:
                useOne = True
                useOneClose = hasOneClose
            elif lev < 6 and lev_ > 5:
                useOne = VO.useOne
                useOneClose = VO.useOneClose
            elif lev > 5 and lev_ < 6:
                useOne = True
                useOneClose = hasOneClose
            else:
                assert False
            #print useOne, hasOne, ';', useOneClose, hasOneClose

            ### change headline level and/or format
            # 2-style unchanged, only adjust level of underline
            if not useOne and not hasOne:
                if not levDelta: continue
                Body[bln] = LEVELS_ADS[lev]*len(L2)
            # 1-style unchanged, adjust level of ='s and add/remove closing ='s
            elif useOne and hasOne:
                # no format change, there are closing ='s
                if useOneClose and hasOneClose:
                    if not levDelta: continue
                    Body[bln-1] = '%s%s%s' %('='*lev, theHead, '='*lev)
                # no format change, there are no closing ='s
                elif not useOneClose and not hasOneClose:
                    if not levDelta: continue
                    Body[bln-1] = '%s%s' %('='*lev, theHead)
                # add closing ='s
                elif useOneClose and not hasOneClose:
                    Body[bln-1] = '%s%s %s' %('='*lev, theHead.rstrip(), '='*lev)
                # remove closing ='s
                elif not useOneClose and hasOneClose:
                    Body[bln-1] = '%s%s' %('='*lev, theHead.rstrip())
            # insert underline, remove ='s
            elif not useOne and hasOne:
                L1 = theHead.strip()
                Body[bln-1] = L1
                # insert underline
                Body[bln:bln] = [LEVELS_ADS[lev]*len(L1.decode(ENC,'replace'))]
                update_bnodes(VO, i+1, 1)
                b_delta+=1
            # remove underline, insert ='s
            elif useOne and not hasOne:
                if useOneClose:
                    Body[bln-1] = '%s %s %s' %('='*lev, theHead.strip(), '='*lev)
                else:
                    Body[bln-1] = '%s %s' %('='*lev, theHead.strip())
                # delete underline
                Body[bln:bln+1] = []
                update_bnodes(VO, i+1, -1)
                b_delta-=1

    ### Make sure first headline is preceded by a blank line.
    blnum1 = bnodes[tlnum1-1]
    if DO_BLANKS and blnum1 > 1 and Body[blnum1-2].strip():
        Body[blnum1-1:blnum1-1] = ['']
        update_bnodes(VO, tlnum1 ,1)
        b_delta+=1

    ### After 'down' : insert blank line if there is none
    # between the nodes used to be separated by the moved region.
    if DO_BLANKS and oop=='down' and (0 < blnumCut < Z) and Body[blnumCut-1].strip():
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


autoload/voom/voom_mode_cwiki.py	[[[1
68
# voom_mode_cwiki.py
# Last Modified: 2013-10-31
# VOoM -- Vim two-pane outliner, plugin for Python-enabled Vim 7.x
# Website: http://www.vim.org/scripts/script.php?script_id=2657
# Author: Vlad Irnov (vlad DOT irnov AT gmail DOT com)
# License: CC0, see http://creativecommons.org/publicdomain/zero/1.0/

"""
VOoM markup mode for cwiki Vim plugin. Contributed by Craig B. Allen.
http://www.vim.org/scripts/script.php?script_id=2176
See |voom-mode-various|,  ../../doc/voom.txt#*voom-mode-various*

+++ headline level 1
some text
++++ headline level 2
more text
+++++ headline level 3
++++++ headline level 4
etc.

First + must be at start of line. Whitespace after the last + is optional.
"""

import re
headline_match = re.compile(r'^\+\+(\++)').match


def hook_makeOutline(VO, blines):
    """Return (tlines, bnodes, levels) for Body lines blines.
    blines is either Vim buffer object (Body) or list of buffer lines.
    """
    Z = len(blines)
    tlines, bnodes, levels = [], [], []
    tlines_add, bnodes_add, levels_add = tlines.append, bnodes.append, levels.append
    for i in xrange(Z):
        if not blines[i].startswith('+'):
            continue
        bline = blines[i]
        m = headline_match(bline)
        if not m:
            continue
        lev = len(m.group(1))
        head = bline[2+lev:].strip()
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
    bodyLines = ['++%s %s' %('+'*level, tree_head), '']
    return (tree_head, bodyLines)


def hook_changeLevBodyHead(VO, h, levDelta):
    """Increase of decrease level number of Body headline by levDelta."""
    if levDelta==0: return h
    m = headline_match(h)
    level = len(m.group(1))
    return '++%s%s' %('+'*(level+levDelta), h[m.end(1):])


autoload/voom/voom_mode_dokuwiki.py	[[[1
132
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


autoload/voom/voom_mode_fmr.py	[[[1
14
# voom_mode_fmr1.py
# Last Modified: 2013-10-31
# VOoM -- Vim two-pane outliner, plugin for Python-enabled Vim 7.x
# Website: http://www.vim.org/scripts/script.php?script_id=2657
# Author: Vlad Irnov (vlad DOT irnov AT gmail DOT com)
# License: CC0, see http://creativecommons.org/publicdomain/zero/1.0/

"""
This mode changes absolutely nothing, it is identical to the default mode.
See |voom-mode-fmr|, ../../doc/voom.txt#*voom-mode-fmr*
"""

# Define this mode as an 'fmr' mode.
MTYPE = 0
autoload/voom/voom_mode_fmr1.py	[[[1
59
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


autoload/voom/voom_mode_fmr2.py	[[[1
59
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


autoload/voom/voom_mode_hashes.py	[[[1
70
# voom_mode_hashes.py
# Last Modified: 2013-11-07
# VOoM -- Vim two-pane outliner, plugin for Python-enabled Vim 7.x
# Website: http://www.vim.org/scripts/script.php?script_id=2657
# Author: Vlad Irnov (vlad DOT irnov AT gmail DOT com)
# License: CC0, see http://creativecommons.org/publicdomain/zero/1.0/

"""
VOoM markup mode for headlines marked with #'s (atx-headers, a subset of Markdown format).
See |voom-mode-hashes|,  ../../doc/voom.txt#*voom-mode-hashes*

# heading level 1
##heading level 2
### heading level 3
"""

import re

# Marker character can be changed to any ASCII character.
CHAR = '#'

# Use this if whitespace after marker chars is optional.
headline_match = re.compile(r'^(%s+)' %re.escape(CHAR)).match

# Use this if a whitespace is required after marker chars (as in org-mode).
#headline_match = re.compile(r'^(%s+)\s' %re.escape(CHAR)).match

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
        lev = len(m.group(1))
        head = bline[lev:].strip()
        # Do this instead if optional closing markers need to be stripped.
        #head = bline[lev:].strip().rstrip(CHAR).rstrip()
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
    bodyLines = ['%s %s' %(CHAR * level, tree_head), '']
    return (tree_head, bodyLines)


def hook_changeLevBodyHead(VO, h, levDelta):
    """Increase of decrease level number of Body headline by levDelta."""
    if levDelta==0: return h
    m = headline_match(h)
    level = len(m.group(1))
    return '%s%s' %(CHAR * (level+levDelta), h[m.end(1):])


autoload/voom/voom_mode_html.py	[[[1
69
# voom_mode_html.py
# Last Modified: 2013-10-31
# VOoM -- Vim two-pane outliner, plugin for Python-enabled Vim 7.x
# Website: http://www.vim.org/scripts/script.php?script_id=2657
# Author: Vlad Irnov (vlad DOT irnov AT gmail DOT com)
# License: CC0, see http://creativecommons.org/publicdomain/zero/1.0/

"""
VOoM markup mode for HTML headings.
See |voom-mode-html|,  ../../doc/voom.txt#*voom-mode-html*

<h1>headline level 1</h1>
some text
 <h2> headline level 2 </h2>
more text
 <H3  ALIGN="CENTER"> headline level 3 </H3>
 <  h4 >    headline level 4       </H4    >
  some text <h4> <font color=red> headline 5 </font> </H4> </td></div>
     etc.
"""

import re
headline_search = re.compile(r'<\s*h(\d+).*?>(.*?)</h(\1)\s*>', re.IGNORECASE).search
html_tag_sub = re.compile('<.*?>').sub


def hook_makeOutline(VO, blines):
    """Return (tlines, bnodes, levels) for Body lines blines.
    blines is either Vim buffer object (Body) or list of buffer lines.
    """
    Z = len(blines)
    tlines, bnodes, levels = [], [], []
    tlines_add, bnodes_add, levels_add = tlines.append, bnodes.append, levels.append
    for i in xrange(Z):
        bline = blines[i]
        if not ('</h' in bline or '</H' in bline):
            continue
        m = headline_search(bline)
        if not m:
            continue
        lev = int(m.group(1))
        head = m.group(2)
        # delete all html tags
        head = html_tag_sub('',head)
        tline = '  %s|%s' %('. '*(lev-1), head.strip())
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
    bodyLines = ['<h%s>%s</h%s>' %(level, tree_head, level), '']
    return (tree_head, bodyLines)


def hook_changeLevBodyHead(VO, h, levDelta):
    """Increase of decrease level number of Body headline by levDelta."""
    if levDelta==0: return h
    m = headline_search(h)
    level = int(m.group(1))
    lev = level+levDelta
    return '%s%s%s%s%s' %(h[:m.start(1)], lev, h[m.end(1):m.start(3)], lev, h[m.end(3):])

autoload/voom/voom_mode_inverseAtx.py	[[[1
170
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


autoload/voom/voom_mode_latex.py	[[[1
307
# voom_mode_latex.py
# Last Modified: 2014-04-09
# VOoM -- Vim two-pane outliner, plugin for Python-enabled Vim 7.x
# Website: http://www.vim.org/scripts/script.php?script_id=2657
# Author: Vlad Irnov (vlad DOT irnov AT gmail DOT com)
# License: CC0, see http://creativecommons.org/publicdomain/zero/1.0/

"""
VOoM markup mode for LaTeX.
See |voom-mode-latex|,  ../../doc/voom.txt#*voom-mode-latex*
"""

# SECTIONS, ELEMENTS, VERBATIMS can be defined here or in Vim variables:
#   g:voom_latex_sections
#   g:voom_latex_elements
#   g:voom_latex_verbatims
#
# SECTIONS defines sectioning commands, in order of increasing level:
#     \part{A Heading}
#     \chapter{A Heading}
#     \section{A Heading}
#     \subsection{A Heading}
#     \subsubsection{A Heading}
#     \paragraph{A Heading}
#     \subparagraph{A Heading}
#
# ELEMENTS defines fixed elements -- always at level 1:
#     \begin{document}
#     \begin{abstract}
#     \begin{thebibliography}
#     \end{document}
#     \bibliography{...
# 
# VERBATIMS defines regions where headlines are ignored:
#     \begin{verbatim} ... \end{verbatim}
#     \begin{comment} ... \end{comment}
#
# The actual levels are determined by sections that are present in the buffer.
# Levels are always incremented by 1. That is, if there are only
# \section and \paragraph then \section is level 1 and \paragraph is level 2.

# sectioning commands, in order of increasing level
SECTIONS = ['part', 'chapter',
            'section', 'subsection', 'subsubsection',
            'paragraph', 'subparagraph']

# fixed elements -- always at level 1
ELEMENTS = r'^\s*\\(begin\s*\{(document|abstract|thebibliography)\}|end\s*\{document\}|bibliography\s*\{)'

# verbatim regions, headlines are ignored inside \begin{verbatim} ... \end{verbatim}
VERBATIMS = ['verbatim', 'comment']
#---------------------------------------------------------------------

try:
    import vim
    if vim.eval('exists("g:voom_latex_sections")')=='1':
        SECTIONS = vim.eval("g:voom_latex_sections")
    if vim.eval('exists("g:voom_latex_elements")')=='1':
        ELEMENTS = vim.eval("g:voom_latex_elements")
    if vim.eval('exists("g:voom_latex_verbatims")')=='1':
        VERBATIMS = vim.eval("g:voom_latex_verbatims")
except ImportError:
    pass
import re

# \section{head}  or  \section*{head}  or  \section[optionaltitle]{head}
# NOTE: match leading whitespace to preserve it during outline operations
#                 m.group()    1      2                    3
SECTS_RE = re.compile(r'^\s*\\(%s)\s*(\*|\[[^]{]*\])?\s*\{(.*)' %('|'.join(SECTIONS))).match

if ELEMENTS:
    ELEMS_RE = re.compile(ELEMENTS).match
else:
    ELEMS_RE = 0

if VERBATIMS:
    # NOTE: leading whitespace must be lstripped before matching
    VERBS_RE = re.compile(r'^\\begin\s*\{(%s)\}' %('|'.join(VERBATIMS))).match
else:
    VERBS_RE = 0

SECTIONS = ['\\'+s for s in SECTIONS]
SECTS_LEVS = {} # {section: its default level, ...}
LEVS_SECTS = {} # {level: its default section, ...}
i = 1
for s in SECTIONS:
    SECTS_LEVS[s] = i
    LEVS_SECTS[i] = s
    i+=1


def hook_makeOutline(VO, blines):
    """Return (tlines, bnodes, levels) for Body lines blines.
    blines is either Vim buffer object (Body) or list of buffer lines.
    """
    Z = len(blines)
    tlines, bnodes, levels = [], [], []
    tlines_add, bnodes_add, levels_add = tlines.append, bnodes.append, levels.append
    marks, heads = [], []
    marks_add, heads_add = marks.append, heads.append

    sects_levs = {} # {section: its default level} for all section found in the buffer
    inVerbatim = False
    isHead = False
    mark = ' ' # * or -
    for i in xrange(Z):
        L = blines[i].lstrip()
        if not L.startswith('\\'): continue
        # regions to ignore: \begin{verbatim} ... \end{verbatim}
        if VERBS_RE:
            if inVerbatim:
                if re.match(inVerbatim, L):
                    inVerbatim = False
                continue
            else:
                m = VERBS_RE(L)
                if m:
                    inVerbatim = r'\\end\s*\{%s\}' %m.group(1)
                    continue
        # check for sections
        m = SECTS_RE(L)
        if m:
            isHead = True
            s = '\\' + m.group(1)
            lev = SECTS_LEVS[s]
            sects_levs[s] = lev
            if m.group(2) and m.group(2)=='*':
                mark = '*'
            head = m.group(3)
            # truncate head before the matching '}'
            j = 0; k = 1
            for ch in head:
                if ch=='{': k+=1
                elif ch=='}': k-=1
                if not k: break
                j+=1
            head = head[:j].strip()
        # check for fixed level 1 elements
        elif ELEMS_RE:
            m = ELEMS_RE(L)
            if m:
                isHead = True
                lev = 1
                head = L.rstrip()
                mark = '-'
        # add node to outline
        if isHead:
            isHead = False
            bnodes_add(i+1)
            levels_add(lev)
            # tlines must be constructed from marks and heads and after levels are adjusted
            marks_add(mark)
            mark = ' '
            heads_add(head)

    # adjust default level numbers to reflect only sections present in the buffer
    # that is make all level numbers continuous, top level is 1
    d = {} # {default level: actual level, ...}
    levs_sects = {} # {actual level: section, ...}
    sects = [(sects_levs[s], s) for s in sects_levs.keys()]
    sects.sort()
    sects = [i[1] for i in sects]
    i = 1
    for s in sects:
        d[sects_levs[s]] = i
        levs_sects[i] = s
        i+=1
    levels = [d.get(i,i) for i in levels]

    # construct tlines
    for i in xrange(len(levels)):
        tlines_add(' %s%s|%s' %(marks[i], '. '*(levels[i]-1), heads[i]))

    # save levs_sects for outline operations
    # don't clobber VO.levs_sects when parsing clipboard during Paste
    # which is the only time blines is not Body
    if blines is VO.Body:
        VO._levs_sects = levs_sects

    return (tlines, bnodes, levels)


def hook_newHeadline(VO, level, blnum, tlnum):
    """Return (tree_head, bodyLines).
    tree_head is new headline string in Tree buffer (text after |).
    bodyLines is list of lines to insert in Body buffer.
    """
    tree_head = 'NewHeadline'
    (sect, lev) = get_sect_for_lev(VO._levs_sects, level)
    assert lev <= level
    if not lev==level:
        vim.command("call voom#ErrorMsg('VOoM (LaTeX): MAXIMUM LEVEL EXCEEDED')")

    bodyLines = ['%s{%s}' %(sect, tree_head), '']
    return (tree_head, bodyLines)


#def hook_changeLevBodyHead(VO, h, levDelta):
#    DO NOT CREATE THIS HOOK


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
    # Sections must always be adjusted after Paste, even if level is unchanged,
    # in case pasting was done from another outline with different style.
    if not (levDelta or oop=='paste'):
        return

    # Examine each headline in the affected region from top to bottom.
    # For sections: change them to the current level and style.
    # Correct invalid levels: ../../doc/voom.txt#ID_20120520092604
    #   use max level if max possible level is exeeded
    #   use 1 for fixed elements at level >1
    invalid_sects, invalid_elems = [], [] # tree lnums of nodes with disallowed levels
    levs_sects = VO._levs_sects
    #for i in xrange(tlnum2, tlnum1-1, -1):
    for i in xrange(tlnum1, tlnum2+1):
        # required level based on new VO.levels, can be disallowed
        lev_ = levels[i-1]
        # Body line
        bln = bnodes[i-1]
        L = Body[bln-1] # NOTE: original line, not lstripped

        m = SECTS_RE(L)
        if not m:
            assert ELEMS_RE(L)
            # fixed level 1 element at level >1
            if lev_ > 1:
                invalid_elems.append(i)
                levels[i-1] = 1 # correct VO.levels
            continue

        # current section
        sect_ = '\\' + m.group(1)
        # required section and its actual level
        (sect, lev) = get_sect_for_lev(levs_sects, lev_)
        # change section (NOTE: SECTS_RE matches after \, thus -1)
        if not sect == sect_:
            Body[bln-1] = '%s%s%s' %(L[:m.start(1)-1], sect, L[m.end(1):])
        # check if max level was exceeded
        if not lev == lev_:
            invalid_sects.append(i)
            levels[i-1] = lev # correct VO.levels
        # changes VO._levs_sects
        if not lev in levs_sects:
            levs_sects[lev] = sect

    ### --- the end ---
    if invalid_elems or invalid_sects:
        vim.command("call voom#ErrorMsg('VOoM (LaTeX): Disallowed levels have been corrected after ''%s''')" %oop)
        if invalid_elems:
            invalid_elems = ', '.join(['%s' %i for i in invalid_elems])
            vim.command("call voom#ErrorMsg('              level set to 1 for nodes: %s')" %invalid_elems)
        if invalid_sects:
            invalid_sects = ', '.join(['%s' %i for i in invalid_sects])
            vim.command("call voom#ErrorMsg('              level set to maximum for nodes: %s')" %invalid_sects)


def get_sect_for_lev(levs_sects, level):
    """Return (section, actual level) corresponding to the desired level.
    levs_sects contains all sections currently in use.
    If level exceeds the maximum, return section for maximum possible level and max level.
    """

    if level in levs_sects:
        return (levs_sects[level], level)

    z = len(SECTIONS)
    # outline is empty
    if not levs_sects:
        if level <= z:
            return (SECTIONS[level-1], level)
        else:
            return (SECTIONS[-1], z)

    # pick new sect from SECTIONS
    levmax = max(levs_sects.keys()) # currently used max level
    sectmax = levs_sects[levmax]
    idx = SECTS_LEVS[sectmax] + (level - levmax)
    if idx <= z:
        return (SECTIONS[idx-1], level)
    else:
        return (SECTIONS[-1], level-(idx-z))


autoload/voom/voom_mode_markdown.py	[[[1
326
# voom_mode_markdown.py
# Last Modified: 2014-04-09
# VOoM -- Vim two-pane outliner, plugin for Python-enabled Vim 7.x
# Website: http://www.vim.org/scripts/script.php?script_id=2657
# Author: Vlad Irnov (vlad DOT irnov AT gmail DOT com)
# License: CC0, see http://creativecommons.org/publicdomain/zero/1.0/

"""
VOoM markup mode for Markdown headers.
See |voom-mode-markdown|,   ../../doc/voom.txt#*voom-mode-markdown*
"""

### NOTES
# When an outline operation changes level, it has to deal with two ambiguities:
#   a) Level 1 and 2 headline can use underline-style or hashes-style.
#   b) Hashes-style can have or not have closing hashes.
# To determine current preferences: check first headline at level <3 and check
# first headline with hashes. This must be done in hook_makeOutline().
# (Save in VO, similar to reST mode.) Cannot be done during outline operation,
# that is in hook_doBodyAfterOop().
# Defaults: use underline, use closing hashes.

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
            continue

        if L2 and (L2[0] in ADS_LEVELS) and not L2.lstrip(L2[0]):
            isHead = True
            lev = ADS_LEVELS[L2[0]]
            head = L1.strip()
            L2 = ''
            if not useHash:
                useHash = 1
        elif L1.startswith('#'):
            isHead = True
            lev = len(L1) - len(L1.lstrip('#'))
            head = L1.strip('#').strip()
            if not useHash and lev < 3:
                useHash = 2
            if not useCloseHash:
                if L1.endswith('#'): useCloseHash = 1
                else: useCloseHash = 2
        else:
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

#------ the rest is identical to voom_mode_pandoc.py ------


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


autoload/voom/voom_mode_org.py	[[[1
57
# voom_mode_org.py
# Last Modified: 2013-10-31
# VOoM -- Vim two-pane outliner, plugin for Python-enabled Vim 7.x
# Website: http://www.vim.org/scripts/script.php?script_id=2657
# Author: Vlad Irnov (vlad DOT irnov AT gmail DOT com)
# License: CC0, see http://creativecommons.org/publicdomain/zero/1.0/

"""
VOoM markup mode for Emacs Org-mode headline format.
See |voom-mode-org|,  ../../doc/voom.txt#*voom-mode-org*
"""

import re
headline_match = re.compile(r'^(\*+)\s').match


def hook_makeOutline(VO, blines):
    """Return (tlines, bnodes, levels) for Body lines blines.
    blines is either Vim buffer object (Body) or list of buffer lines.
    """
    Z = len(blines)
    tlines, bnodes, levels = [], [], []
    tlines_add, bnodes_add, levels_add = tlines.append, bnodes.append, levels.append
    for i in xrange(Z):
        if not blines[i].startswith('*'):
            continue
        bline = blines[i]
        m = headline_match(bline)
        if not m:
            continue
        lev = len(m.group(1))
        head = bline[lev:].strip()
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
    bodyLines = ['%s %s' %('*'*level, tree_head), '']
    return (tree_head, bodyLines)


def hook_changeLevBodyHead(VO, h, levDelta):
    """Increase of decrease level number of Body headline by levDelta."""
    if levDelta==0: return h
    m = headline_match(h)
    level = len(m.group(1))
    return '%s%s' %('*'*(level+levDelta), h[m.end(1):])


autoload/voom/voom_mode_pandoc.py	[[[1
348
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


autoload/voom/voom_mode_python.py	[[[1
253
# voom_mode_python.py
# Last Modified: 2014-04-13
# VOoM -- Vim two-pane outliner, plugin for Python-enabled Vim 7.x
# Website: http://www.vim.org/scripts/script.php?script_id=2657
# Author: Vlad Irnov (vlad DOT irnov AT gmail DOT com)
# License: CC0, see http://creativecommons.org/publicdomain/zero/1.0/

"""
VOoM markup mode for Python code.
See |voom-mode-python|,  ../../doc/voom.txt#*voom-mode-python*
"""

import token, tokenize
import traceback
import vim


def hook_makeOutline(VO, blines):
    """Return (tlines, bnodes, levels) for Body lines blines.
    blines is either Vim buffer object (Body) or list of buffer lines.
    """
    Z = len(blines)
    tlines, bnodes, levels = [], [], []
    tlines_add, bnodes_add, levels_add = tlines.append, bnodes.append, levels.append

    #ignore_lnums, func_lnums = get_lnums_from_tokenize(blines)
    try:
        ignore_lnums, func_lnums = get_lnums_from_tokenize(blines)
    except (IndentationError, tokenize.TokenError):
        vim.command("call voom#ErrorMsg('VOoM: EXCEPTION WHILE PARSING PYTHON OUTLINE')")
        # DO NOT print to sys.stderr -- triggers Vim error when default stderr (no PyLog)
        #traceback.print_exc()  --this goes to sys.stderr
        #print traceback.format_exc() --ok but no highlighting
        lines = traceback.format_exc().replace("'","''").split('\n')
        for ln in lines:
            vim.command("call voom#ErrorMsg('%s')" %ln)
        return (['= |!!!ERROR: OUTLINE IS INVALID'], [1], [1])

    isHead = False # True if current line is a headline
    indents = [0,] # indents of previous levels
    funcLevels = [] # levels of previous def or class
    indentError = '' # inconsistent indent
    isDecor = 0 # keeps track of decorators, set to lnum of the first decorator
    X = ' ' # char in Tree's column 2 (marks)
    for i in xrange(Z):
        bnode = i + 1
        if bnode in ignore_lnums: continue
        bline = blines[i]
        bline_s = bline.strip()
        if not bline_s: continue
        if bline_s.startswith('#'):
            # ignore comment lines consisting only of #, -, =, spaces, tabs (separators, pretty headers)
            if not bline_s.lstrip('# \t-='): continue
            isComment = True
        else:
            isComment = False
        bline_ls = bline.lstrip()

        # compute indent and level
        indent = len(bline) - len(bline_ls)
        if indent > indents[-1]:
            indents.append(indent)
        elif indent < indents[-1]:
            while indents and (indents[-1] > indent):
                indents.pop()
            if indents[-1]==indent:
                indentError = ''
            else:
                indentError = '!!! '
        lev = len(indents)

        # First line after the end of a class or def block.
        if funcLevels and lev <= funcLevels[-1]:
            isHead = True
            while funcLevels and funcLevels[-1] >= lev:
                funcLevels.pop()
        # First line of a class or def block.
        if bnode in func_lnums:
            isHead = True
            if isDecor:
                bnode = isDecor
                isDecor = 0
                X = 'd'
            if not funcLevels or (lev > funcLevels[-1]):
                funcLevels.append(lev)
        # Line after a decorator. Not a def or class.
        elif isDecor:
            # ingore valid lines between the first decorator and function/class
            if bline_s.startswith('@') or isComment or not bline_s:
                isHead = False
                continue
            # Invalid line after a decorator (should be syntax error): anything
            # other than another decorator, comment, blank line, def/class.
            # If it looks like a headline, let it be a headline.
            else:
                isDecor = 0
        # Decorator line (the first one if a group of several).
        elif bline_s.startswith('@'):
            isDecor = bnode
            isHead = False
            continue
        # Special comment line (unconditional headline). Not a separator or pretty header line.
        elif isComment:
            if bline_s.startswith('###') or bline_s.startswith('#--') or bline_s.startswith('#=='):
                isHead = True

        if isHead:
            ##########################################
            # Take care of pretty headers like this. #
            ##########################################
            if isComment:
                # add preceding lines to the current node if they consist only of #, =, -, whitespace
                while bnode > 1:
                    bline_p = blines[bnode-2].lstrip()
                    if not bline_p.startswith('#') or bline_p.lstrip('# \t-='):
                        break
                    else:
                        bnode -= 1
            # the end
            isHead = False
            tline = ' %s%s|%s%s' %(X, '. '*(lev-1), indentError, bline_s)
            X = ' '
            tlines_add(tline)
            bnodes_add(bnode)
            levels_add(lev)

    return (tlines, bnodes, levels)


class BLines:
    """Wrapper around Vim buffer object or list of Body lines to provide
    readline() method for use with tokenize.generate_tokens().
    """
    def __init__(self, blines):
        self.blines = blines
        self.size = len(blines)
        self.idx = -1

    def readline(self):
        self.idx += 1
        if self.idx == self.size:
            return ''
        return "%s\n" %self.blines[self.idx]


### toktypes of tokens
STRING = token.STRING
NAME = token.NAME
NEWLINE = token.NEWLINE

def get_lnums_from_tokenize(blines):
    """Return dicts. Keys are Body lnums.
    The main purpose is to get list of lnums to ignore: multi-line strings and
    expressions.
    """
    # lnums to ignore: multi-line strings and expressions other than the first line
    ignore_lnums = {}
    # lnums of 'class' and 'def' tokens
    func_lnums = {}

    inName = False

    for tok in tokenize.generate_tokens(BLines(blines).readline):
        toktype, toktext, (srow, scol), (erow, ecol), line = tok
        #print token.tok_name[toktype], tok
        if toktype == NAME:
            if not inName:
                inName = True
                srow_name = srow
            if toktext in ('def','class'):
                func_lnums[srow] = toktext
        elif toktype == NEWLINE and inName:
            inName = False
            if srow_name != erow:
                for i in xrange(srow_name+1, erow+1):
                    ignore_lnums[i] = 0
        elif toktype == STRING:
            if srow != erow:
                for i in xrange(srow+1, erow+1):
                    ignore_lnums[i] = 0

    return (ignore_lnums, func_lnums)


def get_body_indent(body):
    """Return string used for indenting Body lines."""
    et = int(vim.eval("getbufvar(%s,'&et')" %body))
    if et:
        ts = int(vim.eval("getbufvar(%s,'&ts')" %body))
        return ' '*ts
    else:
        return '\t'


def hook_newHeadline(VO, level, blnum, tlnum):
    """Return (tree_head, bodyLines).
    tree_head is new headline string in Tree buffer (text after |).
    bodyLines is list of lines to insert in Body buffer.
    """
    tree_head = '### NewHeadline'
    indent = get_body_indent(VO.body)
    body_head = '%s%s' %(indent*(level-1), tree_head)
    return (tree_head, [body_head])


#def hook_changeLevBodyHead(VO, h, levDelta):
    #"""Increase of decrease level number of Body headline by levDelta."""
    #if levDelta==0: return h


def hook_doBodyAfterOop(VO, oop, levDelta, blnum1, tlnum1, blnum2, tlnum2, blnumCut, tlnumCut):
    # this is instead of hook_changeLevBodyHead()
    #print oop, levDelta, blnum1, tlnum1, blnum2, tlnum2, tlnumCut, blnumCut
    Body = VO.Body
    Z = len(Body)

    ind = get_body_indent(VO.body)
    # levDelta is wrong when pasting because hook_makeOutline() looks at relative indent
    # determine level of pasted region from indent of its first line
    if oop=='paste':
        bline1 = Body[blnum1-1]
        lev = (len(bline1) - len(bline1.lstrip())) / len(ind) + 1
        levDelta = VO.levels[tlnum1-1] - lev

    if not levDelta: return

    indent = abs(levDelta) * ind
    #--- copied from voom_mode_thevimoutliner.py -----------------------------
    if blnum1:
        assert blnum1 == VO.bnodes[tlnum1-1]
        if tlnum2 < len(VO.bnodes):
            assert blnum2 == VO.bnodes[tlnum2]-1
        else:
            assert blnum2 == Z

    # dedent (if possible) or indent every non-blank line in Body region blnum1,blnum2
    blines = []
    for i in xrange(blnum1-1,blnum2):
        line = Body[i]
        if not line.strip():
            blines.append(line)
            continue
        if levDelta > 0:
            line = '%s%s' %(indent,line)
        elif levDelta < 0 and line.startswith(indent):
            line = line[len(indent):]
        blines.append(line)

    # replace Body region
    Body[blnum1-1:blnum2] = blines
    assert len(Body)==Z


autoload/voom/voom_mode_rest.py	[[[1
377
# voom_mode_rest.py
# Last Modified: 2014-04-09
# VOoM -- Vim two-pane outliner, plugin for Python-enabled Vim 7.x
# Website: http://www.vim.org/scripts/script.php?script_id=2657
# Author: Vlad Irnov (vlad DOT irnov AT gmail DOT com)
# License: CC0, see http://creativecommons.org/publicdomain/zero/1.0/

"""
VOoM markup mode for reStructuredText.
See |voom-mode-rest|,  ../../doc/voom.txt#*voom-mode-rest*

http://docutils.sourceforge.net/docs/ref/rst/restructuredtext.html#sections
    The following are all valid section title adornment characters:
    ! " # $ % & ' ( ) * + , - . / : ; < = > ? @ [ \ ] ^ _ ` { | } ~

    Some characters are more suitable than others. The following are recommended:
    = - ` : . ' " ~ ^ _ * + #

http://docs.python.org/documenting/rest.html#sections
Python recommended styles:   ##  **  =  -  ^  "
"""

# All valid section title adornment characters.
AD_CHARS = """  ! " # $ % & ' ( ) * + , - . / : ; < = > ? @ [ \ ] ^ _ ` { | } ~  """
AD_CHARS = AD_CHARS.split()

# List of adornment styles, in order of preference.
# Adornment style (ad) is a char or double char: '=', '==', '-', '--', '*', etc.
# Char is adornment char, double if there is overline.
AD_STYLES = """  ==  --  =  -  *  "  '  `  ~  :  ^  +  #  .  _  """
AD_STYLES = AD_STYLES.split()

# add all other possible styles to AD_STYLES
d = {}.fromkeys(AD_STYLES)
for c in AD_CHARS:
    if not c*2 in d:
        AD_STYLES.append(c*2)
    if not c in d:
        AD_STYLES.append(c)
assert len(AD_STYLES)==64

# convert AD_CHARS to dict for faster lookups
AD_CHARS = {}.fromkeys(AD_CHARS)


def hook_makeOutline(VO, blines):
    """Return (tlines, bnodes, levels) for Body lines blines.
    blines is either Vim buffer object (Body) or list of buffer lines.
    """
    Z = len(blines)
    tlines, bnodes, levels = [], [], []
    tlines_add, bnodes_add, levels_add = tlines.append, bnodes.append, levels.append
    ENC = VO.enc

    # {adornment style: level, ...}
    # Level indicates when the first instance of this style was found.
    ads_levels = {}

    # diagram of Body lines when a headline is detected
    # trailing whitespace always removed with rstrip()
    # a b c
    # ------ L3, blines[i-2] -- an overline or a blank line
    #  head  L2, blines[i-1] -- title line, not blank, <= than underline, can be inset only if overline
    # ------ L1, blines[i]   -- current line, always an underline
    # x y z
    L1, L2, L3 = '','',''

    # An underline can be only the 2nd or 3rd line of a block after a blank
    # line or previous underline. Thus, index of the next underline must be ok or ok+1.
    ok = 1
    isHead = False
    for i in xrange(Z):
        L2, L3 = L1, L2
        L1 = blines[i].rstrip()
        if not L1:
            ok = i+2
            continue
        if i < ok or not L2:
            continue
        # At this point both the current line (underline) and previous line (title) are not blank.

        # current line must be an underline
        if not ((L1[0] in AD_CHARS) and L1.lstrip(L1[0])==''):
            if i > ok: ok = Z
            continue
        # underline must be as long as headline text
        if len(L1) < len(L2.decode(ENC,'replace')):
            if i > ok: ok = Z
            continue
        head = L2.lstrip()
        # headline text cannot look like an underline unless it's shorter than underline
        if (head[0] in AD_CHARS) and head.lstrip(head[0])=='' and len(head)==len(L1):
            if i > ok: ok = Z
            continue
        # there is no overline; L3 must be blank line; L2 must be not inset
        if not L3 and len(L2)==len(head):
            #if len(L1) < len(L2.decode(ENC,'replace')): continue
            isHead = True
            ad = L1[0]
            bnode = i
        # there is overline -- bnode is lnum of overline!
        elif L3==L1:
            #if len(L1) < len(L2.decode(ENC,'replace')): continue
            isHead = True
            ad = L1[0]*2
            bnode = i-1
        else:
            if i > ok: ok = Z
            continue

        if isHead:
            if not ad in ads_levels:
                ads_levels[ad] = len(ads_levels)+1
            lev = ads_levels[ad]
            isHead = False
            L1, L2, L3 = '','',''
            ok = i+2

            tline = '  %s|%s' %('. '*(lev-1), head)
            tlines_add(tline)
            bnodes_add(bnode)
            levels_add(lev)

    # save ads_levels for outline operations
    # don't clobber VO.ads_levels when parsing clipboard during Paste
    # which is the only time blines is not Body
    if blines is VO.Body:
        VO.ads_levels = ads_levels

    return (tlines, bnodes, levels)


def hook_newHeadline(VO, level, blnum, tlnum):
    """Return (tree_head, bodyLines).
    tree_head is new headline string in Tree buffer (text after |).
    bodyLines is list of lines to insert in Body buffer.
    """
    tree_head = 'NewHeadline'
    ads_levels = VO.ads_levels
    levels_ads = dict([[v,k] for k,v in ads_levels.items()])

    if level in levels_ads:
        ad = levels_ads[level]
    else:
        ad = get_new_ad(levels_ads, ads_levels, level)

    if len(ad)==1:
        bodyLines = [tree_head, ad*11, '']
    elif len(ad)==2:
        ad = ad[0]
        bodyLines = [ad*11, tree_head, ad*11, '']

    # Add blank line when inserting after non-blank Body line.
    if VO.Body[blnum-1].strip():
        bodyLines[0:0] = ['']

    return (tree_head, bodyLines)


#def hook_changeLevBodyHead(VO, h, levDelta):
#    DO NOT CREATE THIS HOOK


def hook_doBodyAfterOop(VO, oop, levDelta, blnum1, tlnum1, blnum2, tlnum2, blnumCut, tlnumCut):
    # this is instead of hook_changeLevBodyHead()
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
    # 'up', 'down'. We need to check if there is blank line between nodes
    # used to be separated by the cut/moved region to prevent headline loss.
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

    ### Prevent loss of headline after last node in the region:
    # insert blank line after blnum2 if blnum2 is not blank, that is insert
    # blank line before bnode at tlnum2+1.
    if blnum2 < Z and Body[blnum2-1].strip():
        Body[blnum2:blnum2] = ['']
        update_bnodes(VO, tlnum2+1 ,1)
        b_delta+=1

    ### Change levels and/or styles of headlines in the affected region.
    # Always do this after Paste, even if level is unchanged -- adornments can
    # be different when pasting from other outlines.
    # Examine each headline, from bottom to top, and change adornment style.
    # To change from underline to overline style:
    #   insert overline.
    # To change from overline to underline style:
    #   delete overline if there is blank before it;
    #   otherwise change overline to blank line;
    #   remove inset from headline text.
    # Update bnodes after inserting or deleting a line.
    if levDelta or oop=='paste':
        ads_levels = VO.ads_levels
        levels_ads = dict([[v,k] for k,v in ads_levels.items()])
        # Add adornment styles for new levels. Can't do this in the main loop
        # because it goes backwards and thus will add styles in reverse order.
        for i in xrange(tlnum1, tlnum2+1):
            lev = levels[i-1]
            if not lev in levels_ads:
                ad = get_new_ad(levels_ads, ads_levels, lev)
                levels_ads[lev] = ad
                ads_levels[ad] = lev
        for i in xrange(tlnum2, tlnum1-1, -1):
            # required level (VO.levels has been updated)
            lev = levels[i-1]
            # required adornment style
            ad = levels_ads[lev]

            # deduce current adornment style
            bln = bnodes[i-1]
            L1 = Body[bln-1].rstrip()
            L2 = Body[bln].rstrip()
            if bln+1 < len(Body):
                L3 = Body[bln+1].rstrip()
            else:
                L3 = ''
            ad_ = deduce_ad_style(L1,L2,L3,ENC)

            # change adornment style
            # see deduce_ad_style() for diagram
            if ad_==ad:
                continue
            elif len(ad_)==1 and len(ad)==1:
                Body[bln] = ad*len(L2)
            elif len(ad_)==2 and len(ad)==2:
                Body[bln-1] = ad[0]*len(L1)
                Body[bln+1] = ad[0]*len(L3)
            elif len(ad_)==1 and len(ad)==2:
                # change underline if different
                if not ad_ == ad[0]:
                    Body[bln] = ad[0]*len(L2)
                # insert overline; current bnode doesn't change
                Body[bln-1:bln-1] = [ad[0]*len(L2)]
                update_bnodes(VO, i+1, 1)
                b_delta+=1
            elif len(ad_)==2 and len(ad)==1:
                # change underline if different
                if not ad_[0] == ad:
                    Body[bln+1] = ad*len(L3)
                # remove headline inset if any
                if not len(L2) == len(L2.lstrip()):
                    Body[bln] = L2.lstrip()
                # check if line before overline is blank
                if bln >1:
                    L0 = Body[bln-2].rstrip()
                else:
                    L0 = ''
                # there is blank before overline
                # delete overline; current bnode doesn't change
                if not L0:
                    Body[bln-1:bln] = []
                    update_bnodes(VO, i+1, -1)
                    b_delta-=1
                # there is no blank before overline
                # change overline to blank; only current bnode needs updating
                else:
                    Body[bln-1] = ''
                    bnodes[i-1]+=1

    ### Prevent loss of first headline: make sure it is preceded by a blank line
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


def get_new_ad(levels_ads, ads_levels, level):
    """Return adornment style for new level, that is level missing from
    levels_ads and ads_levels.
    """
    for ad in AD_STYLES:
        if not ad in ads_levels:
            return ad
    # all 64 adornment styles are in use, return style for level 64
    assert len(levels_ads)==64
    return levels_ads[64]


def deduce_ad_style(L1,L2,L3,ENC):
    """Deduce adornment style given first 3 lines of Body node.
    1st line is bnode line. Lines must be rstripped. L1 and L2 are not blank.
    """
    # '--' style    '-' style
    #
    #       L0            L0             Body[bln-2]
    # ----  L1      head  L1   <--bnode  Body[bln-1]
    # head  L2      ----  L2             Body[bln]
    # ----  L3      text  L3             Body[bln+1]

    # bnode is headline text, L2 is underline
    if (L2[0] in AD_CHARS) and L2.lstrip(L2[0])=='' and (len(L2) >= len(L1.decode(ENC,'replace'))):
        ad = L2[0]
    # bnode is overline
    elif L1==L3 and (L1[0] in AD_CHARS) and L1.lstrip(L1[0])=='' and (len(L1) >= len(L2.decode(ENC,'replace'))):
        ad = 2*L1[0]
    else:
        print L1
        print L2
        print L3
        print ENC
        assert None

    return ad


def test_deduce_ad_style(VO):
    """ A test to verify deduce_ad_style(). Execute from Vim
      :py _VOoM.VOOMS[1].mModule.test_deduce_ad_style(_VOoM.VOOMS[1])
    """
    bnodes, levels, Body = VO.bnodes, VO.levels, VO.Body
    ads_levels = VO.ads_levels
    levels_ads = dict([[v,k] for k,v in ads_levels.items()])
    ENC = VO.enc

    for i in xrange(2, len(bnodes)+1):
        bln = bnodes[i-1]
        L1 = Body[bln-1].rstrip()
        L2 = Body[bln].rstrip()
        if bln+1 < len(Body):
            L3 = Body[bln+1].rstrip()
        else:
            L3 = ''
        ad = deduce_ad_style(L1,L2,L3,ENC)
        lev = levels[i-1]
        print i, ad, levels_ads[lev]
        assert ad == levels_ads[lev]


autoload/voom/voom_mode_taskpaper.py	[[[1
91
# voom_mode_taskpaper.py
# Last Modified: 2013-10-31
# VOoM -- Vim two-pane outliner, plugin for Python-enabled Vim 7.x
# Website: http://www.vim.org/scripts/script.php?script_id=2657
# Author: Vlad Irnov (vlad DOT irnov AT gmail DOT com)
# License: CC0, see http://creativecommons.org/publicdomain/zero/1.0/

"""
VOoM markup mode for TaskPaper format.
See |voom-mode-taskpaper|,  ../../doc/voom.txt#*voom-mode-taskpaper*
"""

import re
# match for Project line, as in syntax/taskpaper.vim
project_match = re.compile(r'^.+:(\s+@[^ \t(]+(\([^)]*\))?)*$').match

def hook_makeOutline(VO, blines):
    """Return (tlines, bnodes, levels) for Body lines blines.
    blines is either Vim buffer object (Body) or list of buffer lines.
    """
    Z = len(blines)
    tlines, bnodes, levels = [], [], []
    tlines_add, bnodes_add, levels_add = tlines.append, bnodes.append, levels.append
    for i in xrange(Z):
        bline = blines[i]
        h = bline.lstrip('\t')
        # line is a Task
        if h.startswith('- '):
            head = h[2:]
            mark = ' '
        # line is a Project
        # the "in" test is for efficiency sake in case there is lots of Notes
        elif h.endswith(':') or (':' in h and project_match(h)):
            head = h
            mark = 'x'
        else:
            continue
        lev = len(bline) - len(h) + 1

        tline = ' %s%s|%s' %(mark, '. '*(lev-1), head)
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
    bodyLines = ['%s- %s' %('\t'*(level-1), tree_head),]
    return (tree_head, bodyLines)


# ---- The rest is identical to vimoutliner/thevimoutliner modes. -----------

def hook_doBodyAfterOop(VO, oop, levDelta, blnum1, tlnum1, blnum2, tlnum2, blnumCut, tlnumCut):
    # this is instead of hook_changeLevBodyHead()
    if not levDelta: return

    indent = abs(levDelta) * '\t'

    Body = VO.Body
    Z = len(Body)

    # ---- identical to voom_mode_python.py code ----------------------------
    if blnum1:
        assert blnum1 == VO.bnodes[tlnum1-1]
        if tlnum2 < len(VO.bnodes):
            assert blnum2 == VO.bnodes[tlnum2]-1
        else:
            assert blnum2 == Z

    # dedent (if possible) or indent every non-blank line in Body region blnum1,blnum2
    blines = []
    for i in xrange(blnum1-1,blnum2):
        line = Body[i]
        if not line.strip():
            blines.append(line)
            continue
        if levDelta > 0:
            line = '%s%s' %(indent,line)
        elif levDelta < 0 and line.startswith(indent):
            line = line[len(indent):]
        blines.append(line)

    # replace Body region
    Body[blnum1-1:blnum2] = blines
    assert len(Body)==Z
autoload/voom/voom_mode_thevimoutliner.py	[[[1
93
# voom_mode_thevimoutliner.py
# Last Modified: 2013-10-31
# VOoM -- Vim two-pane outliner, plugin for Python-enabled Vim 7.x
# Website: http://www.vim.org/scripts/script.php?script_id=2657
# Author: Vlad Irnov (vlad DOT irnov AT gmail DOT com)
# License: CC0, see http://creativecommons.org/publicdomain/zero/1.0/

"""
VOoM markup mode for The Vim Outliner format.
See |voom-mode-thevimoutliner|,  ../../doc/voom.txt#*voom-mode-thevimoutliner*

Headlines and body lines are indented with Tabs. Number of tabs indicates
level. 0 Tabs means level 1.

Headlines are lines with >=0 Tabs followed by any character except '|'.

Blank lines are not headlines.
"""

# Body lines start with these chars
BODY_CHARS = {'|':0,}

# ------ the rest is identical to voom_mode_vimoutliner.py -------------------
def hook_makeOutline(VO, blines):
    """Return (tlines, bnodes, levels) for Body lines blines.
    blines is either Vim buffer object (Body) or list of buffer lines.
    """
    Z = len(blines)
    tlines, bnodes, levels = [], [], []
    tlines_add, bnodes_add, levels_add = tlines.append, bnodes.append, levels.append
    for i in xrange(Z):
        bline = blines[i].rstrip()
        if not bline:
            continue
        head = bline.lstrip('\t')
        if head[0] in BODY_CHARS:
            continue
        lev = len(bline) - len(head) + 1

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
    bodyLines = ['%s%s' %('\t'*(level-1), tree_head),]
    return (tree_head, bodyLines)


#def hook_changeLevBodyHead(VO, h, levDelta):
    #"""Increase of decrease level number of Body headline by levDelta."""
    #if levDelta==0: return h

def hook_doBodyAfterOop(VO, oop, levDelta, blnum1, tlnum1, blnum2, tlnum2, blnumCut, tlnumCut):
    # this is instead of hook_changeLevBodyHead()
    if not levDelta: return

    indent = abs(levDelta) * '\t'

    Body = VO.Body
    Z = len(Body)

    # ---- identical to voom_mode_python.py code ----------------------------
    if blnum1:
        assert blnum1 == VO.bnodes[tlnum1-1]
        if tlnum2 < len(VO.bnodes):
            assert blnum2 == VO.bnodes[tlnum2]-1
        else:
            assert blnum2 == Z

    # dedent (if possible) or indent every non-blank line in Body region blnum1,blnum2
    blines = []
    for i in xrange(blnum1-1,blnum2):
        line = Body[i]
        if not line.strip():
            blines.append(line)
            continue
        if levDelta > 0:
            line = '%s%s' %(indent,line)
        elif levDelta < 0 and line.startswith(indent):
            line = line[len(indent):]
        blines.append(line)

    # replace Body region
    Body[blnum1-1:blnum2] = blines
    assert len(Body)==Z
autoload/voom/voom_mode_txt2tags.py	[[[1
103
# voom_mode_txt2tags.py
# Last Modified: 2014-04-09
# VOoM -- Vim two-pane outliner, plugin for Python-enabled Vim 7.x
# Website: http://www.vim.org/scripts/script.php?script_id=2657
# Author: Vlad Irnov (vlad DOT irnov AT gmail DOT com)
# License: CC0, see http://creativecommons.org/publicdomain/zero/1.0/

"""
VOoM markup mode for txt2tags titles.
See |voom-mode-txt2tags|,  ../../doc/voom.txt#*voom-mode-txt2tags*
"""

import re
# headline regexps from txt2tags.py:
#   titskel = r'^ *(?P<id>%s)(?P<txt>%s)\1(\[(?P<label>[\w-]*)\])?\s*$'
#   bank[   'title'] = re.compile(titskel%('[=]{1,5}','[^=](|.*[^=])'))
#   bank['numtitle'] = re.compile(titskel%('[+]{1,5}','[^+](|.*[^+])'))

# === headline ===[optional-label]
headline1_match = re.compile(r'^ *(=+)([^=].*[^=]|[^=])(\1)(\[[\w-]*\])?\s*$').match
# +++ headline +++[optional-label]
headline2_match = re.compile(r'^ *(\++)([^+].*[^+]|[^+])(\1)(\[[\w-]*\])?\s*$').match


def hook_makeOutline(VO, blines):
    """Return (tlines, bnodes, levels) for Body lines blines.
    blines is either Vim buffer object (Body) or list of buffer lines.
    """
    Z = len(blines)
    tlines, bnodes, levels = [], [], []
    tlines_add, bnodes_add, levels_add = tlines.append, bnodes.append, levels.append

    # tags between which headlines should be ignored: Verbatim/Raw/Tagged/Comment Areas
    fenceTags = {'```' : 1, '"""' : 2, "'''" : 3, '%%%' : 4}
    isFenced = '' # set to Area tag when in an ignored Area
    for i in xrange(Z):
        bline = blines[i]

        # ignore Verbatim/Raw/Tagged/Comment Areas
        bline_rs = bline.rstrip() # tests show rstrip() is needed for these tags
        if bline_rs in fenceTags:
            if not isFenced:
                isFenced = bline_rs
            elif isFenced==bline_rs:
                isFenced = ''
            continue
        if isFenced: continue

        # there can be leading spaces but not tabs
        bline = bline.lstrip(' ')
        if bline.startswith('='):
            m = headline1_match(bline)
            if not m: continue
            X = ' '
        elif bline.startswith('+'):
            m = headline2_match(bline)
            if not m: continue
            X = '+'
        else:
            continue
        lev = len(m.group(1))
        head = m.group(2).strip()
        tline = ' %s%s|%s' %(X, '. '*(lev-1), head)
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
    # choose = or + headline type -- same as previous headline
    if tlnum > 1:
        prev_head = VO.Body[VO.bnodes[tlnum-1] - 1]
        if prev_head.lstrip()[0] == '=':
            lev = '='*level
        else:
            lev = '+'*level
    else:
        lev = '='*level
    bodyLines = ['%s NewHeadline %s' %(lev, lev), '']
    return (tree_head, bodyLines)


def hook_changeLevBodyHead(VO, h, levDelta):
    """Increase of decrease level number of Body headline by levDelta."""
    if levDelta==0: return h
    hLS = h.lstrip()
    if hLS[0] == '=':
        m = headline1_match(h)
        level = len(m.group(1))
        s = '='*(level+levDelta)
    elif hLS[0] == '+':
        m = headline2_match(h)
        level = len(m.group(1))
        s = '+'*(level+levDelta)
    else: assert False
    return '%s%s%s%s%s' %(h[:m.start(1)], s, h[m.end(1):m.start(3)], s, h[m.end(3):])

autoload/voom/voom_mode_viki.py	[[[1
87
# voom_mode_viki.py
# Last Modified: 2014-04-09
# VOoM -- Vim two-pane outliner, plugin for Python-enabled Vim 7.x
# Website: http://www.vim.org/scripts/script.php?script_id=2657
# Author: Vlad Irnov (vlad DOT irnov AT gmail DOT com)
# License: CC0, see http://creativecommons.org/publicdomain/zero/1.0/

"""
VOoM markup mode for headline markup used by Vim Viki/Deplate plugin.
See |voom-mode-viki|,  ../../doc/voom.txt#*voom-mode-viki*
"""

import re
headline_match = re.compile(r'^(\*+)\s').match

# Ignore Regions other than #Region
#
#    #Type [OPTIONS] <<EndOfRegion
#    .......
#    EndOfRegion
#
# syntax/viki.vim:
#   syn region vikiRegion matchgroup=vikiMacroDelim
#               \ start=/^[[:blank:]]*#\([A-Z]\([a-z][A-Za-z]*\)\?\>\|!!!\)\(\\\n\|.\)\{-}<<\z(.*\)$/
#               \ end=/^[[:blank:]]*\z1[[:blank:]]*$/
#               \ contains=@vikiText,vikiRegionNames
#
# EndOfRegion can be empty string, leading/trailing white space matters
# Don't know what !!! is for.
#
region_match = re.compile(r'^\s*#([A-Z]([a-z][A-Za-z]*)?)\b.*?<<(.*)').match


def hook_makeOutline(VO, blines):
    """Return (tlines, bnodes, levels) for Body lines blines.
    blines is either Vim buffer object (Body) or list of buffer lines.
    """
    Z = len(blines)
    tlines, bnodes, levels = [], [], []
    tlines_add, bnodes_add, levels_add = tlines.append, bnodes.append, levels.append
    isFenced = False # EndOfRegion match object when inside a region
    for i in xrange(Z):
        bline = blines[i]

        if isFenced:
            if re.match(isFenced, bline):
                isFenced = False
            continue

        if bline.lstrip().startswith('#') and '<<' in bline:
            r_m = region_match(bline)
            if r_m and r_m.group(1) != 'Region':
                isFenced = '^\s*%s\s*$' %re.escape(r_m.group(3) or '')
                continue
        elif not bline.startswith('*'):
            continue

        m = headline_match(bline)
        if not m:
            continue
        lev = len(m.group(1))
        head = bline[lev:].strip()
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
    bodyLines = ['%s %s' %('*'*level, tree_head), '']
    return (tree_head, bodyLines)


def hook_changeLevBodyHead(VO, h, levDelta):
    """Increase of decrease level number of Body headline by levDelta."""
    if levDelta==0: return h
    m = headline_match(h)
    level = len(m.group(1))
    return '%s%s' %('*'*(level+levDelta), h[m.end(1):])


autoload/voom/voom_mode_vimoutliner.py	[[[1
92
# voom_mode_vimoutliner.py
# Last Modified: 2013-10-31
# VOoM -- Vim two-pane outliner, plugin for Python-enabled Vim 7.x
# Website: http://www.vim.org/scripts/script.php?script_id=2657
# Author: Vlad Irnov (vlad DOT irnov AT gmail DOT com)
# License: CC0, see http://creativecommons.org/publicdomain/zero/1.0/

"""
VOoM markup mode for VimOutliner format.
See |voom-mode-vimoutliner|,  ../../doc/voom.txt#*voom-mode-vimoutliner*

Headlines are lines with >=0 Tabs followed by any character except:
    : ; | > <
Otherwise this mode is identical to the "thevimoutliner" mode.
"""

# Body lines start with these chars
BODY_CHARS = {':':0, ';':0, '|':0, '<':0, '>':0,}


#-------------copy/pasted from voom_mode_thevimoutliner.py -------------------
def hook_makeOutline(VO, blines):
    """Return (tlines, bnodes, levels) for Body lines blines.
    blines is either Vim buffer object (Body) or list of buffer lines.
    """
    Z = len(blines)
    tlines, bnodes, levels = [], [], []
    tlines_add, bnodes_add, levels_add = tlines.append, bnodes.append, levels.append
    for i in xrange(Z):
        bline = blines[i].rstrip()
        if not bline:
            continue
        head = bline.lstrip('\t')
        if head[0] in BODY_CHARS:
            continue
        lev = len(bline) - len(head) + 1

        tline = '  %s|%s' %('. '*(lev-1), head)
        tlines_add(tline)
        bnodes_add(i+1)
        levels_add(lev)
    return (tlines, bnodes, levels)


def hook_newHeadline(VO, level, blnum, tlnum):
    """Return (tree_head, bodyLines).
    tree_head is new headline string in Tree buffer (text after |).
    bodyLines is list of lines to insert in Body buffer.
    column is cursor position in new headline in Body buffer.
    """
    tree_head = 'NewHeadline'
    bodyLines = ['%s%s' %('\t'*(level-1), tree_head),]
    return (tree_head, bodyLines)


#def hook_changeLevBodyHead(VO, h, levDelta):
    #"""Increase of decrease level number of Body headline by levDelta."""
    #if levDelta==0: return h

def hook_doBodyAfterOop(VO, oop, levDelta, blnum1, tlnum1, blnum2, tlnum2, blnumCut, tlnumCut):
    # this is instead of hook_changeLevBodyHead()
    if not levDelta: return

    indent = abs(levDelta) * '\t'

    Body = VO.Body
    Z = len(Body)

    # ---- identical to Python mode ----
    if blnum1:
        assert blnum1 == VO.bnodes[tlnum1-1]
        if tlnum2 < len(VO.bnodes):
            assert blnum2 == VO.bnodes[tlnum2]-1
        else:
            assert blnum2 == Z

    # dedent (if possible) or indent every non-blank line in Body region blnum1,blnum2
    blines = []
    for i in xrange(blnum1-1,blnum2):
        line = Body[i]
        if not line.strip():
            blines.append(line)
            continue
        if levDelta > 0:
            line = '%s%s' %(indent,line)
        elif levDelta < 0 and line.startswith(indent):
            line = line[len(indent):]
        blines.append(line)

    # replace Body region
    Body[blnum1-1:blnum2] = blines
    assert len(Body)==Z
autoload/voom/voom_mode_vimwiki.py	[[[1
66
# voom_mode_vimwiki.py
# Last Modified: 2013-10-31
# VOoM -- Vim two-pane outliner, plugin for Python-enabled Vim 7.x
# Website: http://www.vim.org/scripts/script.php?script_id=2657
# Author: Vlad Irnov (vlad DOT irnov AT gmail DOT com)
# License: CC0, see http://creativecommons.org/publicdomain/zero/1.0/

"""
VOoM markup mode for headline markup used by vimwiki plugin:
http://www.vim.org/scripts/script.php?script_id=2226
See |voom-mode-vimwiki|,  ../../doc/voom.txt#*voom-mode-vimwiki*

= headline level 1 =
body text
== headline level 2 ==
body text
  === headline level 3 ===

"""

import re
headline_match = re.compile(r'^\s*(=+).+(\1)\s*$').match


def hook_makeOutline(VO, blines):
    """Return (tlines, bnodes, levels) for Body lines blines.
    blines is either Vim buffer object (Body) or list of buffer lines.
    """
    Z = len(blines)
    tlines, bnodes, levels = [], [], []
    tlines_add, bnodes_add, levels_add = tlines.append, bnodes.append, levels.append
    for i in xrange(Z):
        bline = blines[i].strip()
        if not bline.startswith('='):
            continue
        m = headline_match(bline)
        if not m:
            continue
        lev = len(m.group(1))
        bline = bline.strip()
        head = bline[lev:-lev].strip()
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
    bodyLines = ['%s %s %s' %('='*level, tree_head, '='*level), '']
    return (tree_head, bodyLines)


def hook_changeLevBodyHead(VO, h, levDelta):
    """Increase of decrease level number of Body headline by levDelta."""
    if levDelta==0: return h
    m = headline_match(h)
    level = len(m.group(1))
    s = '='*(level+levDelta)
    return '%s%s%s%s%s' %(h[:m.start(1)], s, h[m.end(1):m.start(2)], s, h[m.end(2):])

autoload/voom/voom_mode_wiki.py	[[[1
73
# voom_mode_wiki.py
# Last Modified: 2013-10-31
# VOoM -- Vim two-pane outliner, plugin for Python-enabled Vim 7.x
# Website: http://www.vim.org/scripts/script.php?script_id=2657
# Author: Vlad Irnov (vlad DOT irnov AT gmail DOT com)
# License: CC0, see http://creativecommons.org/publicdomain/zero/1.0/

"""
VOoM markup mode for MediaWiki headline markup.
See |voom-mode-wiki|, ../../doc/voom.txt#*voom-mode-wiki*

= headline level 1 =
some text
== headline level 2 == 
more text
=== headline level 3 === <!--comment-->
==== headline level 4 ====<!--comment-->

"""


import re
comment_tag_sub = re.compile('<!--.*?-->\s*$').sub
headline_match = re.compile(r'^(=+).*(\1)\s*$').match


def hook_makeOutline(VO, blines):
    """Return (tlines, bnodes, levels) for Body lines blines.
    blines is either Vim buffer object (Body) or list of buffer lines.
    """
    Z = len(blines)
    tlines, bnodes, levels = [], [], []
    tlines_add, bnodes_add, levels_add = tlines.append, bnodes.append, levels.append
    for i in xrange(Z):
        if not blines[i].startswith('='):
            continue
        bline = blines[i]
        if '<!--' in bline:
            bline = comment_tag_sub('',bline)
        bline = bline.strip()
        m = headline_match(bline)
        if not m:
            continue
        lev = len(m.group(1))
        head = bline[lev:-lev].strip()
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
    bodyLines = ['%s %s %s' %('='*level, tree_head, '='*level), '']
    return (tree_head, bodyLines)


def hook_changeLevBodyHead(VO, h, levDelta):
    """Increase of decrease level number of Body headline by levDelta."""
    if levDelta==0: return h
    hs = h # need to strip trailing comment tags first
    if '<!--' in h:
        hs = comment_tag_sub('',hs)
    m = headline_match(hs)
    level = len(m.group(1))
    s = '='*(level+levDelta)
    return '%s%s%s%s' %(s, h[m.end(1):m.start(2)], s, h[m.end(2):])

autoload/voom/voom_vim.py	[[[1
2059
# voom_vim.py
# Last Modified: 2014-05-28
# Version: 5.1
# VOoM -- Vim two-pane outliner, plugin for Python-enabled Vim 7.x
# Website: http://www.vim.org/scripts/script.php?script_id=2657
# Author: Vlad Irnov (vlad DOT irnov AT gmail DOT com)
# License: CC0, see http://creativecommons.org/publicdomain/zero/1.0/

"""This module is meant to be imported by voom.vim ."""

import vim
import sys, os, re
import traceback
import bisect
# lazy imports
shuffle = None # random.shuffle

#Vim = sys.modules['__main__']

# see ../voom.vim for conventions
# voom_WhatEver() is Python code for voom#WhatEver() function in voom.vim


#---Constants and Settings--------------------{{{1=

# VO is instance of VoomOutline class, stored in dict VOOMS
# create VOOMS in voom.vim: less disruption if this module is reloaded
#VOOMS = {} # {body: VO, ...}

# {filetype: make_head_<filetype> function, ...}
MAKE_HEAD = {}

# default start fold marker string and regexp
MARKER = '{{{'                            #}}}
MARKER_RE = re.compile(r'{{{(\d+)(x?)')   #}}}

# {'markdown': 'markdown', 'tex': 'latex', ...}
if vim.eval("exists('g:voom_ft_modes')")=='1':
    FT_MODES = vim.eval('g:voom_ft_modes')
else:
    FT_MODES = {}
# default markup mode
if vim.eval("exists('g:voom_default_mode')")=='1':
    MODE = vim.eval('g:voom_default_mode')
else:
    MODE = ''

# which Vim register to use for copy/cut/paste operations
if vim.eval("exists('g:voom_clipboard_register')")=='1':
    CLIP = vim.eval('g:voom_clipboard_register')
elif vim.eval("has('clipboard')")=='1':
    CLIP = '+'
else:
    CLIP = 'o'

# allow/disallow Move Left when nodes are not at the end of their subtree
if vim.eval("exists('g:voom_always_allow_move_left')")=='1':
    AAMLEFT = int(vim.eval('g:voom_always_allow_move_left'))
else:
    AAMLEFT = 0


#---Outline Construction----------------------{{{1o


class VoomOutline: #{{{2
    """Outline data for one Body buffer.
    Instantiated from Body by voom#Init().
    """
    def __init__(self,body):
        assert body == int(vim.eval("bufnr('')"))


def voom_Init(body): #{{{2
    VO = VoomOutline(body)
    VO.bnodes = [] # Body lnums of headlines
    VO.levels = [] # headline levels
    VO.body = body
    VO.Body = vim.current.buffer
    VO.tree = None # will set later
    VO.Tree = None # will set later
    VO.snLn = 1 # will change later if different
    # first Tree line is Body buffer name and path
    VO.bname = vim.eval('l:firstLine')
    # Body &filetype
    VO.filetype = vim.eval('&filetype')
    VO.enc = get_vim_encoding()

    # start fold marker string and regexp (default and 'fmr' modes)
    marker = vim.eval('&foldmarker').split(',')[0]
    VO.marker = marker
    if marker==MARKER:
        VO.marker_re = MARKER_RE
    else:
        VO.marker_re = re.compile(re.escape(marker) + r'(\d+)(x?)')

    # chars to strip from right side of Tree headlines (default and 'fmr' modes)
    if vim.eval("exists('g:voom_rstrip_chars_{&ft}')")=="1":
        VO.rstrip_chars = vim.eval("g:voom_rstrip_chars_{&ft}")
    else:
        VO.rstrip_chars = vim.eval("&commentstring").split('%s')[0].strip() + " \t"

    ### get markup mode, l:qargs is mode's name ###
    mModule = 0
    mmode = vim.eval('l:qargs').strip() or FT_MODES.get(VO.filetype, MODE)
    if mmode:
        mName = 'voom_mode_%s' %mmode
        try:
            mModule = __import__(mName)
            VO.bname += ', %s' %mmode
        except ImportError:
            vim.command("call voom#ErrorMsg('VOoM: cannot import Python module %s')" %mName.replace("'","''"))
            return

    VO.mmode = mmode
    vim.command("let l:mmode='%s'" %mmode.replace("'","''"))
    VO.mModule = mModule
    ### define mode-specific methods ###
    # no markup mode, default behavior
    if not mModule:
        VO.MTYPE = 0
        if VO.filetype in MAKE_HEAD:
            VO.makeOutline = makeOutlineH
        else:
            VO.makeOutline = makeOutline
        VO.newHeadline = newHeadline
        VO.changeLevBodyHead = changeLevBodyHead
        VO.hook_doBodyAfterOop = 0
    # markup mode for fold markers, similar to the default behavior
    elif getattr(mModule,'MTYPE',1)==0:
        VO.MTYPE = 0
        f = getattr(mModule,'hook_makeOutline',0)
        if f:
            VO.makeOutline = f
        elif VO.filetype in MAKE_HEAD:
            VO.makeOutline = makeOutlineH
        else:
            VO.makeOutline = makeOutline
        VO.newHeadline = getattr(mModule,'hook_newHeadline',0) or newHeadline
        VO.changeLevBodyHead = changeLevBodyHead
        VO.hook_doBodyAfterOop = 0
    # markup mode not for fold markers
    else:
        VO.MTYPE = 1
        VO.makeOutline = getattr(mModule,'hook_makeOutline',0) or makeOutline
        VO.newHeadline = getattr(mModule,'hook_newHeadline',0) or newHeadline
        # These must be False if not defined by the markup mode.
        VO.changeLevBodyHead = getattr(mModule,'hook_changeLevBodyHead',0)
        VO.hook_doBodyAfterOop = getattr(mModule,'hook_doBodyAfterOop',0)

    ### the end ###
    vim.command('let l:MTYPE=%s' %VO.MTYPE)
    VOOMS[body] = VO


def voom_TreeCreate(): #{{{2
    """This is part of voom#TreeCreate(), called from Tree."""
    body = int(vim.eval('a:body'))
    blnr = int(vim.eval('a:blnr')) # Body cursor lnum
    VO = VOOMS[body]

    if VO.MTYPE:
        computeSnLn(body, blnr)
        # reST, wiki files often have most headlines at level >1
        vim.command('setl fdl=2')
        return

    bnodes = VO.bnodes
    Body = VO.Body
    z = len(bnodes)

    ### compute snLn, create Tree folding

    # find bnode marked with '='
    # find bnodes marked with 'o'
    snLn = 0
    marker_re = VO.marker_re
    marker_re_search = marker_re.search
    oFolds = []
    for i in xrange(1,z):
        bline = Body[bnodes[i]-1]
        # part of Body headline after marker+level+'x'
        bline2 = bline[marker_re_search(bline).end():]
        if not bline2: continue
        if bline2[0]=='=':
            snLn = i+1
        elif bline2[0]=='o':
            oFolds.append(i+1)
            if bline2[1:] and bline2[1]=='=':
                snLn = i+1

    # create Tree folding
    if oFolds:
        cFolds = foldingFlip(VO,2,z,oFolds)
        foldingCreate(2,z,cFolds)

    if snLn:
        vim.command('call voom#SetSnLn(%s,%s)' %(body,snLn))
        VO.snLn = snLn
        # set blnShow if Body cursor is on or before the first headline
        if z > 1 and blnr <= bnodes[1]:
            vim.command('let l:blnShow=%s' %bnodes[snLn-1])
    else:
        # no Body headline is marked with =
        # select current Body node
        computeSnLn(body, blnr)


def makeOutline(VO, blines): #{{{2
    """Return (tlines, bnodes, levels) for Body lines blines.
    blines is either Vim buffer object (Body) or list of buffer lines.
    """
    # blines is usually Body. It is list of clipboard lines during Paste.
    # This function is slower when blines is Vim buffer object instead of
    # Python list. But overall time to do outline update is the same and memory
    # usage is less because we don't create new list (see v3.0 notes)

    # Optimized for buffers in which most lines don't have fold markers.

    # NOTE: duplicate code with makeOutlineH(), only head construction is different
    marker = VO.marker
    marker_re_search = VO.marker_re.search
    Z = len(blines)
    tlines, bnodes, levels = [], [], []
    tlines_add, bnodes_add, levels_add = tlines.append, bnodes.append, levels.append
    c = VO.rstrip_chars
    for i in xrange(Z):
        if not marker in blines[i]: continue
        bline = blines[i]
        m = marker_re_search(bline)
        if not m: continue
        lev = int(m.group(1))
        head = bline[:m.start()].lstrip().rstrip(c).strip('-=~').strip()
        tline = ' %s%s|%s' %(m.group(2) or ' ', '. '*(lev-1), head)
        tlines_add(tline)
        bnodes_add(i+1)
        levels_add(lev)
    return (tlines, bnodes, levels)


def makeOutlineH(VO, blines): #{{{2
    """Identical to makeOutline(), duplicate code. The only difference is that
    a custom function is used to construct Tree headline text.
    """
    # NOTE: duplicate code with makeOutline(), only head construction is different
    marker = VO.marker
    marker_re_search = VO.marker_re.search
    Z = len(blines)
    tlines, bnodes, levels = [], [], []
    tlines_add, bnodes_add, levels_add = tlines.append, bnodes.append, levels.append
    h = MAKE_HEAD[VO.filetype]
    for i in xrange(Z):
        if not marker in blines[i]: continue
        bline = blines[i]
        m = marker_re_search(bline)
        if not m: continue
        lev = int(m.group(1))
        head = h(bline,m)
        tline = ' %s%s|%s' %(m.group(2) or ' ', '. '*(lev-1), head)
        tlines_add(tline)
        bnodes_add(i+1)
        levels_add(lev)
    return (tlines, bnodes, levels)


#--- make_head functions --- {{{2

def make_head_html(bline,match):
    s = bline[:match.start()].strip().strip('-=~').strip()
    if s.endswith('<!'):
        return s[:-2].strip()
    else:
        return s
MAKE_HEAD['html'] = make_head_html

#def make_head_vim(bline,match):
#    return bline[:match.start()].lstrip().rstrip('" \t').strip('-=~').strip()
#MAKE_HEAD['vim'] = make_head_vim

#def make_head_py(bline,match):
#    return bline[:match.start()].lstrip().rstrip('# \t').strip('-=~').strip()
#for ft in 'python ruby perl tcl'.split():
#    MAKE_HEAD[ft] = make_head_py


def updateTree(body,tree): #{{{2
    """Construct outline for Body body.
    Update lines in Tree buffer if needed.
    This can be run from any buffer as long as Tree is set to ma.
    """
    ### Construct outline.
    VO = VOOMS[body]
    assert VO.tree == tree
    #blines = VO.Body[:] # wasteful, see v3.0 notes
    tlines, bnodes, levels  = VO.makeOutline(VO, VO.Body)
    tlines[0:0], bnodes[0:0], levels[0:0] = [VO.bname], [1], [1]
    VO.bnodes, VO.levels = bnodes, levels

    ### Add the = mark.
    snLn = VO.snLn
    Z = len(bnodes)
    # snLn got larger than the number of nodes because some nodes were
    # deleted while editing the Body
    if snLn > Z:
        snLn = Z
        vim.command('call voom#SetSnLn(%s,%s)' %(body,snLn))
        VO.snLn = snLn
    tlines[snLn-1] = '=%s' %tlines[snLn-1][1:]

    ### Compare Tree lines, draw as needed.
    # Draw all Tree lines only when needed. This is optimization for large
    # outlines, e.g. >1000 Tree lines. Drawing all lines is slower than
    # comparing all lines and then drawing nothing or just one line.

    Tree = VO.Tree
    #tlines_ = Tree[:]
    if not len(Tree)==len(tlines):
        Tree[:] = tlines
        vim.command('let l:ok=1')
        return

    # If only one line is modified, draw that line only. This ensures that
    # editing (and inserting) a single headline in a large outline is fast.
    # If more than one line is modified, draw all lines from first changed line
    # to the end of buffer.
    draw_one = False
    for i in xrange(len(tlines)):
        if not tlines[i]==Tree[i]:
            if draw_one==False:
                draw_one = True
                diff = i
            else:
                Tree[diff:] = tlines[diff:]
                vim.command('let l:ok=1')
                return
    if draw_one:
        Tree[diff] = tlines[diff]

    vim.command('let l:ok=1')
    # why l:ok is needed:  ../../doc/voom.txt#id_20110213212708


def computeSnLn(body, blnr): #{{{2
    """Compute Tree lnum for node at line blnr in Body body.
    Assign Vim and Python snLn vars.
    """
    # snLn should be 1 if blnr is before the first node, top of Body
    VO = VOOMS[body]
    snLn = bisect.bisect_right(VO.bnodes, blnr)
    vim.command('call voom#SetSnLn(%s,%s)' %(body,snLn))
    VO.snLn = snLn


def voom_UnVoom(body): #{{{2
    if body in VOOMS: del VOOMS[body]


def voom_Voominfo(): #{{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    vimvars = vim.eval('l:vimvars')
    print '%s CURRENT VOoM OUTLINE %s' %('-'*10, '-'*18)
    if not tree:
        print 'current buffer %s is not a VOoM buffer' %body
    else:
        VO = VOOMS[body]
        assert VO.tree == tree
        print VO.bname
        print 'Body buffer %s, Tree buffer %s' %(body,tree)
        if VO.mModule:
            print 'markup mode: %s [%s]' %(VO.mmode, os.path.abspath(VO.mModule.__file__))
        else:
            print 'markup mode: NONE'
        if VO.MTYPE==0:
            print 'headline markers: %s1, %s2, ...' %(VO.marker,VO.marker)
    if vimvars:
        print '%s VOoM INTERNALS %s' %('-'*10, '-'*24)
        print "_VOoM.FT_MODES =", FT_MODES
        print "_VOoM.MODE =", repr(MODE)
        print "_VOoM.CLIP = ", repr(CLIP)
        print "_VOoM.AAMLEFT = ", repr(AAMLEFT)
        print '_VOoM:           %s' %(os.path.abspath(sys.modules['voom_vim'].__file__))
        print vimvars


#---Outline Traversal-------------------------{{{1
# Functions for getting node's parents, children, ancestors, etc.
# Nodes here are Tree buffer lnums.
# All we do is traverse VO.levels.


def nodeHasChildren(VO, lnum): #{{{2
    """Determine if node at Tree line lnum has children."""
    levels = VO.levels
    if lnum==1 or lnum==len(levels): return False
    elif levels[lnum-1] < levels[lnum]: return True
    else: return False


def nodeSubnodes(VO, lnum): #{{{2
    """Number of all subnodes for node at Tree line lnum."""
    levels = VO.levels
    z = len(levels)
    if lnum==1 or lnum==z: return 0
    lev = levels[lnum-1]
    for i in xrange(lnum,z):
        if levels[i]<=lev:
            return i-lnum
    return z-lnum


def nodeParent(VO, lnum): #{{{2
    """Return lnum of closest parent of node at Tree line lnum."""
    levels = VO.levels
    lev = levels[lnum-1]
    if lev==1: return None
    for i in xrange(lnum-2,0,-1):
        if levels[i] < lev: return i+1


def nodeAncestors(VO, lnum): #{{{2
    """Return lnums of ancestors of node at Tree line lnum."""
    levels = VO.levels
    lev = levels[lnum-1]
    if lev==1: return []
    ancestors = []
    for i in xrange(lnum-2,0,-1):
        levi = levels[i]
        if levi < lev:
            lev = levi
            ancestors.append(i+1)
            if lev==1:
                ancestors.reverse()
                return ancestors
    # we get here if there are no nodes at level 1 (wiki mode)
    ancestors.reverse()
    return ancestors


def nodeUNL(VO, lnum): #{{{2
    """Compute UNL of node at Tree line lnum.
    Return list of headlines.
    """
    Tree = VO.Tree
    levels = VO.levels
    if lnum==1: return ['top-of-buffer']
    parents = nodeAncestors(VO,lnum)
    parents.append(lnum)
    heads = [Tree[ln-1].split('|',1)[1] for ln in parents]
    return heads


def nodeSiblings(VO, lnum): #{{{2
    """Return lnums of siblings for node at Tree line lnum.
    These are nodes with the same parent and level as lnum node. Sorted in
    ascending order. lnum itself is included. First node (line 1) is never
    included, that is minimum lnum in results is 2.
    """
    levels = VO.levels
    lev = levels[lnum-1]
    siblings = []
    # scan back
    for i in xrange(lnum-1,0,-1):
        levi = levels[i]
        if levi < lev:
            break
        elif levi==lev:
            siblings[0:0] = [i+1]
    # scan forward
    for i in xrange(lnum,len(levels)):
        levi = levels[i]
        if levi < lev:
            break
        elif levi==lev:
            siblings.append(i+1)
    return siblings


def rangeSiblings(VO, lnum1, lnum2): #{{{2
    """Return lnums of siblings for nodes in Tree range lnum1,lnum2.
    These are nodes with the same parent and level as lnum1 node.
    First node (first Tree line) is never included, that is minimum lnum in results is 2.
    Return None if range is ivalid.
    """
    if lnum1==1: lnum1 = 2
    if lnum1 > lnum2: return None
    levels = VO.levels
    lev = levels[lnum1-1]
    siblings = [lnum1]
    for i in xrange(lnum1,lnum2):
        levi = levels[i]
        # invalid range
        if levi < lev:
            return None
        elif levi==lev:
            siblings.append(i+1)
    return siblings


def getSiblingsGroups(VO, siblings): #{{{2
    """Return list of groups of siblings in the region defined by 'siblings'
    group, which is list of siblings in ascending order (Tree lnums).
    Siblings in each group are nodes with the same parent and level.
    Siblings in each group are in ascending order.
    List of groups is reverse-sorted by level of siblings and by parent lnum:
        from RIGHT TO LEFT and from BOTTOM TO TOP.
    """
    if not siblings: return []
    levels = VO.levels
    lnum1, lnum2 = siblings[0], siblings[-1]
    lnum2 = lnum2 + nodeSubnodes(VO,lnum2)

    # get all parents (nodes with children) in the range
    parents = [i for i in xrange(lnum1,lnum2) if levels[i-1]<levels[i]]
    if not parents:
        return [siblings]

    # get children for each parent
    results_dec = [(levels[lnum1-1], 0, siblings)]
    for p in parents:
        sibs = [p+1]
        lev = levels[p] # level of siblings of this parent
        for i in xrange(p+1, lnum2):
            levi = levels[i]
            if levi==lev:
                sibs.append(i+1)
            elif levi < lev:
                break
        results_dec.append((lev, p, sibs))

    results_dec.sort()
    results_dec.reverse()
    results = [i[2] for i in results_dec]
    assert len(parents)+1 == len(results)
    return results


def nodesBodyRange(VO, ln1, ln2, withSubnodes=False): #{{{2
    """Return Body start and end lnums (bln1, bln2) corresponding to nodes at
    Tree lnums ln1 to ln2. Include ln2's subnodes if withSubnodes."""
    bln1 = VO.bnodes[ln1-1]
    if withSubnodes:
        ln2 += nodeSubnodes(VO,ln2)
    if ln2 < len(VO.bnodes):
        bln2 = VO.bnodes[ln2]-1
    else:
        bln2 = len(VO.Body)
    return (bln1,bln2)
    # (bln1,bln2) can be (1,0), see voom_TreeSelect()
    # this is what we want: getbufline(body,1,0)==[]


#---Outline Navigation------------------------{{{1


def voom_TreeSelect(): #{{{2
    # Get first and last lnums of Body node for Tree line lnum.
    lnum = int(vim.eval('l:lnum'))
    body = int(vim.eval('l:body'))
    VO = VOOMS[body]
    VO.snLn = lnum
    vim.command('let l:blnum1=%s' %(VO.bnodes[lnum-1]))
    if lnum < len(VO.bnodes):
        vim.command('let l:blnum2=%s' %(VO.bnodes[lnum]-1 or 1))
    else:
        vim.command("let l:blnum2=%s" %(len(VO.Body)+1))
    # "or 1" takes care of situation when:
    # lnum is 1 (first Tree line) and first Body line is a headline.
    # In that case VO.bnodes is [1, 1, ...] and (l:blnum1,l:blnum2) is (1,0)


def voom_TreeToStartupNode(): #{{{2
    body = int(vim.eval('l:body'))
    VO = VOOMS[body]
    bnodes = VO.bnodes
    Body = VO.Body
    marker_re = VO.marker_re
    z = len(bnodes)
    # find Body headlines marked with '='
    lnums = []
    for i in xrange(1,z):
        bline = Body[bnodes[i]-1]
        # part of Body headline after marker+level+'x'+'o'
        bline2 = bline[marker_re.search(bline).end():]
        if not bline2: continue
        if bline2[0]=='=':
            lnums.append(i+1)
        elif bline2[0]=='o':
            if bline2[1:] and bline2[1]=='=':
                lnums.append(i+1)
    vim.command('let l:lnums=%s' %repr(lnums))


def voom_EchoUNL(): #{{{2
    bufType = vim.eval('l:bufType')
    body = int(vim.eval('l:body'))
    tree = int(vim.eval('l:tree'))
    lnum = int(vim.eval('l:lnum'))

    VO = VOOMS[body]
    assert VO.tree == tree

    if bufType=='Body':
        lnum = bisect.bisect_right(VO.bnodes, lnum)

    heads = nodeUNL(VO,lnum)
    UNL = ' -> '.join(heads)
    vim.command("let @n='%s'" %UNL.replace("'", "''"))
    for h in heads[:-1]:
        vim.command("echon '%s'" %(h.replace("'", "''")))
        vim.command("echohl TabLineFill")
        vim.command("echon ' -> '")
        vim.command("echohl None")
    vim.command("echon '%s'" %(heads[-1].replace("'", "''")))


def voom_Grep(): #{{{2
    body = int(vim.eval('l:body'))
    tree = int(vim.eval('l:tree'))
    VO = VOOMS[body]
    assert VO.tree == tree
    bnodes = VO.bnodes
    matchesAND, matchesNOT = vim.eval('l:matchesAND'), vim.eval('l:matchesNOT')
    inhAND, inhNOT = vim.eval('l:inhAND'), vim.eval('l:inhNOT')

    # Convert blnums of mathes into tlnums, that is node numbers.
    tlnumsAND, tlnumsNOT = [], [] # lists of AND and NOT "tlnums" dicts

    # Process AND matches.
    counts = {} # {tlnum: count of all AND matches in this node, ...}
    blnums = {} # {tlnum: blnum of first AND match in this node, ...}
    inh_only = {} # tlnums of nodes added to an AND match by inheritance only
    idx = 0 # index into matchesAND and inhAND
    for L in matchesAND:
        tlnums = {} # {tlnum of node with a match:0, ...}
        for bln in L:
            bln = int(bln)
            tln = bisect.bisect_right(bnodes, bln)
            tlnums[tln] = 0
            if tln in counts:
                counts[tln]+=1
            else:
                counts[tln] = 1
            if not tln in blnums:
                blnums[tln] = bln
            elif blnums[tln] > bln or counts[tln]==1:
                blnums[tln] = bln
        # inheritace: add subnodes for each node with a match
        if int(inhAND[idx]):
            ks = tlnums.keys()
            for t in ks:
                subn = nodeSubnodes(VO,t)
                for s in xrange(t+1,t+subn+1):
                    if not s in tlnums:
                        tlnums[s] = 0
                        counts[s] = 0
                        blnums[s] = bnodes[s-1]
                        # node has no match, added thank to inheritance only
                        inh_only[s] = 0
        idx+=1
        tlnumsAND.append(tlnums)

    # Process NOT matches.
    idx = 0 # index into matchesNOT and inhNOT
    for L in matchesNOT:
        tlnums = {} # {tlnum of node with a match:0, ...}
        for bln in L:
            bln = int(bln)
            tln = bisect.bisect_right(bnodes, bln)
            tlnums[tln] = 0
        # inheritace: add subnodes for each node with a match
        if int(inhNOT[idx]):
            ks = tlnums.keys()
            for t in ks:
                subn = nodeSubnodes(VO,t)
                for s in xrange(t+1,t+subn+1):
                    tlnums[s] = 0
        idx+=1
        tlnumsNOT.append(tlnums)

    # There are only NOT patterns.
    if not matchesAND:
        tlnumsAND = [{}.fromkeys(range(1,len(bnodes)+1))]

    # Compute intersection.
    results = intersectDicts(tlnumsAND, tlnumsNOT)
    results = results.keys()
    results.sort()
    #print results

    # Compute max_size to left-align UNLs in the qflist.
    # Add missing data for each node in results.
    nNs = {} # {tlnum : 'N' if node has all AND matches, 'n' otherwise, ...}
    max_size = 0
    for t in results:
        # there are only NOT patterns
        if not matchesAND:
            blnums[t] = bnodes[t-1]
            counts[t] = 0
            nNs[t] = 'n'
        # some nodes in results do not contain all AND matches
        elif inh_only:
            if t in inh_only:
                nNs[t] = 'n'
            else:
                nNs[t] = 'N'
        # every node in results contains all AND matches
        else:
            nNs[t] = 'N'
        size = len('%s%s%s' %(t, counts[t], blnums[t]))
        if size > max_size:
            max_size = size

    # Make list of dictionaries for setloclist() or setqflist().
    loclist = []
    for t in results:
        size = len('%s%s%s' %(t, counts[t], blnums[t]))
        spaces = ' '*(max_size - size)
        UNL = ' -> '.join(nodeUNL(VO,t)).replace("'", "''")
        #text = 'n%s:%s%s|%s' %(t, counts[t], spaces, UNL)
        text = '%s%s:%s%s|%s' %(nNs[t], t, counts[t], spaces, UNL)
        d = "{'text':'%s', 'lnum':%s, 'bufnr':%s}, " %(text, blnums[t], body)
        loclist .append(d)
    #print '\n'.join(loclist)

    vim.command("call setqflist([%s],'a')" %(''.join(loclist)) )


def intersectDicts(dictsAND, dictsNOT): #{{{2
    """Arguments are two lists of dictionaries. Keys are Tree lnums.
    Return dict: intersection of all dicts in dictsAND and non-itersection with
    all dicts in dictsNOT.
    """
    if not dictsAND:
        return {}
    if len(dictsAND)==1:
        res = dictsAND[0]
    else:
        res = {}
        # intersection with other dicts in dictsAND
        for key in dictsAND[0]:
            for d in dictsAND[1:]:
                if not key in d:
                    break
            else:
                res[key] = 0
    # non-intersection with all dicts in dictsNOT
    for d in dictsNOT:
        for key in d:
            if key in res:
                del res[key]
    return res


#---Outline Operations------------------------{{{1o
# voom_Oop... functions are called from voom#Oop... Vim functions.
# They use local Vim vars set by the caller and can create and change Vim vars.
# Most of them set lines in Tree and Body via vim.buffer objects.
#
# l:blnShow is initially set by the VimScript caller to -1.
# Returning before setting l:blnShow means no changes were made.
# If Python code fails, l:blnShow also stays at -1.
# Subsequent VimScript code relies on l:blnShow.


def setLevTreeLines(tlines, levels, j): #{{{2
    """Set level of each Tree line in tlines to corresponding level from levels.
    levels should be VO.levels.
    j is index of the first item in levels.
    """
    results = []
    i = 0
    for t in tlines:
        results.append('%s%s%s' %(t[:2], '. '*(levels[j+i]-1), t[t.index('|'):]))
        i+=1
    return results


def changeLevBodyHead(VO, h, levDelta): #{{{2
    """Increase or decrease level number of Body headline by levDelta.
    NOTE: markup modes can replace this function with hook_changeLevBodyHead.
    """
    if levDelta==0: return h
    m = VO.marker_re.search(h)
    level = int(m.group(1))
    return '%s%s%s' %(h[:m.start(1)], level+levDelta, h[m.end(1):])


def newHeadline(VO, level, blnum, ln): #{{{2
    """Return (tree_head, bodyLines).
    tree_head is new headline string in Tree buffer (text after |).
    bodyLines is list of lines to insert in Body buffer.
    """
    tree_head = 'NewHeadline'
    bodyLines = ['---%s--- %s%s' %(tree_head, VO.marker, level), '']
    return (tree_head, bodyLines)


def setClipboard(s): #{{{2
    """Set Vim register CLIP (usually +) to string s."""
    # important: use '' for Vim string
    vim.command("let @%s = '%s'" %(CLIP, s.replace("'", "''")))

    # The above failed once: empty clipboard after copy/delete >5MB outline. Could
    # not reproduce after Windows restart. Probably stale system. Thus the
    # following check. It adds about 0.09 sec for each 1MB in the clipboard.
    # 30-40% increase overall in the time of Copy operation (yy).
    if not vim.eval('len(@%s)' %CLIP)=='%s' %len(s):
        vim.command("call voom#ErrorMsg('VOoM: error setting clipboard')")


def voom_OopVerify(): #{{{2
    body, tree = int(vim.eval('a:body')), int(vim.eval('a:tree'))
    VO = VOOMS[body]
    assert VO.tree == tree
    ok = True

    tlines, bnodes, levels  = VO.makeOutline(VO, VO.Body)
    if not len(VO.Tree)==len(tlines)+1:
        vim.command("call voom#ErrorMsg('VOoM: outline verification failed: wrong Tree size')")
        vim.command("call voom#ErrorMsg('VOoM: OUTLINE MAY BE CORRUPT!!! YOU MUST UNDO THE LAST OPERATION!!!')")
        ok = False
        return
    tlines[0:0], bnodes[0:0], levels[0:0] = [VO.bname], [1], [1]
    snLn = VO.snLn
    tlines[snLn-1] = '=%s' %tlines[snLn-1][1:]

    if not VO.bnodes == bnodes:
        vim.command("call voom#ErrorMsg('VOoM: outline verification failed: wrong bnodes')")
        vim.command("call voom#ErrorMsg('VOoM: OUTLINE MAY BE CORRUPT!!! YOU MUST UNDO THE LAST OPERATION!!!')")
        return
    if not VO.levels == levels:
        ok = False
        vim.command("call voom#ErrorMsg('VOoM: outline verification failed: wrong levels')")
    if not VO.Tree[:] == tlines:
        ok = False
        vim.command("call voom#ErrorMsg('VOoM: outline verification failed: wrong Tree lines')")

    if ok:
        vim.command("let l:ok=1")


def voom_OopSelEnd(): #{{{2
    """This is part of voom#Oop() checks.
    Selection in Tree starts at line ln1 and ends at line ln2.
    Selection can have many sibling nodes: nodes with the same level as ln1 node.
    Return lnum of last node in the last sibling node's branch.
    Return 0 if selection is invalid.
    """
    body = int(vim.eval('l:body'))
    ln1, ln2  = int(vim.eval('l:ln1')), int(vim.eval('l:ln2'))
    if ln1==1: return 0
    levels = VOOMS[body].levels
    z, lev0 = len(levels), levels[ln1-1]
    for i in xrange(ln1,z):
        lev = levels[i]
        # invalid selection: there is node with level smaller than that of ln1 node
        if i+1 <= ln2 and lev < lev0: return 0
        # node after the last sibling node's branch
        elif i+1 > ln2 and lev <= lev0: return i
    return z


def voom_OopSelectBodyRange(): # {{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln1, ln2 = int(vim.eval('l:ln1')), int(vim.eval('l:ln2'))
    VO = VOOMS[body]
    assert VO.tree == tree
    bln1, bln2 = nodesBodyRange(VO, ln1, ln2)
    vim.command("let [l:bln1,l:bln2]=[%s,%s]" %(bln1,bln2))


def voom_OopEdit(): # {{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    lnum, op = int(vim.eval('l:lnum')), vim.eval('a:op')
    VO = VOOMS[body]
    assert VO.tree == tree
    if op=='i':
        bLnr = VO.bnodes[lnum-1]
    elif op=='I':
        if lnum < len(VO.bnodes):
            bLnr = VO.bnodes[lnum]-1
        else:
            bLnr = len(VO.Body)
    vim.command("let l:bLnr=%s" %(bLnr))


def voom_OopInsert(as_child=False): #{{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln, ln_status = int(vim.eval('l:ln')), vim.eval('l:ln_status')
    VO = VOOMS[body]
    assert VO.tree == tree
    Body, Tree, levels, snLn = VO.Body, VO.Tree, VO.levels, VO.snLn

    # Compute where to insert and at what level.
    # Insert new headline after node at ln.
    # If node is folded, insert after the end of node's tree.
    # default level
    lev = levels[ln-1]
    # after first Tree line
    if ln==1: lev=1
    # as_child always inserts as first child of current node, even if it's folded
    elif as_child: lev+=1
    # after last Tree line, same level
    elif ln==len(levels): pass
    # node has children, it can be folded
    elif lev < levels[ln]:
        # folded: insert after current node's branch, same level
        if ln_status=='folded': ln += nodeSubnodes(VO,ln)
        # not folded, insert as child
        else: lev+=1

    # remove = mark before modifying Tree
    Tree[snLn-1] = ' ' + Tree[snLn-1][1:]

    # insert headline in Tree and Body
    # bLnum is Body lnum after which to insert new headline
    if ln < len(levels):
        bLnum = VO.bnodes[ln]-1
    else:
        bLnum = len(Body)

    tree_head, bodyLines = VO.newHeadline(VO,lev,bLnum,ln)

    treeLine = '= %s|%s' %('. '*(lev-1), tree_head)
    Tree[ln:ln] = [treeLine]
    Body[bLnum:bLnum] = bodyLines

    vim.command('let l:bLnum=%s' %(bLnum+1))

    # write = mark and set snLn to new headline
    Tree[ln] = '=' + Tree[ln][1:]
    VO.snLn = ln+1
    vim.command('call voom#SetSnLn(%s,%s)' %(body, ln+1))


def voom_OopCopy(): #{{{2
    body = int(vim.eval('l:body'))
    ln1, ln2 = int(vim.eval('l:ln1')), int(vim.eval('l:ln2'))
    VO = VOOMS[body]
    Body, bnodes = VO.Body, VO.bnodes

    # body lines to copy
    bln1 = bnodes[ln1-1]
    if ln2 < len(bnodes): bln2 = bnodes[ln2]-1
    else: bln2 = len(Body)
    blines = Body[bln1-1:bln2]
    setClipboard('\n'.join(blines))


def voom_OopCut(): #{{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln1, ln2 = int(vim.eval('l:ln1')), int(vim.eval('l:ln2'))
    lnUp1 = int(vim.eval('l:lnUp1'))
    VO = VOOMS[body]
    assert VO.tree == tree
    Body, Tree = VO.Body, VO.Tree
    bnodes, levels = VO.bnodes, VO.levels

    # diagram {{{
    # .............. blnUp1-1
    # ============== blnUp1=bnodes[lnUp1-1]
    # ..............
    # ============== bln1=bnodes[ln1-1]
    # range being
    # deleted
    # .............. bln2=bnodes[ln2]-1, or last Body line
    # ==============
    # .............. }}}

    ### copy and delete body lines
    bln1 = bnodes[ln1-1]
    if ln2 < len(bnodes): bln2 = bnodes[ln2]-1
    else: bln2 = len(Body)
    blines = Body[bln1-1:bln2]
    setClipboard('\n'.join(blines))
    Body[bln1-1:bln2] = []

    blnShow = bnodes[lnUp1-1] # does not change

    ### update bnodes
    # decrement lnums after deleted range
    delta = bln2-bln1+1
    for i in xrange(ln2,len(bnodes)):
        bnodes[i]-=delta
    # cut
    bnodes[ln1-1:ln2] = []

    ### delete range in levels (same as in Tree)
    levels[ln1-1:ln2] = []

    if VO.hook_doBodyAfterOop:
        VO.hook_doBodyAfterOop(VO, 'cut', 0,  None, None,  None, None,  bln1-1, ln1-1)

    ### ---go back to Tree---
    vim.command("call voom#OopFromBody(%s,%s,%s)" %(body,tree,blnShow))

    ### remove = mark before modifying Tree
    snLn = VO.snLn
    Tree[snLn-1] = ' ' + Tree[snLn-1][1:]
    ### delete range in Tree (same as in levels))
    Tree[ln1-1:ln2] = []

    ### add snLn mark
    Tree[lnUp1-1] = '=' + Tree[lnUp1-1][1:]
    VO.snLn = lnUp1

    # do this last to tell vim script that there were no errors
    vim.command('let l:blnShow=%s' %blnShow)


def voom_OopPaste(): #{{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln, ln_status = int(vim.eval('l:ln')), vim.eval('l:ln_status')
    VO = VOOMS[body]
    assert VO.tree == tree
    Body, Tree = VO.Body, VO.Tree
    levels, bnodes = VO.levels, VO.bnodes

    ### clipboard
    pText = vim.eval('@%s' %CLIP)
    if not pText:
        vim.command("call voom#ErrorMsg('VOoM (paste): clipboard is empty')")
        vim.command("call voom#OopFromBody(%s,%s,-1)" %(body,tree))
        return
    pBlines = pText.split('\n') # Body lines to paste
    pTlines, pBnodes, pLevels = VO.makeOutline(VO, pBlines)

    ### verify that clipboard is a valid outline
    if pBnodes==[] or pBnodes[0]!=1:
        vim.command("call voom#ErrorMsg('VOoM (paste): invalid clipboard--first line is not a headline')")
        vim.command("call voom#OopFromBody(%s,%s,-1)" %(body,tree))
        return
    lev_ = pLevels[0]
    for lev in pLevels:
        # there is node with level smaller than that of the first node
        if lev < pLevels[0]:
            vim.command("call voom#ErrorMsg('VOoM (paste): invalid clipboard--root level error')")
            vim.command("call voom#OopFromBody(%s,%s,-1)" %(body,tree))
            return
        # level incremented by 2 or more
        elif lev-lev_ > 1:
            vim.command("call voom#WarningMsg('VOoM (paste): inconsistent levels in clipboard--level incremented by >1', ' ')")
        lev_ = lev

    ### compute where to insert and at what level
    # insert nodes after node at ln at level lev
    # if node is folded, insert after the end of node's tree
    lev = levels[ln-1] # default level
    # after first Tree line: use level of next node in case min level is not 1 (wiki mode)
    if ln==1:
        if len(levels)>1: lev = levels[1]
        else: lev=1
    # after last Tree line, same level
    elif ln==len(levels): pass
    # node has children, it can be folded
    elif lev < levels[ln]:
        # folded: insert after current node's branch, same level
        if ln_status=='folded': ln += nodeSubnodes(VO,ln)
        # not folded, insert as child
        else: lev+=1

    ### adjust levels of nodes being inserted
    levDelta = lev - pLevels[0]
    if levDelta:
        pLevels = [(lev+levDelta) for lev in pLevels]
        f = VO.changeLevBodyHead
        if f:
            for bl in pBnodes:
                pBlines[bl-1] = f(VO, pBlines[bl-1], levDelta)

    ### insert body lines in Body
    # bln is Body lnum after which to insert
    if ln < len(bnodes): bln = bnodes[ln]-1
    else: bln = len(Body)
    Body[bln:bln] = pBlines
    blnShow = bln+1

    ### update bnodes
    # increment bnodes being pasted
    for i in xrange(0,len(pBnodes)):
        pBnodes[i]+=bln
    # increment bnodes after pasted region
    delta = len(pBlines)
    for i in xrange(ln,len(bnodes)):
        bnodes[i]+=delta
    # insert pBnodes after ln
    bnodes[ln:ln] = pBnodes

    ### insert new levels in levels
    levels[ln:ln] = pLevels

    ### start and end lnums of inserted region
    ln1 = ln+1
    ln2 = ln+len(pBnodes)

    if VO.hook_doBodyAfterOop:
        VO.hook_doBodyAfterOop(VO, 'paste', levDelta,
                    blnShow, ln1,
                    blnShow+len(pBlines)-1, ln2,
                    None, None)

    ### ---go back to Tree---
    vim.command("call voom#OopFromBody(%s,%s,%s)" %(body,tree,blnShow))

    # remove = mark before modifying Tree
    snLn = VO.snLn
    Tree[snLn-1] = ' ' + Tree[snLn-1][1:]
    ### adjust levels of new headlines, insert them in Tree
    if levDelta:
        pTlines = setLevTreeLines(pTlines, levels, ln1-1)
    Tree[ln:ln] = pTlines

    ### start and end lnums of inserted region
    vim.command('let l:ln1=%s' %ln1)
    vim.command('let l:ln2=%s' %ln2)
    # set snLn to first headline of inserted nodes
    Tree[ln1-1] = '=' + Tree[ln1-1][1:]
    VO.snLn = ln1

    # do this last to tell vim script that there were no errors
    vim.command('let l:blnShow=%s' %blnShow)


def voom_OopUp(): #{{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln1, ln2 = int(vim.eval('l:ln1')), int(vim.eval('l:ln2'))
    lnUp1, lnUp2 = int(vim.eval('l:lnUp1')), int(vim.eval('l:lnUp2'))
    VO = VOOMS[body]
    assert VO.tree == tree
    Body, Tree = VO.Body, VO.Tree
    bnodes, levels = VO.bnodes, VO.levels

    # diagram {{{
    # .............. blnUp1-1
    # ============== blnUp1=bnodes[lnUp1-1]
    # range before
    # which to move
    # ..............
    # ============== bln1=bnodes[ln1-1]
    # range being
    # moved
    # .............. bln2=bnodes[ln2]-1, or last Body line
    # ==============
    # .............. }}}

    ### compute change in level
    # current level of root nodes in selection
    levOld = levels[ln1-1]
    # new level of root nodes in selection
    # lnUp1 is fist child of lnUp2, insert also as first child
    if levels[lnUp2-1] + 1 == levels[lnUp1-1]:
        levNew = levels[lnUp1-1]
    # all other cases, includes insertion after folded node
    else:
        levNew = levels[lnUp2-1]
    levDelta = levNew-levOld

    ### body lines to move
    bln1 = bnodes[ln1-1]
    if ln2 < len(bnodes): bln2 = bnodes[ln2]-1
    else: bln2 = len(Body)
    blines = Body[bln1-1:bln2]
    if levDelta:
        f = VO.changeLevBodyHead
        if f:
            for bl in bnodes[ln1-1:ln2]:
                blines[bl-bln1] = f(VO, blines[bl-bln1], levDelta)

    ### move body lines: cut, then insert
    # insert before line blnUp1, it will not change after bnodes update
    blnUp1 = bnodes[lnUp1-1]
    blnShow = blnUp1
    Body[bln1-1:bln2] = []
    Body[blnUp1-1:blnUp1-1] = blines

    ###update bnodes
    # increment lnums in the range before which the move is made
    delta = bln2-bln1+1
    for i in xrange(lnUp1-1,ln1-1):
        bnodes[i]+=delta
    # decrement lnums in the range which is being moved
    delta = bln1-blnUp1
    for i in xrange(ln1-1,ln2):
        bnodes[i]-=delta
    # cut, insert
    nLines = bnodes[ln1-1:ln2]
    bnodes[ln1-1:ln2] = []
    bnodes[lnUp1-1:lnUp1-1] = nLines

    ### update levels (same as for Tree)
    nLevels = levels[ln1-1:ln2]
    if levDelta:
        nLevels = [(lev+levDelta) for lev in nLevels]
    # cut, then insert
    levels[ln1-1:ln2] = []
    levels[lnUp1-1:lnUp1-1] = nLevels

    if VO.hook_doBodyAfterOop:
        VO.hook_doBodyAfterOop(VO, 'up', levDelta,
                    blnShow, lnUp1,
                    blnShow+len(blines)-1, lnUp1+len(nLevels)-1,
                    bln1-1+len(blines), ln1-1+len(nLevels))

    ### ---go back to Tree---
    vim.command("call voom#OopFromBody(%s,%s,%s)" %(body,tree,blnShow))

    ### remove snLn mark before modifying Tree
    snLn = VO.snLn
    Tree[snLn-1] = ' ' + Tree[snLn-1][1:]

    ### update Tree (same as for levels)
    tlines = Tree[ln1-1:ln2]
    if levDelta:
        tlines = setLevTreeLines(tlines, levels, lnUp1-1)
    # cut, then insert
    Tree[ln1-1:ln2] = []
    Tree[lnUp1-1:lnUp1-1] = tlines

    ### add snLn mark
    Tree[lnUp1-1] = '=' + Tree[lnUp1-1][1:]
    VO.snLn = lnUp1

    # do this last to tell vim script that there were no errors
    vim.command('let l:blnShow=%s' %blnShow)


def voom_OopDown(): #{{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln1, ln2 = int(vim.eval('l:ln1')), int(vim.eval('l:ln2'))
    lnDn1, lnDn1_status = int(vim.eval('l:lnDn1')), vim.eval('l:lnDn1_status')
    # note: lnDn1 == ln2+1
    VO = VOOMS[body]
    assert VO.tree == tree
    Body, Tree = VO.Body, VO.Tree
    bnodes, levels = VO.bnodes, VO.levels

    # diagram {{{
    # ..............
    # ============== bln1=bnodes[ln1-1]
    # range being
    # moved
    # .............. bln2=bnodes[ln2]-1
    # ============== blnDn1=bnodes[lnDn1-1]
    # range after
    # which to move
    # .............. blnIns=bnodes[lnIns]-1, or last Body line
    # ==============
    # .............. }}}

    ### compute change in level, and line after which to insert
    # current level
    levOld = levels[ln1-1]
    # new level is either that of lnDn1 or +1
    levNew = levels[lnDn1-1]
    # line afer which to insert
    lnIns = lnDn1
    if lnDn1==len(levels): # end of Tree
        pass
    # lnDn1 has children; insert as child unless it's folded
    elif levels[lnDn1-1] < levels[lnDn1]:
        if lnDn1_status=='folded':
            lnIns += nodeSubnodes(VO,lnDn1)
        else:
            levNew+=1
    levDelta = levNew-levOld

    ### body lines to move
    bln1 = bnodes[ln1-1]
    bln2 = bnodes[ln2]-1
    blines = Body[bln1-1:bln2]
    if levDelta:
        f = VO.changeLevBodyHead
        if f:
            for bl in bnodes[ln1-1:ln2]:
                blines[bl-bln1] = f(VO, blines[bl-bln1], levDelta)

    ### move body lines: insert, then cut
    if lnIns < len(bnodes): blnIns = bnodes[lnIns]-1
    else: blnIns = len(Body)
    Body[blnIns:blnIns] = blines
    Body[bln1-1:bln2] = []

    ### update bnodes
    # increment lnums in the range which is being moved
    delta = blnIns-bln2
    for i in xrange(ln1-1,ln2):
        bnodes[i]+=delta
    # decrement lnums in the range after which the move is made
    delta = bln2-bln1+1
    for i in xrange(ln2,lnIns):
        bnodes[i]-=delta
    # insert, cut
    nLines = bnodes[ln1-1:ln2]
    bnodes[lnIns:lnIns] = nLines
    bnodes[ln1-1:ln2] = []

    ### compute and set new snLn, blnShow
    snLn_ = VO.snLn
    snLn = lnIns+1-(ln2-ln1+1)
    VO.snLn = snLn
    vim.command('let snLn=%s' %snLn)

    blnShow = bnodes[snLn-1] # must compute after bnodes update

    ### update levels (same as for Tree)
    nLevels = levels[ln1-1:ln2]
    if levDelta:
        nLevels = [(lev+levDelta) for lev in nLevels]
    # insert, then cut
    levels[lnIns:lnIns] = nLevels
    levels[ln1-1:ln2] = []

    if VO.hook_doBodyAfterOop:
        VO.hook_doBodyAfterOop(VO, 'down', levDelta,
                    blnShow, snLn,
                    blnShow+len(blines)-1, snLn+len(nLevels)-1,
                    bln1-1, ln1-1)

    ### ---go back to Tree---
    vim.command("call voom#OopFromBody(%s,%s,%s)" %(body,tree,blnShow))

    ### remove snLn mark before modifying Tree
    Tree[snLn_-1] = ' ' + Tree[snLn_-1][1:]

    ### update Tree (same as for levels)
    tlines = Tree[ln1-1:ln2]
    if levDelta:
        tlines = setLevTreeLines(tlines, levels, snLn-1)
    # insert, then cut
    Tree[lnIns:lnIns] = tlines
    Tree[ln1-1:ln2] = []

    ### add snLn mark
    Tree[snLn-1] = '=' + Tree[snLn-1][1:]

    # do this last to tell vim script that there were no errors
    vim.command('let l:blnShow=%s' %blnShow)


def voom_OopRight(): #{{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln1, ln2 = int(vim.eval('l:ln1')), int(vim.eval('l:ln2'))
    VO = VOOMS[body]
    assert VO.tree == tree
    Body, Tree = VO.Body, VO.Tree
    bnodes, levels = VO.bnodes, VO.levels

    ### Move right means increment level by 1 for all nodes in the range.

    # can't move right if ln1 node is child of previous node
    if levels[ln1-1] > levels[ln1-2]:
        vim.command('let l:doverif=0')
        vim.command("call voom#OopFromBody(%s,%s,-1)" %(body,tree))
        return

    ### change levels of Body headlines
    f = VO.changeLevBodyHead
    if f:
        for bln in bnodes[ln1-1:ln2]:
            Body[bln-1] = f(VO, Body[bln-1], 1)

    # new snLn will be set to ln1
    blnShow = bnodes[ln1-1]

    ### change levels of VO.levels (same as for Tree)
    nLevels = levels[ln1-1:ln2]
    nLevels = [(lev+1) for lev in nLevels]
    levels[ln1-1:ln2] = nLevels

    if VO.hook_doBodyAfterOop:
        if ln2 < len(bnodes): blnum2 = bnodes[ln2]-1
        else: blnum2 = len(Body)
        VO.hook_doBodyAfterOop(VO, 'right', 1, blnShow, ln1, blnum2, ln2, None, None)

    ### ---go back to Tree---
    vim.command("let &fdm=b_fdm")
    vim.command("call voom#OopFromBody(%s,%s,%s)" %(body,tree,blnShow))

    ### change levels of Tree lines (same as for VO.levels)
    tlines = Tree[ln1-1:ln2]
    tlines = setLevTreeLines(tlines, levels, ln1-1)
    Tree[ln1-1:ln2] = tlines

    ### set snLn to ln1
    snLn = VO.snLn
    if not snLn==ln1:
        Tree[snLn-1] = ' ' + Tree[snLn-1][1:]
        snLn = ln1
        Tree[snLn-1] = '=' + Tree[snLn-1][1:]
        VO.snLn = snLn

    # do this last to tell vim script that there were no errors
    vim.command('let l:blnShow=%s' %blnShow)


def voom_OopLeft(): #{{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln1, ln2 = int(vim.eval('l:ln1')), int(vim.eval('l:ln2'))
    VO = VOOMS[body]
    assert VO.tree == tree
    Body, Tree = VO.Body, VO.Tree
    bnodes, levels = VO.bnodes, VO.levels

    ### Move left means decrement level by 1 for all nodes in the range.

    # can't move left if at top level 1
    if levels[ln1-1]==1:
        vim.command('let l:doverif=0')
        vim.command("call voom#OopFromBody(%s,%s,-1)" %(body,tree))
        return
    # don't move left if the range is not at the end of subtree
    if not AAMLEFT and ln2 < len(levels) and levels[ln2]==levels[ln1-1]:
        vim.command('let l:doverif=0')
        vim.command("call voom#OopFromBody(%s,%s,-1)" %(body,tree))
        return

    ### change levels of Body headlines
    f = VO.changeLevBodyHead
    if f:
        for bln in bnodes[ln1-1:ln2]:
            Body[bln-1] = f(VO, Body[bln-1], -1)

    # new snLn will be set to ln1
    blnShow = bnodes[ln1-1]

    ### change levels of VO.levels (same as for Tree)
    nLevels = levels[ln1-1:ln2]
    nLevels = [(lev-1) for lev in nLevels]
    levels[ln1-1:ln2] = nLevels

    if VO.hook_doBodyAfterOop:
        if ln2 < len(bnodes): blnum2 = bnodes[ln2]-1
        else: blnum2 = len(Body)
        VO.hook_doBodyAfterOop(VO, 'left', -1, blnShow, ln1, blnum2, ln2, None, None)

    ### ---go back to Tree---
    vim.command("let &fdm=b_fdm")
    vim.command("call voom#OopFromBody(%s,%s,%s)" %(body,tree,blnShow))

    ### change levels of Tree lines (same as for VO.levels)
    tlines = Tree[ln1-1:ln2]
    tlines = setLevTreeLines(tlines, levels, ln1-1)
    Tree[ln1-1:ln2] = tlines

    ### set snLn to ln1
    snLn = VO.snLn
    if not snLn==ln1:
        Tree[snLn-1] = ' ' + Tree[snLn-1][1:]
        snLn = ln1
        Tree[snLn-1] = '=' + Tree[snLn-1][1:]
        VO.snLn = snLn

    # do this last to tell vim script that there were no errors
    vim.command('let l:blnShow=%s' %blnShow)


def voom_OopMark(): # {{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln1, ln2 = int(vim.eval('l:ln1')), int(vim.eval('l:ln2'))
    VO = VOOMS[body]
    assert VO.tree == tree
    Body, Tree = VO.Body, VO.Tree
    bnodes, levels = VO.bnodes, VO.levels
    marker_re = VO.marker_re

    for i in xrange(ln1-1,ln2):
        # insert 'x' in Tree line
        tline = Tree[i]
        if tline[1]!='x':
            Tree[i] = '%sx%s' %(tline[0], tline[2:])
            # insert 'x' in Body headline
            bln = bnodes[i]
            bline = Body[bln-1]
            end = marker_re.search(bline).end(1)
            Body[bln-1] = '%sx%s' %(bline[:end], bline[end:])


def voom_OopUnmark(): # {{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln1, ln2 = int(vim.eval('l:ln1')), int(vim.eval('l:ln2'))
    VO = VOOMS[body]
    assert VO.tree == tree
    Body, Tree = VO.Body, VO.Tree
    bnodes, levels = VO.bnodes, VO.levels
    marker_re = VO.marker_re

    for i in xrange(ln1-1,ln2):
        # remove 'x' from Tree line
        tline = Tree[i]
        if tline[1]=='x':
            Tree[i] = '%s %s' %(tline[0], tline[2:])
            # remove 'x' from Body headline
            bln = bnodes[i]
            bline = Body[bln-1]
            end = marker_re.search(bline).end(1)
            # remove one 'x', not enough
            #Body[bln-1] = '%s%s' %(bline[:end], bline[end+1:])
            # remove all consecutive 'x' chars
            Body[bln-1] = '%s%s' %(bline[:end], bline[end:].lstrip('x'))


def voom_OopMarkStartup(): # {{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln = int(vim.eval('l:ln'))
    VO = VOOMS[body]
    assert VO.tree == tree
    Body, Tree = VO.Body, VO.Tree
    bnodes, levels = VO.bnodes, VO.levels
    marker_re = VO.marker_re

    if ln==1:
        bln_selected = 0
    else:
        bln_selected = bnodes[ln-1]
    # remove '=' from all other Body headlines
    # also, strip 'x' and 'o' after removed '='
    for bln in bnodes[1:]:
        if bln==bln_selected: continue
        bline = Body[bln-1]
        end = marker_re.search(bline).end()
        bline2 = bline[end:]
        if not bline2: continue
        if bline2[0]=='=':
            Body[bln-1] = '%s%s' %(bline[:end], bline[end:].lstrip('=xo'))
        elif bline2[0]=='o' and bline2[1:] and bline2[1]=='=':
            Body[bln-1] = '%s%s' %(bline[:end+1], bline[end+1:].lstrip('=xo'))

    if ln==1: return

    # insert '=' in current Body headline, but only if it's not there already
    bline = Body[bln_selected-1]
    end = marker_re.search(bline).end()
    bline2 = bline[end:]
    if not bline2:
        Body[bln_selected-1] = '%s=' %bline
        return
    if bline2[0]=='=':
        return
    elif bline2[0]=='o' and bline2[1:] and bline2[1]=='=':
        return
    elif bline2[0]=='o':
        end+=1
    Body[bln_selected-1] = '%s=%s' %(bline[:end], bline[end:])


#--- Tree Folding Operations --- {{{2
# Opened/Closed Tree buffer folds are equivalent to Expanded/Contracted nodes.
# By default, folds are closed.
# Opened folds are marked by 'o' in Body headlines (after 'x', before '=').
#
# To determine which folds are currently closed/opened, we open all closed
# folds one by one, from top to bottom, starting from top level visible folds.
# This produces list of closed folds.
#
# To restore folding according to a list of closed folds:
#   open all folds;
#   close folds from bottom to top.
#
# Conventions:
#   cFolds --lnums of closed folds
#   oFolds --lnums of opened folds
#   ln, ln1, ln2  --Tree line number
#
# NOTE: Cursor position and window view are not restored here.
# See also:
#   ../../doc/voom.txt#id_20110120011733


def voom_OopFolding(action): #{{{3
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    VO = VOOMS[body]
    assert VO.tree == tree
    # check and adjust range lnums
    # don't worry about invalid range lnums: Vim checks that
    if not action=='cleanup':
        ln1, ln2 = int(vim.eval('a:ln1')), int(vim.eval('a:ln2'))
        if ln2<ln1: ln1,ln2=ln2,ln1 # probably redundant
        if ln2==1: return
        #if ln1==1: ln1=2
        if ln1==ln2:
            ln2 = ln2 + nodeSubnodes(VO, ln2)
            if ln1==ln2: return

    if action=='save':
        cFolds = foldingGet(ln1, ln2)
        foldingWrite(VO, ln1, ln2, cFolds)
    elif action=='restore':
        cFolds = foldingRead(VO, ln1, ln2)
        foldingCreate(ln1, ln2, cFolds)
    elif action=='cleanup':
        foldingCleanup(VO)


def foldingGet(ln1, ln2): #{{{3
    """Get all closed folds in line range ln1-ln2, including subfolds.
    If line ln2 is visible and is folded, its subfolds are included.
    Executed in Tree buffer.
    """
    cFolds = []
    lnum = ln1
    # go through top level folded lines (visible closed folds)
    while lnum < ln2+1:
        # line lnum is first line of a closed fold
        if int(vim.eval('foldclosed(%s)' %lnum))==lnum:
            cFolds.append(lnum)
            # line after this fold and subfolds
            foldend = int(vim.eval('foldclosedend(%s)' %lnum))+1
            lnum0 = lnum
            lnum = foldend
            vim.command('keepj normal! %sGzo' %lnum0)
            # open every folded line in this fold
            for ln in xrange(lnum0+1, foldend):
                # line ln is first line of a closed fold
                if int(vim.eval('foldclosed(%s)' %ln))==ln:
                    cFolds.append(ln)
                    vim.command('keepj normal! %sGzo' %ln)
        else:
            lnum+=1

    cFolds.reverse()
    # close back opened folds
    for ln in cFolds:
        vim.command('keepj normal! %sGzc' %ln)
    return cFolds


def foldingCreate(ln1, ln2, cFolds): #{{{3
    """Create folds in range ln1-ln2 from a list of closed folds in that range.
    The list must be reverse sorted. Must not contain nodes without children.
    Executed in Tree buffer.
    """
    #cFolds.sort()
    #cFolds.reverse()
    #vim.command('%s,%sfoldopen!' %(ln1,ln2))
    # see  ../../doc/voom.txt#id_20110120011733
    vim.command(r'try | %s,%sfoldopen! | catch /^Vim\%%((\a\+)\)\=:E490/ | endtry'
            %(ln1,ln2))
    for ln in cFolds:
        vim.command('keepj normal! %sGzc' %ln)


def foldingFlip(VO, ln1, ln2, folds): #{{{3
    """Convert list of opened/closed folds in range ln1-ln2 into list of
    closed/opened folds.
    """
    # Important: this also eliminates lnums of nodes without children,
    # so we don't get Vim E490 (no fold found) error on :foldclose.
    folds = {}.fromkeys(folds)
    folds_flipped = []
    for ln in xrange(ln1,ln2+1):
        if nodeHasChildren(VO, ln) and not ln in folds:
            folds_flipped.append(ln)
    folds_flipped.reverse()
    return folds_flipped


def foldingRead(VO, ln1, ln2): #{{{3
    """Read "o" marks in Body headlines."""
    cFolds = []
    marker_re = VO.marker_re
    bnodes = VO.bnodes
    Body = VO.Body

    for ln in xrange(ln1,ln2+1):
        if not nodeHasChildren(VO, ln):
            continue
        bline = Body[bnodes[ln-1]-1]
        end = marker_re.search(bline).end()
        if end<len(bline) and bline[end]=='o':
            continue
        else:
            cFolds.append(ln)

    cFolds.reverse()
    return cFolds


def foldingWrite(VO, ln1, ln2, cFolds): #{{{3
    """Write "o" marks in Body headlines."""
    cFolds = {}.fromkeys(cFolds)
    marker_re = VO.marker_re
    bnodes = VO.bnodes
    Body = VO.Body

    for ln in xrange(ln1,ln2+1):
        if not nodeHasChildren(VO, ln):
            continue
        bln = bnodes[ln-1]
        bline = Body[bln-1]
        end = marker_re.search(bline).end()
        isClosed = ln in cFolds
        # headline is marked with 'o'
        if end<len(bline) and bline[end]=='o':
            # remove 'o' mark
            if isClosed:
                Body[bln-1] = '%s%s' %(bline[:end], bline[end:].lstrip('ox'))
        # headline is not marked with 'o'
        else:
            # add 'o' mark
            if not isClosed:
                if end==len(bline):
                    Body[bln-1] = '%so' %bline
                elif bline[end] != 'o':
                    Body[bln-1] = '%so%s' %(bline[:end], bline[end:])


def foldingCleanup(VO): #{{{3
    """Remove "o" marks from  from nodes without children."""
    marker_re = VO.marker_re
    bnodes = VO.bnodes
    Body = VO.Body

    for ln in xrange(2,len(bnodes)+1):
        if nodeHasChildren(VO, ln): continue
        bln = bnodes[ln-1]
        bline = Body[bln-1]
        end = marker_re.search(bline).end()
        if end<len(bline) and bline[end]=='o':
            Body[bln-1] = '%s%s' %(bline[:end], bline[end:].lstrip('ox'))


#--- Sort Operations --- {{{2
# 1) Sort siblings of the current node.
# - Get list of siblings of the current node (as Tree lnums).
#   Two nodes are siblings if they have the same parent and the same level.
# - Construct list of corresponding Tree headlines. Decorate with indexes and
#   Tree lnums. Sort by headline text.
# - Construct new Body region from nodes in sorted order. Replace the region.
#   IMPORTANT: this does not change outline data (Tree, VO.levels, VO.bnodes)
#   for nodes with smaller levels or for nodes outside of the siblings region.
#   Thus, recursive sort is possible.
#
# 2) Deep (recursive) sort: sort siblings of the current node and siblings in
# all subnodes. Sort as above for all groups of siblings in the affected
# region, starting from the most deeply nested.
# - Construct list of groups of all siblings: top to bottom, decorate each
#   siblings group with level and parent lnum.
# - Reverse sort the list by levels.
# - Do sort for each group of siblings in the list: from right to left and from
#   bottom to top.
#
# 3) We modify only the Body buffer. We then do global outline update to redraw
# the Tree and to update outline data. Performing targeted update as in other
# outline operations is too tedious.


def voom_OopSort(): #{{{3
    # Returning before setting l:blnShow means no changes were made.
    ### parse options {{{
    oDeep = False
    D = {'oIgnorecase':0, 'oUnicode':0, 'oEnc':0, 'oReverse':0, 'oFlip':0, 'oShuffle':0}
    options = vim.eval('a:qargs')
    options = options.strip().split()
    for o in options:
        if o=='deep': oDeep = True
        elif o=='i':       D['oIgnorecase'] = 1
        elif o=='u':       D['oUnicode']    = 1
        elif o=='r':       D['oReverse']    = 1 # sort in reverse order
        elif o=='flip':    D['oFlip']       = 1 # reverse without sorting
        elif o=='shuffle': D['oShuffle']    = 1
        else:
            vim.command("call voom#ErrorMsg('VOoM (sort): invalid option: %s')" %o.replace("'","''"))
            vim.command("call voom#WarningMsg('VOoM (sort): valid options are: deep, i (ignore-case), u (unicode), r (reverse-sort), flip, shuffle')")
            return

    if (D['oReverse'] + D['oFlip'] + D['oShuffle']) > 1:
        vim.command("call voom#ErrorMsg('VOoM (sort): these options cannot be combined: r, flip, shuffle')")
        return

    if D['oShuffle']:
        global shuffle
        if shuffle is None: from random import shuffle

    if D['oUnicode']:
        D['oEnc'] = get_vim_encoding()
    ###### }}}

    ### get other Vim data, compute 'siblings' {{{
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln1, ln2 = int(vim.eval('a:ln1')), int(vim.eval('a:ln2'))
    if ln2<ln1: ln1,ln2=ln2,ln1 # probably redundant
    VO = VOOMS[body]
    assert VO.tree == tree
    Body, Tree = VO.Body, VO.Tree
    bnodes, levels = VO.bnodes, VO.levels

    if ln1==ln2:
        # Tree lnums of all siblings of the current node
        siblings = nodeSiblings(VO,ln1)
    else:
        # Tree lnums of all siblings in the range
        siblings = rangeSiblings(VO,ln1,ln2)
        if not siblings:
            vim.command("call voom#ErrorMsg('VOoM (sort): invalid Tree selection')")
            return
    ###### }}}
    #print ln1, ln2, siblings

    ### do sorting
    # progress flags: (got >1 siblings, order changed after sort)
    flag1,flag2 = 0,0
    if not oDeep:
        flag1,flag2 = sortSiblings(VO, siblings, **D)
    else:
        siblings_groups = getSiblingsGroups(VO,siblings)
        for group in siblings_groups:
            m, n = sortSiblings(VO, group, **D)
            flag1+=m; flag2+=n

    if flag1==0:
        vim.command("call voom#WarningMsg('VOoM (sort): nothing to sort')")
        return
    elif flag2==0:
        vim.command("call voom#WarningMsg('VOoM (sort): already sorted')")
        return

    # Show first sibling. Tracking the current node and bnode is too hard.
    lnum1 = siblings[0]
    lnum2 = siblings[-1] + nodeSubnodes(VO,siblings[-1])
    blnShow = bnodes[lnum1-1]
    vim.command('let [l:blnShow,l:lnum1,l:lnum2]=[%s,%s,%s]' %(blnShow,lnum1,lnum2))


def sortSiblings(VO, siblings, oIgnorecase, oUnicode, oEnc, oReverse, oFlip, oShuffle): #{{{3
    """Sort sibling nodes. 'siblings' is list of Tree lnums in ascending order.
    This only modifies Body buffer. Outline data are not updated.
    Return progress flags (flag1,flag2), see voom_OopSort().
    """
    sibs = siblings
    if len(sibs) < 2:
        return (0,0)
    Body, Tree = VO.Body, VO.Tree
    bnodes, levels = VO.bnodes, VO.levels
    z, Z = len(sibs), len(bnodes)

    ### decorate siblings for sorting
    # [(Tree headline text, index, lnum), ...]
    sibs_dec = []
    for i in xrange(z):
        sib = sibs[i]
        head = Tree[sib-1].split('|',1)[1]
        if oUnicode and oEnc:
            head = unicode(head, oEnc, 'replace')
        if oIgnorecase:
            head = head.lower()
        sibs_dec.append((head, i, sib))

    ### sort
    if oReverse:
        sibs_dec.sort(key=lambda x: x[0], reverse=True)
    elif oFlip:
        sibs_dec.reverse()
    elif oShuffle:
        shuffle(sibs_dec)
    else:
        sibs_dec.sort()

    sibs_sorted = [i[2] for i in sibs_dec]
    #print sibs_dec; print sibs_sorted
    if sibs==sibs_sorted:
        return (1,0)

    ### blnum1, blnum2: first and last Body lnums of the affected region
    blnum1 = bnodes[sibs[0]-1]
    n = sibs[-1] + nodeSubnodes(VO,sibs[-1])
    if n < Z:
        blnum2 = bnodes[n]-1
    else:
        blnum2 = len(Body)

    ### construct new Body region
    blines = []
    for i in xrange(z):
        sib = sibs[i]
        j = sibs_dec[i][1] # index into sibs that points to new sib
        sib_new = sibs[j]

        # get Body region for sib_new branch
        bln1 = bnodes[sib_new-1]
        if j+1 < z:
            sib_next = sibs[j+1]
            bln2 = bnodes[sib_next-1]-1
        else:
            node_last = sib_new + nodeSubnodes(VO,sib_new)
            if node_last < Z:
                bln2 = bnodes[node_last]-1
            else:
                bln2 = len(Body)

        blines.extend(Body[bln1-1:bln2])

    ### replace Body region with the new, sorted region
    body_len = len(Body)
    Body[blnum1-1:blnum2] = blines
    assert body_len == len(Body)

    return (1,1)


#---EXECUTE SCRIPT----------------------------{{{1
#

def voom_GetVoomRange(withSubnodes=0): #{{{2
    body = int(vim.eval('l:body'))
    VO = VOOMS[body]
    lnum = int(vim.eval('a:lnum'))
    if vim.eval('l:bufType')=='Body':
        lnum = bisect.bisect_right(VO.bnodes, lnum)
    bln1, bln2 = nodesBodyRange(VO, lnum, lnum, withSubnodes)
    vim.command("let [l:bln1,l:bln2]=[%s,%s]" %(bln1,bln2))


def voom_GetBuffRange(): #{{{2
    body = int(vim.eval('l:body'))
    ln1, ln2 = int(vim.eval('a:ln1')), int(vim.eval('a:ln2'))
    VO = VOOMS[body]
    bln1, bln2 = nodesBodyRange(VO, ln1, ln2)
    vim.command("let [l:bln1,l:bln2]=[%s,%s]" %(bln1,bln2))


def voom_Exec(): #{{{2
    if vim.eval('l:bufType')=='Tree':
        Buf = VOOMS[int(vim.eval('l:body'))].Body
    else:
        Buf = vim.current.buffer
    bln1, bln2 = int(vim.eval('l:bln1')), int(vim.eval('l:bln2'))
    blines = Buf[bln1-1:bln2]
    # specifiy script encoding (Vim internal encoding) on the first line
    enc = '# -*- coding: %s -*-' %get_vim_encoding()
    # prepend extra \n's to make traceback lnums match buffer lnums
    # TODO: find less silly way to adjust traceback lnums
    script = '%s\n%s%s\n' %(enc, '\n'*(bln1-2), '\n'.join(blines))
    d = {'vim':vim, '_VOoM':sys.modules['voom_vim']}
    try:
        exec script in d
    #except Exception: # does not catch vim.error
    except:
        #traceback.print_exc()  # writes to sys.stderr
        printTraceback(bln1,bln2)

    print '---end of Python script (%s-%s)---' %(bln1,bln2)

# id_20101214100357
# NOTES on printing Python tracebacks and Vim errors.
#
# When there is no PyLog, we want Python traceback echoed as Vim error message.
# Writing to sys.stderr accomplishes that:
#   :py sys.stderr.write('oopsy-doopsy')
# Drawback: writing to default sys.stderr (no PyLog) triggers Vim error.
# Thus, without PyLog there are two useless lines on top with Vim error:
#   Error detected while processing function voom#Exec:
#   line 63:
#
# Vim code:
#
# 1) PyLog is enabled. Must execute this inside try/catch/entry.
# Otherwise, something weird happens when Vim error occurs, most likely
# Vim error echoing interferes with PyLog scrolling.
# The only downside is that only v:exception is printed, no details
# about Vim error location (v:throwpoint is useless).
#
# 2) PyLog is not enabled. Do not execute this inside try/catch/endtry.
# Python traceback is not printed if we do.
#


def printTraceback(bln1,bln2): #{{{2
    """Print traceback from exception caught during Voomexec."""
    out = None
    # like traceback.format_exc(), traceback.print_exc()
    try:
        etype, value, tb = sys.exc_info()
        out = traceback.format_exception(etype, value, tb)
        #out = traceback.format_exception(etype, value, tb.tb_next)
    finally:
        etype = value = tb = None
    if not out:
        sys.stderr.write('ERROR: Voomexec failed to format Python traceback')
        return
    info = '  ...exception executing script (%s-%s)...\n' %(bln1,bln2)
    if bln1==1:
        info += '  ...subtract 1 from traceback lnums to get buffer lnums...\n'
    out[1:2] = [info]
    #out[1:1] = [info]
    sys.stderr.write(''.join(out))


#---LOG BUFFER--------------------------------{{{1
#
class LogBufferClass: #{{{2
    """A file-like object for replacing sys.stdout and sys.stdin with a Vim buffer."""
    def __init__(self): #{{{3
        self.buffer = vim.current.buffer
        self.logbnr = vim.eval('bufnr("")')
        self.buffer[0] = 'Python Log buffer ...'
        #self.encoding = vim.eval('&enc')
        self.encoding = get_vim_encoding()
        self.join = False

    def write(self,s): #{{{3
        """Append string to buffer, scroll Log windows in all tabs."""
        # Messages are terminated by sending '\n' (null string? ^@).
        # Thus "print '\n'" sends '\n' twice.
        # The message itself can contain '\n's.
        # One line can be sent in many strings which don't always end with \n.
        # This is certainly true for Python errors and for 'print a, b, ...' .

        # Can't append unicode strings. This produces an error:
        #  :py vim.current.buffer.append(u'test')

        # Can't have '\n' in appended list items, so always use splitlines().
        # A trailing \n is lost after splitlines(), but not for '\n\n' etc.
        #print self.buffer.name

        if not s: return
        # Nasty things happen when printing to unloaded PyLog buffer.
        # This also catches printing to noexisting buffer, as in pydoc help() glitch.
        if vim.eval("bufloaded(%s)" %self.logbnr)=='0':
            vim.command("call voom#ErrorMsg('VOoM (PyLog): PyLog buffer %s is unloaded or doesn''t exist')" %self.logbnr)
            vim.command("call voom#ErrorMsg('VOoM (PyLog): unable to write string:')")
            vim.command("echom '%s'" %(repr(s).replace("'", "''")) )
            vim.command("call voom#ErrorMsg('VOoM (PyLog): please try executing command :Voomlog to fix')")
            return
        try:
            if type(s) == type(u" "):
                s = s.encode(self.encoding)
            # Join with previous message if it had no ending newline.
            if self.join:
                s = self.buffer[-1] + s
                del self.buffer[-1]
            self.join = not s[-1]=='\n'
            self.buffer.append(s.splitlines())
        except:
            # list of all exception lines, no newlines in items
            exc_lines = traceback.format_exc().splitlines()
            self.buffer.append('')
            self.buffer.append('VOoM: exception writing to PyLog buffer:')
            self.buffer.append(repr(s))
            self.buffer.append(exc_lines)
            self.buffer.append('')

        vim.command('call voom#LogScroll()')


#---misc--------------------------------------{{{1

def get_vim_encoding(): #{{{2
    """Return Vim internal encoding."""
    # When &enc is any Unicode Vim allegedly uses utf-8 internally.
    # See |encoding|, mbyte.c, values are from |encoding-values|
    enc = vim.eval('&enc')
    if enc in ('utf-8','ucs-2','ucs-2le','utf-16','utf-16le','ucs-4','ucs-4le'):
        return 'utf-8'
    return enc


# modelines {{{1
# vim:fdm=marker:fdl=0:
# vim:foldtext=getline(v\:foldstart).'...'.(v\:foldend-v\:foldstart):
autoload/voom.vim	[[[1
2953
" voom.vim
" Last Modified: 2014-05-28
" Version: 5.1
" VOoM -- Vim two-pane outliner, plugin for Python-enabled Vim 7.x
" Website: http://www.vim.org/scripts/script.php?script_id=2657
" Author: Vlad Irnov (vlad DOT irnov AT gmail DOT com)
" License: CC0, see http://creativecommons.org/publicdomain/zero/1.0/


"---Conventions-------------------------------{{{1
" Tree      --Tree buffer
" Body      --Body buffer
" tree      --Tree buffer number
" body      --Body buffer number
" headline  --Body line with a matching fold marker, also a Tree line
" node      --Body region between two headlines, usually also a fold.
"             A node is identified by Tree lnum (nodes) or Body lnum (bnodes).
" nodes     --list of Tree lnums
" bnodes    --list of Body lnums, line numbers of Body headlines
" bnr       --buffer number
" wnr, tnr  --window number, tab number
" lnum, ln, lnr      --line number, usually Tree
" blnum, bln, blnr   --Body line number
" tline(s)  --Tree line(s)
" bline(s)  --Body line(s)
" snLn      --selected node line number, a Tree line number
" var_      --previous value of var
" l:var     --this var is set or may be changed by Python code (l:blnShow)
" z, Z      --list siZe, usually len(bnodes)


"---Initialize--------------------------------{{{1
if !exists('s:voom_did_init')
    let s:script_path = expand("<sfile>:p")
    let s:script_dir = expand("<sfile>:p:h")
    let s:voom_dir = fnamemodify(s:script_dir, ':p') . 'voom'
    let s:voom_logbnr = 0
    " {tree : associated body,  ...}
    let s:voom_trees = {}
    " {body : {'tree' : associated tree,
    "          'snLn' : selected node Tree lnum,
    "          'MTYPE' : 0--no mode or fmr mode, 1--markup mode
    "          'tick' : b:changedtick of Body on Body BufLeave,
    "          'tick_' : b:changedtick of Body on last Tree update}, {...}, ... }
    let s:voom_bodies = {}
    " force one-time outline verification
    let s:verify = 0
python << EOF
import sys, vim
if not vim.eval("s:voom_dir") in sys.path:
    sys.path.append(vim.eval("s:voom_dir"))
import voom_vim as _VOoM
sys.modules['voom_vim'].VOOMS = {}
EOF
    let s:voom_did_init = 'v5.1'
endif


"---User Options------------------------------{{{1
" These can be defined in .vimrc .

" Where Tree window is created: 'left', 'right', 'top', 'bottom'
" This is relative to the current window.
if !exists('g:voom_tree_placement')
    let g:voom_tree_placement = 'left'
endif
" Initial Tree window width.
if !exists('g:voom_tree_width')
    let g:voom_tree_width = 30
endif
" Initial Tree window height.
if !exists('g:voom_tree_height')
    let g:voom_tree_height = 12
endif

" Where Log window is created: 'left', 'right', 'top', 'bottom'
" This is far left/right/top/bottom.
if !exists('g:voom_log_placement')
    let g:voom_log_placement = 'bottom'
endif
" Initial Log window width.
if !exists('g:voom_log_width')
    let g:voom_log_width = 30
endif
" Initial Log window height.
if !exists('g:voom_log_height')
    let g:voom_log_height = 12
endif

" Verify outline after outline operations.
if !exists('g:voom_verify_oop')
    let g:voom_verify_oop = 1
endif

" Which key to map to Select-Node-and-Shuttle-between-Body/Tree
if !exists('g:voom_return_key')
    let g:voom_return_key = '<Return>'
endif

" Which key to map to Shuttle-between-Body/Tree
if !exists('g:voom_tab_key')
    let g:voom_tab_key = '<Tab>'
endif

" g:voom_rstrip_chars_{filetype} -- string with chars to strip from right side
" of Tree headlines for Body 'filetype' {filetype}.
" If defined, these will be used instead of 'commentstring' chars.
if !exists('g:voom_rstrip_chars_vim')
    let g:voom_rstrip_chars_vim = "\"# \t"
endif
if !exists('g:voom_rstrip_chars_text')
    let g:voom_rstrip_chars_text = " \t"
endif
if !exists('g:voom_rstrip_chars_help')
    let g:voom_rstrip_chars_help = " \t"
endif


"---Commands----------------------------------{{{1
" Main commands are defined in ../plugin/voom.vim.
" Naming convention: Voomdoit will not modify Body, VoomDoit can modify Body.

com! Voomunl call voom#EchoUNL()
com! -nargs=? Voomgrep call voom#Grep(<q-args>)
com! -range -nargs=? VoomSort call voom#OopSort(<line1>,<line2>, <q-args>)

com! -range VoomFoldingSave    call voom#OopFolding(<line1>,<line2>, 'save')
com! -range VoomFoldingRestore call voom#OopFolding(<line1>,<line2>, 'restore')
com! -range VoomFoldingCleanup call voom#OopFolding(<line1>,<line2>, 'cleanup')

com! Voomtoggle call voom#ToggleTreeWindow()
com! Voomquit call voom#DeleteOutline()
com! VoomQuitAll call voom#DeleteOutlines()
com! -nargs=? Voominfo call voom#Voominfo(<q-args>)

""" development helpers
if exists('g:voom_create_devel_commands')
    " reload autoload/voom.vim (outlines are preserved)
    com! VoomReloadVim exe 'so '.s:script_path
    " wipe out Trees, PyLog, delete Python modules; reload autoload/voom.vim, voom_vim.py
    " Note: simply reloading Python modules is pointless since v4.2
    com! VoomReloadAll call voom#ReloadAllPre() | exe 'so '.s:script_path
endif


"---voom#Init(), various commands, helpers----{{{1

func! voom#Init(qargs, ...) "{{{2
" Commands :Voom, :VoomToggle.
    let bnr = bufnr('')
    " Current buffer is Tree.
    if has_key(s:voom_trees, bnr)
        let body = s:voom_trees[bnr]
        if a:0 && a:1
            call voom#UnVoom(body, bnr)
            return
        endif
        if !hasmapto('voom#ToTreeOrBodyWin','n')
            call voom#ErrorMsg("VOoM: Tree lost mappings. Reconfiguring...")
            call voom#TreeConfig()
            call voom#TreeConfigFt(a:body)
        endif
        call voom#ToBody(body)
        return
    " Current buffer is Body.
    elseif has_key(s:voom_bodies, bnr)
        let tree = s:voom_bodies[bnr].tree
        if a:0 && a:1
            call voom#UnVoom(bnr, tree)
            return
        endif
        if !hasmapto('voom#ToTreeOrBodyWin','n')
            call voom#ErrorMsg("VOoM: Body lost mappings. Reconfiguring...")
            call voom#BodyConfig()
        endif
        call voom#ToTree(tree)
        return
    endif
    " Current buffer is not a VOoM buffer. Create Tree for it. Current buffer
    " becomes a Body buffer.
    let body = bnr
    let s:voom_bodies[body] = {}
    let blnr = line('.')
    let [b_name, b_dir] = [expand('%:p:t'), expand('%:p:h')]
    if b_name=='' | let b_name='No Name' | endif
    let l:firstLine = ' '.b_name.' ['.b_dir.'], b'.body
    let [l:MTYPE, l:qargs] = [-1, a:qargs]
    python _VOoM.voom_Init(int(vim.eval('l:body')))
    if l:MTYPE < 0 | unlet s:voom_bodies[body] | return | endif
    let s:voom_bodies[body].MTYPE = l:MTYPE
    let s:voom_bodies[body].mmode = l:mmode
    call voom#BodyConfig()
    call voom#ToTreeWin()
    call voom#TreeCreate(body, blnr)
    if a:0 && a:1
        call voom#ToBody(body)
        return
    endif
endfunc


func! voom#TreeSessionLoad() "{{{2
" Create outline when loading session created with :mksession.
    if !exists('g:SessionLoad') || &modified || line('$')>1 || getline(1)!=''
        return
    endif
    call setline(1,[' PLEASE','  KILL','   ME (:bw)'])
    setl nomod noma bh=wipe
    " don't -- horrible errors if two tabs with a Tree in each
    "exe 'au SessionLoadPost <buffer> bw '.bufnr('')
    "au SessionLoadPost <buffer> call voom#TreeSessionLoadPost()
    let [tree, tname] = [bufnr(''), bufname('')]
    if has_key(s:voom_trees,tree) | return | endif
    """ try to find Body matching this Tree buffer name
    let treeName = fnamemodify(tname,':t')
    if treeName !~# '^.\+_VOOM\d\+$' | return | endif
    let bodyName = substitute(treeName, '\C_VOOM\d\+$', '', '')
    let bodyNameM = substitute(bodyName, '[', '[[]', 'g') . '$'
    let [body, bodyWnr] = [bufnr(bodyNameM), bufwinnr(bodyNameM)]
    "echo 'DEBUG' treeName tree '|' bodyName body bodyWnr
    " Body must exist and be in a window in the current tabpage
    if body < 0 || bodyName !=# fnamemodify(bufname(body),':t')
        return
    elseif bodyWnr < 0 || bodyWnr == winnr() || bodyWnr != bufwinnr(body)
        return
    " there is already an outline for this Body
    elseif has_key(s:voom_bodies, body)
        exe 'b'.s:voom_bodies[body].tree
        call voom#TreeConfigWin()
        return
    endif
    " rename Tree (current buffer), if needed, to correct Body bufnr
    let tname_new = substitute(tname, '\C_VOOM\d\+$', '_VOOM'.body, '')
    if tname !=# tname_new
        if bufexists(tname_new) | return | endif
        let bnrMax_ = bufnr('$')
        exe 'silent file '.fnameescape(tname_new)
        " An unlisted buffer is created to hold the old name. Kill it.
        let bnrMax = bufnr('$')
        if bnrMax > bnrMax_ && bnrMax==bufnr(tname.'$')
            exe 'bwipeout '.bnrMax
        endif
    endif
    """ go to Body, create outline, go back, configure Tree
    let wnr_ = winnr()
    let wnr_p = winnr('#')
    try
        exe 'noautocmd '.bodyWnr.'wincmd w'
        let s:voom_bodies[body] = {}
        let blnr = line('.')
        let b_dir = expand('%:p:h')
        let l:firstLine = ' '.bodyName.' ['.b_dir.'], b'.body
        let [l:MTYPE, l:qargs] = [-1, '']
        python _VOoM.voom_Init(int(vim.eval('l:body')))
        if l:MTYPE < 0 | unlet s:voom_bodies[body] | return | endif
        let s:voom_bodies[body].MTYPE = l:MTYPE
        let s:voom_bodies[body].mmode = l:mmode
        call voom#BodyConfig()
    finally
        if wnr_p | exe 'noautocmd '.wnr_p.'wincmd w' | endif
        exe 'noautocmd '.wnr_.'wincmd w'
    endtry
    if bufnr('')==tree
        call voom#TreeCreate(body, blnr)
    endif
endfunc


func! voom#Complete(A,L,P) "{{{2
" Argument completion for command :Voom. Return string "wiki\nvimwiki\nviki..."
" constructed from file names ../plugin/voom/voom_mode_{whatever}.py .
    let thefiles = split(glob(s:voom_dir.'/voom_mode_?*.py'), "\n")
    let themodes = []
    for the in thefiles
        let themode = substitute(fnamemodify(the,':t'), '\c^voom_mode_\(.*\)\.py$', '\1', '')
        call add(themodes, themode)
    endfor
    return join(themodes, "\n")
endfunc


func! voom#Help() "{{{2
" Open voom.txt as outline in a new tabpage.
    let help_path = fnamemodify(s:script_dir.'/../doc/voom.txt', ":p")
    if !filereadable(help_path)
        call voom#ErrorMsg("VOoM: can't read help file:" help_path)
        return
    endif

    """ voom.txt exists and is shown in some window in some tab -- go there
    let help_bufnr =  bufnr('^'.help_path.'$')
    if help_bufnr > 0
        let alltabs = range(tabpagenr(),tabpagenr('$')) + range(1,tabpagenr()-1)
        for tnr in alltabs
            if index(tabpagebuflist(tnr), help_bufnr) > -1
                exe 'tabnext '.tnr
                exe bufwinnr(help_bufnr).'wincmd w'
                " make sure critical settings are correct
                if &ft!=#'help'
                    set ft=help
                endif
                if &fmr!=#'[[[,]]]' || &fdm!=#'marker'
                    setl fmr=[[[,]]] fdm=marker
                endif
                " make sure outline is present
                call voom#Init('')
                return
            endif
        endfor
    endif

    """ try 'tab help' command
    let help_installed = 1
    let [tnr_, tnrM_] = [tabpagenr(), tabpagenr('$')]
    try
        silent tab help voom.txt
    catch /^Vim\%((\a\+)\)\=:E149/ " no help for voom.txt
        let help_installed = 0
    catch /^Vim\%((\a\+)\)\=:E429/ " help file not found--removed after installing
        let help_installed = 0
    endtry
    if help_installed==1
        if fnamemodify(bufname(""), ":t")!=#'voom.txt'
            echoerr "VOoM: INTERNAL ERROR"
            return
        endif
        if &fmr!=#'[[[,]]]' || &fdm!=#'marker'
            setl fmr=[[[,]]] fdm=marker
        endif
        call voom#Init('')
        return
    " 'tab help' failed, we are on new empty tabpage -- kill it
    elseif tabpagenr()!=tnr_ && tabpagenr('$')==tnrM_+1 && bufname('')=='' && winnr('$')==1
        bwipeout
        exe 'tabnext '.tnr_
    endif

    """ open voom.txt as regular file
    exe 'tabnew '.fnameescape(help_path)
    if fnamemodify(bufname(""), ":t")!=#'voom.txt'
        echoerr "VOoM: INTERNAL ERROR"
        return
    endif
    if &ft!=#'help'
        setl ft=help
    endif
    if &fmr!=#'[[[,]]]' || &fdm!=#'marker'
        setl fmr=[[[,]]] fdm=marker
    endif
    call voom#Init('')
endfunc


func! voom#DeleteOutline(...) "{{{2
" Delete current outline, execute Ex command if in Body or non-VOoM buffer.
    let bnr = bufnr('')
    " current buffer is Tree
    if has_key(s:voom_trees, bnr)
        call voom#UnVoom(s:voom_trees[bnr], bnr)
        return
    " current buffer is Body
    elseif has_key(s:voom_bodies, bnr)
        call voom#UnVoom(bnr, s:voom_bodies[bnr].tree)
    endif
    " current buffer is Body or non-VOoM buffer
    if a:0
        execute a:1
    endif
endfunc


func! voom#DeleteOutlines() "{{{2
" Delete all VOoM outlines.
    for bnr in keys(s:voom_trees)
        let tree = str2nr(bnr)
        call voom#UnVoom(s:voom_trees[tree], tree)
    endfor
endfunc


func! voom#UnVoom(body,tree) "{{{2
" Remove VOoM data for Body body and its Tree tree.
" Wipeout Tree, delete Body au, etc.
" Can be called from any buffer.
" Note: when called from Tree BufUnload au, tree doesn't exist.
    if has_key(s:voom_bodies, a:body) && has_key(s:voom_trees, a:tree)
        unlet s:voom_bodies[a:body]
        unlet s:voom_trees[a:tree]
    else
        echoerr 'VOoM: INTERNAL ERROR'
        return
    endif
    python _VOoM.voom_UnVoom(int(vim.eval('a:body')))
    exe 'au! VoomBody * <buffer='.a:body.'>'
    if bufexists(a:tree)
        "exe 'noautocmd bwipeout '.a:tree
        exe 'au! VoomTree * <buffer='.a:tree.'>'
        exe 'bwipeout '.a:tree
    endif
    if bufnr('')==a:body
        call voom#BodyUnMap()
    endif
endfunc


func! voom#FoldStatus(lnum) "{{{2
    " there is no fold
    if foldlevel(a:lnum)==0
        return 'nofold'
    endif
    let fc = foldclosed(a:lnum)
    " line is hidden in fold, cannot determine it's status
    if fc < a:lnum && fc > 0
        return 'hidden'
    " line is first line of a closed fold
    elseif fc==a:lnum
        return 'folded'
    " line is in an opened fold
    else
        return 'notfolded'
    endif
" Helper for dealing with folds. Determine if line lnum is:
"  not in a fold;
"  hidden in a closed fold;
"  not hidden and is a closed fold;
"  not hidden and is in an open fold.
endfunc


func! voom#WarningMsg(...) "{{{2
    echohl WarningMsg
    for line in a:000
        echo line
    endfor
    echohl None
endfunc


func! voom#ErrorMsg(...) "{{{2
    echohl ErrorMsg
    for line in a:000
        echom line
    endfor
    echohl None
endfunc


func! voom#BufNotLoaded(body) "{{{2
    if bufloaded(a:body)
        return 0
    endif
    if bufexists(a:body)
        let bname = fnamemodify(bufname(a:body),":t")
        call voom#ErrorMsg('VOoM: Body buffer '.a:body.' ('.bname.') is not loaded')
    else
        call voom#ErrorMsg('VOoM: Body buffer '.a:body.' does not exist')
    endif
    return 1
endfunc


func! voom#BufNotEditable(body) "{{{2
    if getbufvar(a:body, "&ma")==1 && getbufvar(a:body, "&ro")==0
        return 0
    endif
    let bname = fnamemodify(bufname(a:body),":t")
    call voom#ErrorMsg("VOoM: Body buffer ".a:body." (".bname.") is 'nomodifiable' or 'readonly'")
    return 1
" If buffer doesn't exist, getbufvar() returns '' .
endfunc


func! voom#BufNotTree(tree) "{{{2
    if has_key(s:voom_trees,a:tree) && !getbufvar(a:tree,'&ma')
        return 0
    endif
    if !has_key(s:voom_trees,a:tree)
        call voom#ErrorMsg('VOoM: current buffer is not Tree')
    elseif getbufvar(a:tree,'&ma')
        echoerr "VOoM: Tree buffer is 'modifiable'"
    endif
    return 1
endfunc


func! voom#SetSnLn(body, snLn) "{{{2
" Set snLn. Used by Python code.
    let s:voom_bodies[a:body].snLn= a:snLn
endfunc


func! voom#ToggleTreeWindow() "{{{2
" Mimimize/restore Tree window.
    let bnr = bufnr('')
    if has_key(s:voom_bodies, bnr)
        let [body, tree, inBody] = [bnr, s:voom_bodies[bnr].tree, 1]
    elseif has_key(s:voom_trees, bnr)
        let [body, tree, inBody] = [s:voom_trees[bnr], bnr, 0]
    else
        call voom#ErrorMsg("VOoM: current buffer is not a VOoM buffer")
        return
    endif

    if inBody
        if voom#ToTree(tree)!=0 | return | endif
    endif

    " current window width (w) and height (h)
    let [winw, winh] = [winwidth(0), winheight(0)]
    " maximum possible w and h (-2 for statusline and tabline)
    let [maxw, maxh] = [&columns, &lines-&cmdheight-2]
    " minimize w, h, or both
    if winw > 1 && winh > 1
        let w:voom_winsave = winsaveview()
        if winw < maxw
            let w:voom_w = winw
            vertical resize 1
        endif
        if winh < maxh
            let w:voom_h = winh
            resize 1
        endif
    " restore w, h, or both
    else
        if winw <= 1
            let w = exists('w:voom_w') ? w:voom_w : g:voom_tree_width
            exe 'vertical resize '.w
        endif
        if winh <= 1
            let h = exists('w:voom_h') ? w:voom_h : g:voom_tree_height
            exe 'resize '.h
        endif
        if exists('w:voom_winsave')
            call winrestview(w:voom_winsave)
        endif
    endif

    if inBody | call voom#ToBody(body) | endif
endfunc


func! voom#Voominfo(qargs) "{{{2
    let bnr = bufnr('')
    if has_key(s:voom_trees, bnr)
        let [body, tree] = [s:voom_trees[bnr], bnr]
    elseif has_key(s:voom_bodies, bnr)
        let [body, tree] = [bnr, s:voom_bodies[bnr].tree]
    else
        let [body, tree] = [bnr, 0]
    endif
    let l:vimvars = ''
    if a:qargs==#'all'
        for var in ['s:script_path', 's:script_dir', 's:voom_dir', 'g:voom_did_load_plugin', 's:voom_did_init', 's:voom_logbnr', 's:verify', 'g:voom_verify_oop', 's:voom_trees', 's:voom_bodies']
            let l:vimvars = l:vimvars . printf("%-13s = %s\n", var, string({var}))
        endfor
    endif
    python _VOoM.voom_Voominfo()
endfunc


func! voom#ReloadAllPre() "{{{2
" Helper for reloading the entire plugin and all modes.
" Wipe out all Tree buffers and PyLog buffer. Delete Python voom modules.
    call voom#DeleteOutlines()
    if s:voom_logbnr && bufexists(s:voom_logbnr)
        exe 'bwipeout '.s:voom_logbnr
    endif
python << EOF
sys.exc_clear()
del sys.modules['voom_vim']
for k in sys.modules.keys():
    if k.startswith('voom_mode_'):
        del sys.modules[k]
del k
EOF
    unlet s:voom_did_init
endfunc


"--- for external scripts --- {{{2

func! voom#GetVar(var) "{{{2
    return {a:var}
endfunc


func! voom#GetBodiesTrees() "{{{2
    return [s:voom_bodies, s:voom_trees]
endfunc


func! voom#GetTypeBodyTree(...) "{{{2
    let bnr = bufnr('')
    if has_key(s:voom_trees, bnr)
        let [bufType, body, tree] = ['Tree', s:voom_trees[bnr], bnr]
        if voom#BufNotLoaded(body) | return ['Tree',-1,-1] | endif
    elseif has_key(s:voom_bodies, bnr)
        let [bufType, body, tree] = ['Body', bnr, s:voom_bodies[bnr].tree]
        if voom#BodyUpdateTree() < 0 | return ['Body',-1,-1] | endif
    else
        if !(a:0 && a:1)
            call voom#ErrorMsg("VOoM: current buffer is not a VOoM buffer")
        endif
        return ['None',0,0]
    endif
    return [bufType, body, tree]
" Return ['Body'/'Tree', body, tree] for the current buffer.
" Return ['None',0,0] if current buffer is neither Body nor Tree and print
"   error message. To supress the error message: voom#GetTypeBodyTree(1)
" Return ['Body'/'Tree',-1,-1] if outline is not available.
" Update outline if needed if the current buffer is Body.
endfunc


func! voom#GetModeBodyTree(bnr) "{{{2
    if has_key(s:voom_trees, a:bnr)
        let [body, tree] = [s:voom_trees[a:bnr], a:bnr]
    elseif has_key(s:voom_bodies, a:bnr)
        let [body, tree] = [a:bnr, s:voom_bodies[a:bnr].tree]
    else
        return ['',-1,0,0]
    endif
    return [s:voom_bodies[body].mmode, s:voom_bodies[body].MTYPE, body, tree]
" Return [markup mode, MTYPE, body, tree] for buffer number bnr.
" Return ['',-1,0,0] if the buffer is not a VOoM buffer.
endfunc


"---Windows Navigation and Creation-----------{{{1
" These deal only with the current tab page.

func! voom#ToTreeOrBodyWin() "{{{2
" If in Tree window, move to Body window.
" If in Body window, move to Tree window.
" If possible, use previous window.
    let bnr = bufnr('')
    " current buffer is Tree
    if has_key(s:voom_trees, bnr)
        let target = s:voom_trees[bnr]
    " current buffer is Body
    else
        " This happens after Tree is wiped out.
        if !has_key(s:voom_bodies, bnr)
            call voom#BodyUnMap()
            return
        endif
        let target = s:voom_bodies[bnr].tree
    endif
    " Try previous window. It's the most common case.
    let wnr = winnr('#')
    if winbufnr(wnr)==target
        exe wnr.'wincmd w'
        return
    endif
    " Use any other window.
    if bufwinnr(target) > 0
        exe bufwinnr(target).'wincmd w'
        return
    endif
endfunc


func! voom#ToTreeWin() "{{{2
" Move to window or create a new one where a Tree will be loaded.
    " Already in a Tree buffer.
    if has_key(s:voom_trees, bufnr('')) | return | endif
    " Use previous window if it shows Tree.
    let wnr = winnr('#')
    if has_key(s:voom_trees, winbufnr(wnr))
        exe wnr.'wincmd w'
        call voom#SplitIfUnique()
        return
    endif
    " Use any window with a Tree buffer.
    for bnr in tabpagebuflist()
        if has_key(s:voom_trees, bnr)
            exe bufwinnr(bnr).'wincmd w'
            call voom#SplitIfUnique()
            return
        endif
    endfor
    " Create new window.
    if g:voom_tree_placement==#'top'
        exe 'leftabove '.g:voom_tree_height.'split'
    elseif g:voom_tree_placement==#'bottom'
        exe 'rightbelow '.g:voom_tree_height.'split'
    elseif g:voom_tree_placement==#'left'
        exe 'leftabove '.g:voom_tree_width.'vsplit'
    elseif g:voom_tree_placement==#'right'
        exe 'rightbelow '.g:voom_tree_width.'vsplit'
    endif
endfunc


func! voom#SplitIfUnique() "{{{2
" Split current window if current buffer is not displayed in any other window
" in current tabpage.
    let bnr = bufnr('')
    let wnr = winnr()
    for i in range(1,winnr('$'))
        if winbufnr(i)==bnr && i!=wnr
            return
        endif
    endfor
    if winheight(0) * 2 >= winwidth(0)
        leftabove split
    else
        leftabove vsplit
    endif
endfunc


func! voom#ToTree(tree) abort "{{{2
" Move cursor to window with Tree buffer tree.
" If there is no such window, load buffer in a new window.
    " Already there.
    if bufnr('')==a:tree | return | endif
    " Try previous window.
    let wnr = winnr('#')
    if winbufnr(wnr)==a:tree
        exe wnr.'wincmd w'
        return
    endif
    " There is window with buffer a:tree.
    if bufwinnr(a:tree) > 0
        exe bufwinnr(a:tree).'wincmd w'
        return
    endif
    " Bail out if Tree is unloaded or doesn't exist.
    " Because of au, this should never happen.
    if !bufloaded(a:tree)
        let body = s:voom_trees[a:tree]
        call voom#UnVoom(body,a:tree)
        echoerr "VOoM: Tree buffer" a:tree "is not loaded or does not exist. Cleanup has been performed."
        return -1
    endif
    " Load Tree in appropriate window.
    call voom#ToTreeWin()
    silent exe 'b '.a:tree
    " window-local options will be set on BufEnter
    return 1
endfunc


func! voom#ToBodyWin() "{{{2
" Split current Tree window to create window where Body will be loaded
    if g:voom_tree_placement==#'top'
        exe 'leftabove '.g:voom_tree_height.'split'
        wincmd p
    elseif g:voom_tree_placement==#'bottom'
        exe 'rightbelow '.g:voom_tree_height.'split'
        wincmd p
    elseif g:voom_tree_placement==#'left'
        exe 'leftabove '.g:voom_tree_width.'vsplit'
        wincmd p
    elseif g:voom_tree_placement==#'right'
        exe 'rightbelow '.g:voom_tree_width.'vsplit'
        wincmd p
    endif
endfunc


func! voom#ToBody(body) abort "{{{2
" Move to window with Body a:body or load it in a new window.
    " Already there.
    if bufnr('')==a:body | return | endif
    " Try previous window.
    let wnr = winnr('#')
    if winbufnr(wnr)==a:body
        exe wnr.'wincmd w'
        return
    endif
    " There is a window with buffer a:body .
    if bufwinnr(a:body) > 0
        exe bufwinnr(a:body).'wincmd w'
        return
    endif
    if !bufloaded(a:body)
        " Body is unloaded. Load it and force outline update.
        if bufexists(a:body)
            call voom#ToBodyWin()
            exe 'b '.a:body
            call voom#BodyUpdateTree()
            call voom#WarningMsg('VOoM: loaded Body buffer and updated outline')
        " Body doesn't exist. Bail out.
        else
            let tree = s:voom_bodies[a:body].tree
            if !has_key(s:voom_trees, tree) || s:voom_trees[tree]!=a:body
                echoerr "VOoM: INTERNAL ERROR"
                return -1
            endif
            call voom#UnVoom(a:body,tree)
            call voom#ErrorMsg("VOoM: Body ".a:body." does not exist. Cleanup has been performed.")
        endif
        return -1
    endif
    " Create new window and load there.
    call voom#ToBodyWin()
    exe 'b '.a:body
    return 1
endfunc


func! voom#ToLogWin() "{{{2
" Create new window where PyLog will be loaded.
    if g:voom_log_placement==#'top'
        exe 'topleft '.g:voom_log_height.'split'
    elseif g:voom_log_placement==#'bottom'
        exe 'botright '.g:voom_log_height.'split'
    elseif g:voom_log_placement==#'left'
        exe 'topleft '.g:voom_log_width.'vsplit'
    elseif g:voom_log_placement==#'right'
        exe 'botright '.g:voom_log_width.'vsplit'
    endif
endfunc


"---TREE BUFFERS------------------------------{{{1

func! voom#TreeCreate(body, blnr) "{{{2
" Create new Tree buffer in the current window for Body body, Body line blnr.
    let b_name = fnamemodify(bufname(a:body),":t")
    if b_name=='' | let b_name='NoName' | endif
    silent exe 'edit '.fnameescape(b_name).'_VOOM'.a:body
    let tree = bufnr('')

    """ Finish initializing VOoM data for this Body.
    let s:voom_bodies[a:body].tree = tree
    let s:voom_trees[tree] = a:body
    let s:voom_bodies[a:body].tick_ = 0
    python _VOoM.VOOMS[int(vim.eval('a:body'))].tree = int(vim.eval('l:tree'))
    python _VOoM.VOOMS[int(vim.eval('a:body'))].Tree = vim.current.buffer

    call voom#TreeConfig()
    let l:blnShow = -1
    """ Create outline and draw Tree lines.
    let lz_ = &lz | set lz
    setl ma
    let ul_ = &l:ul | setl ul=-1
    try
        let l:ok = 0
        keepj python _VOoM.updateTree(int(vim.eval('a:body')), int(vim.eval('l:tree')))
        " Draw = mark. Create folding from o marks.
        " This must be done afer creating outline.
        " this assigns s:voom_bodies[body].snLn
        if l:ok
            python _VOoM.voom_TreeCreate()
            let snLn = s:voom_bodies[a:body].snLn
            " Initial draw puts = on first line.
            if snLn > 1
                keepj call setline(snLn, '='.getline(snLn)[1:])
                keepj call setline(1, ' '.getline(1)[1:])
            endif
            let s:voom_bodies[a:body].tick_ = s:voom_bodies[a:body].tick
        endif
    finally
        let &l:ul = ul_
        setl noma
        let &lz=lz_
    endtry
    call voom#TreeConfigFt(a:body)

    """ Position cursor on snLn line. ../doc/voom.txt#id_20110125210844
    keepj normal! gg
    if snLn > 1
        exe "normal! ".snLn."G0f|m'"
        call voom#TreeZV()
        if line('w0')!=1 && line('w$')!=line('$')
            normal! zz
        endif
    endif

    "--- the end if markup mode ---
    " blnShow is set by voom_TreeCreate() when there is Body headline marked with =
    if l:blnShow > 0
        " go to Body
        let wnr_ = winnr()
        if voom#ToBody(a:body) < 0 | return | endif
        " show fold at l:blnShow
        exe 'keepj normal! '.l:blnShow.'G'
        if &fdm==#'marker'
            normal! zMzvzt
        else
            normal! zvzt
        endif
        " go back to Tree
        let wnr_ = winnr('#')
        if winbufnr(wnr_)==tree
            exe wnr_.'wincmd w'
        else
            exe bufwinnr(tree).'wincmd w'
        endif
    endif
endfunc


func! voom#TreeConfig() "{{{2
" Configure the current buffer as a Tree buffer.
    augroup VoomTree
        au! * <buffer>
        au BufEnter  <buffer> call voom#TreeBufEnter()
        "au BufUnload <buffer> call voom#TreeBufUnload()
        au BufUnload <buffer> nested call voom#TreeBufUnload()
    augroup END
    call voom#TreeMap()
    call voom#TreeConfigWin()
    " local to buffer, may be changed by the user
    setl bufhidden=wipe
    " Options local to buffer. DO NOT CHANGE.
    setl nobuflisted buftype=nofile noswapfile
    setl noro ma ff=unix noma
endfunc


func! voom#TreeConfigWin() "{{{2
" Tree window-local options.
    setl foldenable
    setl foldtext=getline(v:foldstart).'\ \ \ /'.(v:foldend-v:foldstart)
    setl foldmethod=expr
    setl foldexpr=voom#TreeFoldexpr(v:lnum)
    setl cul nocuc nowrap nolist
    "setl winfixheight
    setl winfixwidth
    let w:voom_tree = 'VOoM'
endfunc


func! voom#TreeConfigFt(body) "{{{2
" This is to allow customization via ftplugin.
    setl ft=voomtree
    if exists('b:current_syntax')
        return
    endif
" Tree buffer default syntax highlighting. 'set ft=...' removes syntax hi.
    " first line
    syn match Title /\%1l.*/

    let FT = getbufvar(a:body, "&ft")
    if FT==#'text'
        " organizer nodes: /headline/
        syn match Comment '^[^|]\+|\zs[/#].*' contains=Todo
        syn keyword Todo TODO XXX FIXME
    elseif FT==#'python'
        syn match Statement /^[^|]\+|\zs\%(def\s\|class\s\)/
        syn match Define /^[^|]\+|\zs@/
        syn match Comment /^[^|]\+|\zs#.*/ contains=Todo
        syn keyword Todo contained TODO XXX FIXME
    elseif FT==#'vim'
        syn match Statement /^[^|]\+|\zs\%(fu\%[nction]\>\|def\s\|class\s\)/
        syn match Comment /^[^|]\+|\zs\%("\|#\).*/ contains=Todo
        syn keyword Todo contained TODO XXX FIXME
    elseif FT==#'html' || FT==#'xml'
        syn match Comment /^[^|]\+|\zs<!.*/ contains=Todo
        syn keyword Todo contained TODO XXX FIXME
    elseif FT==#'tex'
        syn match Comment /^[^|]\+|\zs%.*/ contains=Todo
        syn keyword Todo contained TODO XXX FIXME
    else
        """ organizer nodes: /headline/
        "syn match Directory @^[^|]\+|\zs/.*@ contains=Todo
        """ line comment chars: "  #  //  /*  %  ;  <!--
        "syn match Comment @^[^|]\+|\zs\%("\|#\|//\|/\*\|%\|<!--\).*@ contains=Todo
        """ line comment chars with / (organizer nodes) instead of // and /*
        syn match Comment '^[^|]\+|\zs["#/%;].*' contains=Todo
        syn keyword Todo TODO XXX FIXME
    endif

    syn match WarningMsg /^[^|]\+|\zs!\+/

    """ selected node hi, useless with folding
    "syn match Pmenu /^=.\{-}|\zs.*/
    "syn match Pmenu /^=.\{-}\ze|/
endfunc


func! voom#TreeBufEnter() "{{{2
" Tree BufEnter au.
" Update outline if Body changed since last update. Redraw Tree if needed.
    let tree = bufnr('')
    let body = s:voom_trees[tree]
    if !exists('w:voom_tree') | call voom#TreeConfigWin() | endif
    if s:voom_bodies[body].tick_==s:voom_bodies[body].tick || &ma || voom#BufNotLoaded(body)
        return
    endif
    let snLn_ = s:voom_bodies[body].snLn
    setl ma
    let ul_ = &l:ul | setl ul=-1
    try
        let l:ok = 0
        keepj python _VOoM.updateTree(int(vim.eval('l:body')), int(vim.eval('l:tree')))
        if l:ok
            let s:voom_bodies[body].tick_ = s:voom_bodies[body].tick
        endif
    finally
        let &l:ul = ul_
        setl noma
    endtry
    " The = mark is placed by updateTree()
    " When nodes are deleted by editing Body, snLn can get > last Tree lnum,
    " updateTree() will set snLn to the last line lnum.
    if snLn_ != s:voom_bodies[body].snLn
        keepj normal! Gzv
    endif
endfunc


func! voom#TreeBufUnload() "{{{2
" Tree BufUnload au. Wipe out Tree and cleanup.
    let tree = expand("<abuf>")
    if !exists("s:voom_trees") || !has_key(s:voom_trees, tree)
        echoerr "VOoM: INTERNAL ERROR"
        return
    endif
    let body = s:voom_trees[tree]
    "echom bufexists(tree) --always 0
    "exe 'noautocmd bwipeout '.tree
    exe 'au! VoomTree * <buffer='.tree.'>'
    exe 'bwipeout '.tree
    call voom#UnVoom(body,tree)
endfunc


func! voom#TreeFoldexpr(lnum) "{{{2
    let ind = stridx(getline(a:lnum),'|') / 2
    let indn = stridx(getline(a:lnum+1),'|') / 2
    return indn>ind ? '>'.ind : ind-1
    "return indn>ind ? '>'.ind : indn<ind ? '<'.indn : ind-1
    "return indn==ind ? ind-1 : indn>ind ? '>'.ind : '<'.indn
endfunc


func! voom#TreeMap() "{{{2=
" Tree buffer local mappings and commands.
    let cpo_ = &cpo | set cpo&vim

    """ disable keys that change text {{{
" disable common text change commands
nnoremap <buffer><silent> o <Esc>
noremap <buffer><silent> O <Esc>
noremap <buffer><silent> i <Esc>
noremap <buffer><silent> I <Esc>
noremap <buffer><silent> a <Esc>
noremap <buffer><silent> A <Esc>
noremap <buffer><silent> s <Esc>
noremap <buffer><silent> S <Esc>
noremap <buffer><silent> r <Esc>
noremap <buffer><silent> R <Esc>
noremap <buffer><silent> x <Esc>
noremap <buffer><silent> X <Esc>
noremap <buffer><silent> D <Esc>
noremap <buffer><silent> J <Esc>
noremap <buffer><silent> c <Esc>
noremap <buffer><silent> C <Esc>
noremap <buffer><silent> P <Esc>
noremap <buffer><silent> . <Esc>
noremap <buffer><silent> = <Esc>
noremap <buffer><silent> ~ <Esc>
noremap <buffer><silent> <Ins> <Esc>
noremap <buffer><silent> <Del> <Esc>
noremap <buffer><silent> <C-x> <Esc>
noremap <buffer><silent> p <Esc>
noremap <buffer><silent> d <Esc>
noremap <buffer><silent> < <Esc>
noremap <buffer><silent> > <Esc>
noremap <buffer><silent> ^ <Esc>
noremap <buffer><silent> _ <Esc>

" disable undo (also case conversion)
noremap <buffer><silent> u <Esc>
noremap <buffer><silent> U <Esc>
noremap <buffer><silent> <C-r> <Esc>

" disable creation/deletion of folds
noremap <buffer><silent> zf <Esc>
noremap <buffer><silent> zF <Esc>
noremap <buffer><silent> zd <Esc>
noremap <buffer><silent> zD <Esc>
noremap <buffer><silent> zE <Esc>
    """ }}}

    """ node navigation and selection {{{
"--- the following select node -----------
exe "nnoremap <buffer><silent> ".g:voom_return_key." :<C-u>call voom#TreeSelect(0)<CR>"
exe "vnoremap <buffer><silent> ".g:voom_return_key." <Esc>:<C-u>call voom#TreeSelect(0)<CR>"
"exe "vnoremap <buffer><silent> ".g:voom_return_key." <Nop>"
exe "nnoremap <buffer><silent> ".g:voom_tab_key." :<C-u>call voom#ToTreeOrBodyWin()<CR>"
exe "vnoremap <buffer><silent> ".g:voom_tab_key." <Esc>:<C-u>call voom#ToTreeOrBodyWin()<CR>"
"exe "vnoremap <buffer><silent> ".g:voom_tab_key." <Nop>"

" MOUSE: Left mouse release. Triggered when resizing window with the mouse.
nnoremap <buffer><silent> <LeftRelease> <LeftRelease>:<C-u>call voom#TreeMouseClick()<CR>
inoremap <buffer><silent> <LeftRelease> <LeftRelease><Esc>
" disable Left mouse double click to avoid entering Visual mode
nnoremap <buffer><silent> <2-LeftMouse> <Nop>

nnoremap <buffer><silent> <Down> <Down>:<C-u>call voom#TreeSelect(1)<CR>
nnoremap <buffer><silent>   <Up>   <Up>:<C-u>call voom#TreeSelect(1)<CR>

nnoremap <buffer><silent> <Left>  :<C-u>call voom#TreeLeft()<CR>
nnoremap <buffer><silent> <Right> :<C-u>call voom#TreeRight()<CR>

nnoremap <buffer><silent> x :<C-u>call voom#TreeToMark(0)<CR>
nnoremap <buffer><silent> X :<C-u>call voom#TreeToMark(1)<CR>

"--- the following don't select node -----------

nnoremap <buffer><silent> <Space> :<C-u>call voom#TreeToggleFold()<CR>
vnoremap <buffer><silent> <Space> <Esc>
"vnoremap <buffer><silent> <Space> <Esc>:<C-u>call voom#TreeToggleFold()<CR>

" put cursor on the selected node
nnoremap <buffer><silent> = :<C-u>call voom#TreeToSelected()<CR>
" put cursor on the node marked with '=', if any
nnoremap <buffer><silent> + :<C-u>call voom#TreeToStartupNode()<CR>

" go up to the parent node
nnoremap <buffer><silent> P :<C-u>call voom#Tree_Pco('P','n')<CR>
" go up to the parent node and contract it
nnoremap <buffer><silent> c :<C-u>call voom#Tree_Pco('c','n')<CR>
" go down to direct child node
nnoremap <buffer><silent> o :<C-u>call voom#Tree_Pco('o','n')<CR>

" contract all siblings of current node
nnoremap <buffer><silent> C :<C-u>call voom#Tree_CO('zC','n')<CR>
" contract all nodes in Visual selection
vnoremap <buffer><silent> C :<C-u>call voom#Tree_CO('zC','v')<CR>
" expand all siblings of current node
nnoremap <buffer><silent> O :<C-u>call voom#Tree_CO('zO','n')<CR>
" expand all nodes in Visual selection
vnoremap <buffer><silent> O :<C-u>call voom#Tree_CO('zO','v')<CR>

" go up to the previous sibling
nnoremap <buffer><silent> K :<C-u>call voom#Tree_KJUD('K','n')<CR>
vnoremap <buffer><silent> K :<C-u>call voom#Tree_KJUD('K','v')<CR>
" go down to the next sibling
nnoremap <buffer><silent> J :<C-u>call voom#Tree_KJUD('J','n')<CR>
vnoremap <buffer><silent> J :<C-u>call voom#Tree_KJUD('J','v')<CR>
" go up to the uppermost sibling
nnoremap <buffer><silent> U :<C-u>call voom#Tree_KJUD('U','n')<CR>
vnoremap <buffer><silent> U :<C-u>call voom#Tree_KJUD('U','v')<CR>
" go down to the downmost sibling
nnoremap <buffer><silent> D :<C-u>call voom#Tree_KJUD('D','n')<CR>
vnoremap <buffer><silent> D :<C-u>call voom#Tree_KJUD('D','v')<CR>
    """ }}}

    """ outline operations {{{
" edit Body text
nnoremap <buffer><silent> i :<C-u>call voom#OopEdit('i')<CR>
nnoremap <buffer><silent> I :<C-u>call voom#OopEdit('I')<CR>

" insert new node
nnoremap <buffer><silent> <LocalLeader>a :<C-u>call voom#OopInsert('')<CR>
nnoremap <buffer><silent>             aa :<C-u>call voom#OopInsert('')<CR>
nnoremap <buffer><silent> <LocalLeader>A :<C-u>call voom#OopInsert('as_child')<CR>
nnoremap <buffer><silent>             AA :<C-u>call voom#OopInsert('as_child')<CR>

" move
nnoremap <buffer><silent> <LocalLeader>u :<C-u>call voom#Oop('up', 'n')<CR>
nnoremap <buffer><silent>         <C-Up> :<C-u>call voom#Oop('up', 'n')<CR>
nnoremap <buffer><silent>             ^^ :<C-u>call voom#Oop('up', 'n')<CR>
vnoremap <buffer><silent> <LocalLeader>u :<C-u>call voom#Oop('up', 'v')<CR>
vnoremap <buffer><silent>         <C-Up> :<C-u>call voom#Oop('up', 'v')<CR>
vnoremap <buffer><silent>             ^^ :<C-u>call voom#Oop('up', 'v')<CR>

nnoremap <buffer><silent> <LocalLeader>d :<C-u>call voom#Oop('down', 'n')<CR>
nnoremap <buffer><silent>       <C-Down> :<C-u>call voom#Oop('down', 'n')<CR>
nnoremap <buffer><silent>             __ :<C-u>call voom#Oop('down', 'n')<CR>
vnoremap <buffer><silent> <LocalLeader>d :<C-u>call voom#Oop('down', 'v')<CR>
vnoremap <buffer><silent>       <C-Down> :<C-u>call voom#Oop('down', 'v')<CR>
vnoremap <buffer><silent>             __ :<C-u>call voom#Oop('down', 'v')<CR>

nnoremap <buffer><silent> <LocalLeader>l :<C-u>call voom#Oop('left', 'n')<CR>
nnoremap <buffer><silent>       <C-Left> :<C-u>call voom#Oop('left', 'n')<CR>
nnoremap <buffer><silent>             << :<C-u>call voom#Oop('left', 'n')<CR>
vnoremap <buffer><silent> <LocalLeader>l :<C-u>call voom#Oop('left', 'v')<CR>
vnoremap <buffer><silent>       <C-Left> :<C-u>call voom#Oop('left', 'v')<CR>
vnoremap <buffer><silent>             << :<C-u>call voom#Oop('left', 'v')<CR>

nnoremap <buffer><silent> <LocalLeader>r :<C-u>call voom#Oop('right', 'n')<CR>
nnoremap <buffer><silent>      <C-Right> :<C-u>call voom#Oop('right', 'n')<CR>
nnoremap <buffer><silent>             >> :<C-u>call voom#Oop('right', 'n')<CR>
vnoremap <buffer><silent> <LocalLeader>r :<C-u>call voom#Oop('right', 'v')<CR>
vnoremap <buffer><silent>      <C-Right> :<C-u>call voom#Oop('right', 'v')<CR>
vnoremap <buffer><silent>             >> :<C-u>call voom#Oop('right', 'v')<CR>

" cut/copy/paste
nnoremap <buffer><silent> dd :<C-u>call voom#Oop('cut', 'n')<CR>
vnoremap <buffer><silent> dd :<C-u>call voom#Oop('cut', 'v')<CR>

nnoremap <buffer><silent> yy :<C-u>call voom#Oop('copy', 'n')<CR>
vnoremap <buffer><silent> yy :<C-u>call voom#Oop('copy', 'v')<CR>

nnoremap <buffer><silent> pp :<C-u>call voom#OopPaste()<CR>

" mark/unmark
nnoremap <buffer><silent> <LocalLeader>m :<C-u>call voom#OopMark('mark', 'n')<CR>
vnoremap <buffer><silent> <LocalLeader>m :<C-u>call voom#OopMark('mark', 'v')<CR>

nnoremap <buffer><silent> <LocalLeader>M :<C-u>call voom#OopMark('unmark', 'n')<CR>
vnoremap <buffer><silent> <LocalLeader>M :<C-u>call voom#OopMark('unmark', 'v')<CR>

" mark node as selected node
nnoremap <buffer><silent> <LocalLeader>= :<C-u>call voom#OopMarkStartup()<CR>

" select Body region
nnoremap <buffer><silent> R :<C-u>call voom#OopSelectBodyRange('n')<CR>
vnoremap <buffer><silent> R :<C-u>call voom#OopSelectBodyRange('v')<CR>
    """ }}}

    """ save/Restore Tree folding {{{
nnoremap <buffer><silent> <LocalLeader>fs  :<C-u>call voom#OopFolding(line('.'),line('.'), 'save')<CR>
nnoremap <buffer><silent> <LocalLeader>fr  :<C-u>call voom#OopFolding(line('.'),line('.'), 'restore')<CR>
nnoremap <buffer><silent> <LocalLeader>fas :<C-u>call voom#OopFolding(1,line('$'), 'save')<CR>
nnoremap <buffer><silent> <LocalLeader>far :<C-u>call voom#OopFolding(1,line('$'), 'restore')<CR>
    """ }}}

    """ various commands {{{

" echo Tree headline
nnoremap <buffer><silent> s :<C-u>echo getline('.')[(stridx(getline('.'),'<Bar>')+1):]<CR>
" echo UNL
nnoremap <buffer><silent> S :<C-u>call voom#EchoUNL()<CR>
"nnoremap <buffer><silent> <F1> :<C-u>call voom#Help()<CR>
nnoremap <buffer><silent> <LocalLeader>e :<C-u>call voom#Exec('')<CR>
" delete outline
nnoremap <buffer><silent> q :<C-u>call voom#DeleteOutline()<CR>

    """ }}}

    let &cpo = cpo_
    return
    " Use noremap to disable keys. This must be done first.
    " Use nnoremap and vnoremap in VOoM mappings, don't use noremap.
    " It's better to disable keys by mapping to <Esc> instead of <Nop>:
    "       ../doc/voom.txt#id_20110121201243
    "
    " Do not map <LeftMouse>. Not triggered on first click in the buffer.
    " Triggered on first click in another buffer. Vim probably doesn't know
    " what buffer it is until after the click.
    "
    " Can't use Ctrl: <C-i> is Tab; <C-u>, <C-d> are page up/down.
    " Use <LocalLeader> instead of Ctrl.
    "
    " Still up for grabs: <C-x> <C-j> <C-k> <C-p> <C-n> [ ] { } ~ - !
endfunc


"---Outline Navigation---{{{2
" To select node from Tree, call voom#TreeSelect().  ALWAYS return immediately
" after calling voom#TreeSelect() in case Body checks fail.
"
" To position cursor on | in Tree (not needed if voom#TreeSelect() is called):
"   call cursor(0,stridx(getline('.'),'|')+1)
"       or
"   normal! 0f|

" Notes: ../doc/voom.txt#id_20110116213809

" zt is affected by 'scrolloff' (voom#TreeSelect)


func! voom#TreeSelect(stayInTree) "{{{3
" Select node corresponding to the current Tree line.
" Show correspoding Body's node.
" Leave cursor in Body if current line was in the selected node and !stayInTree.
    let tree = bufnr('')
    let body = s:voom_trees[tree]
    if voom#BufNotLoaded(body) | return | endif
    let lnum = line('.')

    let snLn = s:voom_bodies[body].snLn

    let lz_ = &lz | set lz
    call voom#TreeZV()
    call cursor(0,stridx(getline('.'),'|')+1)

    " compute l:blnum1, l:blnum2 -- start and end of the selected Body node
    " set VO.snLn before going to Body in case outline update is forced
    python _VOoM.voom_TreeSelect()

    """ Mark new line with =. Remove old = mark.
    if lnum != snLn
        setl ma | let ul_ = &l:ul | setl ul=-1
        keepj call setline(lnum, '='.getline(lnum)[1:])
        keepj call setline(snLn, ' '.getline(snLn)[1:])
        setl noma | let &l:ul = ul_
        let s:voom_bodies[body].snLn = lnum
    endif

    """ Go to Body, show selected node, come back or stay in Body.
    if voom#ToBody(body) < 0 | let &lz=lz_ | return | endif
    if voom#BodyCheckTicks(body) < 0 | let &lz=lz_ | return | endif
    let blnum = line('.')
    let gotNewNode = (blnum < l:blnum1) || (blnum > l:blnum2)
    if gotNewNode
        exe 'keepj normal! '.l:blnum1.'G'
        if &fdm ==# 'marker'
            normal! zMzvzt
        else
            normal! zvzt
        endif
    endif

    """ Go back to Tree after showing new node in Body.
    """ Stay in Body if Body's current line was in the selected node.
    if gotNewNode || a:stayInTree
        let wnr_ = winnr('#')
        if winbufnr(wnr_)==tree
            exe wnr_.'wincmd w'
        else
            exe bufwinnr(tree).'wincmd w'
        endif
    endif

    let &lz=lz_
endfunc


func! voom#TreeZV() "{{{3
" Make current line visible. Return -1 if it was hidden. Like zv, but when
" current line starts a fold, do not open that fold.
    let lnum = line('.')
    let fc = foldclosed(lnum)
    if fc < lnum && fc > 0
        normal! zo
        let fc = foldclosed(lnum)
        while fc < lnum && fc > 0
            normal! zo
            let fc = foldclosed(lnum)
        endwhile
        return -1
    endif
endfunc


func! voom#TreeToLine(lnum) "{{{3
" Put cursor on line lnum, e.g., snLn.
    if (line('w0') < a:lnum) && (a:lnum > 'w$')
        let offscreen = 0
    else
        let offscreen = 1
    endif
    exe 'keepj normal! '.a:lnum.'G'
    call voom#TreeZV()
    call cursor(0,stridx(getline('.'),'|')+1)
    if offscreen==1
        normal! zz
    endif
endfunc


func! voom#TreeToggleFold() "{{{3
" Toggle fold at cursor: expand/contract node.
    let lnum=line('.')
    let ln_status = voom#FoldStatus(lnum)
    if ln_status==#'folded'
        normal! zo
    elseif ln_status==#'notfolded'
        if stridx(getline(lnum),'|') < stridx(getline(lnum+1),'|')
            normal! zc
        endif
    elseif ln_status==#'hidden'
        call voom#TreeZV()
    endif
endfunc


func! voom#TreeMouseClick() "{{{3
" Select node. Toggle fold if click is outside of headline text.
    if !has_key(s:voom_trees, bufnr(''))
        call voom#ErrorMsg('VOoM: <LeftRelease> in wrong buffer')
        return
    endif
    if virtcol('.')+1 >= virtcol('$') || col('.')-1 < stridx(getline('.'),'|')
        call voom#TreeToggleFold()
    endif
    call voom#TreeSelect(1)
endfunc


func! voom#TreeLeft() "{{{3
" Go to parent node, but first contract current node if it's expanded.
    if voom#TreeZV() < 0
        call voom#TreeSelect(1)
        return
    endif
    let lnum = line('.')
    if lnum==1 | return | endif

    let ind = stridx(getline(lnum),'|')
    " next line has bigger indent and line is an opened fold -- close fold
    if stridx(getline(lnum+1),'|') > ind && foldclosed(lnum) < 0
        normal! zc
    " top level -- do not go anywhere
    elseif ind < 3
    " go to parent
    else
        call search('\m^[^|]\{0,'.(ind-2).'}|', 'bWe')
    endif
    call voom#TreeSelect(1)
endfunc


func! voom#TreeRight() "{{{3
" Go to first child of current node.
    if voom#TreeZV() < 0
        call voom#TreeSelect(1)
        return
    endif
    let lnum = line('.')
    if lnum==1 | return | endif

    " line is first line of a closed fold, does not necessarily have children
    if foldclosed(lnum)==lnum
        normal! zv
    " next line has bigger indent
    elseif stridx(getline(lnum),'|') < stridx(getline(lnum+1),'|')
        normal! j
    endif
    call voom#TreeSelect(1)
endfunc


func! voom#Tree_KJUD(action, mode) "{{{3
" Move cursor to a sibling node as specified by action: U D K J.
    if voom#TreeZV() < 0
        call cursor(0,stridx(getline('.'),'|')+1)
        return
    endif
    let lnum = line('.')
    if lnum==1 | return | endif
    if a:mode==#'v'
        let [ln1,ln2] = [line("'<"), line("'>")]
    else
        let [ln1,ln2] = [lnum, lnum]
    endif

    let vcount1 = v:count1
    if ln2 > ln1
        " put the cursor on the last _visible_ line of selection
        if a:action==#'D' || a:action==#'J'
            exe 'keepj normal! '.ln2.'Gkj'
        " put the cursor on the first line of selection, should be always visible
        elseif a:action==#'U' || a:action==#'K'
            exe 'keepj normal! '.ln1.'G'
        endif
    endif
    " node's level is indent of first |
    keepj normal! 0f|
    let ind = virtcol('.')-1
    let lnum = line('.')

    " go to the downmost sibling: down to next elder, up to sibling
    if a:action==#'D'
        call search('\m^[^|]\{0,'.(ind-2).'}|', 'We')
        if line('.') > lnum
            call search('\m^[^|]\{'.(ind).'}|', 'bWe')
        else
            keepj normal! G0f|
            call search('\m^[^|]\{'.(ind).'}|', 'bcWe')
        endif
    " go to the uppermost sibling: up to parent, down to sibling
    elseif a:action==#'U'
        call search('\m^[^|]\{0,'.(ind-2).'}|', 'bWe')
        if line('.') < lnum
            call search('\m^[^|]\{'.(ind).'}|', 'We')
        else
            keepj normal! gg
            call search('\m^[^|]\{'.(ind).'}|', 'We')
        endif
    " go down to the next sibling, stopline is next elder node
    elseif a:action==#'J'
        let stopline = search('\m^[^|]\{0,'.(ind-2).'}|', 'Wn')
        for i in range(vcount1)
            call search('\m^[^|]\{'.(ind).'}|', 'We', stopline)
        endfor
    " go up to the previous sibling, stopline is parent
    elseif a:action==#'K'
        let stopline = search('\m^[^|]\{0,'.(ind-2).'}|', 'bWn')
        for i in range(vcount1)
            call search('\m^[^|]\{'.(ind).'}|', 'bWe', stopline)
        endfor
    endif
    call voom#TreeZV()

    " restore and extend Visual selection
    if a:mode==#'v'
        let lnum = line(".")
        exe 'keepj normal! gv'.lnum.'G0f|'
    endif
endfunc


func! voom#Tree_Pco(action, mode) "{{{3
" action: P c o
    if voom#TreeZV() < 0
        call cursor(0,stridx(getline('.'),'|')+1)
        return
    endif
    let lnum = line('.')
    if lnum==1 | return | endif

    """ action 'P' or 'c': go up to parent, contract if 'c'
    if a:action==#'c' || a:action==#'P'
        keepj normal! 0f|
        let ind = virtcol('.')-1
        call search('\m^[^|]\{0,'.(ind-2).'}|', 'bWe')
        if a:action==#'c' && line('.') < lnum
            normal! zc
        endif
        return
    " action 'o': go to first child node, same as voom#TreeRight()
    elseif a:action==#'o'
        " line is first line of a closed fold, does not necessarily have children
        if foldclosed(lnum)==lnum
            normal! zv
        endif
        if stridx(getline(lnum),'|') < stridx(getline(lnum+1),'|')
            normal! j
        endif
        normal! 0f|
    endif
endfunc



func! voom#Tree_CO(action, mode) "{{{3
" action: zC zO
    if voom#TreeZV() < 0
        call cursor(0,stridx(getline('.'),'|')+1)
        return
    endif
    let lnum = line('.')
    if lnum==1 | return | endif

    """ do 'zC' or 'zO' for all siblings of current node
    let winsave_dict = winsaveview()
    if a:mode==#'n'
        keepj normal! 0f|
        let ind = virtcol('.')-1

        " go the uppermost sibling: up to parent, down to sibling
        call search('\m^[^|]\{0,'.(ind-2).'}|', 'bWe')
        if line('.') < lnum
            let lnUp = search('\m^[^|]\{'.(ind).'}|', 'We')
        else
            keepj normal! gg
            let lnUp = search('\m^[^|]\{'.(ind).'}|', 'We')
        endif
        exe 'keepj normal! '.lnum.'G0f|'

        " go to the last subnode of the downmost sibling: down to elder node, up
        call search('\m^[^|]\{0,'.(ind-2).'}|', 'We')
        if line('.') > lnum
            exe 'keepj normal! '.(line('.')-1).'G0f|'
        else
            keepj normal! G0f|
        endif

        try
            "exe 'keepj normal! V'.lnUp.'GzC'
            exe 'keepj normal! V'.lnUp.'G'.a:action
        catch /^Vim\%((\a\+)\)\=:E490/
        endtry

    """ do 'zC' or 'zO' for all nodes in Visual selection
    elseif a:mode==#'v'
        try
            "normal! gvzC
            exe 'normal! gv'.a:action
        catch /^Vim\%((\a\+)\)\=:E490/
        endtry
    endif

    exe 'keepj normal! '.lnum.'G0f|'
    call voom#TreeZV()
    call winrestview(winsave_dict)
endfunc



func! voom#TreeToSelected() "{{{3
" Put cursor on selected node, that is on SnLn line.
    let lnum = s:voom_bodies[s:voom_trees[bufnr('')]].snLn
    call voom#TreeToLine(lnum)
endfunc


func! voom#TreeToStartupNode() "{{{3
" Put cursor on startup node, if any: node marked with '=' in Body headline.
" Warn if there are several such nodes.
    let body = s:voom_trees[bufnr('')]
    if s:voom_bodies[body].MTYPE
        call voom#ErrorMsg('VOoM: startup nodes are not available in this markup mode')
        return
    endif
    " this creates l:lnums
    python _VOoM.voom_TreeToStartupNode()
    if len(l:lnums)==0
        call voom#WarningMsg("VOoM: no nodes marked with '='")
        return
    endif
    call voom#TreeToLine(l:lnums[-1])
    if len(l:lnums)>1
        call voom#WarningMsg("VOoM: multiple nodes marked with '=': ".join(l:lnums, ', '))
    endif
endfunc


func! voom#TreeToMark(back) "{{{3
" Go to next or previous marked node.
    if a:back==1
        normal! 0
        let found = search('\C\v^.x', 'bw')
    else
        let found = search('\C\v^.x', 'w')
    endif
    if found==0
        call voom#WarningMsg("VOoM: there are no marked nodes")
    else
        call voom#TreeSelect(1)
    endif
endfunc


"---Outline Operations---{{{2
" NOTES:
" getbufvar(body,'changedtick') returns '' if Vim version is < 7.3.105
"
" Operations other than Sort rely on verification and must call
" voom#OopFromBody() while Tree is &ma to suppress outline update on Tree
" BufEnter.
"
" Note that voom#OopFromBody() is often called from Python code.


func! voom#OopSelectBodyRange(mode) "{{{3
" Move to Body and select region corresponding to node(s) in the Tree.
    let tree = bufnr('')
    if voom#BufNotTree(tree) | return | endif
    let body = s:voom_trees[tree]
    if voom#BufNotLoaded(body) | return | endif
    let ln = line('.')
    if voom#FoldStatus(ln)==#'hidden'
        call voom#ErrorMsg("VOoM: current node is hidden in fold")
        return
    endif
    " normal mode: use current line
    if a:mode==#'n'
        let [ln1, ln2] = [ln, ln]
    " visual mode: use range
    elseif a:mode==#'v'
        let [ln1, ln2] = [line("'<"), line("'>")]
    endif

    if voom#ToBody(body) < 0 | return | endif
    if voom#BodyCheckTicks(body) < 0 | return | endif
    " compute bln1 and bln2
    python _VOoM.voom_OopSelectBodyRange()
    " this happens when ln2==1 and the first headline is top of buffer
    if l:bln2==0 | return | endif
    exe 'normal! '.bln1.'Gzv'.bln2.'GzvV'.bln1.'G'
    if line('w$') < bln2
        normal! zt
    endif
endfunc


func! voom#OopEdit(op) "{{{3
" Edit Body. Move cursor to Body on the node's first (i) or last (I) line.
    let tree = bufnr('')
    if voom#BufNotTree(tree) | return | endif
    let body = s:voom_trees[tree]
    if voom#BufNotLoaded(body) | return | endif
    let lnum = line('.')
    "if lnum==1 | return | endif
    if voom#FoldStatus(lnum)==#'hidden'
        call voom#ErrorMsg("VOoM: current node is hidden in fold")
        return
    endif
    let head = getline(lnum)[1+stridx(getline(lnum),'|') :]

    " compute l:bLnr -- Body lnum to which to jump
    python _VOoM.voom_OopEdit()

    let lz_ = &lz | set lz
    if voom#ToBody(body) < 0 | let &lz=lz_ | return | endif
    if voom#BodyCheckTicks(body) < 0 | let &lz=lz_ | return | endif

    " do zz only when target line is not in the window
    if l:bLnr < line('w0') || l:bLnr > line('w$')
        let do_zz = 1
    else
        let do_zz = 0
    endif
    exe 'keepj normal! '.l:bLnr.'Gzv^'
    if do_zz
        normal! zz
    endif
    if a:op==#'i'
        " put cursor on the headline text, then on the first word char
        call search('\V'.substitute(head,'\','\\\\','g'), 'c', line('.'))
        call search('\m\<', 'c', line('.'))
    endif
    let &lz=lz_
endfunc


func! voom#OopInsert(as_child) "{{{3
" Insert new node, headline text should be NewHeadline.
    let tree = bufnr('')
    if voom#BufNotTree(tree) | return | endif
    let body = s:voom_trees[tree]
    if voom#BufNotLoaded(body) | return | endif
    if voom#BufNotEditable(body) | return | endif
    let ln = line('.')
    let ln_status = voom#FoldStatus(ln)
    if ln_status==#'hidden'
        call voom#ErrorMsg("VOoM: current node is hidden in fold")
        return
    endif

    let lz_ = &lz | set lz
    " check ticks, getbufvar(body,'changedtick') is '' if Vim < 7.3.105
    if s:voom_bodies[body].tick_ != getbufvar(body,'changedtick')
        if voom#ToBody(body) < 0 | let &lz=lz_ | return | endif
        if voom#BodyCheckTicks(body) < 0 | let &lz=lz_ | return | endif
        call voom#OopFromBody(body,tree,-1)
    endif

    setl ma
    if a:as_child==#'as_child'
        keepj python _VOoM.voom_OopInsert(as_child=True)
    else
        keepj python _VOoM.voom_OopInsert(as_child=False)
    endif
    setl noma

    let snLn = s:voom_bodies[body].snLn
    exe "keepj normal! ".snLn."G0f|"
    call voom#TreeZV()

    if voom#ToBody(body) < 0 | let &lz=lz_ | return | endif
    exe "keepj normal! ".l:bLnum."Gzvz\<CR>"
    call search('\CNewHeadline', 'c', line('.'))
    let &lz=lz_
endfunc


func! voom#OopPaste() "{{{3
" Paste the content of the "+ register as an outline.
    let tree = bufnr('')
    if voom#BufNotTree(tree) | return | endif
    let body = s:voom_trees[tree]
    if voom#BufNotLoaded(body) | return | endif
    if voom#BufNotEditable(body) | return | endif
    let ln = line('.')
    let ln_status = voom#FoldStatus(ln)
    if ln_status==#'hidden'
        call voom#ErrorMsg("VOoM: current node is hidden in fold")
        return
    endif

    let lz_ = &lz | set lz
    if voom#ToBody(body) < 0 | let &lz=lz_ | return | endif
    if voom#BodyCheckTicks(body) < 0 | let &lz=lz_ | return | endif
    " default bnlShow -1 means pasting not possible
    let l:blnShow = -1

    call setbufvar(tree, '&ma', 1)
    keepj python _VOoM.voom_OopPaste()
    call setbufvar(tree, '&ma', 0)

    if l:blnShow > 0
        let s:voom_bodies[body].snLn = l:ln1
        if l:ln1==l:ln2
            call voom#OopShowTree(l:ln1, l:ln2, 'n')
        else
            call voom#OopShowTree(l:ln1, l:ln2, 'v')
        endif
    endif
    let &lz=lz_
    call voom#OopVerify(body, tree, 'paste')
endfunc


func! voom#OopMark(op, mode) "{{{3
" Mark or unmark current node or all nodes in selection
    " Checks and init vars. {{{
    let tree = bufnr('')
    if voom#BufNotTree(tree) | return | endif
    let body = s:voom_trees[tree]
    if s:voom_bodies[body].MTYPE
        call voom#ErrorMsg('VOoM: marked nodes are not available in this markup mode')
        return
    endif
    if voom#BufNotLoaded(body) | return | endif
    if voom#BufNotEditable(body) | return | endif
    let ln = line('.')
    if voom#FoldStatus(ln)==#'hidden'
        call voom#ErrorMsg("VOoM: current node is hidden in fold")
        return
    endif
    " normal mode: use current line
    if a:mode==#'n'
        let ln1 = ln
        let ln2 = ln
    " visual mode: use range
    elseif a:mode==#'v'
        let ln1 = line("'<")
        let ln2 = line("'>")
    endif
    " don't touch first line
    if ln1==1 && ln2==ln1
        return
    elseif ln1==1 && ln2>1
        let ln1=2
    endif
    " }}}

    let lz_ = &lz | set lz
    let t_fdm = &fdm
    if voom#ToBody(body) < 0 | let &lz=lz_ | return | endif
    if voom#BodyCheckTicks(body) < 0 | let &lz=lz_ | return | endif

    let b_fdm=&fdm | setl fdm=manual
    call setbufvar(tree, '&fdm', 'manual')
    call setbufvar(tree, '&ma', 1)
    if a:op==#'mark'
        keepj python _VOoM.voom_OopMark()
    elseif a:op==#'unmark'
        keepj python _VOoM.voom_OopUnmark()
    endif
    let &fdm=b_fdm
    call voom#OopFromBody(body,tree,-1)
    call setbufvar(tree, '&ma', 0)
    let &fdm=t_fdm
    let &lz=lz_
    call voom#OopVerify(body, tree, a:op)
endfunc


func! voom#OopMarkStartup() "{{{3
" Mark current node as startup node.
    let tree = bufnr('')
    if voom#BufNotTree(tree) | return | endif
    let body = s:voom_trees[tree]
    if s:voom_bodies[body].MTYPE
        call voom#ErrorMsg('VOoM: startup nodes are not available in this markup mode')
        return
    endif
    if voom#BufNotLoaded(body) | return | endif
    if voom#BufNotEditable(body) | return | endif
    let ln = line('.')
    if voom#FoldStatus(ln)==#'hidden'
        call voom#ErrorMsg("VOoM: current node is hidden in fold")
        return
    endif

    let lz_ = &lz | set lz
    if voom#ToBody(body) < 0 | let &lz=lz_ | return | endif
    if voom#BodyCheckTicks(body) < 0 | let &lz=lz_ | return | endif

    call setbufvar(tree, '&ma', 1)
    keepj python _VOoM.voom_OopMarkStartup()
    call voom#OopFromBody(body,tree,-1)
    call setbufvar(tree, '&ma', 0)

    let &lz=lz_
    call voom#OopVerify(body, tree, 'markStartup')
endfunc


func! voom#Oop(op, mode) "{{{3
" Outline operations that can be perfomed on the current node or on nodes in
" Visual selection. All apply to branches, not to single nodes.
    " Checks and init vars. {{{
    let tree = bufnr('')
    if voom#BufNotTree(tree) | return | endif
    let body = s:voom_trees[tree]
    if voom#BufNotLoaded(body) | return | endif
    if a:op!=#'copy' && voom#BufNotEditable(body) | return | endif
    let ln = line('.')
    if voom#FoldStatus(ln)==#'hidden'
        call voom#ErrorMsg("VOoM: current node is hidden in fold")
        return
    endif
    " normal mode: use current line
    if a:mode==#'n'
        let [ln1,ln2] = [ln,ln]
    " visual mode: use range
    elseif a:mode==#'v'
        let [ln1,ln2] = [line("'<"),line("'>")]
        " before op: move cursor to ln1 or ln2
    endif
    if ln1==1
        call voom#ErrorMsg("VOoM (".a:op."): first Tree line cannot be operated on")
        return
    endif
    " set ln2 to last node in the last sibling branch in selection
    " check validity of selection
    python vim.command('let ln2=%s' %_VOoM.voom_OopSelEnd())
    if ln2==0
        call voom#ErrorMsg("VOoM: invalid Tree selection")
        return
    endif
    " }}}

    let lz_ = &lz | set lz
    let l:doverif = 1
    " default bnlShow -1 means no changes were made or Python code failed
    let l:blnShow = -1

    if a:op==#'up' " {{{
        if ln1<3 | let &lz=lz_ | return | endif
        if a:mode==#'v'
            " must be on first line of selection
            exe "keepj normal! ".ln1."G"
        endif
        " ln before which to insert, also, new snLn
        normal! k
        let lnUp1 = line('.')
        " top node of a tree after which to insert
        normal! k
        let lnUp2 = line('.')

        if voom#ToBody(body) < 0 | let &lz=lz_ | return | endif
        if voom#BodyCheckTicks(body) < 0 | let &lz=lz_ | return | endif

        call setbufvar(tree, '&ma', 1)
        keepj python _VOoM.voom_OopUp()
        call setbufvar(tree, '&ma', 0)

        if l:blnShow > 0
            let s:voom_bodies[body].snLn = lnUp1
            let lnEnd = lnUp1+ln2-ln1
            call voom#OopShowTree(lnUp1, lnEnd, a:mode)
        endif
        " }}}

    elseif a:op==#'down' " {{{
        if ln2==line('$') | let &lz=lz_ | return | endif
        " must be on the last node of current tree or last tree in selection
        exe "keepj normal! ".ln2."G"
        " line after which to insert
        normal! j
        let lnDn1 = line('.') " should be ln2+1
        let lnDn1_status = voom#FoldStatus(lnDn1)

        if voom#ToBody(body) < 0 | let &lz=lz_ | return | endif
        if voom#BodyCheckTicks(body) < 0 | let &lz=lz_ | return | endif

        call setbufvar(tree, '&ma', 1)
        keepj python _VOoM.voom_OopDown()
        call setbufvar(tree, '&ma', 0)

        if l:blnShow > 0
            let s:voom_bodies[body].snLn = l:snLn
            let lnEnd = snLn+ln2-ln1
            call voom#OopShowTree(snLn, lnEnd, a:mode)
        endif
        " }}}

    elseif a:op==#'right' " {{{
        if ln1==2 | let &lz=lz_ | return | endif

        if voom#ToBody(body) < 0 | let &lz=lz_ | return | endif
        if voom#BodyCheckTicks(body) < 0 | let &lz=lz_ | return | endif

        let b_fdm=&fdm | setl fdm=manual
        call setbufvar(tree, '&ma', 1)
        keepj python _VOoM.voom_OopRight()
        call setbufvar(tree, '&ma', 0)

        if l:blnShow > 0
            let s:voom_bodies[body].snLn = ln1
            call voom#OopShowTree(ln1, ln2, a:mode)
        else
            call setbufvar(body, '&fdm', b_fdm)
        endif
        " }}}

    elseif a:op==#'left' " {{{
        if ln1==2 | let &lz=lz_ | return | endif

        if voom#ToBody(body) < 0 | let &lz=lz_ | return | endif
        if voom#BodyCheckTicks(body) < 0 | let &lz=lz_ | return | endif

        let b_fdm=&fdm | setl fdm=manual
        call setbufvar(tree, '&ma', 1)
        keepj python _VOoM.voom_OopLeft()
        call setbufvar(tree, '&ma', 0)

        if l:blnShow > 0
            let s:voom_bodies[body].snLn = ln1
            call voom#OopShowTree(ln1, ln2, a:mode)
        else
            call setbufvar(body, '&fdm', b_fdm)
        endif
        " }}}

    elseif a:op==#'cut' " {{{
        if a:mode==#'v'
            " must be on first line of selection
            exe "keepj normal! ".ln1."G"
        endif
        " new snLn
        normal! k
        let lnUp1 = line('.')

        if voom#ToBody(body) < 0 | let &lz=lz_ | return | endif
        if voom#BodyCheckTicks(body) < 0 | let &lz=lz_ | return | endif

        call setbufvar(tree, '&ma', 1)
        keepj python _VOoM.voom_OopCut()
        call setbufvar(tree, '&ma', 0)

        if l:blnShow > 0
            let s:voom_bodies[body].snLn = lnUp1
            call cursor(0,stridx(getline('.'),'|')+1)
        endif
        " }}}

    elseif a:op==#'copy' " {{{
        " check ticks, getbufvar(body,'changedtick') is '' if Vim < 7.3.105
        if s:voom_bodies[body].tick_ != getbufvar(body,'changedtick')
            if voom#ToBody(body) < 0 | let &lz=lz_ | return | endif
            if voom#BodyCheckTicks(body) < 0 | let &lz=lz_ | return | endif
            call voom#OopFromBody(body,tree,-1)
        endif
        python _VOoM.voom_OopCopy()
        let l:doverif = 0
        "}}}
    endif

    let &lz=lz_
    if l:doverif
        call voom#OopVerify(body, tree, a:op)
    endif
endfunc


func! voom#OopFolding(ln1, ln2, action) "{{{3
" Deal with Tree folding in range ln1-ln2 according to action:
" save, restore, cleanup. Range is ignored if 'cleanup'.
" Since potentially large lists are involved, folds are manipulated in Python.
    let tree = bufnr('')
    if voom#BufNotTree(tree) | return | endif
    let body = s:voom_trees[tree]
    if s:voom_bodies[body].MTYPE
        call voom#ErrorMsg('VOoM: Tree folding operations are not available in this markup mode')
        return
    endif
    if voom#BufNotLoaded(body) | return | endif
    if a:action!=#'restore' && voom#BufNotEditable(body)
        return
    endif
    if a:action!=#'cleanup' && voom#FoldStatus(a:ln1)==#'hidden'
        call voom#ErrorMsg("VOoM: current node is hidden in fold")
        return
    endif

    let lz_ = &lz | set lz
    " check ticks, getbufvar(body,'changedtick') is '' if Vim < 7.3.105
    if s:voom_bodies[body].tick_ != getbufvar(body,'changedtick')
        if voom#ToBody(body) < 0 | let &lz=lz_ | return | endif
        if voom#BodyCheckTicks(body) < 0 | let &lz=lz_ | return | endif
        call voom#OopFromBody(body,tree,-1)
    endif

    """ diddle with folds
    let winsave_dict = winsaveview()
    python _VOoM.voom_OopFolding(vim.eval('a:action'))
    call winrestview(winsave_dict)

    if a:action==#'restore' | let &lz=lz_ | return | endif

    " go to Body, set ticks, go back
    if voom#ToBody(body) < 0 | let &lz=lz_ | return | endif
    call setbufvar(tree, '&ma', 1)
    call voom#OopFromBody(body,tree,-1)
    call setbufvar(tree, '&ma', 0)
    let &lz=lz_
    call voom#OopVerify(body, tree, a:action.' folding marks')
endfunc

func! voom#OopSort(ln1,ln2,qargs) "{{{3
" Sort siblings in Tree range ln1:ln2 according to options qargs.
" Sort siblings of the current node if range is one line (ln1==ln2).
" If one of the options is 'deep' -- also sort siblings in all subnodes.
" Options are dealt with in the Python code.
    let tree = bufnr('')
    if voom#BufNotTree(tree) | return | endif
    let body = s:voom_trees[tree]
    if voom#BufNotLoaded(body) | return | endif
    if voom#BufNotEditable(body) | return | endif
    if a:ln1 < 2 || a:ln2 < 2
        call voom#ErrorMsg("VOoM (sort): first Tree line cannot be operated on")
        return
    endif
    if voom#FoldStatus(a:ln1)==#'hidden'
        call voom#ErrorMsg("VOoM: current node is hidden in fold")
        return
    endif

    let lz_ = &lz | set lz
    let Z = line('$')
    if voom#ToBody(body) < 0 | let &lz=lz_ | return | endif
    if voom#BodyCheckTicks(body) < 0 | let &lz=lz_ | return | endif

    " default l:bnlShow -1 means no changes were made
    let l:blnShow = -1
    " Modify Body buffer. NOTE: Tree buffer and outline data are not adjusted.
    keepj python _VOoM.voom_OopSort()
    " IMPORTANT: we rely on Tree BufEnter au to update outline
    call voom#OopFromBody(body,tree,l:blnShow)
    if l:blnShow > 0
        call voom#OopShowTree(l:lnum1, l:lnum2, a:ln1==a:ln2 ? 'n' : 'v')
    endif
    let &lz=lz_

    " Sorting must not change the number of headlines!
    " (This is problem with reST, asciidoc, Python modes.)
    if Z != line('$')
        let d = line('$') - Z
        call voom#ErrorMsg("VOoM (sort): ERROR OCCURRED DURING SORTING!!! YOU SHOULD UNDO THIS SORT!!!")
        call voom#ErrorMsg("             Total number of nodes has changed by ".d.".")
        call voom#ErrorMsg("             If a blank line is required before headlines (reST, AsciiDoc), make sure every node ends with a blank line.")
    endif
endfunc


func! voom#OopFromBody(body,tree,blnShow) "{{{3
" Move from Body to Tree, usually during an outline operation when Tree is &ma.
" Show line at Body lnum blnShow if blnShow > 0.
" Set tick_ if Tree is &ma to suppress subsequent updates on Tree BufEnter.
" NOTE: outline update on Tree BufEnter is always blocked when Tree is &ma.
    if bufnr('')!=a:body | echoerr 'VOoM: INTERNAL ERROR 1' | return | endif
    " set .tick_ to suppress Tree updates; always set .tick in case BufLeave au fails
    let b_tick = b:changedtick
    let s:voom_bodies[a:body].tick = b:changedtick
    if getbufvar(a:tree,'&ma')
        let s:voom_bodies[a:body].tick_ = b:changedtick
    endif
    " show line at blnShow
    if a:blnShow > 0
        exe 'keepj normal! '.a:blnShow.'G'
        if &fdm==#'marker'
            normal! zMzvzt
        else
            normal! zvzt
        endif
    endif
    " go back to Tree window, which should be previous window
    let wnr_ = winnr('#')
    if winbufnr(wnr_)==a:tree
        exe wnr_.'wincmd w'
    else
        exe bufwinnr(a:tree).'wincmd w'
    endif
    if bufnr('')!=a:tree | echoerr 'VOoM: INTERNAL ERROR 2' | return | endif
    if &ma
        if s:voom_bodies[a:body].tick != b_tick
            let s:voom_bodies[a:body].tick_ = s:voom_bodies[a:body].tick
            let s:verify = 1
        endif
    elseif s:voom_bodies[a:body].tick_ != s:voom_bodies[a:body].tick
        call voom#ErrorMsg('VOoM: wrong ticks. Forcing outline update...')
        call voom#TreeBufEnter()
    endif
endfunc


func! voom#OopShowTree(ln1, ln2, mode) " {{{3
    " select range ln2-ln1 and close all folds
    " first zv ensures node ln1 is expanded when extending selection to it
    exe 'keepj normal! '.a:ln1.'Gzv'.a:ln2.'G0f|V'.a:ln1.'G0f|'
    try
        normal! zC
    catch /^Vim\%((\a\+)\)\=:E490/
    endtry
    call voom#TreeZV()
    call cursor(0,stridx(getline('.'),'|')+1)
    " close subnodes below ln2 after Move Left with g:voom_always_allow_move_left
    if stridx(getline(a:ln2+1),'|') > stridx(getline(a:ln1),'|')
        let ind = virtcol('.')-1
        exe 'keepj normal! '.(a:ln2+1).'Gzv'
        call search('\m^[^|]\{0,'.ind.'}|', 'We')
        if line('.') > a:ln2+1
            exe 'keepj normal! '.(line('.')-1).'GV'.(a:ln2+1).'G'
        else
            exe 'keepj normal! GV'.(a:ln2+1).'G'
        endif
        try
            normal! zC
        catch /^Vim\%((\a\+)\)\=:E490/
        endtry
        call voom#TreeZV()
        exe 'keepj normal! '.a:ln2.'G0f|V'.a:ln1.'G0f|'
    " end in visual mode if outline operation was started in visual mode
    elseif a:mode ==# 'v'
        normal! gv
    endif
    return
        " alternatives to gv:
        "exe 'keepj normal! '.a:ln2.'G0f|V'.a:ln1.'G0f|'
        "exe 'keepj normal! '.a:ln2.'GV'.a:ln1.'G'
" Adjust Tree view after an outline operation.
" ln1 and ln2 are first and last line of the modified range.
" After an outline operation Tree folds in the affected range are usually
" sprung open. To make it look nice, close all folds in the range: select the
" range, zC (watch out for E490: No fold found), show the first node.
" To fix: cursor is not positioned on | in visual mode when ln1 or ln2 is folded.
endfunc


func! voom#OopVerify(body, tree, op) "{{{3
" Verify outline after outline operation. Current buffer must be Tree.
    if s:verify
        let s:verify = 0
    elseif !g:voom_verify_oop
        return
    endif
    let l:ok = 0
    python _VOoM.voom_OopVerify()
    if l:ok | return | endif
    call voom#ErrorMsg('VOoM: outline verification failed after "'.a:op.'". Forcing outline update...')
    let s:voom_bodies[a:body].tick_ = -1
    if bufnr('')!=a:tree || voom#BufNotTree(a:tree)
        echoerr 'VOoM: INTERNAL ERROR. Outline update aborted.'
        return
    endif
    call voom#TreeBufEnter()
endfunc


"---BODY BUFFERS------------------------------{{{1

func! voom#BodyConfig() "{{{2
" Configure current buffer as a Body buffer.
    augroup VoomBody
        au! * <buffer>
        au BufLeave <buffer> call voom#BodyBufLeave()
        au BufEnter <buffer> call voom#BodyBufEnter()
    augroup END
    " will be also set on BufLeave
    let s:voom_bodies[bufnr('')].tick = b:changedtick
    call voom#BodyMap()
endfunc


func! voom#BodyBufLeave() "{{{2
" Body BufLeave au needed because getbufvar() doesn't work with b:changedtick if Vim <7.3.105.
    let s:voom_bodies[bufnr('')].tick = b:changedtick
endfunc


func! voom#BodyBufEnter() "{{{2
" Body BufEnter au. Restore buffer-local mappings lost after :bd.
    if !hasmapto('voom#ToTreeOrBodyWin','n')
        call voom#BodyMap()
    endif
endfunc


func! voom#BodyMap() "{{{2
" Body buffer local mappings.
    let cpo_ = &cpo | set cpo&vim
    exe "nnoremap <buffer><silent> ".g:voom_return_key." :<C-u>call voom#BodySelect()<CR>"
    exe "nnoremap <buffer><silent> ".g:voom_tab_key.   " :<C-u>call voom#ToTreeOrBodyWin()<CR>"
    let &cpo = cpo_
endfunc


func! voom#BodyUnMap() "{{{2
" Remove Body local mappings. Must be called from Body.
    let cpo_ = &cpo | set cpo&vim
    exe "nunmap <buffer> ".g:voom_return_key
    exe "nunmap <buffer> ".g:voom_tab_key
    let &cpo = cpo_
endfunc


func! voom#BodySelect() "{{{2
" Select current Body node. Show corresponding line in the Tree.
" Stay in the Tree if the node is already selected.
    let body = bufnr('')
    " Tree has been wiped out.
    if !has_key(s:voom_bodies, body)
        call voom#BodyUnMap()
        return
    endif

    let wnr_ = winnr()
    let tree = s:voom_bodies[body].tree
    let blnr = line('.')
    " Go to Tree. Outline will be updated on BufEnter.
    if voom#ToTree(tree) < 0 | return | endif
    if s:voom_bodies[body].tick_!=s:voom_bodies[body].tick
        exe bufwinnr(body).'wincmd w'
        call voom#BodyCheckTicks(body)
        return
    endif

    " updateTree() sets = mark and may change snLn to a wrong value if outline was modified from Body.
    let snLn_ = s:voom_bodies[body].snLn
    " Compute new and correct snLn with updated outline.
    python _VOoM.computeSnLn(int(vim.eval('l:body')), int(vim.eval('l:blnr')))
    let snLn = s:voom_bodies[body].snLn

    call voom#TreeToLine(snLn)
    " Node has not changed. Stay in Tree.
    if snLn==snLn_ | return | endif

    " Node has changed. Draw marks. Go back to Body
    setl ma | let ul_ = &l:ul | setl ul=-1
    keepj call setline(snLn_, ' '.getline(snLn_)[1:])
    keepj call setline(snLn, '='.getline(snLn)[1:])
    setl noma | let &l:ul = ul_

    let wnr_ = winnr('#')
    if winbufnr(wnr_)==body
        exe wnr_.'wincmd w'
    else
        exe bufwinnr(body).'wincmd w'
    endif
endfunc


func! voom#BodyCheckTicks(body) "{{{2
" Current buffer is Body body. Check ticks assuming that outline is up to date,
" as after going to Body from Tree.
" note: 'abort' argument is not needed and would be counterproductive
    if bufnr('')!=a:body
        echoerr 'VOoM: wrong buffer'
        return -1
    endif
    " Wrong ticks, probably after :bun or :bd. Force outline update.
    if s:voom_bodies[a:body].tick_!=b:changedtick
        let tree = s:voom_bodies[a:body].tree
        if !exists("s:voom_trees") || !has_key(s:voom_trees, tree)
            echoerr "VOoM: INTERNAL ERROR"
            return -1
        endif
        call voom#BodyUpdateTree()
        call voom#ErrorMsg('VOoM: wrong ticks for Body buffer '.a:body.'. Outline has been updated.')
        return -1
    endif
endfunc


func! voom#BodyUpdateTree() "{{{2
" Current buffer is Body. Update outline and Tree.
    let body = bufnr('')
    if !has_key(s:voom_bodies, body)
        call voom#ErrorMsg('VOoM: current buffer is not Body')
        return -1
    endif
    let tree = s:voom_bodies[body].tree
    " paranoia
    if !bufloaded(tree)
        call voom#UnVoom(body,tree)
        echoerr "VOoM: Tree buffer" tree "is not loaded or does not exist. Cleanup has been performed."
        return -1
    endif
    " update is not needed
    if s:voom_bodies[body].tick_==b:changedtick | return | endif
    " do update
    call setbufvar(tree, '&ma', 1)
    let ul_ = &l:ul
    call setbufvar(tree, '&ul', -1)
    try
        let l:ok = 0
        keepj python _VOoM.updateTree(int(vim.eval('l:body')), int(vim.eval('l:tree')))
        if l:ok
            let s:voom_bodies[body].tick_ = b:changedtick
            let s:voom_bodies[body].tick  = b:changedtick
        endif
    finally
        " &ul is global, but 'let &ul=ul_' causes 'undo list corrupt' error. WHY?
        call setbufvar(tree, '&ul', ul_)
        call setbufvar(tree, '&ma', 0)
    endtry
endfunc


"---Tree or Body------------------------------{{{1

func! voom#EchoUNL() "{{{2
" Display UNL (Uniformed Node Locator) of current node.
" Copy UNL to register 'n'.
" Can be called from any buffer.
    let bnr = bufnr('')
    let lnum = line('.')
    if has_key(s:voom_trees, bnr)
        let [bufType, body, tree] = ['Tree', s:voom_trees[bnr], bnr]
        if voom#BufNotLoaded(body) | return | endif
    elseif has_key(s:voom_bodies, bnr)
        let [bufType, body, tree] = ['Body', bnr, s:voom_bodies[bnr].tree]
        if voom#BodyUpdateTree() < 0 | return | endif
    else
        call voom#ErrorMsg("VOoM: current buffer is not a VOoM buffer")
        return
    endif
    python _VOoM.voom_EchoUNL()
endfunc


func! voom#Grep(input) "{{{2
" Seach Body for pattern(s). Show list of UNLs of nodes with matches.
" Input can have several patterns separated by boolean 'AND' and 'NOT'.
" Stop if >500000 matches found for a pattern.
" Set "/ register to AND patterns.

    """ Process input first in case we are in Tree and want word under cursor.
    if a:input==''
        let input = expand('<cword>')
        let input = substitute(input, '\s\+$', '', '')
        if input=='' | return | endif
        let [pattsAND, pattsNOT] = [['\<'.input.'\>'], []]
        call histdel('cmd', -1)
        call histadd('cmd', 'Voomgrep '.pattsAND[0])
    else
        let input = substitute(a:input, '\s\+$', '', '')
        if input=='' | return | endif
        let [pattsAND, pattsNOT] = voom#GrepParseInput(input)
    endif

    """ Search must be done in Body buffer. Move to Body if in Tree.
    let bnr = bufnr('')
    if has_key(s:voom_trees, bnr)
        let body = s:voom_trees[bnr]
        let tree = bnr
        if voom#BufNotLoaded(body) | return | endif
        if voom#ToBody(body) < 0 | return | endif
        if voom#BodyCheckTicks(body) < 0 | return | endif
    elseif has_key(s:voom_bodies, bnr)
        let body = bnr
        let tree = s:voom_bodies[bnr].tree
        " update outline
        if voom#BodyUpdateTree() < 0 | return | endif
    else
        call voom#ErrorMsg("VOoM: current buffer is not a VOoM buffer")
        return
    endif

    """ Search for each pattern with search().
    let [lnum_,cnum_] = [line('.'), col('.')]
    let lz_ = &lz | set lz
    let winsave_dict = winsaveview()
    " search results: list of lists with blnums for each pattern
    let [matchesAND, matchesNOT] = [[], []]
    " inheritance flags (hierarchical search): 0 or 1
    let [inhAND, inhNOT] = [[], []]
    let pattsAND1 = []
    for patt in pattsAND
        if patt =~ '\m^\*.'
            let patt = patt[1:]
            call add(inhAND, 1)
        else
            call add(inhAND, 0)
        endif
        call add(pattsAND1, patt)
        let [matches, notOK] = voom#GrepSearch(patt)
        if notOK
            if notOK == 1
                call voom#ErrorMsg('VOoM (Voomgrep): pattern not found: '. patt)
            endif
            call winrestview(winsave_dict)
            call winline()
            let &lz=lz_
            return
        endif
        call add(matchesAND, matches)
    endfor
    for patt in pattsNOT
        if patt =~ '\m^\*.'
            let patt = patt[1:]
            call add(inhNOT, 1)
        else
            call add(inhNOT, 0)
        endif
        let [matches, notOK] = voom#GrepSearch(patt)
        if notOK > 1
            call winrestview(winsave_dict)
            call winline()
            let &lz=lz_
            return
        endif
        call add(matchesNOT, matches)
    endfor
    call winrestview(winsave_dict)
    call winline()
    let &lz=lz_

    let [lenAND, lenNOT] = [len(pattsAND), len(pattsNOT)]
    """ Highlight all AND pattern.
    " Problem: there is no search highlight after :noh
    " Problem: \c \C get combined
    if lenAND
        if lenAND==1
            let @/ = pattsAND1[0]
        else
            " add \m or \M to to negate any preceding \v \V \m \M
            let mm = &magic ? '\m' : '\M'
            let @/ = mm.'\%('. join(pattsAND1, mm.'\)\|\%(') .mm.'\)'
        endif
        call histadd('search', @/)
    endif

    """ Set and display quickfix list.
    let [line1] = getbufline(tree,1)
    " 2nd line shows patterns and numbers of matches
    let line2 = ':Voomgrep'
    for i in range(lenAND)
        let L = matchesAND[i]
        if i == 0
            let line2 = line2 .    '  '. pattsAND[i] .' {'. len(L) .' matches}'
        else
            let line2 = line2 .'  AND '. pattsAND[i] .' {'. len(L) .' matches}'
        endif
    endfor
    for i in range(lenNOT)
        let L = matchesNOT[i]
        let line2 = line2 .'  NOT '. pattsNOT[i] .' {'. len(L) .' matches}'
    endfor
    " initiate quickfix list with two lines
    call setqflist([{'text':line1, 'bufnr':body, 'lnum':lnum_, 'col':cnum_}, {'text':line2}])

    python _VOoM.voom_Grep()

    botright copen
    " Configure quickfix buffer--strip file names, adjust syntax hi.
    if &buftype!=#'quickfix' || &ma || &mod | return | endif
    setl ma
    let ul_ = &l:ul | setl ul=-1
    silent 1,2s/\m^.\{-}|.\{-}|//
    call histdel('search', -1)
    if line('$')>2
        silent 3,$s/\m^.\{-}\ze|//
        call histdel('search', -1)
    endif
    keepj normal! 1G0
    let &l:ul = ul_
    setl nomod noma
    syn clear
    syn match Title /\%1l.*/
    syn match Statement /\%2l.*/
    syn match LineNr /^|.\{-}|.\{-}|/
    syn match Title / -> /
endfunc


func! voom#GrepParseInput(input) "{{{2
" Input string is patterns separated by AND or NOT.
" There can be a leading NOT, but not leading AND.
" Segregate patterns into AND and NOT lists.
    let [pattsAND, pattsNOT] = [[], []]
    let S = a:input
    " bop -- preceding boolean operator: 1 if AND, 0 if NOT
    " i -- start of pattern
    " j,k -- start,end+1 of the next operator string
    let k = matchend(S, '\v\c^\s*not\s+')
    let [i,bop] = k==-1 ? [0,1] : [k,0]
    let OP = '\v\c\s+(and|not)\s+'
    let j = match(S,OP,i)
    while j > -1
        let patt = S[i : j-1]
        call add(bop ? pattsAND : pattsNOT, patt)
        let k = matchend(S,OP,i)
        let bop = S[j : k] =~? 'and' ? 1 : 0
        let i = k
        let j = match(S,OP,i)
    endwhile
    call add(bop ? pattsAND : pattsNOT, S[i : ])
    return [pattsAND, pattsNOT]
endfunc


func! voom#GrepSearch(pattern) "{{{2
" Seach buffer for pattern. Return [[lnums-of-matches], notOK] .
" notOK is 0 (success), 1 (no matches), 2 (search stopped after >500000 matches found).
    let [matches, notOK, n] = [[], 0, 0]
    " always search from start
    keepj normal! gg0
    " special effort needed to detect match at cursor
    if searchpos(a:pattern, 'nc', 1) == [1,1]
        call add(matches,1)
        let n += 1
    endif
    " do search
    try 
        let found = search(a:pattern, 'W')
        while found > 0
            call add(matches, found)
            let n += 1
            if n > 500000
                call voom#ErrorMsg('VOoM (Voomgrep): too many matches (>500000) for pattern: '. a:pattern)
                return [[], 2]
            endif
            let found = search(a:pattern, 'W')
        endwhile
    catch /^Vim:Interrupt$/
        " FIXME this message is not visible, it is overwritten by Vim's CTRL-C message
        call voom#ErrorMsg("VOoM (Voomgrep): search interrupted after ". n ." matches found for pattern: " .a:pattern)
        return [[], 4]
    endtry
    " no matches found
    if matches == []
        let notOK = 1
    endif
    return [matches, notOK]
endfunc


"---LOG BUFFER (Voomlog)----------------------{{{1
"
" Do "normal! G" to position cursor and scroll Log window.
" "call cursor('$',1)" does not scroll Log window.


func! voom#LogInit() "{{{2
" Create and configure PyLog buffer or show existing one.
    let bnr_ = bufnr('')
    """ Log buffer exists, show it.
    if s:voom_logbnr
        if !bufloaded(s:voom_logbnr)
            python sys.stdout, sys.stderr = _voom_py_sys_stdout, _voom_py_sys_stderr
            python if 'pydoc' in sys.modules: del sys.modules['pydoc']
            if bufexists(s:voom_logbnr)
                exe 'au! VoomLog * <buffer='.s:voom_logbnr.'>'
                exe 'bwipeout '.s:voom_logbnr
            endif
            let bnr = s:voom_logbnr
            let s:voom_logbnr = 0
            echoerr "VOoM: PyLog buffer" bnr "was not shut down properly. Cleanup has been performed. Execute the command :Voomlog again."
            return
        endif
        if bufwinnr(s:voom_logbnr) < 0
            call voom#ToLogWin()
            silent exe 'b '.s:voom_logbnr
            keepj normal! G
            exe bufwinnr(bnr_).'wincmd w'
        endif
        return
    endif

    """ Create and configure PyLog buffer.
    if bufexists('__PyLog__') > 0
        call voom#ErrorMsg('VOoM: there is already a buffer named __PyLog__')
        return
    endif
    call voom#ToLogWin()
    silent edit __PyLog__
    call voom#LogConfig()
    """ Go back.
    exe bufwinnr(bnr_).'wincmd w'
endfunc


func! voom#LogConfig() "{{{2
" Configure current buffer as PyLog. Redirect Python stdout and stderr to it.
" NOTE: the caller must check if PyLog already exists.
    let s:voom_logbnr = bufnr('')
    augroup VoomLog
        au! * <buffer>
        au BufUnload <buffer> nested call voom#LogBufUnload()
    augroup END
    setl cul nocuc list wrap
    setl bufhidden=wipe
    setl ft=voomlog
    setl noro ma ff=unix
    setl nobuflisted buftype=nofile noswapfile
    call voom#LogSyntax()
python << EOF
_voom_py_sys_stdout, _voom_py_sys_stderr = sys.stdout, sys.stderr
sys.stdout = sys.stderr = _VOoM.LogBufferClass()
if 'pydoc' in sys.modules: del sys.modules['pydoc']
EOF
endfunc


func! voom#LogBufUnload() "{{{2
    if !s:voom_logbnr || expand("<abuf>")!=s:voom_logbnr
        echoerr 'VOoM: INTERNAL ERROR'
        return
    endif
    python sys.stdout, sys.stderr = _voom_py_sys_stdout, _voom_py_sys_stderr
    python if 'pydoc' in sys.modules: del sys.modules['pydoc']
    exe 'au! VoomLog * <buffer='.s:voom_logbnr.'>'
    exe 'bwipeout '.s:voom_logbnr
    let s:voom_logbnr = 0
endfunc


func! voom#LogSyntax() "{{{2
" Log buffer syntax highlighting.

    " Python tracebacks
    syn match Error /^Traceback (most recent call last):/
    syn match Error /^\u\h*Error/
    syn match Error /^vim\.error/
    syn region WarningMsg start="^Traceback (most recent call last):" end="\%(^\u\h*Error.*\)\|\%(^\s*$\)\|\%(^vim\.error\)" contains=Error keepend

    "Vim exceptions
    syn match Error /^Vim.*:E\d\+:.*/

    " VOoM messages
    syn match Error /^ERROR: .*/
    syn match Error /^EXCEPTION: .*/
    syn match PreProc /^---end of \w\+ script.*---$/

    " -> UNL separator
    syn match Title / -> /

endfunc


func! voom#LogScroll() "{{{2
" Scroll windows with the __PyLog__ buffer.
" All tabs are searched. Only the first found Log window in each tab is scrolled.
" Uses noautocmd when jumping between tabs and windows.
" Note: don't use Python here: an error will result in recursive loop.

    " can't go to other windows when in Ex mode (after 'Q' or 'gQ')
    if mode()==#'c' | return | endif
    " This should never happen.
    if !s:voom_logbnr || !bufloaded(s:voom_logbnr)
        echoerr "VOoM: INTERNAL ERROR"
        return
    endif

    let lz_=&lz | set lz
    let log_found = 0
    let [tnr_, wnr_, bnr_] = [tabpagenr(), winnr(), bufnr('')]
    " search among visible buffers in all tabs
    for tnr in range(1, tabpagenr('$'))
        if index(tabpagebuflist(tnr), s:voom_logbnr) > -1
            let log_found = 1
            if tabpagenr() != tnr
                exe 'noautocmd tabnext '.tnr
            endif
            let [wnr__, wnr__p] = [winnr(), winnr('#')]
            exe 'noautocmd '. bufwinnr(s:voom_logbnr).'wincmd w'
            keepj normal! G
            " restore tab's current and previous window numbers
            if wnr__p
                exe 'noautocmd '.wnr__p.'wincmd w'
            endif
            exe 'noautocmd '.wnr__.'wincmd w'
        endif
    endfor
    " At least one Log window was found and scrolled. Return to original tab and window.
    if log_found==1
        if tabpagenr() != tnr_
            exe 'noautocmd tabnext '.tnr_
            exe 'noautocmd '.wnr_.'wincmd w'
        endif
    " Log window was not found. Create it.
    else
        call voom#ToLogWin()
        exe 'b '.s:voom_logbnr
        keepj normal! G
        exe 'tabnext '.tnr_
        exe bufwinnr(bnr_).'wincmd w'
    endif
    let &lz=lz_
endfunc


func! voom#LogSessionLoad() "{{{2
" Activate PyLog when loading Vim session created with :mksession.
    if !exists('g:SessionLoad') || &modified || line('$')>1 || getline(1)!='' || (exists('s:voom_logbnr') && s:voom_logbnr)
        return
    endif
    call voom#LogConfig()
endfunc


"---EXECUTE SCRIPT (Voomexec)-----------------{{{1

func! voom#GetVoomRange(lnum, withSubnodes) "{{{2
    let bnr = bufnr('')
    if has_key(s:voom_trees, bnr)
        let [bufType, body, tree] = ['Tree', s:voom_trees[bnr], bnr]
        if voom#BufNotLoaded(body) | return ['Tree',-1,-1,-1] | endif
    elseif has_key(s:voom_bodies, bnr)
        let [bufType, body, tree] = ['Body', bnr, s:voom_bodies[bnr].tree]
        if voom#BodyUpdateTree() < 0 | return ['Body',-1,-1,-1] | endif
    else
        return ['None',0,0,0]
    endif
    if a:withSubnodes
        python _VOoM.voom_GetVoomRange(withSubnodes=1)
    else
        python _VOoM.voom_GetVoomRange()
    return [bufType, body, l:bln1, l:bln2]
" Return [bufType, body, bln1, bln2] for node at line lnum of the current
" VOoM buffer (Tree or Body).
" bln1, bln2: VOoM node's first and last Body lnums. Current node only if
" a:withSubnodes==0. Include all subnodes if a:withSubnodes==1.
" Return [bufType,-1,-1,-1] in case of an error (unloaded Body, etc.)
" Return ['None',0,0,0] for a non-VOoM buffer.
" This is for use by external scripts:
"       let [bufType, body, bln1, bln2] = voom#GetVoomRange(line('.'),0)
"       let bodyLines = getbufline(body,bln1,bln2)
endfunc


func! voom#GetBuffRange(ln1, ln2) "{{{2
    let bnr = bufnr('')
    if has_key(s:voom_trees, bnr)
        let [bufType, body, tree] = ['Tree', s:voom_trees[bnr], bnr]
        if voom#BufNotLoaded(body) | return ['Tree',-1,-1,-1] | endif
        python _VOoM.voom_GetBuffRange()
        return [bufType, body, l:bln1, l:bln2]
    elseif has_key(s:voom_bodies, bnr)
        return ['Body',bnr,a:ln1,a:ln2]
    else
        return ['None',bnr,a:ln1,a:ln2]
    endif
" Return [bufType, body, bln1, bln2] for line range lnum1,lnum2.
" If current buffer is a Tree: bln1, bln2 are start and end lnums of the
" corresponding Body line range; 'body' is Body's buffer number.
" Return ['Tree',-1,-1,-1] in case of an error (unloaded Body.)
" If current buffer is not a Tree: bln1, bln2 are lnum1, lnum2; 'body' is the
" current buffer number.
" NOTE: Outline is not updated if the current buffer is Body.
endfunc


func! voom#GetExecRange(lnum) "{{{2
" Return line range info for Voomexec: [bufType, bufnr, start lnum, end lnum]
    let bnr = bufnr('')
    let status = voom#FoldStatus(a:lnum)
    if status==#'hidden'
        call voom#ErrorMsg('VOoM: current node is hidden in fold')
        return ['',-1,-1,-1]
    endif
    " Tree buffer: get start/end of Body node and subnodes.
    if has_key(s:voom_trees, bnr)
        let [bufType, body, tree] = ['Tree', s:voom_trees[bnr], bnr]
        if voom#BufNotLoaded(body) | return ['',-1,-1,-1] | endif
        python _VOoM.voom_GetVoomRange(withSubnodes=1)
        return [bufType, body, l:bln1, l:bln2]
    endif
    " Any other buffer: get start/end of the current fold and subfolds.
    if &fdm !=# 'marker'
        call voom#ErrorMsg('VOoM: ''foldmethod'' must be "marker"')
        return ['',-1,-1,-1]
    endif
    if status==#'nofold'
        call voom#ErrorMsg('VOoM: no fold at cursor')
        return ['',-1,-1,-1]
    elseif status==#'folded'
        return ['', bnr, foldclosed(a:lnum), foldclosedend(a:lnum)]
    elseif status==#'notfolded'
        let lz_ = &lz | set lz
        let winsave_dict = winsaveview()
        normal! zc
        let foldStart = foldclosed(a:lnum)
        let foldEnd   = foldclosedend(a:lnum)
        normal! zo
        call winrestview(winsave_dict)
        let &lz=lz_
        return ['', bnr, foldStart, foldEnd]
    endif
endfunc


func! voom#Exec(qargs) "{{{2
" Execute text from the current node (Tree or Body, include subnodes) or fold
" (non-VOoM buffer, include subfolds) as a script.
" If argument is 'vim' or 'py'/'python': execute as Vim or Python script.
" Otherwise execute according to filetype.

    " If current buffer is a Tree: use Body filetype, encodings, etc.
    let bnr = bufnr('')
    if has_key(s:voom_trees, bnr)
        let bnr = s:voom_trees[bnr]
    endif
    let FT = getbufvar(bnr, '&ft')

    if a:qargs==#'vim'
        let scriptType = 'vim'
    elseif a:qargs==#'py' || a:qargs==#'python'
        let scriptType = 'python'
    elseif a:qargs!=''
        call voom#ErrorMsg('VOoM: unsupported script type: "'.a:qargs.'"')
        return
    elseif FT==#'vim'
        let scriptType = 'vim'
    elseif FT==#'python'
        let scriptType = 'python'
    else
        call voom#ErrorMsg('VOoM: unsupported script type: "'.FT.'"')
        return
    endif

    " Get script lines.
    let [bufType, body, bln1, bln2] = voom#GetExecRange(line('.'))
    if body<1 | return | endif

    " Execute Vim script: Copy list of lines to register and execute it.
    " Problem: Python errors do not terminate script and Python tracebacks are
    " not printed. They are printed to the PyLog if it's enabled. Probably
    " caused by 'catch', but without it foldtext is temporarily messed up in
    " all windows after any error.
    if scriptType==#'vim'
        let lines = getbufline(body, bln1, bln2)
        if lines==[] | return | endif
        let reg_z = getreg('z')
        let reg_z_mode = getregtype('z')
        let script = join(lines, "\n") . "\n"
        call setreg('z', script, "l")
        try
            call s:ExecVim()
        catch
            call voom#ErrorMsg(v:exception)
        finally
            call setreg('z', reg_z, reg_z_mode)
            echo '---end of Vim script ('.bln1.'-'.bln2.')---'
        endtry
    " Execute Python script.
    elseif scriptType==#'python'
        " do not change, see ./voom/voom_vim.py#id_20101214100357
        if s:voom_logbnr
            try
                python _VOoM.voom_Exec()
            catch
                python print vim.eval('v:exception')
            endtry
        else
            python _VOoM.voom_Exec()
        endif
    endif
endfunc


func! s:ExecVim() "{{{2
    @z
endfunc


"---execute user command----------------------{{{1
if exists('g:voom_user_command')
    execute g:voom_user_command
endif


" modelines {{{1
" vim:fdm=marker:fdl=0:
" vim:foldtext=getline(v\:foldstart).'...'.(v\:foldend-v\:foldstart):
doc/voom.txt	[[[1
5106
*voom.txt*      VOoM -- Vim two-pane outliner
Last Modified: 2014-06-22
Version: 5.1
VOoM -- Vim two-pane outliner, plugin for Python-enabled Vim 7.x
Website: http://www.vim.org/scripts/script.php?script_id=2657
Author: Vlad Irnov (vlad DOT irnov AT gmail DOT com)
License: CC0, see http://creativecommons.org/publicdomain/zero/1.0/


    Overview  . . . . . . . . . . . . . . . . . . . .|voom-overview|
    Requirements  . . . . . . . . . . . . . . . . . .|voom-requirements|
    Installation  . . . . . . . . . . . . . . . . . .|voom-install|
    Quick Start . . . . . . . . . . . . . . . . . . .|voom-quickstart|
    ALL MAPPINGS & COMMANDS . . . . . . . . . . . . .|voom-map|
    Options . . . . . . . . . . . . . . . . . . . . .|voom-options|
    OUTLINING (:Voom) . . . . . . . . . . . . . . . .|voom-Voom|
    EXECUTING NODES (:Voomexec) . . . . . . . . . . .|voom-Voomexec|
    __PyLog__ BUFFER (:Voomlog) . . . . . . . . . . .|voom-Voomlog|
    Add-ons . . . . . . . . . . . . . . . . . . . . .|voom-addons|
    Implementation notes  . . . . . . . . . . . . . .|voom-notes|


==============================================================================
Overview   [[[1~
                                                 *voom-overview*
VOoM (Vim Outliner of Markups) is a plugin for Vim that emulates a two-pane
text outliner.

Home page: http://www.vim.org/scripts/script.php?script_id=2657
Screenshots and an animation: http://vim-voom.github.io/
Bug reports, questions, requests: https://github.com/vim-voom/vim-voom.github.com/issues
Supplementary materials: https://github.com/vim-voom/VOoM_extras

VOoM was originally written to work with start fold markers with level numbers,
such as in this help file. This is the most versatile outline markup -- it is
suitable for organizing all kinds of files, including source code, and it
allows features not possible with other markups (|fold-marker|).
(Markers are specified by option 'foldmarker'. End fold markers with levels are
not supported.)

VOoM can currently handle a variety of markup formats that have headlines and
support an outline structure, including popular lightweight markup languages.
(Headlines are also called headings, headers, section headers, titles.)
Available markup modes:
    fmr, fmr1, fmr2  |voom-mode-fmr|
    wiki             |voom-mode-wiki|
    vimwiki          |voom-mode-vimwiki|
    dokuwiki         |voom-mode-dokuwiki|
    viki             |voom-mode-viki|
    org              |voom-mode-org|
    rest             |voom-mode-rest|
    markdown         |voom-mode-markdown|
    pandoc           |voom-mode-pandoc|
    hashes           |voom-mode-hashes|
    txt2tags         |voom-mode-txt2tags|
    asciidoc         |voom-mode-asciidoc|
    latex            |voom-mode-latex|
    html             |voom-mode-html|
    thevimoutliner   |voom-mode-thevimoutliner|
    vimoutliner      |voom-mode-vimoutliner|
    taskpaper        |voom-mode-taskpaper|
    python           |voom-mode-python|
    various other    |voom-mode-various|


FEATURES AND BENEFITS:
    - VOoM is a full-featured outliner. It has a complete set of commands for
      outline structure manipulation: move nodes up/down, promote/demote,
      copy/cut/paste, insert new node, sort in various ways, randomize.
    - There are many one-character mappings for efficient outline navigation
      which can be combined into complex commands, e.g., "UVD" selects all
      siblings of the current node.
    - VOoM is mice-friendly: outlines can be browsed with a mouse.
    - An outline can be searched (:Voomgrep). Boolean AND/NOT searches (OR is
      provided by |/bar|). Hierarchical searches (tag inheritance).
    - An outline is updated automagically on entering the corresponding Tree
      buffer.
    - VOoM works with Vim buffers, not with files on disk as ctags-based tools.
    - VOoM is not a 'filetype' plugin. It has (almost) no side effects on the
      buffer being outlined.
    - VOoM is not tied to a particular outline format. It works with many
      popular light-weight markup languages.
    - VOoM is fast and efficient enough to handle MB-sized files with >1000
      headlines. (Some markup modes are slower than other.)

There are four main Ex commands: Voom, Voomhelp, Voomexec, Voomlog.

:Voom [MarkupMode]
            Scan the current buffer for headlines and create an outline from
            them. By default, headlines are lines with a start fold marker
            (specified by option 'foldmarker') followed by a number.
            To work with headlines in a different format, an argument
            specifying the desired markup mode must be provided, see above and
            |voom-markup-modes|. There is an argument completion for installed
            markup modes: type ":Voom " and press <Tab> or <C-d>.
            The outline is displayed in a special buffer in a separate window
            which emulates the tree pane of a two-pane outliner. Such buffers
            are referred to as Tree buffers. The current buffer becomes a Body
            buffer. Each Tree line is associated with a region (node) of the
            corresponding source buffer (Body). Nodes can be navigated and
            manipulated in the Tree: moved up/down, promoted/demoted,
            copied/cut/pasted, marked/unmarked, sorted, etc.
            See OUTLINING (|voom-Voom|) for details.

                                                 *voom-Voomhelp*
:Voomhelp   Open help file voom.txt as an outline in a new tabpage. If voom.txt
            is installed via |helptags|, it is opened as a Vim help file
            (:tab help voom.txt) so that all help tags will be active.


VOoM also includes two utilities useful when working with Vim and Python
scripts -- commands :Voomexec and :Voomlog. They can be used independently of
the outlining functionality provided by the command :Voom. These commands
attempt to emulate similar features of Leo outlining editor. A Python file with
code snippets organized via fold markers, plus the command :Voomexec, plus the
PyLog buffer is an alternative to running Python's interactive interpreter.

:Voomexec   Execute the contents of the current node or fold as a Vim script or
            Python script. This is useful for testing code snippets and for
            organizing short scripts by segregating them into folds. This
            command does not require an outline to be created and can be used
            with any buffer that has folds and has fold method set to marker.
            See EXECUTING SCRIPTS (|voom-Voomexec|) for details.

:Voomlog    Create scratch buffer __PyLog__ and redirect Python's sys.stdout
            and sys.stderr to it. This is useful when developing Python scripts
            and when scripting Vim with Python. This feature is not related to
            folding or outlining and is completely independent from the rest of
            the plugin.
            See __PyLog__ BUFFER (|voom-Voomlog|) for details.

See |voom-quickstart| for a quick introduction to VOoM outlining.
See |voom-map| for a concise list of all VOoM commands (cheat sheet).

==============================================================================
Limitations   [[[2~

==============================================================================
File size   [[[3~

VOoM outlining is not scalable to large outlines. The bottleneck is the brute
force update of outline data. Such update, which scans the Body buffer for
headlines and recreates the outline, must be done whenever the user enters a
Tree buffer after modifying the corresponding Body--we can't possibly know what
the user did with the Body while he was away from the Tree.

Fortunately, the performance is good enough for comfortable work with MB-sized
files even on an old hardware. I developed VOoM on a 2002 notebook with 1.6GHz
Pentium 4 Mobile processor. Sample outline "calendar_outline.txt" is
approaching the usable size limit on such old hardware: >
    3.2 Mb, 56527 lines, 4160 headlines.
When moving to Tree after modifying Body, the pause due to outline update is
noticeable but still less than a second: 0.17-0.42 sec. A 2013 entry-level
notebook with 4x Intel Core i3-3120M @ 2.50GHz processor is 5-6 times faster.

Browsing an outline is always fast regardless of it's size.

In case of the stress-test file "calendar_outline.txt", the time-consuming step
is not just scanning for fold markers, but also comparing >4000 headlines
between the old and new outlines, or, if outlines are very different, setting
all lines in the Tree buffer. This means that much larger files can be outlined
comfortably if they have much fewer headlines.

==============================================================================
Numbered Markers: Pros and Cons   [[[3~

VOoM can now handle a variaty of markup formats, but it was originally designed
to work with start fold markers with levels: {{{1, {{{2, etc. Numbered start
fold markers have many advantages:
    - It is a built-in Vim folding method (:set fdm=marker).
    - Folding is fast, suitable for MB-sized files with >1000 headlines.
    - More flexible than indent-based or syntax-based folding. Suitable for
      outlining of most file types, including source code. This is really the
      only viable option for organizing the source code as an outline.
    - They are easy to parse and to search for. Area after the level number is
      a natural place for storing node attributes.
    - Fold markers without levels are handy for folding smaller regions.

One drawback of numbered fold markers is that inserting them is somewhat
awkward and slow. This is not a big deal if outline nodes have a lot of body
text: most of the time is spent writing the body text rather than creating
headlines. For outlines that consist mostly of headlines (e.g., a shopping
list) an indent based outlining mode is more appropriate. See plugins such as
Vim Outliner, The Vim Outliner, TaskPaper.

P.S. I wrote a simple plugin that helps insert start fold markers with levels:
http://www.vim.org/scripts/script.php?script_id=2891

==============================================================================
VOoM is not a 'filetype' plugin   [[[3~

This is a design philosophy rather than a limitation. VOoM is expected to work
with files of any 'filetype': source code, plain text notes, Vim help file, a
large wiki file, a custom GTD format. The command :Voom [markup], which creates
an outline, does not configure the current buffer (Body) in any substantial
way: it does not set Body syntax highlighting, indent settings, folding
settings, mappings (with the exception of |voom-shuttle-keys|).

In other words, VOoM is designed to have (almost) no side effects on the buffer
being outlined (Body). All mappings are bound to the Tree pane (except for
shuttle keys).

In contrast, other text outliners are usually geared toward taking notes and
managing tasks (VO, TVO, Emacs Org-mode). They use special format and typically
provide for custom syntax highlighting and folding, a tagging system, clickable
URLs, intra- and inter-outline linking, mappings to insert dates and other
things. VOoM does not provide such features because they should be
'filetype'-specific.

==============================================================================
Other text outliners  [[[2~

Leo outlining editor:
    http://leoeditor.com/
    - The __PyLog__ buffer, which is created by the command :Voomlog, is the
      equivalent of Leo's log pane.
    - The :Voomexec command is like Leo's Execute Script command when executed
      in a node which contains the @others directive.
    - Mark/Unmark nodes operations are modeled after identical Leo commands.
    - Like Leo, VOoM can save which nodes in the Tree are expanded/contracted
      and which node is the selected node. The difference from Leo is that this
      is done manually via Tree commands and mappings.

The "Tag List" Vim plugin:
    http://vim.sourceforge.net/scripts/script.php?script_id=273
    - Conceptually, VOoM is similar to the "Tag List" plugin and other source
      code browsers. "Tag List" uses the "ctags" program to scan files for
      tags. VOoM uses Python scripts to scan Vim buffer for start fold markers
      with levels or some other headline markers.

Other Vim scripts for outlining are listed at
    http://vim.wikia.com/wiki/Script:List_of_scripts_for_outlining?useskin=monobook

Emacs Org-mode:
    http://orgmode.org/
Emacs oultining modes:
    http://www.emacswiki.org/emacs/CategoryOutline

Code Browser:
    http://tibleiz.net/code-browser/

Listings of outliner programs:
    http://en.wikipedia.org/wiki/Outliner
    http://texteditors.org/cgi-bin/wiki.pl?OutlinerFamily
    http://www.outlinersoftware.com/topics/viewt/807/0/list-of-outliners

==============================================================================
Requirements   [[[1~
                                                 *voom-requirements*
VOoM uses Python and requires Python-enabled Vim 7.x, that is Vim compiled
with the Python interface. Your Vim is Python-enabled if it can do >
    :py print 2**0.5
    :py import sys; print sys.version
Python version should be 2.4 - 2.7. Python 3 is not supported.
Vim version 7.2 or above is preferred.
Vim should be compiled using "normal" or bigger feature list.

==============================================================================
Vim and Python on Windows   [[[2~

Getting Vim and Python to work together on Windows can be a bit tricky
(|python-dynamic|).
    - Obviously, Python must be installed. If not, use Python version 2.7.x
      Windows installer from http://www.python.org/ . The installer will put
      Python DLL in the system search path.
    - Vim must be compiled with the Python interface (:echo has("python")).
    - Finally, the version of Python DLL against which Vim was compiled must
      match the installed Python version.

There are several Vim installers for Windows:
Installer from vim.org, http://www.vim.org/download.php , installs Vim
compiled against Python 2.7 as of version 7.4 (gvim.exe only).
Installer from http://sourceforge.net/projects/cream/files/ (gVim one-click
installer for Windows) should have Vim compiled against Python 2.7.

It is not hard to compile your own Python-enabled Vim on Windows. See
http://vim.wikia.com/wiki/Build_Python-enabled_Vim_on_Windows_with_MinGW?useskin=monobook

==============================================================================
Installation   [[[1~
                                                 *voom-install*
To install VOoM plugin manually:
1) Move the contents of folders "autoload", "doc", "plugin" into the respective
folders in your local Vim directory, that is >
    $HOME/vimfiles/       (Windows)
    $HOME/.vim/           (Unix)
This should make commands :Voom, :Voomhelp, :Voomexec, :Voomlog availabe in all
buffers. (To find out what Vim sees as $HOME, do ":echo $HOME".)
2) Execute the :helptags command to update help tags (|add-local-help|): >
    :helptags $HOME/vimfiles/doc       (Windows)
    :helptags $HOME/.vim/doc           (Unix)

Alternatively, use Pathogen ( https://github.com/tpope/vim-pathogen )
and install VOoM as a bundle, or use a Vim plugin manager (vundle,
vim-addon-manager).

NOTE: VOoM uses the autoload mechanism (|autoload|). The bulk of its Vim script
code is in ../autoload/voom.vim . It is sourced, and the main Python module
../autoload/voom/voom_vim.py is imported, only after a Voom command is executed
for the first time.
NOTE: Directory ../autoload/voom contains VOoM Python modules.
When ../autoload/voom.vim is sourced, its Python code adds directory
../autoload/voom to sys.path and then imports "voom_vim.py" and other required
.py files. This folder will also contain .pyc files created by Python. In some
rare cases it may be necessary to delete the old .pyc files when installing a
new version.

==============================================================================
Quick Start   [[[1~
                                                 *voom-quickstart*
This Quick Start guide explains VOoM's most essential commands and principles.
For a concise list of all VOoM commands (a cheat sheet) see |voom-map|.
This guide teaches VOoM by use. You can use this help file, voom.txt, for
practice. It is organized as an outline using numbered start fold markers. You
can also practice with source files:
    ../autoload/voom.vim  or  ../autoload/voom/voom_vim.py  or even
    $VIMRUNTIME/autoload/netrw.vim  or  $VIMRUNTIME/doc/pi_netrw.txt .
Make sure not to save changes, or work with a copy of practice file.

1) CREATE OUTLINE (:Voom [markup])
----------------------------------
Open a practice file in Vim tabpage. Execute the command >
    :Voom
It will scan the current buffer for headlines and create a Tree buffer, as in
this screenshot: http://vim-voom.github.io/pics/voom_voomhelp.png
The current buffer becomes a Body buffer.

        Each VOoM Tree buffer is associated with exactly one Body buffer and
        vice versa.
        Tree buffers are 'nomodifiable' and should never be edited manually.

Press "q" in the Tree buffer to delete the outline and the Tree buffer.

        The outline is also deleted automatically whenever the Tree buffer is
        unloaded, so you can do :bun, :bd, :bw in the Tree buffer, or close
        Tree windows with "C-w c".

Create another outline with the command: >
    :Voom org
It will scan the current buffer for headlines in the Emacs Org-mode format:
lines starting with *, **, etc. Since there are no such lines, the Tree buffer
will contain only the title line. (It actually represents the node number 1,
the entire Body buffer in this case.).

Delete the wrong outline by pressing "q".
Create the correct outline again with the command :Voom .

        By default, the command :Voom without an argument creates the outline
        from lines with {{{1, {{{2, etc. The actual fold marker string is
        obtained from window-local option 'foldmarker'.
        To outline headlines in another format, an argument must be provided.
        For example, download AsciiDoc user guide from
        http://asciidoc.org/userguide.txt
        Open it Vim and execute
            :Voom asciidoc
        There is an argument completion: you can type "Voom a" and press <Tab>
        or <C-d>.
        Download reStructuredText user guide from
        http://docutils.sourceforge.net/docs/ref/rst/restructuredtext.txt
        Open it Vim and execute
            :Voom rest
        Download Panoc user guide from
        https://raw.githubusercontent.com/jgm/pandoc/master/README
        Open it Vim and execute
            :Voom pandoc

2) SWITCHING BETWEEN TREE AND BODY BUFFERS (<Return> and <Tab>)
---------------------------------------------------------------
Since we are dealing with a two-pane outliner, it is important to have keys for
quick switching between the two panes. By default such keys are Normal mode
<Return> and <Tab> keys. (One may choose other keys, see |voom-shuttle-keys|)

<Return> (also known as <CR> or <Enter>) selects the node under the cursor and
then cycles between the corresponding Tree and Body windows. So, to select
another node, move to it with h, j, etc. and hit Return.

<Tab> simply cycles between Tree and Body windows without selecting new nodes.

Exercise:
- Make sure you are in Normal mode. Press <Tab> a few times. Stop when you are
  in the Tree window.
- Jump to the last line/node by pressing "G".
- Press <Return> once. The corresponding (last) node will be shown in the Body
  window, but the cursor will stay in the Tree window.
- Press <Return> again. The cursor will move to Body window. Subsequent presses
  of <Return> will shuttle the cursor between the Tree and Body.
- See what happens after you move to different regions of the Body buffer and
  press <Return> a few times.

        <Return> and <Tab> are the only keys that get mapped in Body buffers.
        All other VOoM mappings and most commands are for Tree buffers only.

        Whenever you need to do something with an outline, first make sure you
        are in Normal mode, then switch to the Tree buffer by pressing Tab or
        Return.
        The Tree buffer can be viewed as a custom Vim mode -- Outliner mode.
        Vim's Normal and Visual mode commands that modify text are changed in
        the Tree buffer to navigate and edit the outline structure. For
        example, "dd", instead of deleting a line, deletes a node and its
        subnodes.

        You can also use all standard Vim command to handle Tree and Body
        windows (|windows|): split them with :split, resize and reposition them
        with <C-w> commands, etc.
        Example: to duplicate the current outline in another tabpage, execute
        ":tab split" while in a Tree or Body buffer and then press <Return>.

3) OUTLINE NAVIGATION (<Space>, Arrow Keys, Mouse)
--------------------------------------------------
<Space> in the Tree buffer expands/contracts the node under the cursor without
selecting it. Standard Vim folding command (zo, zc, zR, zM, etc.) also
expand/contract nodes.

One can navigate the outline with only <Space>, <Return> and <Tab>:
move between Tree lines with j, k, H, M, L, etc.;
press <Space> to expand/contract branches if needed;
press <Return> and <Tab> to select nodes and to switch between Tree and Body.

<Up>, <Down>, <Left>, <Right> arrow keys move around the Tree and select nodes
(Normal mode).

The Left Mouse Click in the Tree window selects the node under mouse. If the
click is outside of the headline text, the node's expanded/contracted status is
toggled. This means the outline can be browsed with the mouse alone. This of
course requires mouse support (GUI Vim, :set mouse=a).

Tree buffers have many other mappings for outline navigation. For example, "P"
moves the cursor to the parent node. See |voom-map| for a complete list.

        Most VOoM mappings are for Normal mode. Some also work in Visual mode.
        Very few accept a count. You should always leave Insert mode if you
        need to work with an outline.

4) EDIT HEADLINES AND NODES ("i", "I")
--------------------------------------
Press "i" in the Tree buffer (Normal mode) to edit the headline of node under
the cursor. The cursor is moved into the Body window, placed on the first line
of the corresponding node and usually on the first character of the headline
text. Modify the headline text and go back into the Tree (Tab or Return): the
outline will be updated automatically.

Press "I" in the Tree buffer to go to the last Body line of the corresponding
node. This is useful when you want to append text to a node or view the end of
a long node.

To add (insert) a new headline: press "aa" or "AA" in the Tree buffer.

        As you can see, we don't actually edit the text of headlines or nodes.
        We edit the corresponding lines in the Body buffer, then switch back to
        the Tree buffer and let VOoM update the outline.
        The outline is always updated automatically on entering the Tree
        buffer (via BufEnter autocmd).

5) OUTLINE OPERATIONS
---------------------
To rearrange the outline structure, one must first move into the Tree buffer
(press Tab or Return). The following Tree mappings work on the node under the
cursor when in Normal mode, or on a range of sibling nodes when in Visual mode.

<C-Up>, <C-Down> move nodes Up/Down.
<C-Left>, <C-Right> move nodes Left/Right (promote/demote).
The above CTRL mapping may not be recognized in a terminal. One can also move
nodes Up/Down/Left/Right via two-key mappings:
    ^^  __  <<  >> 
or via LocalLeader mappings:
    <LocalLeader>u  <LocalLeader>d  <LocalLeader>l  <LocalLeader>r

"yy" copies nodes into the "+ register (system clipboard).

"dd" deletes nodes and copies them into the "+ register.

"pp" pastes nodes from the "+ register below the current node or fold.
One can move nodes over a long distance by cutting them with "dd", moving to a
new location, and pasting them with "pp".

Outline commands started in Visual mode always end in Visual mode. Paste ("pp")
ends in Visual mode if the pasted region contains >1 nodes. This makes it easy
to apply several commands to the same range of nodes. For example, there is no
command Paste-As-Child. Instead, one can always do "pp" followed by ">>".

To undo the most recent outline operation, switch to the Body buffer (press
Tab or Return) and do undo ("u").
Exercise:
- Select all lines/nodes in the Tree buffer except the first title line: 2GVG .
- Press "dd" to delete all selected nodes.
- Go to Body buffer (Tab or Return).
- Press "u" to undo.
- Go back to Tree (Tab or Return).

6) :Voomlog
-----------
The command :Voomlog creates the __PyLog__ buffer and redirects Python's stdout
and stderr to it. Examples: >
    :Voomlog
    :py assert 2==3
    :py print u"\u042D \u042E \u042F"
    :py import this
To delete the __PyLog__ buffer and restore Python's original stdout and stderr,
do :bun, :bd, or :bw .


==============================================================================
# ALL MAPPINGS & COMMANDS #   [[[1x=  ~
                                                 *voom-map*
------------------------------------------------------------------------------
    MAIN COMMANDS ~
------------------------------------------------------------------------------
:Voom [MarkupMode]  Create the outline for the current buffer. |voom-Voom|
:Voomhelp           Open voom.txt as an outline in a new tabpage. |voom-Voomhelp|
:Voomexec [vim|py]  Execute node or fold as [type] script. |voom-Voomexec|
:Voomlog            Create __PyLog__ buffer. |voom-Voomlog|

------------------------------------------------------------------------------
    SHUTTLE KEYS (BODY AND TREE BUFFERS) ~
------------------------------------------------------------------------------
                    These two keys shuttle the cursor between the corresponding
                    Tree and Body windows.
                    These are the only keys that get mapped in Bodies.
                    Body: Normal mode. Tree: Normal and Visual modes.
                    Configurable by the user, see |voom-shuttle-keys|.

<Return>            Select the node under the cursor. If already selected, move
                    the cursor to Tree or Body window. A Tree or Body window is
                    created in the current tabpage if there is none.

<Tab>               Move the cursor to Tree or Body window.


------------------------------------------------------------------------------
    OUTLINE NAVIGATION (TREE BUFFER) ~
------------------------------------------------------------------------------
<LeftRelease>       Mouse left button click. Select the node under mouse.
                    Toggle node's expanded/contracted state if the click is
                    outside of headline text. (N)
<2-LeftMouse>       Mouse left button double-click. Disabled.

<Up>                Move the cursor Up and select new node. (N)

<Down>              Move the cursor Down and select new node. (N)

<Right>             Move the cursor to the first child and select it. (N)
                    If the current node is contracted, it is expanded first.

<Left>              Move the cursor to the parent and select it. (N)
                    If the current node is expanded, it is contracted first.

------------------------------------------------------------------------------
    EXPAND/CONTRACT NODES
------------------------------------------------------------------------------
<Space>             Expand/contract the current node (node under the cursor). (N)

O                   Recursively expand the current node and its siblings. (N)
                    Recursively expand all nodes in Visual selection. (V)
                    Similar to |zO|.

C                   Recursively contract the current node and its siblings. (N)
                    Recursively contract all nodes in Visual selection. (V)
                    Similar to |zC|.

zc, zo, zM, zR, zv, etc.
                    These are Vim's standard folding commands.
                    They expand/contract nodes (|fold-commands|).
                    Note: zf, zF, zd, zD, zE are disabled.

------------------------------------------------------------------------------
    MOVE THE CURSOR TO ANOTHER NODE (in addition to j, k, H, M, L, etc.)
------------------------------------------------------------------------------
o                   Down to the first child of the current node (like |zo|). (N)

c                   Up to the parent node and contract it (like |zc|). (N)
P                   Up to the parent node. (N)

K                   Up to the previous sibling.   (N,V,count)
J                   Down to the next sibling.     (N,V,count)

U                   Up to the uppermost sibling.  (N,V)
D                   Down to the downmost sibling. (N,V)

=                   Put the cursor on the currently selected node. (N)

------------------------------------------------------------------------------
    GO TO SPECIALLY MARKED NODE |voom-special-marks|
------------------------------------------------------------------------------
x                   Go to next marked node (find headline marked with "x"). (N)
X                   Go to previous marked node. (N)

+                   Put the cursor on the startup node (node with "=" mark in
                    Body headline). Warns if there are several such nodes. (N)

------------------------------------------------------------------------------
    SHOW (ECHO) INFORMATION FOR NODE UNDER THE CURSOR
------------------------------------------------------------------------------
s                   Show Tree headline (text after the first '|'). (N)
S                   Show UNL. Same as :Voomunl (|voom-Voomunl|). (N)


------------------------------------------------------------------------------
    OUTLINE OPERATIONS (TREE BUFFER) ~
------------------------------------------------------------------------------
i                   Edit the first line (headline) of the current node. (N)
I                   Edit the last line of the current node. (N)

aa  <LocalLeader>a
                    Add a new node after the current node or fold. (N)

AA  <LocalLeader>A
                    Add a new node as the first child of the current node. (N)

R                   Switch to Body buffer, select the line range corresponding
                    to the current node or to nodes in Visual selection. (N,V)

^^  <C-Up>  <LocalLeader>u
                    Move node(s) Up. (N,V)

__  <C-Down>  <LocalLeader>d
                    Move node(s) Down. (N,V)

<<  <C-Left>  <LocalLeader>l
                    Move node(s) Left, that is  Promote. (N,V)
                    By default, this is allowed only if nodes are at the end of
                    their subtree, see |g:voom_always_allow_move_left|.

>>  <C-Right>  <LocalLeader>r
                    Move node(s) Right, that is Demote. (N,V)

yy                  Copy node(s). (N,V)

dd                  Cut node(s).  (N,V)

pp                  Paste node(s) after the current node or fold. (N)

                    NOTE: By default, Copy, Cut, Paste use the "+ register if
                    Vim  has clipboard support, the "o register otherwise.
                    See |g:voom_clipboard_register|.

------------------------------------------------------------------------------
    SORT |voom-sort|
------------------------------------------------------------------------------
:VoomSort [options] Sort siblings of node under the cursor.
                    Options are: "deep" (also sort all descendant nodes),
                    "i" (ignore-case), "u" (Unicode-aware), "r" (reverse-sort),
                    "flip" (reverse), "shuffle" (randomize).

:[range]VoomSort [options]
                    Sort siblings in the [range]. The start and end range lines
                    must be different.

------------------------------------------------------------------------------
    MARK/UNMARK |voom-special-marks|
------------------------------------------------------------------------------
<LocalLeader>m      Mark node(s): add "x" to Body headlines. (N,V)

<LocalLeader>M      Unmark node(s): remove "x" from Body headlines. (N,V)

<LocalLeader>=      Mark node as startup node: add "=" to Body headline and
                    remove "=" from all other headlines. When cursor is on
                    Tree line 1, all "=" marks are removed. (N)

------------------------------------------------------------------------------
    SAVE/RESTORE TREE BUFFER FOLDING |voom-tree-folding|
------------------------------------------------------------------------------
:[range]VoomFoldingSave
                    Save Tree folding (writes "o" marks in Body headlines).

:[range]VoomFoldingRestore
                    Restore Tree folding (reads "o" marks in Body headlines).

:[range]VoomFoldingCleanup
                    Cleanup "o" marks: remove them from nodes without children.

<LocalLeader>fs     Save Tree folding for the current node and all descendant
                    nodes. Same as :VoomFoldingSave. (N)

<LocalLeader>fr     Restore Tree folding for the current node and all descendant
                    nodes. Same as :VoomFoldingRestore. (N)

<LocalLeader>fas    Save Tree folding for entire outline.
                    Same as :%VoomFoldingSave. (N)

<LocalLeader>far    Restore Tree folding for entire outline.
                    Same as :%VoomFoldingRestore. (N)


------------------------------------------------------------------------------
    SEARCH NODES (Body and Tree buffers) ~
------------------------------------------------------------------------------
:Voomunl            Display node's UNL (Uniform Node Locator). |voom-Voomunl|

:Voomgrep [pattern(s)]
:Voomgrep {pattern1} and *{pattern2} not {pattern3} not *{pattern4} ...
                    Search the outline for pattern(s) and display UNLs of nodes
                    with matches in the quickfix window.
                    Patterns are separated by words "and"/"not" to indicate
                    Boolean AND/NOT search.
                    An "*" in front of a pattern triggers hierarchical search.
                    If no patterns are provided, the word under the cursor is used.
                    |voom-Voomgrep|

------------------------------------------------------------------------------
    QUIT (DELETE), TOGGLE OUTLINE ~
------------------------------------------------------------------------------
                    (see |voom-quit|)
q                   Delete outline. (Tree buffer Normal mode mapping)
:Voomquit           Delete outline. (Tree or Body buffer)
:VoomQuitAll        Delete all VOoM outlines. (any buffer)
:VoomToggle [MarkupMode]
                    Create outline if current buffer is a non-VOoM buffer.
                    Delete outline if current buffer is a Tree or Body buffer.
:Voomtoggle         Minimize/Restore Tree window. (Tree or Body)

------------------------------------------------------------------------------
    VARIOUS ~
------------------------------------------------------------------------------
Voominfo [all]      Print information about the current outline and VOoM
                    internals. Uses Python "print" function. (any buffer)

<LocalLeader>e      Execute node. Same as :Voomexec. Tree buffer only. (N)

The following commands are intended for VOoM development and are created only
if there exists variable "g:voom_create_devel_commands". (any buffer)
VoomReloadVim       Reload ../autoload/voom.vim . Outlines are preserved.
VoomReloadAll       Wipe out all outlines (same as :VoomQuitAll), wipe out
                    PyLog buffer, reload VOoM code: delete Python voom_*
                    modules from sys.modules, reload ../autoload/voom.vim ,
                    re-import ../autoload/voom/voom_vim.py .
 

==============================================================================
Options   [[[1~
                                                 *voom-options*
This section describes VOoM options and other means of VOoM customization.

VOoM options are Vim global variables that can be defined by users in their
.vimrc files. Example: >
    let g:voom_tree_placement = "top"
    let g:voom_tree_height = 14

Note that changing some options requires Vim restart.

==============================================================================
Window positioning [[[2~

g:voom_tree_placement   ~
    Where Tree window is created: "left", "right", "top", "bottom"
    This is relative to the current window.
    Default: "left"
    Example: >
        let g:voom_tree_placement = "right"

g:voom_tree_width   ~
    Initial Tree window width.
    Default: 30
    Example: >
        let g:voom_tree_width = 40

g:voom_tree_height   ~
    Initial Tree window height.
    Default: 12
    Example: >
        let g:voom_tree_height = 15

g:voom_log_placement   ~
    Where __PyLog__ window is created: "left", "right", "top", "bottom"
    This is far left/right/top/bottom.
    Default: "bottom"
    Example: >
        let g:voom_log_placement = "top"

g:voom_log_width   ~
    Initial __PyLog__ window width.
    Default: 30
    Example: >
        let g:voom_log_width = 40

g:voom_log_height   ~
    Initial __PyLog__ window height.
    Default: 12
    Example: >
        let g:voom_log_height = 15

==============================================================================
Tree/Body shuttle keys   [[[2~
                                                 *voom-shuttle-keys*
Since VOoM emulates a two-pane outliner, it's important to have keys that
shuttle the cursor between the two panes. By default, such keys are <Return>
and <Tab>. These keys are used in buffer-local mappings in Trees (Normal and
Visual modes) and in Bodies (Normal mode). Note that these are the only keys
that get mapped in Body buffer when an outline is created by the command :Voom.

The following two options allow to use keys or key combinations other than
<Return> and <Tab>:

g:voom_return_key   ~
    A key that selects the node under the cursor and, if the node is already
    selected, moves the cursor between the Tree and Body windows.
    Default: "<Return>"

g:voom_tab_key   ~
    A key that simply moves the cursor between the Tree and Body windows.
    Default: "<Tab>"

Example, use Ctrl-Return and Ctrl-Tab: >
    let g:voom_return_key = "<C-Return>"
    let g:voom_tab_key = "<C-Tab>"


Note that Normal mode <Return> and <Tab> have default meaning in Vim. <Return>
moves the cursor down. This is not very useful since "j" does almost the same
thing. <Tab>/CTRL-I in Normal mode by default goes to a newer position in the
jump list (opposite of CTRL-O, see |CTRL-I|). Thus, although tempting, mapping
<Tab> is usually a bad idea. It seems that Ctrl-Tab still works like default
<Tab>/CTRL-I, at least in GUI Vim, when <Tab> is mapped.

==============================================================================
g:voom_ft_modes, g:voom_default_mode   [[[2~
                                       *g:voom_ft_modes* *g:voom_default_mode*
By default, the :Voom command without an argument creates an outline from lines
with start fold markers with level numbers (the default mode). To outline
another format, an argument specifying the desired markup mode must be
provided. E.g., for a Markdown (MultiMarkdown) file: >
    :Voom markdown

User options "g:voom_ft_modes" and "g:voom_default_mode" change which markup
mode the command :Voom will use when it is invoked without an argument. These
variables do not exist by default, they must be created by the user in .vimrc.
Vim restart is required after these options are changed.


g:voom_ft_modes   ~
"g:voom_ft_modes" is a Vim dictionary: keys are filetypes (|ft|), values are
corresponding markup modes (|voom-markup-modes|). Example: >
    let g:voom_ft_modes = {'markdown': 'markdown', 'tex': 'latex'}
This option allows automatic selection of markup mode according to the filetype
of the source buffer. If "g:voom_ft_modes" is defined as above, and 'filetype'
of the current buffer is "tex", then the command >
    :Voom
is identical to the command >
    :Voom latex


g:voom_default_mode   ~
"g:voom_default_mode" is a string with the name of the default markup mode.
Example, if there is this in .vimrc: >
    let g:voom_default_mode = 'asciidoc'
then, the command >
    :Voom
is equivalent to >
    :Voom asciidoc
unless "g:voom_ft_modes" is also defined and has an entry for the current
filetype.


NOTE: To overide these two options, that is to force the original default mode,
specify the "fmr" mode (|voom-mode-fmr|): >
    :Voom fmr

NOTE: The name of the current markup mode, if any, is noted on the first line
of the Tree buffer. You can also run the command :Voominfo [all] to see
detailed information.

==============================================================================
g:voom_clipboard_register   [[[2~
                                                 *g:voom_clipboard_register*
By default, VOoM's copy/cut/paste operations use the "+ register (system
clipboard) to store the contents of nodes. This means outlines can be
copied/cut/pasted between different Vim instances and in other applications.
If the "+ register is not available because Vim was compiled without clipboard
support (|+clipboard|), the "o register is used instead (mnemonic: outline).

To make VOoM always use the register of your choice, add the following to
.vimrc and restart Vim: >
    let g:voom_clipboard_register = "o"
where "o" can be any a-z letter, that is one of the 26 lowercase registers, see
|registers| and |quote_alpha|.

==============================================================================
g:voom_always_allow_move_left   [[[2~
                                               *g:voom_always_allow_move_left*
By default, outline operation Move Left (<<, Ctrl-Left, <localleader>l) is
allowed only when the nodes being moved are at the end of their subtree, that
is when there are no siblings below. Suppose there is an outline: >
          |AAA
          . |BBB
          . |CCC
          . |DDD
          |EEE

Node DDD can be moved left, but individual nodes BBB and CCC cannot. To move
BBB left: 1) select nodes BBB, CCC, DDD  2) move them left 3) select CCC and
DDD and move them right. In one motion: put the cursor on BBB and press VD<<j>>
("D" extends selection to the Downmost sibling).

To always allow Move Left, add the following to .vimrc and restart Vim: >
    let g:voom_always_allow_move_left = 1

==============================================================================
Various options   [[[2~

g:voom_verify_oop   ~
    Verify outline after every outline operation (doesn't apply to :VoomSort).
    Default is 1 (enabled).
    Set to 0 to disable (NOT RECOMMENDED!!!, especially with markup modes).

    This option turns on outline verification after most outline operations.
    It will alert to outline corruption, which is very likely if there is a bug
    in outline operation. The downside is that there is a performance hit,
    usually noticeable only with large outlines (>1000 headlines).
    NOTE: Do not disable this option when using complex outlining modes like
    "rest", "latex", "python" -- these markups have intrinsic problems.


g:voom_rstrip_chars_{filetype}   ~
    NOTE: Not applicable when a non-default markup mode is used
    (|voom-markup-modes|).
    This variable must be created for each 'filetype' of interest.
    The value is a string of characters to be stripped from the right side of
    Tree headlines (from before start fold marker) when the default Tree
    headline construction procedure is used and Body has 'filetype' {filetype}.
    Usually, the chars to be stripped are comment chars, space and tab. For
    details, see node >
        OUTLINING (:Voom [markup]) -> Create Outline -> Tree Headline Text
<
    Defaults exist for filetypes "vim", "text", "help": >
        let g:voom_rstrip_chars_vim = "\"# \t"
        let g:voom_rstrip_chars_text = " \t"
        let g:voom_rstrip_chars_help = " \t"


g:voom_user_command   ~
    This option allows to execute an arbitrary user-defined command when
    autoload/voom.vim is sourced. It is a string to be executed via |execute|
    at the very end of autoload/voom.vim. It does not exist by default. This
    option is intended for loading user add-ons, see |voom-addons|.


g:voom_create_devel_commands   ~
    If this variable exists, several commands are created to help during VOoM
    development. See section "Commands" in ../autoload/voom.vim for details.


g:voom_did_load_plugin   ~
    Loading guard for ../plugin/voom.vim .

==============================================================================
Tree 'filetype'   [[[2~

When a Tree buffer is created, its 'filetype' is set to "voomtree"
When the __PyLog__ buffer is created, its 'filetype' is set to "voomlog".
Thus, users can customize these buffers (foldlevel, syntax, wrap/norwap,
list/nolist, bufhidden, etc.) via standard Vim configuration files:
    ~/.vim/ftplugin/voomtree.vim
    ~/.vim/syntax/voomtree.vim
    ~/.vim/after/ftplugin/voomtree.vim

    ~/.vim/ftplugin/voomlog.vim
    ~/.vim/syntax/voomlog.vim
    etc.

NOTE: VOoM itself does not have any of these files.
NOTE: Be careful not to break VOoM by messing with critical settings.

For example, to always set initial Tree 'foldlevel' to 1, create file
    ~/.vim/ftplugin/voomtree.vim
with line
    setl fdl=1


To modify default Tree buffer-local mappings or create new ones:
    1. Create file ftplugin/voomtree.vim .
    2. Copy relevant mappings from voom.vim function voom#TreeMap().
    3. Change {lhs} and/or {rhs}.


To customize Tree buffers differently for different markup modes and Body
filetypes, the following prototype code can be used in voomtree.vim: >

    let s:bnr = bufnr('')
    let [s:mmode, s:MTYPE, s:body, s:tree] = voom#GetModeBodyTree(s:bnr)
    if s:bnr != s:tree | finish | endif
    let s:FT = getbufvar(s:body, '&ft')
    " No markup mode (default mode) or an fmr mode.
    if s:MTYPE == 0
        " do nothing
    " 'filetype' of Body buffer.
    elseif s:FT ==# 'python'
        setl fdl=0
    " Name of markup mode.
    elseif s:mmode ==# 'wiki'
        setl fdl=3
        " Create Tree buffer-local mappings.
        nnoremap <buffer><silent> <Leader>1 :setl fdl=1<CR>
    endif
    unlet s:bnr s:FT s:mmode s:MTYPE s:body s:tree

See also |voom-addons|.

==============================================================================
Misc customization tips   [[[2~

Most VOoM commands can be mapped to key shortcuts or alias commands in .vimrc: >
    nnoremap <LocalLeader><LocalLeader> :Voom<CR>
    nnoremap <LocalLeader>n :Voomunl<CR>
    com! VM Voom markdown
    com! VMT VoomToggle markdown


To make Body headlines stand out, lines with fold markers can be highlighted.
Since I use .txt files for notes, I have the following line in .vimrc  >
    au BufWinEnter *.txt if &ft==#'text' | exe 'syn match ModeMsg /\V\.\*' . split(&fmr, ',')[0] . '\.\*/' | endif
This method is better than using syntax/text.vim because it also works when a
nonstandard foldmarker is specified on file's modeline.

==============================================================================
Relevant Vim settings   [[[2~

When working with numbered start fold markers (default markup mode and "fmr"
modes), the following Vim options determine how the outline is constructed:
    - 'foldmarker' is used to obtain the start fold marker string. There is
      rarely a reason to change this option from default, which is {{{,}}} .
    - 'commentstring' and 'filetype' affect how Tree headline text is
      constructed. For details, see node
        OUTLINING (:Voom [markup]) -> Create Outline -> Tree Headline Text

'foldmethod' for the buffer for which the command :Voom is executed should be
"marker" (:set fdm=marker). This, however, is not required to create an outline
or to use it. Outline operations do not rely on Vim folds, they use start fold
markers with levels. Other folding options (|fold-options|), such as
'foldtext', can be set according to personal preferences and are usually
'filetype'-specific.


<LocalLeader> is used to start many outline operations while in a Tree buffer.
By default, it's backslash. For example, "\d" moves nodes down. To change
<LocalLeader> to another character, assign maplocalleader in .vimrc: >
     let maplocalleader=','


'scrolloff' should be set to 0 (default) or a small number (1 or 2). This
global Vim option affects how the headline is positioned in Body window after
selecting a node in Tree window. For example, after ":set scrolloff=1", the
headline will be on the 2nd window line in Body window. A very large value can
be confusing when switching between Tree and Body windows.


Vim commands for creating and deleting folds are not very useful and are
potentially dangerous when typed accidentally. They can be disabled in .vimrc
as follows: >
     " Disable commands for creating and deleting folds.
     noremap zf <Nop>
     noremap zF <Nop>
     noremap zd <Nop>
     noremap zD <Nop>
     noremap zE <Nop>


Some color schemes (including default) use the same or similar background
colors for selected text (Visual), folded lines (Folded), and current line
(CursorLine) highlight groups. These highlight groups are used in Tree buffers
and it's better if they are easily distinguished from each other.


==============================================================================
OUTLINING (:Voom [markup])   [[[1o~

==============================================================================
Create Outline   [[[2o~
                                                 *voom-Voom*
:Voom [MarkupMode]
            Scan the current buffer for headlines, construct an indent-based
            outline from them, and display it in a specially configured,
            non-modifiable buffer called Tree buffer. The current buffer
            becomes a Body buffer.
            An optional argument specifies the format of headlines. If an
            argument is given, the markup mode defined in module
            "voom_mode_{MarkupName}.py" is used, see |voom-markup-modes|.
            There is argument completion: type ":Voom " and press <Tab> or <C-d>.
            See |g:voom_ft_modes| and |g:voom_default_mode| on how to select
            the markup mode automatically and to change the default mode.

:Voom       By default, headlines are lines a start fold marker (specified by
            option 'foldmarker') followed by a level numbers: {{{3, {{{1, etc.
            The level of each headline is set to the number after the fold
            marker. The headline text is the part before the fold marker (this
            can be customized).

            NOTE: End fold markers with levels, }}}1, }}}3, etc., are ignored
            and should not be used.

            Matching fold markers without level numbers, {{{ and }}}, are
            ignored. They are handy for folding small areas inside numbered
            folds, e.g. parts of functions. The region between {{{ and }}}
            should not contain fold markers with levels.

            For best results, Body 'foldmethod' should be "marker"
            (|fold-marker|). If this is the case, Body nodes are also folds.
            This is not required. Body buffer folding has no effect on the
            outline construction or outline operations.

NOTE: A TREE BUFFER IS NOT MODIFIABLE AND SHOULD NEVER BE EDITED DIRECTLY.
A Tree buffer has many buffer-local mappings for navigating the outline and for
performing outline operations. Most of Vim standard Normal and Visual text
change commands are either disabled or remapped.

Tree buffers are named {bufname}_VOOM{bufnr} where {bufname} and {bufnr} are
the name and number of the corresponding source buffer (Body). The 'filetype'
of Tree buffers is set to "voomtree".

A Tree buffer is displayed in a separate window which is configured to behave
as the tree pane of a two-pane outliner. Every line in a Tree buffer is
associated with a node of the corresponding Body buffer.

Each "node" is a range of Body buffer lines beginning with a headline and
ending before the next headline (or end-of-buffer). The first Tree line
(outline title) is treated as a special node number 1: it is associated with
the region from start of Body buffer to its first headline (or end-of-file); it
has zero lines if the first Body line is a headline.

When a headline is selected in a Tree window (<Return>, <Up>, <Down>, <Left>,
<Right>), the corresponding node is displayed in the Body window. A Tree buffer
has many commands for changing the outline structure of the corresponding Body
buffer: nodes can be deleted, moved, promoted, demoted, marked, etc. Obviously,
a Body buffer can be edited directly as a regular Vim buffer.

The outline data and the Tree buffer are updated automatically on entering the
Tree buffer (on |BufEnter|). The actual update happens if the Body has been
modified since the last update (when Body's |b:changedtick-variable| is
different). This update is the bottleneck that limits the size of outlines that
can be edited comfortably.

A Body buffer is not configured in any substantial way by the command :Voom.
It has only two VOoM-specific mappings: <Return> and <Tab> in Normal mode
(local to buffer). These mappings select the node under the cursor and cycle
between Body and Tree windows. These two mappings can be changed by the user
(|voom-shuttle-keys|). The user is responsible for setting all other Body
settings to his liking: folding, indenting, syntax highlighting and so on
(these are usually determined by Body 'filetype').

==============================================================================
About Fold Markers   [[[3~

(This section applies only to the default markup mode and "fmr" modes.)
The command :Voom does not create an outline of folds. It creates an outline of
start fold markers with level numbers. When Body has option 'foldmethod' set to
"marker", lines in Tree buffer also represent Body folds.

The start fold marker string is obtained from window-local option 'foldmarker'
when the outline is created by the command :Voom. For example, after >
    :set fmr=<<<,>>>
    :Voom
the outline will be created from lines with <<<1, <<<2, <<<3, etc.

Option 'foldmarker' should not be changed while working with an outline. If you
change it, make sure to recreate the outline: delete the Tree buffer and
execute the command :Voom again.

VOoM scans only for _start_ fold markers with level numbers. End fold markers
with levels and fold markers without levels are ignored. This assumes that the
user follows certain rules of using fold markers. These rules make a lot of
sense and are similar to recommendations given in Vim help (|fold-marker|).

1) Use start fold markers with levels, <<<1, <<<2, etc. to start new
   fold/node. These should correspond to important structures: parts and
   chapters in a book, functions and classes in a code.

2) DO NOT USE END FOLD MARKERS WITH LEVELS: >>>1, >>>2, etc. They are
   redundant and are hard to keep track of in a large outline.

3) Do use pairs of matching fold markers without level, <<< and >>>, to fold
   small areas of text (a screenful), such as parts of functions. Make sure
   the area doesn't contain any numbered fold markers.

Files that do have end fold markers with levels are ok for browsing with VOoM,
but outline operations will most definitely produce unintended results.
Consider the following structure: >
    node 0
        node 1   <<<1
            node 1.1 <<<2
        >>>1
    ? ? ? ?
    ? ? ? ?
        node 2   <<<1
        node 3   <<<1
Lines with ? are not part of any fold. But VOoM considers them part of node
1.1 and will move them accordingly when node 1.1 is moved. When node's level
is changed, only number after the start fold marker is updated.

==============================================================================
Special Node Marks   [[[3~
                                                 *voom-special-marks*
NOTE: Special node marks are available only when outlining start fold markers
with levels, that is in the default markup mode or an "fmr" mode (|voom-mode-fmr|).

The following characters in a Body headline immediately after the start fold
marker level number have special meaning. They are used by VOoM to indicate
node properties:
    "x"     - Node is marked. This is like a checked checkbox. "x" is also
              displayed in the second column of Tree buffer.
    "o"     - Node is opened (expanded). The corresponding Tree buffer fold
              will be opened when the outline is created by the command :Voom.
              Obviously, this applies only to nodes with children.
    "="     - Startup node. This node will be selected when the outline is
              created by the command :Voom.

Various VOoM mappings and commands read and write these special marks.

Each mark is optional, but the order must be xo= . Examples, assuming that
foldmarker is set to <<<,>>> : >
    headline <<<1xo=  --node is marked, opened, startup node
    headline <<<1xo   --node is marked, opened
    headline <<<1o    --node is opened
    headline <<<1x=   --node is marked, startup node

    headline <<<1=xo  --node is startup node, "x" and "o" are ignored
    headline <<<1 xo= --all marks are ignored

==============================================================================
~~~===--- Tree Headline Text ---===~~~   [[[3~

NOTE: This section applies only to the default markup mode (|voom-markup-modes|).

Tree headline text is constructed from the corresponding Body buffer headline.
The default procedure is to take the part before the matching fold marker and
to strip whitespace and other distracting characters. The exact procedure
depends on Body's 'filetype' and can be customized by the user. For most
filetypes, the following happens:
    - Part of the Body line before the first start fold marker with level
      number is taken.
    - Whitespace is stripped from the left side.
    - Spaces, tabs, and comment characters are stripped from the right side.
      Which chars are comment chars is determined by option 'commentstring',
      or by user option "g:voom_rstrip_chars_{filetype}", see below.
    - Leading and trailing filler chars -=~ are removed. These chars can be
      used as decorators to make headlines stand out.
    - Whitespace is stripped again on both ends.

In step 3, characters that are stripped from the right side of headline (from
before the fold marker) are determined as follows:
    - If variable "g:voom_rstrip_chars_{filetype}" exists, it's value is used.
      {filetype} here is Body's 'filetype'. Value is a string of characters to
      be stripped from the right side (Space and Tab must be included).
    - If "g:voom_rstrip_chars_{filetype}" does not exist, comment characters
      are obtained from option 'commentstring'. They, Spaces, and Tabs are
      stripped from the right side.

By default, "g:voom_rstrip_chars_{filetype}" are defined for filetypes "vim",
"text" and "help". For most source code filetypes 'commentstring' is set
correctly by the corresponding ftplugin. If not defined, 'commentstring'
defaults to /*%s*/, which makes no sense for filetypes like text and help.

So, to change what characters are stripped from the right side of Tree
headlines for particular Body filetypes, you can either set 'commentstring' or
you can define "g:voom_rstrip_chars_{filetype}" in vimrc (or in an add-on).
Example for "autohotkey" filetype, ';' is line comment char: >
        let g:voom_rstrip_chars_autohotkey = "; \t"

The above procedure can be replaced completely by a custom Python function
which returns Tree headline text. The function must be registered in Python
dictionary voom_vim.MAKE_HEAD: key is Body filetype, value is the function to
be used with this filetype. By default, this is done for "html" files (we can't
just strip <!-- characters from the right side). For other filetypes, this
should be done via an add-on. Sample add-on "custom_headlines.vim" shows how,
see comments there.

NOTE: Tree headlines are constructed by function makeOutline() or
makeOutlineH() in voom_vim.py. Markup modes use function hook_makeOutline().
You can also customize how Tree headline text is constructed by invoking an
"fmr" markup mode, see |voom-mode-fmr|. 

==============================================================================
Selected Node   [[[3~

At any moment, one node is designated as selected. It is marked by the "="
character in the Tree buffer. This is sort of like "current position" in a true
two-pane outliner.

In contrast, "current node" here means the node under the cursor. The current
node may or may not be selected.

A node is selected by pressing <Return> (Tree or Body, Normal mode), or by
selecting a new node in the Tree with arrow keys or mouse left button click.

It is possible to automatically select a node on startup. (This feature is
available only when using the default on an "fmr" markup mode.) A startup node
has character "=" in the Body headline after the level number and after
optional "x" and "o" marks (|voom-special-marks|). Tree mapping  <LocalLeader>=
inserts "=" in the current node's Body headline and removes "=" from all other
headlines. Next time, when the outline is created by the command :Voom, the
node marked with "=" will be automatically selected.

Related Tree mappings (Normal mode):
=           Put cursor on the currently selected node.
+           Put cursor on the startup node, that is the node marked with "=" in
            Body headline, if any. This will also warn if there are several
            such nodes. Mnemonic: + is Shift-=


Note: it would be nice to have current headline highlighted in the Tree buffer
(as Leo does). Sadly, Vim does not allow to apply syntax highlighting to
folded lines -- the Folded hi group overrides all other highlighting. The
current headline is easy to highlight, but it doesn't work for contracted
nodes: >
    :syn match Pmenu /^=.\{-}|\zs.*/

==============================================================================
Delete Outline   [[[2~
                                                 *voom-quit*
To delete (quit) a VOoM outline for a particular Body buffer:
unload, delete, or wipe out the corresponding Tree buffer (:bun, :bd, :bw).

You can also delete an outline by closing all corresponding Tree windows via
|CTRL-W_c|, |CTRL-W_o|, etc. This happens because Tree buffers have 'bufhidden'
set to "wipe". (If this is inconvenient, change 'bufhidden' to "hide". To do
this by default for all Tree buffers, configure filetype "voomtree": add
"setl bufhidden=hide" in file  ~/.vim/after/ftplugin/voomtree.vim or similar.)

NOTE: the outline is deleted automatically whenever the Tree buffer is unloaded.

When a VOoM outline is deleted:
    - The Tree buffer is wiped out, which obviously closes all Tree windows.
    - VOoM-specific mappings (|voom-shuttle-keys|) and autocommands are removed
      from the Body buffer. (Mappings may remain at first. They will silently
      unmap themselves the next time they are invoked.)

There are also the following convenience commands:

q                   Delete outline (Tree buffer Normal mode mapping).

:Voomquit           Delete outline if the current buffer is a Tree or Body buffer.

:VoomQuitAll        Delete all VOoM outlines. Can be executed from any buffer.

:VoomToggle [MarkupMode]
                    Create outline if the current buffer is a non-VOoM buffer.
                    (Same as the :Voom command except that cursor stays in the
                    current buffer.)
                    Delete outline if the current buffer is a Tree or Body buffer.

:Voomtoggle         Minimize/Restore Tree buffer window in the current tabpage.
                    (Tree or Body)

==============================================================================
Unloaded Body buffers   [[[3~

A buffer cannot be outlined if it is not loaded in memory. A Body buffer is
unloaded after commands :bun :bd :bw . It can also become unloaded after it is
no longer displayed in any window (this depends on Vim options 'hidden' and
'bufhidden').

If the Body buffer is not loaded, the outline is locked. The following actions
in the corresponding Tree buffer are blocked:
    - Automatic outline update on Tree BufEnter.
    - Selecting nodes.
    - All outline operations.
    - Commands :Voomgrep, :Voomunl, etc.

Everything should be back to normal once the Body buffer is loaded again.

If a Body buffer has been wiped out (:bw) it can not be loaded again. The
corresponding Tree buffer is useless and you should delete it.

One way to load an unloaded Body buffer is to execute the command :Voom in the
Tree buffer: it will create a new window, load Body there, and update the
outline. If the Body buffer no longer exists, the outline will be deleted.

==============================================================================
Custom commands for deleting outline   [[[3~

It would be convenient if the VOoM outline was automatically deleted and the
Tree buffer wiped out when the Body buffer is unloaded, deleted, or wiped out.
This is how VOoM worked prior to version 3.0. Such design turned out to be
unsafe and had to be abandoned.

The workaround is function voom#DeleteOutline([ex_command]). It can be used to
create custom commands and mappings that automatically delete the outline. This
function does the following:
    - If the current buffer is a Tree, it deletes outline (Tree is wiped out).
    - If the current buffer is a Body, it deletes outline, and then executes
      argument as an Ex command via |:execute|.
    - If the current buffer is not a VOoM buffer, it executes the argument as
      an Ex command.

The argument (a string) should be an Ex command you use most often to get rid
of buffers: "q", "bun", "bd", "bw", etc.

Example >
    nnoremap <silent> <M-w> :call voom#DeleteOutline('bw')<CR>
    com! BW call voom#DeleteOutline('bw')
Mapping ALT-w and command :BW are identical to the command :bw (wipe out the
current buffer), except that if the current buffer is a Body they also delete
the corresponding VOoM outline.

==============================================================================
Outline Navigation   [[[2o~

See |voom-map| for a list of all mappings. This section explains the basics.

------------------------------------------------------------------------------
If the mouse is enabled (GUI Vim, :set mouse=a), outline can be browsed with
the mouse alone thanks to the following Tree buffer local mappings:
<LeftRelease>
            Mouse left button click. Select the node under mouse.
            Toggle node's expanded/contracted state if the click is outside of
            headline text. (N)
<2-LeftMouse>
            Mouse left button double-click. Disabled.

------------------------------------------------------------------------------
The most essential keyboard mappings for outline navigation are:
    <Return>  -- Tree (Normal, Visual), Body (Normal)
    <Tab>     -- Tree (Normal, Visual), Body (Normal)
    <Space>   -- Tree (Normal)

<Return> and <Tab> shuttle the cursor between the corresponding Tree and Body
windows. They are the only keys mapped by the command :Voom in Body buffers.
Other keys can be used instead by defining custom "g:voom_return_key" and
"g:voom_tab_key", see |voom-shuttle-keys|.

<Return>    - In Body buffer: select the current node and show it in Tree window.
              If the current node is already selected, move the cursor to Tree window.
            - In Tree buffer: select the current node and show it in Body window.
              If Body 'foldmethod' is marker, Body folds are closed so that
              only the selected node is visible (zMzvzt).
              If the current node is already selected, move the cursor to Body window.

              If the current tabpage has no windows with the required Body or
              Tree buffer, a new window is created. Thus, hitting <Return>
              after ":tab split" will create a tabpage with a new outline view.

<Tab>       - In Body buffer: move the cursor to window with the corresponding
              Tree buffer.
            - In Tree buffer: move the cursor to window with the corresponding
              Body buffer.

The command :Voom also cycles between Tree and Body. This is like <Return> but
without selecting a new node. Commands "i" and "I" in the Tree buffer can also
be handy for jumping to the first or last line of the corresponding node in the
Body buffer.

All other mappings are for Tree buffers only.

<Space>     Toggle node's expanded/contracted state without selecting it. (N)
            If the current line is hidden in a fold (after zc or zC), it is
            made visible first.

Nodes in the Tree buffer window can be navigated with just <Return>, <Tab>,
<Space>, and standard Vim commands:
            cursor motion: j, k, H, M, L, ...
            |fold-commands|: zc, zo, zM, zR, zv, zj, zk, ...
            (note: zf, zF, zd, zD, zE are disabled in Trees)
Examples:
    - To select the first child of the current node when it's contracted:
      <Space>j<Return>
    - To recursively contract subtree of the current node: contract it with
      <Space> if it's expanded, hit VzC to close folds, hit <Space> again if
      it's become hidden.
    - To go to the parent of the current node: zckj , zcjk .
      
------------------------------------------------------------------------------
There are about 19 other mappings for easy Tree navigation, see |voom-map|.
Most of them use keys that otherwise would have been wasted because they change
text and thus have to be disabled in Tree buffers. For example, "c" and "P"
move the cursor to the parent of the current node.

Most Tree mappings are defined only for Normal mode and do not accept a count.
The exceptions are:
    - K, J, U, D in Visual mode extend Visual selection. To select all siblings
      of the current node: UVD . To expand all sibling: UVDzo .
    - K, J accept a count:  5J moves the cursor 5 siblings down.
    - O, C can operate on nodes in Visual region.

------------------------------------------------------------------------------
In addition to <Return>, the following Tree keys also select a node:
<Up> <Down> <Right> <Left> x X . All other keys just position the cursor.

Every time a node is selected, the cursor has to jump between the corresponing
Tree and Body windows in the current tabpage. Other tabpages are ignored. If
there is no window with the target buffer, a new window is created. If there
are multiple windows, previous window (^Wp) is re-used if possible.

==============================================================================
:Voomunl   [[[3~
                                                 *voom-Voomunl*
:Voomunl    This commands displays UNL (Uniform Node Locator) of node under
            the cursor. The UNL string is also copied into the "n register.

The current buffer must be a Tree or a Body. If the current buffer is a Body,
the outline data and the Tree will be updated if needed.

The term UNL is from Leo's unl.py plugin:
    http://leoeditor.com/plugins.html#unl-py
An UNL is like a path to the node. It lists headlines of all ancestor nodes.
Example: >
    Part 2 -> Chapter 4 -> Section 3 -> subsection 5

Related Tree mappings:
s           Show Tree headline text. (N)
S           Show UNL. Same as :Voomunl. (N)

==============================================================================
:Voomgrep   [[[3~
                                                 *voom-Voomgrep*
:Voomgrep {pattern}
            Search Body buffer for {pattern} and display results in the
            quickfix window (|quickfix|, |copen|) as a list of UNLs (Uniform
            Node Locators) of nodes with matches.

:Voomgrep
            As above, but use the word under the cursor for pattern (like when
            starting Vim search with * or #).

:Voomgrep *{pattern}
            Hierarchical search (tag inheritance): if a node contains {pattern},
            all its subnodes are automatically considered to match the pattern
            as well. In other words, the entire subtree of a matching node is a
            match.

:Voomgrep {pattern1} and {pattern2} and {pattern3} ...
            Boolean AND search. Search Body for each pattern and show nodes
            that match all patterns.

:Voomgrep not {pattern1} not {pattern2} not {pattern3} ...
            Boolean NOT search. Search Body for each pattern and show nodes
            that do not match any of the patterns.

:Voomgrep {pattern1} and *{pattern2} not {pattern3} not *{pattern4} ...
            Boolean AND/NOT, hierarchical searches can be combined in any order.

The current buffer must be a Tree or a Body. If the current buffer is a Body,
the outline data and the Tree are updated if needed. Searches are always
performed in Body buffer. If the current buffer is a Tree buffer, the cursor
moves to a window with the corresponding Body buffer.

For each pattern, function |search()| is called to search the entire Body
buffer, from top to bottom. According to docs, options 'ignorecase',
'smartcase' and 'magic' apply.

The :Voomgrep command terminates after >500000 matches are found while
searching for a pattern. This is to avoid getting stuck after trying something
like ":Voomgrep ." in a 10 MB file. One may also terminate search with CTRL-C .

The results are displayed in the quickfix window (|copen|) as a list of UNLs.
For example, after executing >
    :Voomg Spam and ham not bacon
in "test_outline.txt" the quickfix window will display: >

     test_outline.txt [D:\SCRIPTS\VOoM\VOoM_extras\test_outlines], b1
     :Voomgrep  Spam {34 matches}  AND ham {6 matches}  NOT bacon {5 matches}
    |149| N46:28|tests -> Voomgrep tests -> n46 lunch
    |156| N47:2 |tests -> Voomgrep tests -> n47 dinner

The numbers between || are:
    - Body line number of the first match in this node. <Return> or mouse
      double-click moves the cursor to this line in the Body buffer.
    - Node number, that is the corresponding Tree line number.
    - The total number of matches in this node for all AND patterns.

To do a hierarchical search, add "*" in front of a pattern.
Example: >
    :Voomgrep *Spam not *HAM
Each node in the results is such that
    a) It or some of its ancestor nodes contains "Spam".
    b) Neither it nor any of its ancestor nodes contains "HAM".
Nodes included by inheritance may not contain all AND matches. Such nodes have
"n" instead of "N" before the node's number in the quickfix window.
Hierarchical searhes are handy when working with markups that have tag
inheritance: http://orgmode.org/org.html#Tag-inheritance .


PATTERNS AND BOOLEAN OPERATORS:

    - There is no OR operator. Use \| instead, see |\bar|.

    - Patterns should not span several lines. Multi-line patterns are likely
      to produce meaningless results because they can span several nodes.

    - Operators AND and NOT that separate patterns are not case sensitive:
      they can be "and", "AND", "not", "NOT", "aND", etc.

    - Whitespace around each pattern and around AND and NOT is ignored.
      Use "\s", "\t", "[ ]", "\%x20" to specify leading or trailing
      whitespace.

    - Operators AND/NOT should not be concatenated. The command
        :Voomgrep ham and not bacon
      searches for "ham" AND "not bacon".

    - To include literal words "and" or "not" in a pattern: >
        :Voomgrep Spam and\ ham not\ bacon
        :Voomgrep Spam[ ]and ham[ ]not bacon
<
    - Patterns separated by AND and NOT are treated independently.
      Switches like \c, \v, \m, \zs, etc. affect only one pattern. For
      example, to do case-insensitive search for nodes with ham and spam: >
        :Voomgrep \cham and \cspam
<
If the search was successful, all AND patterns are copied into the search
register "/ and added to the search history so that search highlight and
commands n, N, etc. can be used. NOTE: This does not always work correctly with
multiple AND patterns because they have to be combined into one pattern:
    - A "\c" or "\C" switch in one AND pattern will be applied to all AND
      patterns. If both "\c" and "\C" are present, "\c" wins.
    - Possibly some other complex regexps might be problematic.
You can get the pattern used for search and highlight after :Voomgrep by
pressing /<Up> .

NOTE: The command :Voomgrep slightly modifies the default look of the quickfix
window for better readability -- buffer name is removed, syntax highlighting is
tweaked. These changes are lost when the quickfix list is reloaded (:colder,
:cnewer, etc.)


==============================================================================
Outline Operations   [[[2o~

Outline operations are always performed in a Tree buffer via buffer-local
mappings or commands.

When appropriate, operations are automatically applied to subtrees, that is to
top-level nodes and all their descendant nodes. E.g., moving a node moves the
node and all its descendants, the levels are adjusted for all descendants.

Most operations can be performed on a range of sibling nodes in Visual
selection. The range is checked for being a valid range: levels (indents) of
nodes in the range must not exceed the level of the topmost node in the range.

When nodes are moved after a folded subtree, they are inserted after the fold,
that is after the visible node. This behavior should be intuitive and similar
to the behavior of most outliner programs, as well as of Vim folds.

Most outline operations usually modify the corresponding Body buffer. Thus,
they are disabled if the Body is 'nomodifiable' or 'readonly'. The exceptions
are Copy and some other commands that never modify Body buffers.

An outline operation can be undone with one undo command in the corresponding
Body buffer.

==============================================================================
Edit Headline, Edit Last Line   [[[3~

i                   Edit headline, that is the first Body line of node under
                    the cursor. The cursor is moved into a window with the Body
                    buffer and placed on the first line of the corresponding
                    Body node. Usually, the cursor will be positioned at the
                    start of the headline text and on the first word character
                    (|\<|). Note that in some markups (reST, AsciiDoc) the
                    actual headline can be a few lines down.

I                   Edit the last Body line of node under the cursor.

These Normal mode commands do not modify the Body buffer. They only move the
cursor from the Tree to the corresponding Body line. They can also be used
instead of <Return> or <Tab> (|voom-shuttle-keys|) for browsing an outline.

==============================================================================
Add New Headline   [[[3~

aa  <LocalLeader>a
                    Add a new node after the current node. If the current node
                    is folded, the new node is added after the fold.
AA  <LocalLeader>A
                    Add a new node as the first child of the current node.

                    (Mnemonic: Add Another node.)

These Tree buffer Normal mode mappings add (insert) a new headline in the Body
buffer. The format of new headlines is determined by the current markup mode.
The text is always "NewHeadline". The cursor is moved into the Body window and
placed on "NewHeadline" which then can be edited ("caw", "caW").

It is often easier to create new headline(s) by editing the Body buffer
directly. I wrote a simple plugin that helps with inserting numbered fold
markers: http://www.vim.org/scripts/script.php?script_id=2891

==============================================================================
Select Body Region   [[[3~

R                   Move the cursor from Tree to Body buffer and select the
                    line range corresponding to node under the cursor (Normal
                    mode) or to all nodes in Visual selection (Visual mode).

This Tree buffer mapping is handy when you want to apply :substitute or some
other range-accepting Vim command to a single node or a group of nodes. The
command deals with individual nodes, not subtrees. Mnemonic: Range, Region.

==============================================================================
Move, Copy, Cut, Paste [[[3~

^^  <C-Up>  <LocalLeader>u
                    Move node(s) up. (N,V)

__  <C-Down>  <LocalLeader>d
                    Move node(s) down. (N,V)

<<  <C-Left>  <LocalLeader>l
                    Move node(s) left, that is promote. (N,V)
                    By default, this is allowed only if nodes are at the end of
                    their subtree, see |g:voom_always_allow_move_left|.

>>  <C-Right>  <LocalLeader>r
                    Move node(s) right, that is demote. (N,V)

yy                  Copy node(s) to the "+ register. (N,V)

dd                  Cut node(s) and copy contents to the "+ register. (N,V)

pp                  Paste node(s) from the "+ register after the current node
                    or fold. (N)
                    The clipboard is checked for being a valid VOoM outline:
                    the first line in the clipboard must be a headline
                    according to the current markup mode.

With the exception of Paste, these Tree buffer mappings are available in
Normal and Visual modes. In Visual mode the range is checked for being valid:
top nodes in the range must be siblings.

These commands always apply to subtrees, that is to top-level nodes and all
their descendant nodes, even when only a part of subtree is selected.

By default, commands Cut, Copy, Paste use the "+ register, that is the system
clipboard (|registers|, |quote+|). This means you can move nodes between
outlines in different instances of Vim, or copy/paste in other applications.
If the "+ register is not available because Vim was compiled without clipboard
support, the "o register is used instead.
You can choose another register, see |g:voom_clipboard_register|.

==============================================================================
Sort Outline   [[[3~
                                                 *voom-sort*
The command :VoomSort sorts sibling nodes according to their Tree headline text
(string after character | in Tree buffer). Nodes are siblings if they have the
same level and the same parent. This command must be executed in a Tree buffer.

:VoomSort           Sort siblings of the current node (node under the cursor).
                    Headlines are sorted by byte value, in ascending order.

:[range]VoomSort    Sort siblings in the range. Start and end range lines must
                    be different (|[range]|).
                    Note that if the range is actually one line, all siblings
                    of the node at that line are sorted. E.g.,
                        :57,57VoomSort
                        :57VoomSort
                    sorts siblings of node at Tree line 57.

:VoomSort [options]
:[range]VoomSort [options]
                    Sort according to options. Options are any combination of
                    the following words, separated by whitespace:
                             deep, i, u, r, flip, shuffle.
    OPTIONS:

    deep            Deep (recursive) sort. Sort top-level siblings and siblings
                    of their descendants. When the cursor is on the 2nd Tree
                    line (first headline) and no range is given, entire outline
                    is sorted.

    i               Ignore-case. Case-insensitive sort. Without the "u" option
                    this should affect only A-Za-z letters. To handle other
                    letters, include the "u" option.

    u               Unicode-aware sort. Convert headlines to Python Unicode
                    strings before sorting. This option is probably needed only
                    for case-insensitive sorts.

    r               Reverse-sort, sort in descending order.

    flip            Reverse the order of nodes without sorting anything.

    shuffle         Shuffle nodes randomly.


Example 1, perform deep sort, ignore-case, Unicode-aware: >
    :VoomSort deep i u

Example 2, sort siblings in Visual selection: >
    :'<,'>VoomSort
NOTE: make sure at least 2 lines are selected. Otherwise, the range contains
only one line, which means all siblings of the selected line will be sorted.


Sorting and reverse-sorting do not change the relative order of nodes with
equal headlines.

Options "r", "flip", "shuffle" cannot be combined.


It is easy to create custom commands that perform sorting with a particular set
of options. For example, if you often do case-insensitive, non-recursive sort
you can add the following line to .vimrc: >
    com! VoomSortI call voom#OopSort(line('.'), line('.'), 'i u')
The command :VoomSortI will be identical to ":VoomSort i u".
It does not accept a range. To make it work with a range: >
    com! -range VoomSortI call voom#OopSort(<line1>, <line2>, 'i u')

==============================================================================
Mark or Unmark Nodes   [[[3~

NOTE: These commands are only available when working with numbered start fold
markers, that is in the default markup mode or an "fmr" mode (|voom-mode-fmr|).

Marking a node is like checking a checkbox. A node is marked/unmarked by
adding/removing "x" in the Body headline after the start fold marker level
number (|voom-special-marks|). The "x" is also displayed in the Tree.

<LocalLeader>m      Normal mode: mark node under the cursor.
                    Visual mode: mark all nodes in the range.
                    "x" is inserted in Body headlines. (N,V)

<LocalLeader>M      Normal mode: unmark node under the cursor.
                    Visual mode: unmark all nodes in the range.
                    "x" is removed from Body headlines. (N,V)

The above commands apply to individual nodes only, not to their descendants.

To unmark all: ggVG<LocalLeader>M

Related Tree mappings, Normal mode:
x                   Go to next marked node and select it.
X                   Go to previous marked node and select it.

==============================================================================
Mark Node As Startup Node   [[[3~

NOTE: These commands are only available when working with numbered start fold
markers, that is in the default markup mode or an "fmr" mode (|voom-mode-fmr|).

<LocalLeader>=      Mark the current node as startup node. (N)

This command inserts character "=" in Body headline after the start fold marker
level number and after optional "x" and "o" marks (|voom-special-marks|). The
"=" mark is removed from all other Body headlines.  If current line is the
first Tree line (outline title), "=" are removed from all Body headlines.

The "=" mark affects only Voom startup: last node marked with "=" is selected
when the outline is created for the first time by the command :Voom.

Related Tree mappings, Normal mode:
+                   Put cursor on the startup node, if any. Warn if there are
                    several such nodes. Mnemonic: + is Shift-=

==============================================================================
Save or Restore Tree Folding   [[[3~
                                                 *voom-tree-folding*
NOTE: These commands are only available when working with numbered start fold
markers, that is in the default markup mode or an "fmr" mode (|voom-mode-fmr|).

Opened/closed folds in a Tree buffer are equivalent to expanded/contracted
nodes. VOoM allows to save and restore Tree buffer folding. To do this, it
relies on special marks in Body headlines: character "o" immediately after the
start fold marker level number or after optional "x" (|voom-special-marks|).
The "o" mark indicates that the fold is opened. Such folds are opened
automatically on startup. (This help file uses "o" marks.)

The following commands execute only in a Tree buffer. They read and write "o"
marks in Body headlines.

:[range]VoomFoldingSave
                    Save Tree folding by writing "o" marks in Body headlines.
                    If a range is supplied, this is done for individual nodes
                    in the range. Without a range, this is done for the current
                    node and all descendant nodes.

:[range]VoomFoldingRestore
                    Restore Tree folding according to "o" marks in Body
                    headlines. If a range is supplied, this is done for
                    individual nodes in the range. Without a range, this is
                    done for the current node and all descendant nodes.

:VoomFoldingCleanup
                    Cleanup "o" marks: remove them from nodes without
                    children. Such marks are redundant but harmless, they
                    don't do anything. This is done for the entire outline,
                    even if a range is supplied.

To save or restore folding for the entire outline: >
    :%VoomFoldingSave
    :%VoomFoldingRestore

There as also the following Tree buffer mappings, Normal mode:

<LocalLeader>fs     Save Tree folding for the current node and all descendant
                    nodes. Same as :VoomFoldingSave.

<LocalLeader>fr     Restore Tree folding for the current node and all descendant
                    nodes. Same as :VoomFoldingRestore.

<LocalLeader>fas    Save Tree folding for the entire outline.
                    Same as :%VoomFoldingSave.

<LocalLeader>far    Restore Tree folding for the entire outline.
                    Same as :%VoomFoldingRestore.

Mnemonics for mappings: Foldins Save/Restore, Folding All Save/Restore.

==============================================================================
MARKUP MODES   [[[2o~
                                                 *voom-markup-modes*
By default, the command :Voom creates the outline from lines with start fold
markers with levels: {{{1, {{{2, etc. If a buffer uses a different markup for
headlines, it is necessary to specify the markup mode. For example, command >
    :Voom MySuperDuperWiki
will try to create the outline using MySuperDuperWiki markup mode.

A markup mode is defined in a Python module named "voom_mode_{MarkupName}.py".
Such module is usually located in Vim folder autoload/voom, but it can also be
placed anywhere in the Python search path. The above command will try to import
module "voom_mode_MySuperDuperWiki.py", which should modify VOoM's core code
when handling this particular outline to accommodate the idiosyncrasies of the
MySuperDuperWiki markup language.

One may use argument completion to list all markup modes present in folder
../autoload/voom : type ":Voom " and press <Tab> or <C-d>.

The name of the current markup mode, if any, is noted on the first line of the
Tree buffer. Execute the command ":Voominfo [all]" to see more details.

It is easy to create an alias command or a mapping identical to the above
command (:Voom MySuperDuperWiki)  >
    :com! Voow call voom#Init("MySuperDuperWiki")
or, if you prefer :VoomToggle behavior >
    :com! Voow call voom#Init("MySuperDuperWiki",1)
Users can also customize which markup mode the command :Voom uses when it is
invoked without an argument, see |g:voom_ft_modes| and |g:voom_default_mode|.

A fully functional markup mode will support all major VOoM commands and outline
operations. Not supported are operations that rely on special node marks,
|voom-special-marks|, unless the mode is an "fmr" mode (|voom-mode-fmr|):
    - mark/unmark nodes
    - startup node
    - save/restore Tree folding.

To customize or create a new markup mode: modify one of the existing
voom_mode_{MarkupName}.py files, save it as voom_mode_{YourName}.py, place it
in Vim folder autoload/voom or anywhere in the Python search path.

The following sections describe markup modes available by default. These modes
are fully functional unless stated otherwise.

==============================================================================
'fmr' modes   [[[3~
                                                 *voom-mode-fmr*
"fmr" modes are very similar to the default mode, that is the :Voom command
without an argument. They deal with start fold markers with level numbers and
support special node marks (|voom-special-marks|).
"fmr" modes can be used to customize how Tree headline text is constructed and
to change the format of new headlines (Insert New Node).

:Voom fmr
MODULE: ../autoload/voom/voom_mode_fmr.py
This mode changes absolutely nothing, it is identical to the default mode.
The purpose of this mode is to make possible the original default mode when
|g:voom_ft_modes| or |g:voom_default_mode| have been defined, e.g., for an
AsciiDoc file with fold markers.

:Voom fmr1
MODULE: ../autoload/voom/voom_mode_fmr1.py
Headline text is before the fold marker. This mode is identical to the default
mode except that no chars other than leading and trailing whitespace are
stripped from headlines. >
    headline level 1 {{{1
    headline level 2 {{{2

:Voom fmr2
MODULE: ../autoload/voom/voom_mode_fmr2.py
Headline text is after the fold marker: >
    {{{1 headline level 1
    {{{2 headline level 2
as seen in some Vim plugins: >
    "{{{1 my functions
    "{{{2 s:DoSomething
    func! s:DoSomething()
NOTE: If {{{'s are in the first column and |matchparen| is enabled, outline
navigation is slow. A workaround: >
    :set mps-={:}

==============================================================================
wiki   [[[3~
                                                 *voom-mode-wiki*
:Voom wiki
MODULE: ../autoload/voom/voom_mode_wiki.py
MediaWiki headline markup. This is the most common Wiki format. Should be
suitable for Wikipedia, vim.wikia.com, etc. >

    = headline level 1 =
    some text
    == headline level 2 == 
    more text
    === headline level 3 === <!--comment-->
    ==== headline level 4 ====<!--comment-->
    etc.

First = must be at the start of the line.
Closing = are required.
Trailing whitespace is ok.
Whitespace around the text is not required.

HTML comment tags are ok if they are after the headline: >
    ==== headline level 4 ==== <!--{{{4-->  
    ===== headline level 5 ===== <!--comment--> <!--comment-->


KNOWN PROBLEMS
--------------

1) Headlines are not ignored inside <pre>, <nowiki> and other special blocks.

2) Only trailing HTML comment tags are stripped.
The following valid headline is not recognized: >
    <!-- comment -->=== missed me ===

A comment inside headline is ok, but it will be displayed in Tree buffer: >
    == <!-- comment --> headline level 2 ==


REFERENCES
----------
http://www.mediawiki.org/wiki/Help:Formatting
http://www.mediawiki.org/wiki/Markup_spec
http://meta.wikimedia.org/wiki/Help:Section
http://en.wikipedia.org/wiki/Help:Section
http://en.wikipedia.org/wiki/Wikipedia:Manual_of_Style#Section_headings

==============================================================================
vimwiki   [[[3~
                                                 *voom-mode-vimwiki*
:Voom vimwiki
MODULE: ../autoload/voom/voom_mode_vimwiki.py
Headline markup used by Vimwiki plugin:
    http://www.vim.org/scripts/script.php?script_id=2226
Example: >

    = headline level 1 =
    body text
    == headline level 2 ==
    body text
           ===headline level 3===

Closing = are required.
There can be leading whitespace (centered headline).
Trailing whitespace is ok.
Whitespace around the text is not required.

KNOWN PROBLEMS
--------------
There is a conflict between mappings: VOoM and Vimwiki both create buffer-local
mappings for keys <Return> and <Tab>. When the command ":Voom vimwiki" creates
the outline, it overwrites Vimwiki's mappings for <Return> and <Tab>, and they
are not restored when the outline is deleted. You can restore original
Vimwiki's mappings with ":set ft=vimwiki". You can configure VOoM to use some
other keys, see |voom-shuttle-keys|. You can also change Vimwiki mappings, see
|vimwiki_<CR>| and |vimwiki_<Tab>| in Vimwiki's help.

==============================================================================
dokuwiki   [[[3~
                                                 *voom-mode-dokuwiki*
:Voom dokuwiki
MODULE: ../autoload/voom/voom_mode_dokuwiki.py
Mode for outlining of DokuWiki headlines:
    https://www.dokuwiki.org/
    https://www.dokuwiki.org/wiki:syntax#sectioning

Headlines typically look like this (the first = is at the start of the line): >
    ====== Headline Level 1 ======
    ===== Headline Level 2 =====
    ==== Headline Level 3 ====
    === Headline Level 4 ===
    == Headline Level 5 ==

The following applies and matches DokuWiki behavior:
    - Only 5 headline levels are possible because the format is ass-backward.
      When an outline operation wants to creates a headline with level >5, the
      level is set to 5 and a warning is echoed.
    - Trailing ='s are not important as long as there are at least 2 of them.
      Outline operations will not change trailing ='s if there are more than 6
      of them.
    - More than 6 leading ='s is allowed and means level 1.
    - One leading space is allowed at start of line before the first =, but not
      a tab or 2 or more spaces.
    - The leading space can be followed by a tab, optionally followed by any
      number of spaces/tabs.

NOTE: No attempt is made to exclude regions in which headlines should be
ignored: <code>, <nowiki>, <file>, %%, etc.

Similar mode: inverseAtx, see |voom-mode-various|.

==============================================================================
viki   [[[3~
                                                 *voom-mode-viki*
:Voom viki
MODULE: ../autoload/voom/voom_mode_viki.py
Mode for outlining Viki/Deplate headings:
    http://www.vim.org/scripts/script.php?script_id=861
    http://deplate.sourceforge.net/Markup.html#hd0010004
>
    * headline level 1
    some text
    ** headline level 2
    more text
    *** headline level 3
    **** headline level 4

The first * must be at the start of the line.
There must be a whitespace after the last * .

Headlines are ignored inside special regions other than #Region:
    http://deplate.sourceforge.net/Regions.html
    http://deplate.sourceforge.net/Regions.html#hd00110013
Special regions have the following format: >
    #Type [OPTIONS] <<EndOfRegion
    .......
    EndOfRegion

Except for ignoring special regions, this mode is identical to the org mode.

==============================================================================
org   [[[3~
                                                 *voom-mode-org*
:Voom org
MODULE: ../autoload/voom/voom_mode_org.py
Mode for outlining Emacs Org-mode headlines:
    http://orgmode.org/org.html#Headlines
>
    * headline level 1
    some text
    ** headline level 2
    more text
    *** headline level 3
    **** headline level 4

The first * must be at the start of the line.
There must be a whitespace after the last * .

==============================================================================
rest   [[[3~
                                                 *voom-mode-rest*
:Voom rest
MODULE: ../autoload/voom/voom_mode_rest.py
Mode for outlining reStructuredText (reST) section titles.
    http://docutils.sourceforge.net/rst.html
    http://docutils.sourceforge.net/docs/ref/rst/restructuredtext.html#sections
    http://docutils.sourceforge.net/docs/user/rst/quickstart.html#sections
    http://docs.python.org/devguide/documenting.html#restructuredtext-primer

For examples of reST files, click "Show Source" or similar link on the above
pages. Vim has reST syntax highlighting, do ":set ft=rst" to enable.

VOoM's reST mode conforms to the following reST specifications for headlines:
    - An underline/overline character may be any non-alphanumeric printable
      7-bit ASCII character.
    - The underline must begin in column 1 and must extend at least to the
      right edge of the title text.
    - The overline must be identical to the underline.
    - The title text may be inset only if there is an overline.
    - Trailing whitespace is always ignored.
    - The levels are assigned to adornment styles in the order they are
      encountered.

There are 64 different headline adornment styles: 32 underline-and-overline
styles, 32 underline-only styles. To customize the default order in which new
adornment styles are deployed during outline operations, you can modify the
constant AD_STYLES near the top of the module. It is a string containing
adornment styles in the order of preference.

When pasting an outline, adornment styles in the pasted text are changed to
match the styles in the destination text.

To reduce ambiguity, VOoM imposes a couple of its own restrictions on
headlines. These are not necessarily a part of reST specifications.
1) A headline must be preceded by a blank line or another headline: >

    ================
    Headline level 1
    ================
    Headline level 2
    ================
    Lorem ipsum dolor sit amet...
    ~~~~~~~~~~~~
    not headline
    ~~~~~~~~~~~~
    not headline
    ````````````

    headline level 3
    ````````````````

2) A section title cannot look like an underline/overline. Such headlines are
difficult to interpret and they cause errors during outline operations.
There are no headlines in the following example: >

    =====
    -----
    =====

    +++++
    =====

It is still possible to write such headlines by making the underline/overline
longer than the title: >

    =======
    -----
    =======

    +++++
    =======

KNOWN PROBLEMS
--------------

1) Any reST directives before a headline are part of the previous node. Thus,
it is generally not safe to move nodes in the Tree pane. For example, a section
is often preceded by a label: >

    .. _my-reference-label:

    Section to cross-reference
    --------------------------

Such node should not be moved: the label is part of the previous node and will
become separated from its headline. (Let me know if this needs to be fixed.)

2) The VoomSort operation can result in an error if the last section
(end-of-file) is not terminated with a blank line. The headline that ends up
sorted after the last node will not be preceded by a blank line and will not be
detected.
Note that there is no such problem with other outline operations--they insert
missing blank lines before headlines to prevent headline loss.

3) Outline verification can fail after an outline operation if there are
inconsistent levels, that is when node's level is incremented by >1. VOoM will
complain about different Tree lines, different levels, and force outline
update.

Example 1. Errors when moving node D up. >

    A level 1
    ===========

    B level 2
    -----------

    C level 3
    """""""""""

    D level 1
    ===========

    E level 3
    """""""""""

Example 2. Errors when moving node C left. This is because node E is also moved
left, even though it is in a different branch. >

    A level 1
    =========

    B level 2
    ---------

    C level 3
    +++++++++

    D level 1
    =========

    E level 4
    *********

==============================================================================
markdown   [[[3~
                                                 *voom-mode-markdown*
:Voom markdown
MODULE: ../autoload/voom/voom_mode_markdown.py
Mode for outlining of standard Markdown headers.
    http://daringfireball.net/projects/markdown/
    http://daringfireball.net/projects/markdown/syntax#header
    http://daringfireball.net/projects/markdown/dingus  --online demo
    http://babelmark.bobtfish.net/  --derivatives
    Vim folding and other set up for Markdown files:
        https://gist.github.com/1035030  --my version
        https://github.com/plasticboy/vim-markdown
        https://github.com/nelstrom/vim-markdown-folding
        https://github.com/tpope/vim-markdown

Related modes: |voom-mode-pandoc|, |voom-mode-hashes|.
Note: Use |voom-mode-pandoc| for Pandoc Markdown. The Pandoc mode may also be
better suited for MultiMarkdown and GitHub Flavored Markdown (GFM) because they
can have fenced code blocks:
    http://johnmacfarlane.net/pandoc/ --Pandoc
    http://fletcherpenney.net/multimarkdown/ --MultiMarkdown
    https://help.github.com/articles/github-flavored-markdown --GFM

There are two types of header styles. Both can be used in the same outline.

Underline-style, levels 1 and 2 only: >
    header level 1
    ==============

    header level 2
    --------------

Hashes-style, any level is possible: >
    # header level 1
    ## header level 2
    ### header level 3 ###

Headlines are interpreted as follows:
    - A blank line before or after a headline is optional. NOTE: Pandoc version
      of Markdown does require blank lines before headlines, unlike traditional
      Markdown. Use |voom-mode-pandoc| for Pandoc Markdown.
    - One = or - in column 1 is sufficient for underline-style.
    - Spaces after opening #'s and before closing #'s are optional.
    - Closing #'s are optional. Their number is not important.
    - The underline-style overrides hashes-style. The leading #'s are then part
      of the headline text. This matches standard Markdown behavior: >
            #### this is headline level 2, not level 4
            ------------------------------------------
<
    - A line consisting only of hashes is interpreted as a blank headline. For
      example, line "###" is blank headline at level 3. In contrast, Markdown
      interprets it as header "#" at level 2, that is <h2>#</h2>.


HOW OUTLINE OPERATIONS CHOOSE THE FORMAT OF HEADLINES
-----------------------------------------------------
When an outline operation changes headline level, it has to choose between
several possible headline formats:
    - When changing to level 1 or 2, choose underline-style or hashes-style.
    - When using hashes-style, choose to add or not to add closing hashes.
Outline operations try to keep the format of headlines consistent throughout
the current outline. The above ambiguities are resolved as follows:

    A) If possible, the headline's current style is preserved.
    Demoting headline
                 Headline
                 ========
    changes it to
                 Headline
                 --------
    Demoting "# Headline" changes it to "## Headline".
    Demoting "#Headline#" changes it to "##Headline##". And so on.

    B) When a choice must be made between underline-style and hashes-style
    (changing level from >2 to 1 or 2), the style of the first level 1 or 2
    headline in the document is used. The default (in case there are no
    headlines with level 1 or 2) is to use underline-style.

    C) When a choice must be made to add or not to add closing hashes (changing
    from underline-style to hashes-style), the style of the first hashes-style
    headline in the document is used. If it ends with "#", then closing hashes
    are added. The default (in case there are no headlines in hashes-style) is
    to add closing hashes.

    The headline format is always chosen as in B) and C) above when:
        - Inserting new headline.
        - Pasting nodes (because we may paste from another outline with a
          different style).
          As a side-effect, cutting and pasting all nodes (2GVG dd pp) converts
          all headlines into default format: underlined and with trailing #'s.

OTHER NOTES
------------
    - If a headline is not preceded by a blank line, outline operations may add
      one when headlines are moved or inserted.
    - Trailing #'s in headlines should not be considered significant: they can
      be added and removed during outline operations.

==============================================================================
pandoc   [[[3~
                                                 *voom-mode-pandoc*
:Voom pandoc
MODULE: ../autoload/voom/voom_mode_pandoc.py
Mode for outlining of Pandoc Markdown headers.
    http://johnmacfarlane.net/pandoc/
    https://github.com/jgm/pandoc
    https://github.com/vim-pandoc/vim-pandoc --Vim configuration

This mode is identical to the Markdown mode (|voom-mode-markdown|) except that
it adds several Pandoc-specific restrictions on headers:
    - A blank line is usually required before a header.
        http://johnmacfarlane.net/pandoc/README.html#headers
    - Headers are ignored inside fenced code blocks.
        http://johnmacfarlane.net/pandoc/README.html#fenced-code-blocks
    - Headers that start with "#. " are ignored, they are fancy_lists.
        http://johnmacfarlane.net/pandoc/README.html#ordered-lists

A Pandoc fenced code block starts on a line that begins with a row of 3 or more
"`" or "~". It ends on a line that is a row of "`" or "~" which is at least as
long as the starting row. (This should also be good enough for MultiMarkdown
and GitHub Flavored Markdown which denote fenced code blocks with ``` .)
Examples of fenced code blocks: >

    ~~~
    no headlines here
    ~~~

    ~~~~~~~~ python
    no headlines here
    ~~~~~~~~~~~~~~~

    ``` Any text can be here.
    no headlines here
    ```

A header or start-of-fenced-code-block must be preceded by one of the
following:
    - a blank line
    - another header
    - an end-of-fenced-code-block
This matches Pandoc's behavior: >

    # Header 1
    ## Header 2
    Header 3
    --------
    ```
    code block
    `````````
    ~~~~
    another code block
    ~~~~
    Header 4
    ========

There are no headers or fenced code blocks in the following example: >

    Lorem ipsum dolor sit amet...
    ## not a header
    not a header
    ------------

    Lorem ipsum dolor sit amet...
    ```
    not a fenced code block
    ```

Closing hashes are not adjusted during outline operations if they are followed
by a header identifier: >
    ## My header ##    {#foo}

==============================================================================
hashes   [[[3~
                                                 *voom-mode-hashes*
:Voom hashes
MODULE: ../autoload/voom/voom_mode_hashes.py
Headlines are marked by #'s. This is a subset of Markdown format (Atx-style
headers): >

    # headline level 1
    ##  headline level 2
    text
    ###headline level 3
    ### headline level 3

#'s must be at the start of the line.
A whitespace after #'s is optional.

This mode is much simpler and more efficient than the full Markdown mode
(|voom-mode-markdown|) because it does not have to deal with underlined
headlines and closing #'s.

NOTE: This mode can be easily modified to work with other Atx-style headlines:
    - To use any ASCII character as a marker instead of '#'.
    - To require a whitespace after the marker chars (as in org-mode).
    - To strip optional closing #'s.
See comments in the module file.

==============================================================================
txt2tags   [[[3~
                                                 *voom-mode-txt2tags*
:Voom txt2tags
MODULE: ../autoload/voom/voom_mode_txt2tags.py
Mode for outlining txt2tags titles.
    http://txt2tags.org/
    http://txt2tags.org/userguide/TitleNumberedTitle.html#6_2

Both Titles and Numbered Titles are recognized. Anchors are OK. >
    = title level 1 =
    == title level 2 ==[anchor-A]
    +++ numbered title level 3 +++
    +++ numbered title level 3 +++[anchor-B]

There can be leading spaces, but not tabs.
The number of = or + chars must be the same on both sides.

Titles are ignored inside Verbatim, Raw, Tagged, Comment Areas, that is between
pairs of lines of ```, """, ''', %%%.

Numbered Titles are indicated in the Tree buffer by "+" in the 2nd column to
help distinguish them from non-numbered titles.

The type of the Title (numbered or not) is preserved during outline operations.

==============================================================================
asciidoc   [[[3~
                                                 *voom-mode-asciidoc*
:Voom asciidoc
MODULE: ../autoload/voom/voom_mode_asciidoc.py
Mode for outlining of AsciiDoc Document and Section Titles.
    http://asciidoc.org/userguide.html#X17
    http://asciidoc.org/
    https://github.com/asciidoc/asciidoc
The AsciiDoc Userguide source is an example of a large and complex document:
    http://asciidoc.org/userguide.txt

Both two-line and one-line title styles are recognized and can be used in the
same outline. Document Titles, that is topmost nodes, are not treated
specially. Note that the topmost level in VOoM is level 1, not level 0 as in
AsciiDoc documentation.


Two-line style, levels 1 to 5 only: >
    Level 1
    =======

    Level 2
    -------

    Level 3
    ~~~~~~~

    Level 4
    ^^^^^^^

    Level 5
    +++++++

The underline must be of the same size as the title line +/- 2 chars.
Both the underline and the title line must be at least 2 chars long.
Trailing whitespace is always ignored and is not counted.


One-line style: >
    = Level 1 =

    == Level 2 ==

    === Level 3 ===

Closing ='s are optional: >
    = Level 1

    == Level 2

    === Level 3

There must be a whitespace between headline text and ='s. The number of closing
='s must match the number of opening ='s.
   
One-line style overrides two-line style: >
    ===== Level 5
    -------------
    listing
    -------------

When a style must be chosen during an outline operation (when changing level,
pasting, inserting new node), the style is chosen so that to preserve the
current style of the document. When that's not possible, the default is to use
two-line and to add closing ='s. See |voom-mode-markdown| for details.

In addition to Titles, the VOoM asciidoc mode is also aware of:
    - Standard Delimited Blocks. Titles are ignored inside of them.
    - Lines with [[ BlockID ]] and [ AttributeList ] preceding the title line.
See below for details.

Because AsciiDoc is a complex format, there are various edge cases and gotchas,
see below. See also file voom_samples/asciidoc.asciidoc for examples.

------------------------------------------------------------------------------
Delimited Blocks   [[[4~

Headlines are ignored inside Delimited Blocks:
    http://asciidoc.org/userguide.html#X104
A delimited block is started and ended by a line consisting of 4 or more of the
following characters: >
    ////
    ++++
    ----
    ....
    ****
    ____
    ====

Example: >
    == headline ==
    ------------------------------------
    
    == listing, not headline ==

    ------------------------------------
    == headline ==
   
Confusing cases when the start of a Delimited Block looks like an underline: >
    == headline ==
    --------------
    == listing, not headline ==
    ---------------------------

    headline
    --------
    --------
    listing, not headline
    ---------------------

------------------------------------------------------------------------------
BlockID, AttributeList   [[[4~

Section titles in AsciiDoc are often preceded by lines with attributes. Thus,
in general, it is dangerous to move nodes around--sections can become separated
from their attributes. VOoM accommodates the most common usage pattern, at
least as seen in the "userguide.txt".

A headline may be preceded by any number of [...] lines, that is lines that
start with "[" and end with "]". This allows for any number of BlockID and
AttributeList elements and in any order. Examples: >

    [[appendix_B]] 
    == Appendix B ==

    [appendix]
    == Appendix B ==

    [[appendix_B]] 
    [appendix]
    == Appendix B ==

    [appendix]
    [[appendix_B]] 
    == Appendix B ==

In such cases, the first line of the node is the topmost [[...]] or [...] line,
not the title line. This means that it is usually safe to move such nodes --
lines with the BlockId and AttributeList will stay with the section title.

NOTE: There must be no comment lines or blank lines in between.

NOTE: No attempt is made to detect any other directives, macros, etc. before
the headline. Stuff like Attribute Entries, that is lines >
    :numbered:
    :numbered!:
and other thingies as well as comments in front of the headline are part of the
preceding node.

------------------------------------------------------------------------------
Blank Lines   [[[4~

A blank separator line is usually required before a headline. The VOoM behavior
is mostly in conformance with AsciiDoc specification for Section Titles, but it
is not perfect and false negatives can occur, see Gotchas below.

NOTE: There should be no blank lines or comment lines between preceding [[...]]
and [...] lines and the title line. That is, unless you do not want them to be
treated as part of the headline.

Wrong: >
    == headline ==
    text
    == not headline ==

Correct: >
    == headline ==
    text

    == headline ==

In the following example the second underline starts Delimited Block: >
    headline
    --------
    text
    not headline
    ------------

    not headline
    ------------

Comment lines are OK, the check for a preceding blank line ignores them: >
    == headline 1 ==
    text
    // comment
    == not headline ==

    // comment
    == headline 2 ==
    text

    // comment
    // comment
    == headline 3 ==


A BLANK LINE IS NOT REQUIRED in the following cases (this matches AsciiDoc
behavior):

1) Between adjacent headlines: >
    == headline 1 ==
    == headline 2 ==
    // comment
    == headline 3 ==
    headline 4
    ----------
    [blah]
    headline 5
    ----------

2) If the title line is preceded by [[...]] or [...] lines: >
    == headline 1 ==
    text
    [[X1]]
    [blah]
    == headline 2 ==

3) After the end of a Delimited Block: >
    == headline 1 ==
    ----------------------------
    listing
    ----------------------------
    == headline 2 ==

Outline operations other than Sort will insert blank lines before headlines if
needed. They are thus not sensitive to missing blank separator lines.

Sort does not check for blank lines before headlines and does not insert them.
There will be an error message after :VoomSort if some headlines disappear due
to a missing blank line at the end of some nodes.

------------------------------------------------------------------------------
Disallowed Headlines (2-line style)   [[[4~

Some lines are never treated by VOoM as headlines when underlined because they
resemble certain AsciiDoc elements commonly found in front of Delimited Blocks.
The following are not headlines, the underline starts Delimited Block instead:
("AAA" can be any text or no text at all)
BlockID >
    [[AAA]]
    -------
Attribute List >
    [AAA]
    -----
Comment line (exactly two // at start) >
    //AAA
    -----
Block Title >
    .AAA
    ----

Tab at start of the title line is also not allowed. Leading spaces are OK.

An underlined headline cannot be just one character. These are not recognized
as headlines (they can be in AsciiDoc): >
    A
    --

    B
    ---

An underlined title cannot look like an underline or a Delimited Block line,
that is a line of only =,-,+, etc. There are no headlines here: >
    =====
    -----
    =====

    +++
    +++++
    ^^^^^^^^^^
    ++++++++++

------------------------------------------------------------------------------
Gotchas   [[[4~

1) Do not insert blank lines or comment lines between [[...]] or [...] and the
following headline.

2) There must be a blank line between a Macro or an Attribute Entry and the
following headline. The underline in the example below is mistaken for a
Delimited Block, which kills subsequent headlines. >
    == headline

    :numbered:
    == not headline

    ifdef::something[]
    not headline
    ------------

    == not headline

3) As already mentioned, any comment lines, Macros, Attribute Entries, etc.
before a headline belong to the previous node and can become separated from the
section title when nodes are moved.

------------------------------------------------------------------------------
Customizing   [[[4~

1) AsciiDoc documents that use non-default characters for title underlines or
for delimited blocks may not be outlined correcty. The workaround is to edit
dictionaries ADS_LEVELS and BLOCK_CHARS at the top of the module
../autoload/voom/voom_mode_asciidoc.py .


2) If you do not want VOoM to check for blank lines before AsciiDoc headlines
and to insert them when cutting/pasting/moving nodes, add the following to
your .vimrc: >
    let g:voom_asciidoc_do_blanks = 0

NOTE: This is not recommended because after an outline operation, a section
title can cease to be a title due to a missing blank line. Example document: >
    Title
    =====
    BBBB
    ----
    AAAA
    ----
    some text, end of file, no blank lines after it
When BBBB is moved after AAAA (via Move Down/Up, or Cut/Paste, or :VoomSort)
it is no longer a section title in accordance with AsciiDoc specifications, but
VOoM will not know that (false-positive node) and will not issue any warnings.

==============================================================================
latex   [[[3~
                                                 *voom-mode-latex*
:Voom latex
MODULE: ../autoload/voom/voom_mode_latex.py
Mode for outlining of LaTeX sections and some other markups.
    http://en.wikipedia.org/wiki/LaTeX
    http://en.wikibooks.org/wiki/LaTeX/Document_Structure#Sectioning_Commands

In this mode, VOoM scans for lines containing standard LaTeX commands listed
below. It is possible to customize these lists, see Customizing .
LaTeX commands begin with "\" and may be indented with whitespace. There may be
a whitespace between the command and "{".

Sectioning commands, in order of increasing depth
------------------------------------------------- >
    \part{A Heading}
    \chapter{A Heading}
    \section{A Heading}
    \subsection{A Heading}
    \subsubsection{A Heading}
    \paragraph{A Heading}
    \subparagraph{A Heading}

Documents can use any subset of section types. Level 1 is assigned to the
section that is the highest in the hierarchy. Levels for other section types
are incremented sequentially.

The first "{" can be followed by any text, which allows multi-line titles: >
    \section{Long long
        long long title}

There can be an asterisk before "{". It will appear in the Tree's marks column: >
    \section*{An Unnumbered Section Title}

Optional alternative titles are OK, as long as they do not contain an "{": >
    \section[alternative title]{A Heading}


Fixed level 1 elements
---------------------- >
    \begin{document}
    \begin{abstract}
    \begin{thebibliography}
    \bibliography{...}
    \end{document}

"-" is placed in the Tree's marks column for such nodes.


Verbatim commands, headlines are ignored in between
--------------------------------------------------- >
    \begin{verbatim}
    ...
    \end{verbatim}

    \begin{comment}
    ...
    \end{comment}

------------------------------------------------------------------------------
Gotchas   [[[4~

Obviously, sections should not be moved unless they are self-contained. It's up
to the user to ensure that no TeX commands get broken when a section is moved.

Level changes are disallowed for some nodes:
    - Fixed level elements are always at level 1. They cannot be demoted or
      pasted at another level.
    - There is a maximum possible level that cannot be exceeded.
Any disallowed levels created during an outline operation are corrected
automatically and a warning is printed.

When pasting an outline, especially into another outline, section types can
change to match the structure of the target outline. As an extreme example,
pasting into an empty outline changes all sections to defaults. For example,
when the following LaTeX outline >
    \section{Material and Methods}
    \paragraph{Assorted Lengths of Wire}
is copied or cut and then pasted into an empty LaTeX outline, it becomes >
    \part{Material and Methods}
    \chapter{Assorted Lengths of Wire}
A workaround is to define custom SECTIONS as ["section","paragraph",...].

In general, the relationship between levels and section types is not always
unambiguous and depends on what section types are currently in use.

In some cases, outline operations can trigger verification errors.
Example: when \section is deleted, \subsection unexpectedly becomes level 1 >
    \section{Section Heading}
    \begin{thebibliography}
    \subsection{Subsection Heading}

VOoM does not detect LaTeX commands if they are preceded by text: >
    Lorem ipsum. Lorem ipsum. \section{Section Heading}
VOoM does not detect "begin{}...end{}" form of sectioning commands: >
    \begin{section}{Section Heading}
    \end{section}
Fortunately, nobody writes like that.

------------------------------------------------------------------------------
Customizing   [[[4~

The VOoM LaTeX mode can be customized by modifying Python variables
    SECTIONS, ELEMENTS, VERBATIMS
either directly in voom_mode_latex.py or by defining Vim variables in .vimrc:
    g:voom_latex_sections
    g:voom_latex_elements
    g:voom_latex_verbatims

SECTONS and VERBATIMS are lists of strings.
ELEMENTS is a string that is used as Python regular expression.
ELEMENTS and VERBATIMS can be empty.

The following examples are equivalent to defaults: >

    let g:voom_latex_sections = ['part', 'chapter', 'section', 'subsection', 'subsubsection', 'paragraph', 'subparagraph']

    let g:voom_latex_elements = '^\s*\\(begin\s*\{(document|abstract|thebibliography)\}|end\s*\{document\}|bibliography\s*\{)'

    let g:voom_latex_verbatims = ['verbatim', 'comment']

Examples of large documents that produce many false headlines and a fix:
http://mirrors.ctan.org/macros/latex/contrib/memoir/doc-src/memman.tex
Fix: >
    let g:voom_latex_verbatims = ['verbatim', 'comment', 'lcode', 'egsource', 'egresult']
http://mirrors.ctan.org/macros/latex/contrib/biblatex/doc/biblatex.tex
Fix: >
    let g:voom_latex_verbatims = ['verbatim', 'comment', 'ltxexample', 'lstlisting']

==============================================================================
html   [[[3~
                                                 *voom-mode-html*
:Voom html
MODULE: ../autoload/voom/voom_mode_html.py
HTML heading tags. Single line only. >

    <h1>headline level 1</h1>
    some text
     <h2> headline level 2 </h2>
    more text
     <H3  ALIGN="CENTER"> headline level 3 </H3>
     <  h4 >    headline level 4       </H4    >
      some text <h4> <font color=red> headline 5 </font> </H4> </td></div>
         etc.

Both tags must be on the same line.
Closing tag must start with </h or </H  --no whitespace after < or /
All HTML tags are deleted from Tree headlines.

WARNING: When outlining a real web page, moving nodes around will very likely
screw up HTML.

==============================================================================
thevimoutliner   [[[3~
                                                 *voom-mode-thevimoutliner*
:Voom thevimoutliner
MODULE: ../autoload/voom/voom_mode_thevimoutliner.py
The Vim Outliner (TVO) format:
    http://www.vim.org/scripts/script.php?script_id=517

Headlines and body lines are indented with Tabs. Number of Tabs indicates
level. 0 Tabs means level 1.

Headlines are lines with >=0 Tabs followed by any character except '|'.

Blank lines are not headlines.

KNOWN PROBLEMS
--------------

If TVO is installed, navigating .otl file with arrows in Tree pane is sluggish,
even with relatively small outlines like README.otl . The culprit seems to be a
time-consuming BufEnter autocommand. Function OtlEnterBuffer() is called on
BufEnter. It sets up among other things window-local folding options, which
apparently triggers recalculation of folds, which is expensive.

The following trick seems to speed up things: change the following lines in
function OtlEnterBuffer() >
    setlocal foldtext=OtlFoldText()
    setlocal foldmethod=expr
    setlocal foldexpr=OtlFoldLevel(v:lnum)
To >
    if &foldtext !=# "OtlFoldText()"
        setlocal foldtext=OtlFoldText()
    endif
    if &foldmethod !=# "expr"
        setlocal foldmethod=expr
    endif
    if &foldexpr !=# "OtlFoldLevel(v:lnum)"
        setlocal foldexpr=OtlFoldLevel(v:lnum)
    endif

==============================================================================
vimoutliner   [[[3~
                                                 *voom-mode-vimoutliner*
:Voom vimoutliner
MODULE: ../autoload/voom/voom_mode_vimoutliner.py
VimOutliner format:
    http://www.vimoutliner.org/ 

Headlines are lines with >=0 Tabs followed by any character except:
    : ; | > <
Otherwise this mode is identical to the "thevimoutliner" mode.

==============================================================================
taskpaper   [[[3~
                                                 *voom-mode-taskpaper*
:Voom taskpaper
MODULE: ../autoload/voom/voom_mode_taskpaper.py
TaskPaper format:
    http://www.vim.org/scripts/script.php?script_id=2027
    http://www.hogbaysoftware.com/products/taskpaper

Everything is indented with tabs. The level is determined by the number of
leading tabs.

Outline is constructed from lines that are Projects or Tasks. Task lines start
with "- ". Project lines end with ":" optionally followed tags.

All other lines (Notes) always belong to the Project or Task directly above
them, regardless of the indentation.

The type of headline (Project or Task) is preserved during outline operations.

The leading "- " is stripped from Task headlines.

Projects are marked with "x" in the Tree buffer, so you can jump to the
next/previous project by pressing x/X.

==============================================================================
python   [[[3~
                                                 *voom-mode-python*
:Voom python
MODULE: ../autoload/voom/voom_mode_python.py
Mode for outlining Python code. This is like a class browser except that
regions between "class" and "def" blocks are also nodes.

Headlines are
    - Classes and functions, that is first lines of "class" and "def" code
      blocks.
    - First non-blank line after the end of any "class" or "def" code block.
      This can be a comment line, but not a decorative comment line, see below.
      (NOTE: Such headlines can be killed or created by an outline operation.)
    - Comment lines that start with "###", "#--", "#==": >
        ### comment text
        #-- comment text
        #== comment text

NOTE 1: Comment lines are generally significant and their indent can influence
the level of next headlines. The exception are decorative comment lines that
consist only of "#", "-", "=", spaces and tabs: >
    #
    ########################
    #---------------------
    #==========================
such decorative comments are ignored and have no effect on the outline when
they are stand-alone. However, if such lines are followed by a comment
headline, they are associated with that headline. This allows correct handling
of pretty comment headers like this: >
    def do_something():
        pass
    ##############################
    #                            #
    # Do Nothing                 #
    #                            #
    ##############################
    def do_nothing():
        pass
The Tree buffer will show "Do Nothing" line, but the corresponding node will
start with the overline above it.

NOTE 2: Python decorators (lines starting with "@") before a function or class
are associated with that function or class. Example: >
    @re_load
    @do_not_retreat
    def hold_the_line(): ...
The Tree buffer will display "hold_the_line()", but the first line of the
corresponding node will be the line with "@re_load". It is thus safe to move
decorated function/classes in the Tree buffer--decorators will stay with them. 
Decorated functions/classes are also marked with "d" in the Tree buffer.

Headline level is determined by the line's indent relative to previous
(smaller) indents. One tab equals one space (not eight). If indent is
inconsistent, the headline is marked with '!!!' to indicate a potential indent
error.

This mode's parser uses tokenize.py to identify lines that should be ignored
(multi-line strings and expressions), as well as lines with "class" and "def".
Note that tokenize.py also checks for inconsistent indenting and can raise
exceptions in which case outline update will not be completed.

Since this mode relies on tokenize.py to do the parsing, it can be slow with
large files (>2000 lines, e.g, Tkinter.py).


OUTLINE OPERATIONS
------------------
This mode have several intrinsic problems with outline operations. Do not
disable post-operation outline verification (g:voom_verify_oop).

Outline operations assume that the Body buffer has tab-related options set
correctly to work with the Python code displayed in the buffer:
    - If 'et' is off, indenting is done with Tabs, one Tab for each level.
    - If 'et' is on, indenting is done with Spaces. The number of spaces is set
      to the value of 'ts'.
The above settings must match indentation style used by the Python code being
outlined. If they don't, an outline operation will create wrong indents
whenever a level must be changed. Outline verification after outline operation
will detect that, display error messages, and force outline update.

Outline operations can cause some headlines to disappear. (It's not clear to me
if they can appear.) This happens because regions between "class" and "def"
blocks are also nodes. This is not a bug but a confusing behavior. In the
following code there are four headlines: >
    def func1():    # headline
        pass
    a = 1           # headline (can disappear)
    def func2():    # headline
        pass
    b = 1           # headline (can disappear)
After "func2" is moved Up, line "b = 1" ceases to be a headline.  Outline
verification will detect that and complain about wrong Tree size. To protect
such fragile headline you can insert a special comment headline: >
    def func1():    # headline
        pass
    a = 1           # headline (can disappear)
    def func2():    # headline
        pass
    ### b=1         # headline (persistent)
    b = 1

Weirdly indented comment lines also can cause various confusing problems during
outline operations.

In summary:
    - Errors "wrong Tree size" after outline operations are expected and can be
      ignored. Such errors occur when nodes are moved and blocks of code
      between "class" and "def" are merged.
    - Errors "wrong levels", "wrong bnodes" could indicate serious problems and
      should not be ignored. Undo the operation after such an error. Make sure
      buffer indent settings are set correctly to handle Python code. Pretty
      comment headers should be preceded by a blank line.

==============================================================================
Miscellaneous Modes   [[[3~
                                                 *voom-mode-various*
:Voom cwiki
MODULE: ../autoload/voom/voom_mode_cwiki.py
For Vim cwiki plugin: http://www.vim.org/scripts/script.php?script_id=2176

:Voom inverseAtx
MODULE: ../autoload/voom/voom_mode_inverseAtx.py
For outlining of invese Atx-style headlines: >
    @@@ Headline level 1
    @@ Headline level 2
    @ Headline level 3
See the docstring and comments in the module for details.
Similar mode: dokuwiki, see |voom-mode-dokuwiki|


More markup modes can be found at
        https://github.com/vim-voom/VOoM_extras/tree/master/markup_modes
voom_mode_blocks.py  -- The first line of each block of non-blank lines
                        (paragraph) is headline level 1. Useful for sorting
                        paragraphs with :VoomSort.
voom_mode_dsl.py     -- Any unindented non-blank line is headline level 1.

==============================================================================
Known Issues   [[[2~

1) Memory used by Vim can increase significantly when outline operations Move
Up/Down are applied repetitively to a large node or a block of nodes (>1MB).
These commands delete and then insert lines in Body buffer. If the range being
moved is large, this can cause dramatic increase in memory used by the undo
history. Thus, to move a large node over a long distance it's better to use
Cut/Paste rather than keep pressing Ctrl-Up/Down.
This problem doesn't exist if 'undolevels' is set to -1, 0, 1.
A handy way to clear undo history:
set 'undoreload' to 0, reload the file with :e or :e! .

2) Undoing some outline operations can take a longer than usual time if a large
number of Body folds (>1000) is affected. The workaround is to temporarily set
Body's 'foldmethod' to manual (:set fdm=manual).

3) Outline navigation and outline operations can be sluggish if there are
time-consuming BufEnter, BufLeave, WinEnter, WinLeave autocommands associated
with the Body buffer. This is because most VOoM commands involve entering and
leaving Body buffer window, often temporarily. This is a problem with .otl
files of The Vim Outliner plugin (|voom-mode-thevimoutliner|).
Heavy syntax highlighting can also make outline navigation slow, especially
when selecting a node in a large outline for the first time. This is a problem
with large reST, Markdown, AsciiDoc, LaTeX files. Disabling cursorline or
cursorcolumn or both helps a bit (:set nocul nocuc).

4) Support for Vim Sessions (|:mksession|) is far from perfect. If 'ssop'
contains "blank", the command :mksession will save info about Tree buffers,
that is no-file buffers named {Body_name}_VOOM{Body_bufnr}. When the session is
restored, VOoM tries to recreate the outline for such buffers.
    - Markup modes are not remembered. Outline is always created with the
      command :Voom. You can use |g:voom_ft_modes| or |g:voom_default_mode| to
      select the desired markup mode automatically.
    - The Tree and corresponding Body buffer must be in the same tab page.
    - If 'ssop' contains "options", the command :mksession saves all Tree
      buffer-local mapping (because all voom.vim functions are global).
      This is redundant and increases the size of the Session file for no good
      reason -- about 120 mappings for each Tree buffer.
    - If 'ssop' contains "folds", :mksession doesn't really save Tree folding,
      only some folding options which will be restored anyway.

5) Some markup modes (rest, asciidoc, markdown) depend on 'encoding'. If it is
changed, the outline needs to be recreated for the new value to take effect.

6) When a VOoM outline is deleted, Body's original mappings for <Return> and
<Tab> (or whatever keys are used by |voom-shuttle-keys|) are not restored if
they were buffer-local. Only global mappings get restored. Since buffer-local
mappings are typically created by filetype plugins, you can restore them by
reapplying the filetype, e.g., ":set ft=vimwiki".

7) ID_20131122200944
If the outline is irregular, i.e, levels are skipped, sibling nodes can become
hidden in folds. This means some commands do not expand such nodes properly.
Example outline: >
      |A
    = . . . |B
      . . . |C
      . . . |D
With cursor on B, command "C" leaves only B visible.

8) Commands Copy/Cut fail with a Python error if the text contains null bytes
(^G). The Body is left unchanged when such error occurs.


==============================================================================
EXECUTING NODES (:Voomexec)   [[[1~
                                                 *voom-Voomexec*
:Voomexec [type]        Execute text from the current node and descendant nodes
                        (Tree buffers) or from the current fold and subfolds
                        (Body and non-VOoM buffers) as [type] script. Supported
                        types are: "vim", "python" or "py".
                        In Tree buffers Voomexec is mapped to <LocalLeader>e.

The following happens when the command :Voomexec is executed:

1) The type of script is determined.
-----------------------------------
    :Voomexec           Without an argument, the type of script is set to
                        buffer 'filetype': "python" if filetype is "python",
                        "vim" if filetype is "vim", etc. When executed from a
                        Tree buffer (also with <LocalLeader>e), filetype of
                        the corresponding Body is used.

    :Voomexec vim       Execute as "vim" script.

    :Voomexec python
    :Voomexec py        Execute as "python" script.

    :Voomexec whatever  Execute as "whatever" script.

    If script type is neither "vim" nor "python", the command aborts.
    It should be possible to add support for other script types.

2) The text of script is obtained.
---------------------------------
    a) If the current buffer is a VOoM Tree buffer, the script's text is set to
       that of the current node (including headline) and all descendant nodes,
       that is to Body's text in the current VOoM subtree. Body folding does
       not matter.

    b) If the current buffer is a VOoM Body or a non-VOoM buffer, the script's
       text is set to that of the current fold, including all subfolds. This is
       most useful when 'foldmethod' is "marker". If 'foldmethod' is not
       "marker", the command aborts and the script is not executed.

3) The script is executed according to its type.
-----------------------------------------------
    a) A "vim" script is executed by copying text into a register and executing
       that register (|:@|) in a function inside try/catch/finally/endtry.
       If an error occurs, v:exception is echoed. (v:throwpoint is useless.)

    b) A "python" script is executed as a string via the "exec" statement, see
       http://docs.python.org/reference/simple_stmts.html#exec .
       The following Python names are pre-defined: vim, _VOoM (module voom_vim).

       An extra line is prepended to script lines to specify encoding as per
       http://www.python.org/dev/peps/pep-0263/ , e.g.
                # -*- coding: utf-8 -*-
       Encoding is Vim's internal encoding ('utf-8' for all Unicode &enc).

       The script is executed inside try/except block. If __PyLog__ is enabled
       and an error occurs, Python traceback is printed to the __PyLog__ buffer
       instead of Vim command line.

NOTE: The "end of script" message shows the first and last line number of the
script's text.

==============================================================================
sample Vim scripts   [[[2~

Scripts in the following subnodes can be executed with >
    :Voome vim

------------------------------------------------------------------------------
"---node 1---[[[3o~
echo 'in node 1'
py print _VOoM.VOOMS.keys()

" section [[[
echo 'inside section in node 1'
" ]]]

"----------------------------------------------------------------------------~
"---node 1.1---[[[4o~
echo 'in node 1.1'

"----------------------------------------------------------------------------~
"---node 1.1.1---[[[5~
echo 'in node 1.1.1'

"============================================================================~
sample Python scripts   [[[2~

Scripts in the following subnodes can be executed with >
    :Voome py

------------------------------------------------------------------------------
#---node 1---[[[3o~
print '   in node 1'

print 'current buffer number:', vim.eval('bufnr("")')
print 'VOoM Body buffer numbers:', _VOoM.VOOMS.keys()
print 'voom_vim.makeOutline() docstring:\n   ', _VOoM.makeOutline.__doc__ ,'\n'
import os
print 'current working dir:', os.getcwd()

# section [[[
print '   inside section in node 1'
# ]]]

#----------------------------------------------------------------------------~
#---node 1.1---[[[4o~
print '   in node 1.1'

#----------------------------------------------------------------------------~
#---node 1.1.1---[[[5~
print '   in node 1.1.1'

#============================================================================~
Alternatives to :Voomexec   [[[2~

Other Vim commands and scripts can retrieve the contents of VOoM nodes as a
range of Body lines and do something with it.

1) In a Tree buffer, the "R" command selects the corresponding Body line range,
which can then be passed to a range-accepting command.

2) Function voom#GetExecRange(lnum) is what :Voomexec uses to obtain the
script's text, that is Body's lines from the current subtree (Tree buffers), or
lines from the current fold (Body buffers, non-VOoM buffers).
The following function shows how to use voom#GetExecRange(): >
    func! Voom_WriteExecRange()
        " Write to a file lines that are executed by :Voomexec.
        let filePath = '~/voomscript'
        let [bufType, body, bln1, bln2] = voom#GetExecRange(line('.'))
        if body<1 | return | endif
        let blines = getbufline(body, bln1, bln2)
        call writefile(blines, expand(filePath))
    endfunc

3) Function voom#GetVoomRange(lnum,withSubnodes) can be used by other scripts
to obtain the contents of a VOoM node at line number lnum (withSubnodes==0),
or the contents of node and its subnodes (withSubnodes==1). Unlike
voom#GetExecRange(), it works the same for Tree and Body buffers, and it
doesn't care about folding or non-VOoM buffers. Typical usage: >
    let [bufType, body, bln1, bln2] = voom#GetVoomRange(line('.'), 0)
    " Error: Body not loaded, outline update failed, etc.
    if body < 0
        echo 'ERROR'
    " Current buffer is not a VOoM buffer. Do something with the current line.
    elseif bufType==#'None'
        echo getline('.')
    elseif bufType==#'Tree'
        echo 'in Tree'
        echo getbufline(body,bln1,bln2)
    elseif bufType==#'Body'
        echo 'in Body'
        echo getbufline(body,bln1,bln2)
    endif

4) Function voom#GetBuffRange(ln1,ln2) can be used by other scripts to obtain
the contents of VOoM nodes in Tree line range ln1,ln2 if the current buffer is
a Tree (same as the "R" command). If the current buffer is not a Tree, it
returns the ln1,ln2 range for the current buffer. Example: >
    let [bufType, body, bln1, bln2] = voom#GetBuffRange(line("'<"),line("'>"))
    if body < 0 | return | endif
    let blines = getbufline(body,bln1,bln2)
    ... do something with blines ...

==============================================================================
Known Issues   [[[2~

1) Vim script code executed this way cannot use |line-continuation|.

2) When :Voomexec executes a Vim script with Python code and a Python error
occurs, Python traceback is not printed. However, Python traceback is printed
to the PyLog buffer if it is enabled. Example in the next fold can be executed
with ":Voome vim". >

    " Vim script with Python error [[[
    echo 'start of vim script'
    py print bogus_name
    py print 'py after error'
    echo 'the end'
    " ]]]

3) As the example above illustrates, Vim script is not terminated when an
error occurs in the Python code.

==============================================================================
__PyLog__ BUFFER (:Voomlog)   [[[1~
                                                 *voom-Voomlog*
:Voomlog        This command creates scratch buffer __PyLog__ and redirects
                Python's stdout and stderr to that buffer.

Subsequent Python print statements and error messages are appended to the
__PyLog__ buffer instead of being printed on Vim command line.

Windows with the __PyLog__ buffer are scrolled automatically in all tabpages
when something is printed to the PyLog buffer. If a tabpage has several PyLog
windows, only the first one is scrolled. If the current tabpage has no PyLog
windows, the command :Voomlog will create one.

To restore original stdout and stderr (that is Vim command line): unload,
delete, or wipeout the __PyLog__ buffer (:bun, :bd, :bw).

NOTE: __PyLog__ buffer is configured to be wiped out when unloaded or
deleted. 'bufhidden' is set to "wipe".

The filetype of the PyLog buffer is set to "voomlog". Some syntax highlighting
is added automatically to highlight Python tracebacks, Vim error, and common
VOoM messages.

When Python attempts to print a unicode string, e.g. >
    :py print u'ascii test'
    :py print u'\u042D \u042E \u042F \u2248 \u2260'
the string is encoded using internal Vim encoding at the time of __PyLog__
buffer creation. Internal encoding is determined from Vim option 'encoding':
"utf-8" if &encoding is a Unicode encoding, &encoding otherwise.

==============================================================================
Known Issues    [[[2~

1) All output lines appear in the __PyLog__ buffer simultaneously after the
script is finished, not in real time. Example (executable with :Voome py):

### demo Python code [[[
import time, datetime
print datetime.datetime.now()
time.sleep(5)
print datetime.datetime.now()
### ]]]


2) Printing many lines one by one can take a long time. Instead of doing >
    :py for i in range(1000): print i
It is much faster to do >
    :py print '\n'.join([str(i) for i in range(1000)])
(It's also easier to undo.)


3) Visiting other tabpages during automatic scrolling is slow on Linux in GUI
Vim (GTK). It's better to have PyLog window only in the current tabpage.


4) __PyLog__ is not usable when in the Ex mode, that is after 'Q' or 'gQ'.
The lines in the __PyLog__ buffer will appear after the Ex mode is exited.

    id_20110213225841
5) When __PyLog__ is enabled, a Python error in a Vim script does not result in
Vim error. This is probably because Python's sys.stderr is redirected. This
disrupts Vim error handling when a Python code is executed by Vim inside
try/endtry. Example Vim script, compare the output with PyLog off and on: >
    try
        python assert 1==2
        echo 'AFTER PYTHON ERROR -- should not be here'
    finally
        echo 'AFTER FINALLY'
    endtry
    echo 'AFTER TRY -- should not be here'


6) In versions before 1.7 there was problem with the output of help(), which
apparently uses Lib/pydoc.py, which does something strange to output trailing
\n. Steps to reproduce:
    1. Open new instance of Vim.
    2. Voomlog
    3. :py help(help)
    4. Wipe out __PyLog__ buffer to restore sys.stdout.
    5. :py help(help)
       An error occurs: '\n' is printed to the nonexisting log buffer.
The culprit is in Lib/pydoc.py:
    help = Helper(sys.stdin, sys.stdout)
The current workaround is to delete pydoc from sys.modules when changing
stdout and stderr.

==============================================================================
Add-ons   [[[1~
                                                 *voom-addons*
VOoM add-ons are Vim or Python scripts that use "voom.vim" and "voom_vim.py"
functions and data. Add-ons make it possible to add new functionality or to
customize default features without modifying the core files.


LOADING ADD-ONS
---------------
Some Vim script add-ons can be sourced at any time, which means they can be
placed in $HOME/.vim/plugin/ like any other plugin.

For finer control, user option "g:voom_user_command" should be used to load
add-ons only when file voom.vim is being sourced. This option defines a string
to be executed via |execute|. This is the last thing done in autoload/voom.vim: >
    if exists('g:voom_user_command')
        execute g:voom_user_command
    endif

There is no default "g:voom_user_command", it must be created by the user.

METHOD 1: Add-ons are .vim files located in $HOME/.vim/add-ons/voom/
To load them all via |runtime|, put this in vimrc: >
    let g:voom_user_command = "runtime! add-ons/voom/*.vim"

METHOD 2: Add-ons are in one file, D:/SCRIPTS/VOoM/voom_addons.vim
To source the file, put this in vimrc: >
    let g:voom_user_command = "source D:/SCRIPTS/VOoM/voom_addons.vim"

METHOD 3: Add-ons are in a Python module voom_addons.py, somewhere in the
Python search path (directory ../autoload/voom will do). To import the module,
put this in vimrc: >
    let g:voom_user_command = "python import voom_addons"
The module voom_vim.py can be accessed from within voom_addons.py as follows: >
    import sys
    voom_vim = sys.modules['voom_vim']


WRITING ADD-ONS
---------------
There is no special API. The following applies:

    - Python-side functions and data are available as attributes of module
      "voom_vim.py". Note that this module is imported in "voom.vim" as
      "_VOoM".
    - Python-side outline data for each Body are attributes of an instance of
      class VoomOutline (VO). These class instances are stored in dictionary
      _VOoM.VOOMS, keys are Body buffer numbers: VO=_VOoM.VOOMS[body].

    - All Vim functions in "voom.vim" are global and start with "voom#".

    - Vim-side data are script-local. Several functions in "voom.vim" allow
      external scripts to retrieve various outline information and data:
            voom#GetTypeBodyTree(...)
            voom#GetModeBodyTree(bnr)
            voom#GetBodiesTrees()
            voom#GetVar(var)
      Sample add-on "voom_stats.vim" shows how to use them. Examples: >
            :let [bufType, body, tree] = voom#GetTypeBodyTree()
            :let [mmode, MTYPE, body, tree] = voom#GetModeBodyTree(bufnr(''))
            :let [voom_bodies, voom_trees] = voom#GetBodiesTrees()
<
      Function voom#GetVar(var) allows external scripts to read any "voom.vim"
      script-local variable if it exists. Examples (these always exist) >
          :echo voom#GetVar('s:voom_logbnr')
          :echo voom#GetVar('s:voom_trees')
          :echo voom#GetVar('s:voom_bodies')
<
      Example: move the cursor to Log window in the current tab >
          :let logwnr = bufwinnr(voom#GetVar('s:voom_logbnr'))
          :if logwnr > 0 | exe logwnr.'wincmd w' | endif
<
    - Several functions allow external scripts to retrieve the contents of
      nodes (a range of Body lines), see
            EXECUTING NODES (:Voomexec) -> Alternatives to :Voomexec


USING ADD-ONS TO ADD NEW FUNCTIONALITY
--------------------------------------
Add-ons can create global commands, menus and mappings.

A global command that accesses VOoM outline data must first check that the
current buffer is a VOoM buffer (Tree or Body) and refuse to execute if it's
not. It should update outline if current buffer is a Body. Sample add-on
"voom_stats.vim" shows how to do that.

The filetype of Tree buffers is set to "voomtree". Thus, you can use the
following files in Vim user folder to create Tree-local mappings and commands: >
    ftplugin/voomtree.vim
    after/ftplugin/voomtree.vim
Tree buffer syntax highlighting can be customized via >
    syntax/voomtree.vim


USING ADD-ONS TO MODIFY VOoM
----------------------------
Add-ons can overwrite and modify core code functions and some data. Add-on
"custom_headlines.vim" is an example of this approach. It shows how to
customize construction of Tree headline text for individual filetypes.
Such add-ons must be loaded after "voom.vim" has been sourced completely, that
is via option g:voom_user_command as explained above.


MARKUP MODES
------------
Markup modes are special kinds of add-ons. They change how outline is
constructed and how outline operations are performed (|voom-markup-modes|).

==============================================================================
Implementation notes   [[[1~
                                                 *voom-notes*

==============================================================================
Theory of Operation   [[[2~

==============================================================================
Why Python   [[[3~

The main reason VOoM uses Python is because some of its critical code is much
faster in Python than in Vim script.

Scanning a buffer for fold markers is >10 times faster with Python code than
with a similar Vim script code. A demo code is given below. To test: select
lines, copy into a register, and execute that register while in any buffer with
a large number of fold markers, or in any large buffer.

Results with "calendar_outline.txt": >
    3.2MB, 56527 lines, 4160 headlines
    Vim 7.3.145; Python 2.6.5; Win2k; Intel Pentium 4 Mobile, 1.6 GHz

    Vim method 1: 1.53 sec
    Vim method 2: 0.70 sec
    Vim method 3: 0.14 sec
    Python:       0.084 sec

While Vim method 3 is fast, it is inconvenient because:
    a) It requires the cursor to be in Body buffer, but outline update should
       be run after entering the Tree buffer.
    b) It moves the cursor.

"--------------GET LINES WITH FOLD MARKERS---------------------------[[[
" Get list of headlines: lines with start fold marker followed by number.
" This is the bare minimum that must be done to create an outline.

""""" Vim method 1
func! Voom_VimTest1()
    let headlines = []
    let allLines = getline(1,'$')
    for line in allLines
        if stridx(line, '{{{')==-1        "}}}
            continue
        endif
        if match(line, '{{{\d\+')!=-1     "}}}
            call add(headlines, line)
        endif
    endfor
    return len(headlines)
endfunc

""""" Vim method 2
func! Voom_VimTest2()
    let lnums = filter(range(1,line('$')), 'getline(v:val)=~''{{{\d\+''')
    let headlines = map(lnums, 'getline(v:val)')
    return len(headlines)
endfunc

""""" Vim method 3
func! Voom_VimTest3()
    let headlines = []
    g/{{{\d\+/ call add(headlines, getline('.'))     "}}}
    return len(headlines)
endfunc

""""" Python code, similar to Vim method 1
python << EOF
def Voom_PyTest():
    import vim
    import re
    re_marker = re.compile(r'{{{\d+')   #}}}
    headlines = []
    allLines = vim.current.buffer[:]
    for line in allLines:
        if not '{{{' in line: continue  #}}}
        if re_marker.search(line):
            headlines.append(line)
    vim.command('let bnodes=%s' %len(headlines))
EOF

""""" timing
let start = reltime()
let nodeCount = Voom_VimTest1()
echo 'Vim method 1: ' . reltimestr(reltime(start)) . 'sec; '. nodeCount . ' nodes'

let start = reltime()
let nodeCount = Voom_VimTest2()
echo 'Vim method 2: ' . reltimestr(reltime(start)) . 'sec; '. nodeCount . ' nodes'

let start = reltime()
let nodeCount = Voom_VimTest3()
echo 'Vim method 3: ' . reltimestr(reltime(start)) . 'sec; '. nodeCount . ' nodes'

let start = reltime()
py Voom_PyTest()
echo 'Python:       ' . reltimestr(reltime(start)) . 'sec; '. nodeCount . ' nodes'

unlet nodeCount
"--------------END OF CODE ------------------------------------------]]]


In addition, Python's FOR loop is >30 times faster then Vim's. In the demo
code below the Python function is >60 times faster.

"------ Vim FOR loop versus Python FOR loop -------------------------[[[
func! Time_VimForLoop()
    let aList = range(1000000)
    for i in aList
        " pass
    endfor
endfunc

python << EOF
def Time_PyForLoop():
    aList =     range(1000000)
    for i in aList:
        pass
EOF

""" 9.76 sec """
let start = reltime()
call Time_VimForLoop()
echo 'Vim:    ' . reltimestr(reltime(start))

""" 0.15 sec """
let start = reltime()
py Time_PyForLoop()
echo 'Python: ' . reltimestr(reltime(start))
"-------END OF CODE--------------------------------------------------]]]

Thus, Python code should be much faster when handling large lists.

==============================================================================
Separate Trees or single Tree   [[[3~

A single Tree buffer could be used to display outlines of many files. Tlist
does that. This makes sense when working with several related files. Also,
having a single Tree would be more like Leo.

VOoM creates new Tree buffer for every new outline. This is simpler. It is
more appropriate for text notes, when outline files are likely to be
unrelated. Searching headlines is easier.

==============================================================================
Checking Bodies for ticks   [[[3~

Tree buffer and associated outline data are updated on entering Tree via
BufEnter autocommand. To perform update only when the Body has changed since
the last update, Body's b:changedtick is used as shown in the docs.
Unfortunately, b:changedtick cannot be read with getbufvar(), so it's not
accessible from Tree on BufEnter (see NOTE 1 below). The workaround is to use
Body's BufLeave autocommand to save Body's b:changedtick.
So the entire update scheme is:
    - on Body BufLeave save Body's b:changedtick as "tick"
    - on Tree BufEnter compare "tick_" to "tick"
    - if different, do the outline update and set "tick_" to "tick"

The outline must be up to date when the cursor is in the Tree buffer. If it's
not, the consequences could be unpleasant. Performing outline operations will
cause data corruption.

Outline update can fail when something goes wrong with autocommands, e.g.,
when the user messes with 'eventignore'. Or, the Body file can be modified by
an external application while cursor is in Tree.

Fortunately, most Voom commands involve a visit from Tree to Body or vice
versa, so we can compare "tick_" directly to Body's "b:changedtick". If they
are different: the command is aborted, outline update is forced, error message
is displayed. Such check is performed:
    - during any outline operation (before modifying the Body buffer)
    - when selecting node from Tree or Body
    - during Voomgrep command initiated from Tree
The function that does this check is voom#BodyCheckTicks().

These checks can be tested by modifying Body and then moving to Tree with
":noau wincmd w" or after ":set ei=BufLeave", etc.

Another precaution is that "tick_" is not set to "tick" when an unexpected
error occurs during update.  voom_vim.updateTree()) is always called from Vim
code inside try/finally/endtry. It also sets Vim var l:ok to indicate success,
see #id_20110213212708 .

NOTE 1: This was fixed by Patch 7.3.105 -- b:changedtick can be obtained via
getbufvar(). In VOoM 4.7 and above a few operations assume that this patch is
present and first try to check Body ticks while in Tree in order to avoid an
unneeded trip to Body and back. The code relies on the fact that
    getbufvar(body,"changedtick")
returns "" without the patch. When the value of getbufvar(body,"changedtick")
is wrong, the next step is always to move the cursor into Body (it may no
longer exist, unloaded, etc.) and check for b:changedtick directly. This
automatically takes care of versions before the patch. See code for operations
Insert Node, Copy, Folding Save/Restore/Cleanup.

NOTE 2: Outline operations other than Sort do not rely on the outline update.
They do a targeted adjustment of outline data and then verify the resulting
outline against the outline produced by the wholesale update.

==============================================================================
Unloaded buffer + python == trouble   [[[3~

Bad things happen when attempting to modify an unloaded buffer via Python
vim.buffer object. (This might be considered a Vim bug.) Example:
    - Create two buffers: buf1 and buf2. They can be new, no-file buffers.
    - With cursor in buf2
      :py buf2=vim.current.buffer
    - Buffer 2 can now be modified via Python:
      :py buf2[0]="xxxxxxxxx"
    - Unload buffer 2
      :bun!
      Buffer 1 is the current buffer.
    - Try writing to buffer 2, which is not loaded
      :py buf2[0]="yyyyy"
    - Buffer 1 is modified instead of buffer 2, and the change cannot be undone!
      Buffer 2 is no longer unloaded, so subsequent writes to it via buf2
      happen correctly.

P.S. (2013-11-18) This behavior is changed in Vim 7.4.52. The unloaded buffer
is automatically loaded and is written to, that is it becomes hidden. This is
better, but is not really helpful: buffer's content was lost when the buffer
was unloaded.

VOoM uses Python vim.buffer methods to modify Tree, Body, and PyLog buffers.
It is essential that these buffers are loaded (bufloaded())before being written
to. Writing to a non-existing (wiped out) buffer is not as dangerous because it
produces an error.

Tree and PyLog BufUnload autocommands make it unlikely that a Tree or PyLog
buffer is unloaded -- they are wiped out on BufUnload.
These buffers can still become unloaded when they are closed improperly with
"noa bun" or "noa bd" or when something goes wrong with autocommands.

Body buffers can be unloaded since VOoM v3.0.

There are checks that ensure that the buffer is loaded (bufloaded()) before it
is modified via Python vim.buffer object.

==============================================================================
Wipe out Tree on BufUnload   [[[3~

A Tree buffer should be wiped out and the corresponding VOoM data deleted
after:

1) Tree is unloaded. All contents is lost, Tree reverts to blank buffer.
2) Tree is deleted. As above, plus buffer-local mappings are lost.
2) Tree is wiped out. VOoM data need to be cleaned up.

This is accomplished via BufUnload autocmd for Tree, which is also triggered on
BufDelete and BufWipeout.

Unloaded, deleted, and wiped out Body buffers are obviously also a problem, see
next node. Prior to v3.0 there was Body BufUnload au that wiped out Tree. That
was found to be too risky.

There are several fail-safe measures that ensure that nothing damaging will
happen if Tree BufUnload autocommand is not triggered, as after "noa bun", "noa
bd", "noa bw".

Most Voom commands check that: Tree is loaded, Body exists, Body is loaded (see
next). This relies on bufloaded() and bufexists().

Functions voom#ToBody() and voom#ToTree(), which are called when selecting
nodes and before almost every outline operation, perform all of the above
checks and will do cleanup if checks fail.


The PyLog buffer should also be wiped out when unloaded or deleted. There is a
check that ensures that PyLog is loaded before printing to it.

==============================================================================
Unloaded, deleted, wiped out Bodies   [[[3~

Unloaded Body buffers are a problem:

It is not possible to outline a buffer if it is unloaded.
Python vim.buffer object is useless for unloaded buffer, it's [""].

When unloaded Body is loaded again the following events are hard to detect:
    - buffer changes were abandoned after q!, bun!, bd!
    - file was modified by external process

Thus, a global outline update must be done after loading Body. This means we
should abort outline command if Body is found unloaded, even if we can load it
and force outline update.

PERFECT: Body b:changedtick is incremented by 2 after unloading/loading.
Outline update is guarantied on Tree BufEnter or when updating from Body.

We deal with unloaded Bodies by disabling Tree buffer commands -- as soon as
Body bufnr is computed, check if it's loaded and abort the command if it's not.
Helper function is voom#BufLoaded(body). It will also detect if Body does not
exist. This must be done for:
    outline update on BufEnter
    all outline operations
    node selection (always done by voom#TreeSelect())
    Voomgrep, Voomunl, Body text getters (Voomexec)
    any other command that requires up-to-date outline, or reads/writes Body

The next line of defense is voom#ToBody(), which is called by almost all Tree
commands. When it detects Body is unloaded it loads it in new window as usual,
runs outline update, returns -1. If Body does not exist it performs clean up.

The b:changedtick check (see "Checking Bodies for ticks") also should prevent
potential troubles after Body unload/reload. This is because b:changedtick
changes after unloading a buffer and loading it again.


When Body buffer is deleted (:bd) it is unloaded. In addition, buffer-local
mappings are lost. The loss of Body-local mappings (shuttle keys) is detected
by Body BufEnter au. It checks for hasmapto('voom#ToTreeOrBodyWin') and
restores mappings if needed.

The command :Voom checks hasmapto('voom#ToTreeOrBodyWin') when executed in Tree
or Body. If not found, it reconfigures Tree/Body. In theory, this can be used
to restore Tree and Body configurations after some perverted unloads/reloads
with ":noa bd", "noa b", etc.


Wiped out Bodies are also unloaded. Tree has no reason to exist after Body has
been wiped out. Sadly, wiping out Tree from Body BufWipeout au is too risky,
see v3.0 notes.


==============================================================================
TODO   [[[2~

Outline operations could use try/finally/endtry for maximum resilience.
Harden against interrupts: slow computer, huge outline, user presses <C-c> in
the middle of an outline operation.
Vim 7.4: vim.error in Python code completely stops Vim script execution.
Vim bug: foldtext is messed up in all windows if uncaught error in try/entry.
Seems to be fixed as of 7.4.052

Write FAQ.
Write implementation notes: data model, markup modes, outline operations.

The most sensible and the least confusing initial behavior for the command
:Voom is to _require_ an argument when creating an outline.
Setting g:voom_default_mode to "fmr" will restore original behavior.
Move relevant code to voom_mode_fmr.py and may be similar .vim file.

Change Tree buffer names so that they contain markup mode:
    source.txt_VOOM99()          --default mode
    source.txt_VOOM99(markdown)  --markdown mode
This is the only way to choose original markup mode when restoring a Session.

Should g:voom_verify_oop be removed?

Do something about Python 3.

Voomgrep enhancements:
    Show results by folding non-matching lines and nodes. (:VoomGrep)
        ?  Need command to restore previous folding settings.
    ~ "foo and not bar" seems better than "foo not bar" and easier to parse.

Add command to Mark/Unmark only visible nodes (not hidden in folds).
Could be add-on.

Tree mapping to move to next/previous sibling with a child. There are no more
letters left to map.

Insert New Node: make new headline text an argument of function to make
programmatic creation of outlines more convenient, especially when there are
underlines/overlines (markdown, reST). Example code at #ID_20111006013436 .
Also need args for mark and level.

Set jump mark when selecting node from Tree with <Enter> or other actions.
This could be used as outline browsing history.
Currently no jump marks are created in Tree or Body during node navigation or
manipulation (:keepj when G, gg, etc).
It is difficult to decide which commands should set a mark.

Outline navigation functions should probably also check that the current buffer
is Tree (voom#BufNotTree) in case external script makes a mistake.

Read-only modes with VimScript parsers: Vim regexp, folds.
This should be handled by setting MTYPE.
Similarly, need a method to disable Move Right: markup modes "dsl", "blocks".

Do something about duplicate Python code, especially among markup modules.
In many cases "from voom_mode_... import ..." should be sufficient.

Fix expanding of sibling nodes in irregular outlines: #ID_20131122200944 .
Hard to fix. Not a big deal because it's rare. Should be handled by TreeZV().

==============================================================================
CHANGELOG   [[[2o~

v5.1, 2014-06-22   [[[3x~

New markup mode: dokuwiki.

Python markup mode: better handling of decorative comment lines (separators and
pretty headers). https://github.com/vim-voom/vim-voom.github.com/issues/13

:Voomgrep improvements.
Maximum number of matches was increased to 500000.
The command now aborts with an error message when maximum number of matches is
exceeded while searching for a pattern.
Changed how results are displaed in quickfix buffer: "N" is shown before the
node's number if the node contains all AND matches, "n" otherwise.

PROBLEM: Copy/Cut fails with a Python error if text contains null bytes (^G).
SOLUTION: Do nothing, let it fail, but make sure there are no consequences and
Body is left unchanged. Copy fails without any consequences. Cut was tweaked to
tolerate such errors: set l:blnShow last to signal that Python code succeeded,
same as with other operations.

PROBLEM: Outline verification is not performed after an outline operation if
Body's b:changedtick is unchanged. This was introduced in previous version to
avoid unneeded verifications after operations that change nothing: marking an
already marked node, moving a child node right, etc. This is wrong: an internal
defect or a badly designed markup mode may leave the Body unchanged but still
modify Tree/bnodes/levels. 
SOLUTION: Do not check if Body's b:changedtick changed before calling outline
verification. Disable unneeded verifications on a case by case bases via
l:doverif. 


v5.0, 2013-11-26   [[[3~

The code and directory structure have been reorganized:
    - The Vim script part of the plugin was rewritten to use |autoload| instead
      of FuncUndefined au. This mostly involved renaming functions Voom_... to
      voom#...
    - The main Python module "voom.py" was renamed "voom_vim.py". It is
      imported in Vim as _VOoM.
    - The VOoM package now contains only the essential (standard) directories
      and files. The extra stuff can be found in github repo VOoM_extras.
    - Helptags were changed: separator is "-" instead of "_".

:Voomgrep can now perform hierarchical searches (tag inheritance).

New option: |g:voom_clipboard_register|. Copy/Cut/Paste by default use the "o
register if Vim does not have clipboard support.

New option: |g:voom_always_allow_move_left|. Allows Move Left if nodes are not
at the end of their subtree.

New markup modes: pandoc (Pandoc Markdown), inverseAtx.

Improved Python markup mode: decorators are no longer headlines and are not
displayed in the Tree buffer. They belong to the corresponding function/class
node, so it is safe to move decorated functions/classes.

Improved Markdown mode. It now handles headlines in ambiguous format correctly:
underline overrides hashes. The parser is slightly faster.

Fixed a bug in Markdown, AsciiDoc modes. During some outline operations an
underline was not removed or changed when it was the last line in the buffer.
That was caused by off-by-one error when checking if the line is the last one.

reST mode:
- The reST parser was optimized for large paragraphs: only check lines 2 and 3
  from the top for an underline and skip the rest. The parser is up to 30%
  faster with large paragraphs.
- The reST parser is now more strict. A headline must be preceded by a blank
  lines or another headline. Previously, headlines with an overline did not
  always need to be preceded by a blank line or another headline.
- Headline text is not allowed to look like an underline/overline unless it is
  shorter than the underline. This is to avoid ambiguities and errors during
  outline operations.

Problem introduced by Vim 7.4: Calling vim.command("echoerr ...") in Python
code triggers Python exception vim.error, breaks the Python code, completely
stops execution of containing Vim script code.
Solution: always use voom#ErrorMsg() to put up error messages from Python.

Problem: Changing fdl in plugin/voomtree.vim has no effect when there is a
markup mode because fdl is set when Tree is drawn.
Solution: Set Tree filetype _after_ the Tree is drawn, in TreeConfigFt().
Related: don't create Tree syntax if b:current_syntax exists.

Changed &ul to &l:ul in voom.vim just in case. "setl" is already used
everywhere to set ul to -1. Vim Patch 7.4.073 makes &ul global-local.

Tree mappings:
Don't disable "o" in Visual, it's useful.
Map <Space> in Visual to <Esc>.
Tweaked how D J U K extend selection in Visual.
Tweaked <Right> and "o": try to handed correctly folded lines with irregular
levels, e.g., outline has only level 3 nodes. Such nodes can be folded, yet
have no children.
There are still problems with irregular outlines: the subtree can be contracted
so that only the first sibling is visible. See  #ID_20131122200944 .


v4.7, 2013-01-28   [[[3~

New markup mode: taskpaper (|voom-mode-taskpaper|).
https://github.com/vim-voom/vim-voom.github.com/issues/6

PROBLEM: https://github.com/vim-voom/vim-voom.github.com/issues/7
The issue can be observed after adding the following au
    :autocmd BufLeave,FocusLost * silent wall
Error in Voom_OopFromBody(). Outline operations fail because b:changedtick is
incremented when Body is saved on BufLeave, which triggers outline update on
Tree BufEnter, which prematurely resets Tree to noma and also renders outline
verification useless.
SOLUTION: Block outline update when Tree is &ma. All outline operations that
rely on verification set Tree ma for the duration of operation to suppress
update. Force outline verification when Body's tick changes unexpectedly
(s:verify overrides g:voom_verify_oop). Other small changes to make outline
operations more resilient.

License changed to CC0.

Code tweaks:
- Another foolproofing measure: Voom_BufNotTree(tree) checks if Tree is &ma.
- Outline verification is now run after Folding Save/Restore.
- Better use of getbufvar(body,"changedtick"). No need to check Vim version, it
  returns "" if Vim < 7.3.105. Use it during Copy.
- New function Voom_GetModeBodyTree() -- external scripts can use it to
  determine the current markup mode.
- Renamed several functions used by external scripts:
      Voom_GetData() > Voom_GetBodiesTrees()
      Voom_GetBufInfo() > Voom_GetTypeBodyTree()


v4.6, 2012-12-03   [[[3~

Warning message is no longer displayed when a markup mode is invoked.

New command :Voominfo [all] prints information about the current outline and
VOoM internals.

Sample add-on voom_info.vim was renamed to voom_stats.vim.

Got rid of s:voom_bodies[body].blnr. It was used only during outline creation.
Renamed some voom.vim functions.


v4.5, 2012-11-13   [[[3~

New Tree mapping: "I" jumps to the last line of the current node.

Improved txt2tags mode.
 - Ignore headlines in Comment Areas, that is between %%% .
 - Display "+" for numbered titles in the Tree marks column instead of
   prepending "+" to headline text.

Fixed a bug in :Voomgrep search. Results were correct only for the first 2 AND
patterns. False results were produced when searching with >2 AND patterns
because intersection was computed incorrectly.

Improved display of :Voomgrep results.
 - Buffer name is removed from lines in the quickfix buffer to save space.
 - Syntax highlighting is adjusted automatically -- it is no longer necessary
   to customize syntax/qf.vim.
 - All AND patterns are added to the "/ register, not only the first one as
   before. This does not always work correctly with multiple AND patterns --
   "\c" and "\C" are problematic.

Rewrote :Voomgrep input parser function.

Added check that the current buffer is Tree to top-level functions for outline
operations (Voom_BufNotTree). This is in case an external script or command
makes a mistake and executes in wrong buffer.


v4.4, 2012-06-03   [[[3~

Added LaTeX mode: |voom-mode-latex|.

Better mappings for Insert New Headline: "aa", "AA". <LocalLeader>i/I were
changed to <LocalLeader>a/A.

Improved Edit Headline ("i", "I"). It now correctly positions the cursor on the
headline text for most markups most of the time.

Improved "C", "O": window layout was not always restored properly.

Don't block commands Edit Headline, Select Body Range if Body is not editable.
They don't modify Body. Edit Headline is useful as an alternative to Return.

ID_20120520092604
Significant change in voom.py in order to accommodate LaTeX mode. Levels of
Tree lines during Paste/Up/Down/Left/Right are now set according to VO.levels,
not levDelta as before. setLevTreeLines() replaced changeLevTreeHead(). This is
done after VO.levels is adjusted and after hook_doBodyAfterOop() is done. Thus,
hook_doBodyAfterOop() can correct disallowed levels by modifying items in
VO.levels: fixed elements at level >1, maximum level exceeded. The Tree is then
constructed with correct levels and will pass verification.


v4.3, 2012-05-06   [[[3~

PROBLEM: The Voom command cannot handle buffer names containing %, #, etc.
Session restore is also affected.
Whitespace in names is also a problem on some systems (Jonathan Reeve).
SOLUTION: Do fnameescape() when :edit, :file, :tabnew, etc.

Added |voom-mode-hashes|.


v4.2, 2012-04-04   [[[3~

New commands for quitting and toggling outline window (|voom-quit|):
"q", VoomToggle, Voomtoggle, Voomquit, VoomQuitAll.
    https://github.com/vim-voom/vim-voom.github.com/issues/2

New Tree mappings ^^ (Move Up) and __ (Move Down) for symmetry with << and >>.

Added support for "fmr" modes (|voom-mode-fmr|). Modes fmr, fmr1, fmr2.

New options |g:voom_ft_modes|, |g:voom_default_mode| allow automatic selection
of markup mode according to filetype of the source buffer.

Improved asciidoc mode: there can be any number of preceding [] or [[]] lines
and in any order; blank line is not required before the topmost [] or [[]].

:Voomexec now executes Python scripts via "exec" instead of execfile(). Temp
file plugin/voom/_voomScript_.py is no longer created and should be deleted.
Python traceback's lnums match buffer lnums.
The "end of script" message shows script's start/end lnums.


Vim code
--------
Replaced Voom_GetBodyLines1() with more useful functions.

Voomexec fix: execute Vim scripts in a separate function Voom_ExecVim() to
avoid potential interference with Voom_Exec() local vars.
Python scripts still have access to Voom_Exec() vars. No big deal, unlikely to
cause any problems. Demo:
### :Voomexec py [[[
vim.command("echo [bufType,body,bln1,bln2]")
print vim.eval("[bufType,body,bln1,bln2]")
### ]]]


Python code
-----------
Mode-specific functions, such as makeOutline(), are now VO methods set during
outline init. Thus got rid of incessant getattr(VO.mmode,...) during outline
updates and outline operations. It's now easier to control what modes can do.

Split makeOutline() into makeOutline() and makeOutlineH() for efficiency sake.
(If needed, the old makeOutline() function can be in a fmr mode.)

Added check for clipboard size in setClipboard() to guard against failures with
very large clipboards.

Get &enc during outline init (VO.enc) instead of during markup mode imports.
Otherwise, it's impossible to change &enc without reloading everything.


v4.1, 2011-11-27   [[[3~

PROBLEM: Tree mappings J/K are supposed to accept a count, but they don't.
This is with Vim 7.3.145. No problem with Vim 7.2.
SOLUTION: Save original v:count1 before
    exe 'normal...
in Voom_Tree_KJUD().

Better argument completion for the :Voom command. The list of modes is
constructed from file names voom_mode_{whatever}.py in ../plugin/voom .


v4.0, 2011-11-06   [[[3~

New markup modes: asciidoc, org (same as old viki), cwiki.
Viki mode now ignores special regions.

New Tree mapping: "R" selects corresponding Body range.

Tweaked Markdown mode.

Fix in viki/org mode: level changing outline operations converted any
whitespace after * into space.

Fixed Tree syntax hi to avoid false hi after "|" inside of headline text.
Example: part after # is not comment >
    = . . |<<test link||#test>>

ID_20111006013436
Improved function Insert Node: use getbufvar(body,"changedtick") if
has("patch105"). This saves one trip to Body and back when checking for ticks.
Code for timing, execute from Tree, the Body is empty: >
    let tree = bufnr('')
    let start = reltime()
    for i in range(1,100)
        call Voom_OopInsert('')
        call Voom_ToTree(tree)
    endfor
    echo reltimestr(reltime(start))
    unlet tree start
0.71 sec vs 1.10-1.13 sec with the old code or if there is no patch.
It seems there are no other functions that would benefit from this.
Note: when check for ticks via getbufvar() fails, the next step should be to
move cursor into Body buffer--it may no longer exist, unloaded, etc.


v4.0b5, 2011-03-24   [[[3~

New markup mode: txt2tags.

Added support for Vim Sessions (:mksession) via BufFilePost autocmd for VOOM
Tree buffers and __PyLog__ buffers.

Fixed bug in :Voomexec -- Python script file encoding was set incorrectly.
Source code encoding of the temp script file should be Vim internal encoding,
not &fenc or &enc.

Fixed command Edit Headline (iIaA): cursor was not positioned on the first word
char in Body headline when there are was no foldmarker (markup modes).

Dealing with Python errors during outline update.
-------------------------------------------------
Working in the python mode revealed a flaw in safeguards against Python errors
during outline update. Such errors are expected while in python mode --
tokenize.py raises exception when indentation is wrong or a quote is missing.

    id_20110213212708 , also see #id_20110213225841
Calling voom.updateTree() via try/python.../finally/endtry in the Vim code
(|try-finally|) does not guard against Python errors when PyLog is on. It looks
like Vim error is not triggered when Python's sys.stderr is redirected. The
result is that changedtick (tick_) is updated despite a failed update.
SOLUTION: always set Vim var l:ok in voom.updateTree() before returning to
indicate a successful update.

Python mode: catch exceptions raised by tokenize.py, echo the error, set Tree
lines to make it clear that update has failed and outline is invalid.

Refactoring
-----------
Insert New Headline -- don't need Body column, just search for "NewHeadline".
voom.newHeadline(), hook_newHeadline() no longer return column.

Voom_LogScroll() -- several optimizations. PyLog is usually only in the current
tabpage. Thus, check tabpagenr() before tabnext--faster than redundant tabnext.


v4.0b4, 2011-01-30   [[[3~
New Tree mappings for navigating outline:
    P (go to parent node),
    c (go to parent and contract it),
    C (contract siblings or everything in Visual selection),
    o (go to first child),
    O (expand siblings or everything in Visual selection),
    K/J/U/D (go to previous/next/uppermost/downmost sibling),
    s (show headline text), S (show UNL).

    id_20110121201243
PROBLEM: Longstanding annoyance with some Tree mappings. Example: hit "d"
(disabled by mapping to <Nop>), wait a few seconds, hit "dd" (cut node) --
there is no response. Can be very confusing.
SOLUTION: disable "d" and similar by mapping them to <Esc> instead of <Nop>.
Another option is to map them to 0f| .

Disabled more text changing keys in Tree: < > <Ctrl-x> etc.

PROBLEM: User placed VOoM package in ~/.vim/plugin. Everything gets loaded on
Vim startup (|load-plugins|). Add-on custom_headlines.vim causes error because
it must  be loaded only after voom.vim has been sourced completely.
SOLUTION: finish loading custom_headlines.vim if !exists('*Voom_Exec').

PROBLEM: Command :Voomhelp does not reuse existing voom.txt windows if current
buffer is not voom.txt or its Tree.
SOLUTION: Start by searching all tabs for voom.txt window.

    id_20110120011733
PROBLEM: Outline has only level 1 headlines and there is a stray "o" mark.
vim.error in voom.foldingCreate() on startup after :Voom.
E490: No fold found, triggered by initial :foldopen, because Tree has no folds.
SOLUTION: Catch E490 when doing :foldopen in foldingCreate().
Note1: must execute :foldopen even when cFolds list is empty.
Note2: cFolds (lnums of closed folds) never contains nodes without children.
This means "zc" will not trigger E490 error. Unless Tree folding is messed up
or lost, e.g., because fdm was reset.

    id_20110125210844
Fixed glitches with initial cursor positioning in Tree when markup mode is
used. snLn can be >1 when markup mode is used or when there is no startup node
(Body cursor on >1 node).
Create jumps marks when outline is created: line 1 and selected node.
Initial gg restores view after jumping around when creating folds.

Added "keepj" when jumping around Tree and Body via G or gg.
No jump marks are created in Tree or Body during node navigation or manipulation.


Vim code for outline navigation   id_20110116213809
---------------------------------------------------
Made Voom_TreeLeft() much faster with large outlines.
The final step (go to parent) used this inefficient code: >
    let ind = stridx(getline('.'),'|')
    let indp = ind
    while indp>=ind
        normal! k
        let indp = stridx(getline('.'),'|')
    endwhile
It is much faster to call search() to find line with required indent of |.
Multibyte chars should not be a problem because there are never any before |.
Timing: 5876 childless siblings, cursor on the last.
Old code: 0.28 sec.  New code: 0.01 sec.

Voom_TreeToSiblings(), etc: also use search() to locate parents/siblings.
virtcol() ensures multibyte chars before | will never be a problem.

Simplified Voom_TreeSelect(lnum, focus) signature. No need for lnum, it's
always current line. focus is 1 (stay in Tree) or 0.

Got rid of Voom_TreePlaceCursor(), just do
    call cursor(0,stridx(getline('.'),'|')+1)
        or
    normal! 0f|


v4.0b3, 2011-01-04   [[[3~

New markup mode: markdown.

Fixed severe bug in reST mode. Paste and level-changing outline operations were
affected. One manifestation: when pasting into an empty outline all headlines
become level 1.

The command :VoomSort now accepts a line range in front of it. If a range is
not a single line, siblings in the range are sorted.

Changed how some outline operations handle the first Tree line (outline title):
    - VoomSort now aborts if the first Tree line is selected. This is to be
      consistent with other outline operations (Cut, Copy, Move) which also
      require a valid range.
    - Print error message when an operation is aborted because the first Tree
      line is selected (Cut, Copy, Move, Sort).
    - Mark Node as Startup is allowed: remove "=" marks from all headlines.

Mode viki: allow any whitespace after last leading *, not just space.

Outline operation Copy: do not display error message complaining about Body
buffer being nomodifiable or readonly.

Code refactoring
----------------

s:voom_logbnr now always exists. It is 0 if there is no Log buffer.

New helper function Voom_GetVar(var) -- allows external scripts to read any
"voom.vim" script-local variable such as s:voom_logbnr.

:Voomexec -- improved printing of errors. When PyLog is not enabled,
Python traceback is echoed as Vim error message. See
    ../autoload/voom/voom.py#id_20101214100357

Assign VO.marker and VO.marker_re to MARKER and MARKER_RE instead of 0 when
foldmarker is default.  MARKER_RE object is reused, so this is still efficient.
This eliminated the need for silly code
    marker = VO.marker or MARKER
    marker_re = VO.marker_re or MARKER_RE
    
------------------------------------------------------------------------------
v4.0b2, 2010-10-24   [[[3~

New markup modes: rest (reStructuredText), python, thevimoutliner, vimoutliner.

Changed default for g:voom_verify_oop to 1 (enabled). We need this to detect
inherent problems with "python" and "rest" modes, to debug other modes. Outline
verification is performed by new function Voom_OopVerify(). It forces outline
update if verification fails.

Option g:voom_rstrip_chars (dictionary) has been removed. Instead, there are
options g:voom_rstrip_chars_{filetype} (strings) for each Body filetype of
interest. REASON: it's easier to define a string for one filetype than to mess
with a dictionary that has settings for a bunch of other filetypes.

Command VoomSort now checks that the number of headlines is not changed after
sorting (after Tree update on BufEnter). When using modes "rest" or "python"
sorting can make some headlines cease to be headlines.

Added argument completion for command :Voom.

Added special syntax hi in Tree when Body's filetype is vim or python.
See Voom_TreeSyntax().

Python code refactoring:
    - Name VOOMS is no longer defined in Vim module namespace. It is available
      only as voom.VOOMS.
    - Changed argument "body" in many functions like makeOutline() to "VO".
      This makes more sense since "VO" is what we need. Makes it easier to
      write markup modes and add-ons -- no need to look up VO in voom.VOOMS.
    - Refactored oops Cut, Paste, Up, Down, Left, Right to accomodate modes
      like "python" and "rest".  The new sequence of actions is:
        - modify Body lines (move);
        - update VO.bnodes; update VO.levels;
        - call hook_doBodyAfterOop() to finish updating Body lines -- change
          indentation, headline adornment styles, etc;
        - go back to Tree; update Tree lines.


'noautocmd' troubles   [[[4~
Testing thevimoutliner mode with TVO plugin installed revealed serious flaw in
node selection functions -- they screw up TVO's BufEnter and BufLeave autocmds
that disable/enable TVO's menu. There are errors about missing menu, etc.

The culprit is "noautocmd" in Voom_TreeSelect() and Voom_BodySelect().

Same problem with VoomSort.

All outline operations use "noautocmd" when cycling between Body and Tree. This
can also cause problems -- if outline operation fails the cursor stuck in Body.

SOLUTION: do not use "noautocmd".

The original reason for "noautocmds" was to increase performance by disabling
autocmds when temporarily visiting Tree or Body window -- a frequent action,
e.g., when selecting nodes. The performance gain is usually minuscule and is
not worth the risk of screwing up autocommands created by other plugins.

There is also problem with Tree BufUnload au -- it must be "nested" to trigger
BufEnter, etc. after Tree is wiped out, and we cannot use "noautocmd" when
wiping out Tree. But without "noautocmd" we get recursive call. 
SOLUTION: first delete Tree autocommands, then wipe out Tree without using
"noautocmd".
This change was made in Voom_TreeBufUnload() and Voom_UnVoom()
Same change was made in Log BufUnload au: made it nested, delete Log au before
wiping out Log.

"noautocmds" is now used only in Voom_LogScroll() for performance sake.
It's very unlikely that something will go wrong there.

------------------------------------------------------------------------------
v4.0b1, 2010-09-21   [[[3~

Added support for headline markups other than start fold markers with levels:
|voom-markup-modes|. Available markup modes: wiki, vimwiki, viki, html.

Changed plugin directory structure: all Python files are now located in folder
plugin/voom.

Changed how global outline data are stored.
Old scheme: class VOOM has a bunch of dictionaries as attribs. Keys are Body
bufnr. Data for one outline:
    bnodes, levels = VOOM.bnodes[body], VOOM.levels[body]
New scheme: there is instance of class VoomOutline for each Body, attribs are
outline properties. These instances are stored in global dict VOOMS, keys are
Body bufnr.
	VO = VOOMS[body]
    bnodes, levels = VO.bnodes, VO.levels

PROBLEM introduced since setting Tree's "bufhidden" to "wipe".
Tabpage has two windows, Tree and Body. Load another buffer in Body window and
create outline.  What is left is one window with new Tree.
FIX: Voom_ToTreeWin(), when re-using another Tree window: split it if current
tabpage has no other windows with this Tree buffer. This actually makes sense
regardless of Tree "bufhidden".

------------------------------------------------------------------------------
v3.0, 2010-08-01   [[[3~

New command :VoomSort [options] for sorting outline, |voom-sort|.

Tree buffer is no longer automatically wiped out when its Body buffer is
unloaded, deleted, or wiped out. Instead, outline is locked until Body is
loaded again. This change was needed to eliminate crashes after :q, :q! and
related problems. This can also make working with outlines easier when buffers
routinely get unloaded, as when 'hidden' and 'bufhidden' are not set.

Option 'bufhidden' for Tree buffers is set to "wipe" instead of "hide".
This should make it less likely that an orphan Tree is hanging around long
after its Body is gone.

PyLog buffer has 'bufhidden' set to "wipe" instead of "hide".
PyLog filetype is set to "voomlog" instead of "log".
PyLog syntax: better highlighting of Python tracebacks.

In several places in voom.py a new list of Body lines was created for no good
reason: VOOM.buffers[body][:]. These were changed to VOOM.buffers[body], which
is Vim buffer object. This substantially reduces memory usage, especially when
working with large buffers. This affects outline update. Timing tests with
calendar_outline.txt: makeOutline() is slower (0.15 vs 0.11 sec). But the
overall time to run update on Tree BufEnter is about the same (0.16 sec if no
outline change), so it's definitely worth it.
Similarly, there is no need to create a new list of current Tree lines in
updateTree() (tlines_ = Tree[:]) since we compare Tree lines one by one.

PROBLEM: Tree window-local settings can be wrong if new window is created
manually.  Example: cursor is in Body, :split, :b[Tree bufnr].
FIX: On Tree BufEnter check if w:voom_tree exists. If not, call
Voom_TreeConfigWin()--it sets window-local options and creates w:voom_tree.

Added "vim" filetype to default g:voom_rstrip_chars: # is stripped in addition
to " because it's comment char in Python etc. sections of .vim files.

    Various code changes

Renamed VOOM.nodes to VOOM.bnodes to make clearer it is list of Body lnums.

voom.py functions no longer access voom.vim script-local variables directly.
This means all voom.py functions can be called from add-ons.
Some functions used to compute tree from body like this
    tree = int(vim.eval('s:voom_bodies[%s].tree' %body))
These now  require both body and tree as arguments. (updateTree, verifyTree,
nodeUNL)
In several places snLn was set:
    vim.command('let s:voom_bodies[%s].snLn=%s' %(body, snLn))
These now call Voom_SetSnLn(body,snLn) instead.

When converting buffer lines to/from Python Unicode objects encoding is set to
"utf-8" if &encoding is any Unicode encoding. It turns out Vim uses utf-8
internally in such cases. See voom.getVimEnc()

Vim code changes due to new scheme of dealing with unloaded and deleted Body
buffers. Body BufUnload au is gone. New Body BufEnter au detects loss of
buffer-local mappings.

Tree autocmds are now buffer-local. This seems more robust than relying on Tree
name pattern, easier to disable for individual Trees should we need to do so.
s:voom_TreeBufEnter is not needed anymore.

Got rid of b:voom_tree and b:voom_body. Use hasmapto('Voom_ToTreeOrBodyWin') to
detect loss of buffer-local mappings.


crash after :q, :q!   [[[4  ~

(reported by William Fugy)
Current tabpage has two windows: Body and corresponding Tree.
There are no other windows with Body or Tree.
'hidden' is off, Body 'bufhidden' is "".
With cursor in Body, :q or :q! produce spectacular crash--sometimes gvim.exe
crashes, sometimes stream of E315 errors.
-------------------------------------------------
The culprit is Body BufUnload autocmd: it wipes out Tree buffer and thus can
close windows and tabs. This confuses :q but not :bun :bd :bw.

Setting hidden or bufhidden doesn't help because :q! always unloads buffer.

Kludge attempt in Body BufUnload, before Tree wipeout: 
    if winnr('$')==2 && bufwinnr(body)>0 && bufwinnr(tree)>0
        new
    endif
No crashes after :q or q!. New crash after :bd, :bw in Body.
Creating new window on BufUnload is as dangerous as closing one.

Not wiping out Tree on Body BufUnload is the only solution.
-------------------------------------------------
Got rid of Body BufUnload au.
Try Body BufWipeout au -- wipe out Tree when Body is wiped out.

Crash after :q still happens if Body 'bufhidden' is "wipe" -- obviously same
situation as with BufUnload. Such setting seems unlikely. :Voom can refuse to
create outline if current buffer has such setting.

ANOTHER NASTY GLITCH:
gvim.exe test_outline.txt
:Voom
:bw1
Tree is gone, window still shows test_outline.txt -- this is horribly wrong.
:Voom
Both Body and Tree are empty.

**CONCLUSION: DON'T DO IT**
The workaround is function Voom_Delete('ex_command') to be used in custom
mappings.
Also, set Tree 'bufhidden' to wipe instead of hide.

-------------------------
Possible Body BufWipeout au, should be safe:
if Tree is shown in a window: set Tree bufhidden to wipe
if not: wipe out Tree
This is too convoluted.


Tree folds are wrong in split windows after outline operation   [[[4~

gvim.exe test_outline.txt
:Voom
:set fdc=6
:split
:split
Copy node "5", Paste after "5.2"
Folds are wrong in 2nd and 3rd window.

Also affects Tree windows in other tabs.
Folds in the current window are fixed after :setl fdm=expr
--------------------------
Sorting is not afflicted with this bug.
Sorting is different from other Oops--Tree is drawn while in Tree, on BufEnter.
Change 
    call Voom_OopFromBody(body,tree,l:blnShow,'')
to 
    if Voom_BodyUpdateTree()==-1 | let &lz=lz_ | return | endif
    call Voom_OopFromBody(body,tree,l:blnShow,'noa')
and folds are wrong in split windows
--------------------------
Thus, the fix is to draw Tree lines while in Tree.

Current Oop scheme for most Oops, start in Tree, Vim code:
    perform checks, get data
    go to Body
    check ticks
    run Python code:
        change Body lines; change Tree lines; adjust bnodes and levels
    call Voom_OopFromBody() -- adjust Body view and go back to Tree
    adjust Tree view

New Oop scheme, start in Tree, Vim code:
    perform checks, get data
    go to Body
    check ticks
    run Python code:
        change Body lines; (adjust bnodes and levels)
        call Voom_OopFromBody() -- adjust Body view and go back to Tree
        change Tree lines; (adjust bnodes and levels)
    adjust Tree view

Changed the following Oops: Paste, Cut, Up, Down, Right, Left.

These Oops do not change Tree folds: Mark/Unmark, Mark as selected
No change is needed for: Insert new node (done from Tree), Copy.
Save/Restore/Cleanup Folding do not modify Tree, they are done from Tree.
--------------------------
Folds can also be wrong in split Tree windows after outline update was forced
from Body after :Voomgrep, :Voomunl, etc. This is rare and no big deal.


v2.1, 2010-06-01   [[[3~

The procedure for constructing Tree headline text was modifed to permit
customization for individual filetypes:
    - Comment chars that are stripped from the right side of Tree headlines
      are by default obtained from Body's 'commentstring' option.
    - User dictionary g:voom_rstrip_chars can be used to control exactly which
      characters are stripped from the right side of Tree headlines. This is
      done for individual filetypes and will overide 'commentstring' option.
    - Finally, an arbitrary headline constructing function can be defined for
      individual filetypes in an add-on. Add-on "custom_headlines.vim" shows
      how.
For details, see node
    OUTLINING (:Voom) -> Create Outline -> Tree Headline Text

New user option "g:voom_create_devel_commands" controls if development helper
commands are created. They are commented out in previous versions.

Removed <F1> Tree-local mapping (same as :Voomhelp).

Bug in PyLog buffer creation/destruction: Python original sys.stdout and
sys.stderr can be lost after some actions, e.g. after command :VoomReloadAll.
FIX: changed how original sys.stdout and sys.stderr are saved.


v2.0, 2010-04-01   [[[3~

The name of this plugin was changed from VOOF (Vim Outliner Of Folds) to VOoM
(Vim Outliner of Markers):
    - The new name is more accurate. It deemphasizes the role of folds. Body
      buffer folding has no effect on outline construction or on outline
      operations. Markers are determined by option "foldmarker", but only
      start fold markers with levels are used.
    - Voom sounds better than Voof, more energetic -- vroom-zoom-boom.
      (Look matey, this parrot wouldn't "voom" if I put four thousand volts
      through it.)

Corresponding changes were made in file names, commands, user options, help
tags, names of functions and variables. All occurrences of VOOF/Voof/voof were
changed to VOOM/Voom/voom: the command "Voof" became "Voom",
"g:voof_tree_placement" became "g:voom_tree_placement", and so on.

If you are upgrading from previous versions, please delete old "voof" files
(voof.vim, voof.py, voof.pyc, voof.txt), delete file "voofScript.py" if any,
edit user options in .vimrc if you have any, run :helptags.

Added rudimentary support for add-ons, sample add-on "voom_info.vim". See node
    Implementation notes -> Extending VOoM with add-ons
for details.

Added instructions for Windows users on how to get Python-enabled Vim.

Renamed some functions. Other minor code style changes.

There is an elusive bug in mouse left click Tree mapping. It seems it's
possible for <LeftRelease> to be triggered in a wrong buffer. Cannot
reproduce, has something to do with resizing windows.
FIX: added check that current buffer is Tree in Voom_TreeMouseClick().


v1.92, 2010-03-03   [[[3~

PROBLEM: outline operations Mark/Unmark, Move Right/Left can be slow when they
involve a large number of folds.
EXAMPLE: mark/unmark all nodes in calendar_outline.txt takes about 3 seconds.
But set Body foldmethod to "manual" and the time is reduced to 0.85 seconds.
Set Tree foldmethod to "manual" and the time is reduced further to 0.16 sec.
FIX: Set Tree and Body foldmethod to "manual" during Mark/Unmark. Set Body
foldmethod to manual during Move Right/Left. Other operations are not
susceptible.

Command :VoofFoldingSave is now much faster when applied to huge and deeply
nested branches with lots of closed folds. The problem was recursive function
foldingGet(). Got rid of recursion -- unnecessary and inefficient.
foldingGet() and foldingGetAll() were merged into foldingGet().

If Body "foldmethod" is not "marker", Body node could be hidden in fold after
selecting node.
FIX: do "zv" in Body after: selecting node in Tree, outline operations, on
startup. In other words, if foldmethod is marker, do "zMzvzt" to show selected
Body node. Otherwise do "zvzt".

Fixed stupid code in Voof_ToTreeOrBodyWin(), which is the <Tab> command -- no
need to visit all windows to find the target. It was causing confusion when
working with split windows.

Code tweaks to save precious microseconds:
voof.vim
    - Use stridx(line,'|') instead of match(line,'|') in various Tree
      functions, including foldexpr.
    - Compacted and simplified Tree foldexpr function.
voof.py
    - xrange() is now used in many places instead of other iteration methods.
    - Cleaned up some code, especially for outline operations.


v1.91, 2010-02-06   [[[3~
Command :Voofgrep can now perform boolean AND and NOT searches.

Increased maximum number of matches when doing Voofgrep to 10000 from 1000.

Annoyance: when outline is created, there can be unnecessary scrolling down in
the Tree window.
Fix: Voof_TreeCreate() code that puts cursor on startup node. Do "gg" before
jumping to startup node to counteract scrolling caused by fiddling with folds.
Don't do "zz" if the first or the last Tree line is in the window.

There were some "normal" in voof.vim. Changed all to "normal!".


v1.9, 2009-12-19   [[[3~
It's now possible to save and restore Tree buffer folding. This feature uses
special node marks "o" in Body headlines. See |voof_VoofFoldingSave|.

New Tree mapping: + (Shift-=) finds startup node, if any, that is  node marked
with "=" in Body headline. Warns if there are several such nodes.

Command "Voofrun" was renamed "Voofexec".

Tree mapping for Execute Script was changed to "<LocalLeader>e" from
"<LocalLeader>r", which was in conflict with mapping for "Move Right".

Executing Python code via Voofexec: source code encoding is now specified on
the first line of script file as per http://www.python.org/dev/peps/pep-0263/.
Encoding is obtained from Body's 'fenc' or, if it's empty, from 'enc'.

Fixed bug in Voofexec: unsupported script type argument was ignored if
buffer's filetype was a supported script type. More informative message if
script type is unsupported.

Improved how the command Edit Headline (iIaA) positions cursor in Body
headline: "\<" is used instead of "\w" to find the first word char. This works
better with unicode.

"g:voof_tree_hight" and "g:voof_log_hight" were renamed "g:voof_tree_height"
and "g:voof_log_height" respectively.


v1.8, 2009-09-18   [[[3~
Bug in Normal mode mappings: nasty errors when attempting to use mapping with
a count, which is not supported, e.g., 3<Return>.
Fix: made all mappings start with ":<C-u>" to clear command line before
calling a function.

Added highlighting of warning and error messages.

Added fancy highlighting of Voofunl output: different highlights for headlines
and separators.

Correction in docs: <Tab>/CTRL-I is Vim default key for going forward in the
jumps list.

Distribution now follows Vim directory structure: there are /plugin and /doc
folders. Simplified Voofhelp accordingly: if voof.vim is in dir a/b, voof.txt
is assumed to be in a/doc.

Changed license to WTFPL, version 2.

v1.7, 2009-08-31   [[[3~
Checks that previously checked that Body or Tree buffer exists now check if
the buffer is loaded (bufloaded()). This is needed because bad things happen
when writing to an unloaded buffer via Python's vim.buffer.
See "Implementation notes -> unloaded buffer + python == trouble"

When killing Trees and PyLog do "bwipeout" instead of "bwipeout!" -- it's
sufficient and safer.

Adjusted how new Tree window is opened: previous window (^wp) is used if it
shows a Tree buffer.

PyLog:
Added fail-safe check that ensures PyLog buffer is loaded before being written
to. This can be tested by unloading PyLog with "noa bun" or "noa bd" and then
printing to it: py print "something".
Added workaround for a glitch with the output of help().
Made voof_logbnr variable script-local.

v1.6, 2009-08-23   [[[3~
Added checks to prevent data corruption when outline update fails for any
reason. When these checks fail, the Tree buffer is wiped out and outline data
are cleaned up. These checks can be tested as follows:
    - Create outline with the Voof command.
    - Delete some lines in Body buffer.
    - Move to Tree buffer with
      :noa wincmd w
    - Tree update did not happen and outline data are out of sync with the
      Body. In previous versions, performing outline operation at this stage
      would cause data corruption.
    - Select new node or try outline operation. Voof will issue error message,
      wipe out Tree buffer, and perform clean up.
Another way to test these checks is to modify Body file with an external
application while cursor is in the Tree window.
There is more details in "Implementation notes -> Checking Bodies for ticks".

Added some other foolproofing measures.

Improved automatic scrolling of PyLog buffer. Both previous (^wp) and current
window numbers are preserved in tabpages where PyLog is scrolled. Previously,
only current window number was preserved.

Fixed some bugs. Streamlined some code.

v1.5, 2009-08-15   [[[3~
New commands: Voofgrep, Voofunl.

Fixed blunder in "Move Down" outline operation that could cause outline
corruption. To find node after which to move, the cursor must be put on the
last node of the branch. That was done in Visual mode, but not in Normal mode.

<Return> and <Tab> in Tree buffers now also work in Visual mode.

Changed behavior of <Tab>: move cursor to Body window if current window is
Tree and vice versa. Previous behavior (cycle through all Body and Tree
windows) was less useful and inconsistent with <Return> behavior.

Added checks for Body foldmethod. If it's not "marker":
 - folds in Body are not collapsed (zMzv) after node selection in Tree and
   after outline operations;
 - Voofrun will refuse to run when executed while in Body buffer.

Made Tree buffers and PyLog buffer unlisted.

If possible, :Voofhelp command will open voof.txt via "tab help voof.txt"
command, so that tags will be active.

Made help tags start with "voof_".

Edited "Why VOoF uses Python": it turns out there is a fast, pure Vim method
to scan for headlines, but it's much less convenient than the Python way: >
    let headlines=[]
    g/{{{\d\+/ call add(headlines, getline('.'))       "}}}

code improvements [[[4~
The way "eventignore" was used to temporarily disable autocommands was unsafe.
"eventignore" is no longer set anywhere. "noautocmd" is used instead:
|autocmd-disable|.

Modified voof.voofUpdate() (formally treeUpdate) to work from any buffer as
long as the Tree is "ma". Voof_TreeBufEnter() now calls voof.voofUpdate()
directly.  Voof_BodyUpdateTree() updates Tree while in Body without moving to
Tree. This is extremely useful--can now use outline data while in Body.

Optimization in voof.voofOutline() parser function: >
    if not marker in line: continue
This makes sense because search with marker regexp is 3-4 times slower than
the above membership test, and in a typical outline most lines don't have
markers. Timing voof.voofUpdate() in Voof_TreeBufEnter(),
"calendar_outline.txt" update when headlines unchanged:
0.17 sec instead of 0.24 sec.

Changed Vim data variables voof_bodies, voof_trees, etc. from global to
script-local. Command VoofPrintData prints these for debugging purposes.
Should external scripts need to read these, a function that returns these
could be provided.

voof.computeSnLn() uses bisect--should be faster than previous naive code.

Changed <f-args> in Voofrun to <q-args> -- simpler.

PyLog code is, hopefully, near the state of perfection: when something goes
wrong, the exception info is displayed no matter what.

voof.oopMarkSelected() -- don't remove just one =, strip all consecutive

Voof_GetLines() uses winsaveview()/winrestview() to prevent scrolling after
zc/zo.

Use setreg() to restore registers exactly as shown in help.
Doing "let @z=z_old" is not reliable enough--register mode can change.


v1.4, 2009-07-12   [[[3~
New Tree navigation commands (Normal mode):
 x   Go to next marked node (mnemonic: find headline marked with "x").
 X   Go to previous marked node.

"Unmark Node" operation now removes all consecutive "x" chars from Body
headline instead of just one. This eliminates confusion when a bunch of "x" is
present after start fold marker level number. For the same reason, "Mark Node
as Selected" (<LocalLeader>=) now strips "x" chars after removed "=" char.

Bug: When Body starts with a headline, click on the first line in Tree (path
info line) doesn't select first node.
Fix: in Python code of Voof_TreeSelect() replaced
 nodeEnd =  VOOF.nodes[body][lnum]-1
   with
 nodeEnd =  VOOF.nodes[body][lnum]-1 or 1

Fixed errors in LogBufferClass write() method, printing messages when log
buffer doesn't exist.

Bug: Select more than one lines in Tree and press i/I/A/a. An error in
Voof_OopEdit() occurs.
Fix: Mapped i/I/A/a keys only for Normal mode with nnoremap. They were
mistakenly mapped with noremap.

A message is now printed when an outline operation is aborted because Body
buffer is readonly or nomodifiable.

Replaced most Python regions in voof.vim with voof.py functions.

Renamed some Python functions:
voof_WhatEver() means it's Python code for Voof_WhatEver() Vim function.

Voof_FoldLines() renamed Voof_GetLines().
Voof_FoldRun() renamed Voof_Run().

Various edits and additions in voof.txt.


v1.3, 2009-06-06   [[[3~
New: start fold marker string is obtained from Vim option 'foldmarker' when
the Voof command is run. Each Body buffer can have its own start fold marker.

Replaced Body's BufDelete autocommand with BufUnload autocommand. Tree buffer
is now wiped out when its Body is unloaded, deleted or wiped out. Corrected
Body and Tree BufUnload au functions: use "nested" and "noautocmd".

Added * to chars being stripped during headline construction to allow /**/
around fold markers. Better syntax highlight for commented headlines in Tree.

Changed how Tree buffer name is constructed: {bufname}_VOOF{bufnr} instead of
VOOF_{bufname}_{bufnr}.

When checking if current buffer is a Tree, instead of checking buffer name, do
has_key(g:voof_trees, bufnr('')).

When eventignore is set, save and restore original eventignore instead of
doing "set eventignore=" .

Annoyance: Moving Tree window to top/bottom (^W K/J) maximizes window height.
Fix: Don't set "winfixheight" when creating Tree window. I don't understand why
this happens. There is no such problem with "winfixwidth".

Got rid of Voof_ErrorMsg() and Voof_InfoMsg().

Expanded help file.

v1.2, 2009-05-30   [[[3~
Bug: after outline operation cursor may be on the last line of range instead
of first (if Visual and there is only one root node).
Fix: tweaked Voof_OopShowTree().

Re-wrote Voof_TreeToggleFold() to handle: no fold at cursor; cursor hidden in
fold.

Allow outline operation Copy when Body is noma or ro.

v1.1, 2009-05-26   [[[3~
Bug fix involving nomodifiable and readonly buffers.
Outline operations now silently abort if Body is noma or ro.

v1.0, 2009-05-25   [[[3~
Initial release.

==============================================================================
modelines   [[[1~
 vim:fdm=marker:fmr=[[[,]]]:ft=help:ai:et:noma:ro:
 vim:foldtext=getline(v\:foldstart).'...'.(v\:foldend-v\:foldstart):
plugin/voom.vim	[[[1
24
" voom.vim
" Last Modified: 2014-05-28
" Version: 5.1
" VOoM -- Vim two-pane outliner, plugin for Python-enabled Vim 7.x
" Website: http://www.vim.org/scripts/script.php?script_id=2657
" Author: Vlad Irnov (vlad DOT irnov AT gmail DOT com)
" License: CC0, see http://creativecommons.org/publicdomain/zero/1.0/

if exists('g:voom_did_load_plugin')
  finish
endif
let g:voom_did_load_plugin = 'v5.1'

com! -complete=custom,voom#Complete -nargs=? Voom call voom#Init(<q-args>)
com! -complete=custom,voom#Complete -nargs=? VoomToggle call voom#Init(<q-args>,1)
com! Voomhelp call voom#Help()
com! Voomlog  call voom#LogInit()
com! -nargs=? Voomexec call voom#Exec(<q-args>)
" other commands are defined in ../autoload/voom.vim

" support for Vim sessions (:mksession)
au BufFilePost __PyLog__ call voom#LogSessionLoad()
au BufFilePost *_VOOM\d\+ call voom#TreeSessionLoad()

