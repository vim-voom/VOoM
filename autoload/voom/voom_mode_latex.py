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


