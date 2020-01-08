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

nnoremap <silent> <buffer> gf :Awiwi asset create<CR>
nnoremap <silent> <buffer> gC :Awiwi continue<CR>
nnoremap <silent> <buffer> gT :Awiwi todo<CR>
nnoremap <silent> <buffer> ge :Awiwi journal today<CR>
nnoremap <silent> <buffer> <F12> :Awiwi tasks<CR>
nnoremap <silent> <buffer> gn :Awiwi journal next<CR>
nnoremap <silent> <buffer> gp :Awiwi journal previous<CR>

fun! s:handle_enter_on_insert() abort "{{{
  let line = getline('.')
  let m = matchlist(getline('.'), '^\([-*]\)\([[:space:]]\+\[[ x]\+\]\)')
  if empty(m)
    return "\n"
  else
    let marker = "\n".m[1].' [ ] '
    return marker
  endif
endfun "}}}


fun! s:handle_enter() abort "{{{
  let line = getline('.')
  let pos = matchend(getline('.'), '^[-*][[:space:]]\+\[[ x]\(\]\)\@=')
  if pos == -1
    return
  endif

  let ch = line[pos-1]
  let cursor = getcurpos()
  if ch == 'x'
    let new_char = ' '
  else
    let new_char = 'x'
  endif
  exe printf('normal! %d|r%s', pos, new_char)
  call setpos('.', cursor)
  sil w
  normal! j
endfun "}}}


if str#endswith(&ft, '.todo')
  nnoremap <silent> <buffer> o o*<Space>
  nnoremap <silent> <buffer> O O*<Space>
  inoremap <silent> <buffer> <Enter> <CR>*<Space>
else
  nnoremap <silent> <buffer> o A<C-r>=<sid>handle_enter_on_insert()<CR>
  inoremap <silent> <buffer> <Enter> <C-r>=<sid>handle_enter_on_insert()<CR>
  nnoremap <silent> <buffer> <Enter> :call <sid>handle_enter()<CR>
endif

augroup awiwiAutosave
  au!
  au InsertLeave,CursorHold *.md silent w
augroup END

iabbrev :shrug: `¯\_(ツ)_/¯`
iabbrev :arrow: →
iabbrev :check: ✔
iabbrev :cross: ✖
