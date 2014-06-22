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
