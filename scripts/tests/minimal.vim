set noswapfile
set shadafile=NONE

let s:deps_path = getcwd() . '/.deps'
let s:test_root = tempname()
call mkdir(s:test_root, 'p')

let g:hangar_test_root = s:test_root
let $XDG_CONFIG_HOME = s:test_root . '/config'
let $XDG_DATA_HOME = s:test_root . '/data'
let $XDG_CACHE_HOME = s:test_root . '/cache'
let $XDG_STATE_HOME = s:test_root . '/state'
call mkdir(stdpath('log'), 'p')
let g:hangar_test_deps_path = s:deps_path
let g:hangar_state_path = s:test_root . '/hangar.json'

function! s:cleanup_test_root() abort
  if isdirectory(s:test_root)
    call delete(s:test_root, 'rf')
  endif
endfunction

augroup HangarTestCleanup
  autocmd!
  autocmd VimLeavePre * call <SID>cleanup_test_root()
augroup END

lua << EOF
local repository = vim.fn.getcwd()
vim.opt.runtimepath = { repository, vim.env.VIMRUNTIME }
vim.opt.packpath = {}
package.path = repository .. "/?.lua;" .. package.path
EOF
execute 'set rtp+=' . fnameescape(s:deps_path . '/plenary.nvim')
runtime! plugin/plenary.vim
lua require('tests.helpers').setup()
