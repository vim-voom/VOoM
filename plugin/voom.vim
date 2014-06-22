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

