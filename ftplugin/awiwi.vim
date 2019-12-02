if exists('b:loaded_awiwi')
  finish
endif
let b:loaded_awiwi = v:true

" assert plugins being available
if !exists('g:awiwi_home')
  throw AwiwiError 'g:awiwi_home is not defined'
elseif !exists('*path#join')
  throw 'AwiwiError: path.vim plugin is required'
elseif !exists('*func#apply')
  throw 'AwiwiError: func.vim plugin is required'
elseif !exists('*str#startswith')
  throw 'AwiwiError: str.vim plugin is required'
endif

" ++++++++++++++++++++++++++++++++++++++++
" +              commands                +
" ++++++++++++++++++++++++++++++++++++++++

command!
      \ -nargs=+
      \ -complete=customlist,awiwi#_get_completion
      \ Awiwi
      \ call awiwi#run(<f-args>)

" ++++++++++++++++++++++++++++++++++++++++
" +                maps                  +
" ++++++++++++++++++++++++++++++++++++++++

nnoremap <silent> <buffer> gf :Awiwi open-asset<CR>
nnoremap <silent> <buffer> gC :Awiwi continue<CR>
nnoremap <silent> <buffer> gT :Awiwi journal todos<CR>
nnoremap <silent> <buffer> ge :Awiwi journal today<CR>
nnoremap <silent> <buffer> <F12> :Awiwi tasks<CR>
nnoremap <silent> <buffer> gn :Awiwi journal next<CR>
nnoremap <silent> <buffer> gp :Awiwi journal previous<CR>

if str#endswith(&ft, '.todo')
  nnoremap <silent> <buffer> o o*<Space>
  nnoremap <silent> <buffer> O O*<Space>
  inoremap <silent> <buffer> <Enter> <CR>*<Space>
endif
