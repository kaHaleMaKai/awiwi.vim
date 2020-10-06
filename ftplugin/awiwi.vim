" assert plugins being available
if !exists('g:awiwi_home')
  echoerr 'g:awiwi_home is not defined'
  finish
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

nnoremap <silent> <buffer> gf :call awiwi#open_link()<CR>
nnoremap <silent> <buffer> gC :Awiwi continue<CR>
nnoremap <silent> <buffer> gT :Awiwi todo<CR>
nnoremap <silent> <buffer> ge :Awiwi journal today<CR>
nnoremap <silent> <buffer> <F12> :Awiwi tasks<CR>
nnoremap <silent> <buffer> gn :Awiwi journal next<CR>
nnoremap <silent> <buffer> gp :Awiwi journal previous<CR>


fun! s:handle_enter_on_insert() abort "{{{
  let line = getline('.')
  let m = matchlist(line, '^\([[:space:]]*\)\([-*]\)\([[:space:]]\+\)\(\[[ x]\+\]\)\?')
  if empty(m)
    normal! o
    starti
    return
  endif
  let find_spaces = matchlist(line, '^\([[:space:]]*\)\([-*]\)\([[:space:]]\+\)\(\[[ x]\+\][[:space:]]*\)\?$')
  if !empty(find_spaces)
    let spaces = find_spaces[1]
    call setline('.', spaces)
    starti
    return
  endif

  " FIXME use m from above
  let append = v:true
  if empty(m)
    let text = ''
    let pos = 0
  elseif empty(m[4])
    if match(line, '[[:space:]][^[:space:]]') == -1
      call setline('.', '')
      normal! o
      starti
      return
    endif
    let text = m[1].m[2].m[3]
    let pos = strlen(text)
  else
    if match(line, '\][[:space:]]*[^[:space:]]') == -1
          \ || match(line, '^[-*][[:space:]]\+\[[x ]\][[:space:]]\+(from [-0-9]\+)[[:space:]]*$') > -1
      call setline('.', '')
      normal! o
      starti
      return
    endif
    let marker = m[1] . m[2] . ' [ ] '
    let pos = strlen(marker) + 1
    if str#endswith(&ft, '.todo')
      let text = marker.printf(' (from %s)', strftime('%F'))
      let append = v:false
    else
      let text = marker
    endif
  endif
  let cursor = getcurpos()
  let cursor[1] += 1
  let cursor[2] = pos
  call append('.', text)
  call setpos('.', cursor)
  if append
    starti!
  else
    starti
  endif
endfun "}}}


fun! s:handle_enter() abort "{{{
  if mode() != 'n'
    stopi
  endif
  let line = getline('.')
  let pos = matchend(line, '^[[:space:]]*[-*][[:space:]]\+\[[ x]\(\]\)\@=')
  if pos == -1
    let m = matchstr(line, '^[[:space:]]*[-*][[:space:]]\+')
    if empty(m)
      normal! <CR>
      return
    endif
    startinsert!
    return
  endif

  let ch = line[pos-1]
  let cursor = getcurpos()
  let is_open = ch == ' '
  let markers = awiwi#get_markers('due', {'join': v:false, 'escape_mode': 'vim'})
  let ms = join(markers, '\|')
  let pattern = printf('\(\(%s\)\([[:space:]]\+[[:digit:]-.:]\+\)\{0,2}\|(\?\(%s\)\([[:space:]]\+[^[:space:])]\+\)*)\?\)', ms, ms)
  let anti_pattern = '\~\~' . pattern . '\~\~'
  let due_pos = []
  if is_open
    let new_char = 'x'
    let m = matchstrpos(line, pattern)
    if m[1] != -1 && line[m[1] - 1] != '~'
      let due_pos = m[1:]
    endif
  else
    let new_char = ' '
    let m = matchstrpos(line, anti_pattern)
    if m[1] != -1
      let due_pos = m[1:]
    endif
  endif

  let new_line = line[:pos-2] . new_char . line[pos:]
  let offset = 0
  if !empty(due_pos)
    let [start, end] = due_pos
    if is_open
      let new_line = new_line[:start-1] . '~~' . new_line[start:end-1] . '~~' . new_line[end:]
      if cursor[2] >= end
        let cursor[2] += 4
      elseif cursor[2] >= start
        let cursor[2] += 2
      endif
    else
      let new_line = new_line[:start-1] . new_line[start+2:end-3] . new_line[end:]
      if cursor[2] >= end
        let cursor[2] -= 4
      elseif cursor[2] >= start
        let cursor[2] -= 2
      endif
    endif
  endif
  call setline(cursor[1], new_line)
  call setpos('.', cursor)
  sil w
  normal! j
endfun "}}}

nnoremap <silent> <buffer> o :call <sid>handle_enter_on_insert()<CR>
inoremap <silent> <buffer> <Enter> <Esc>:call <sid>handle_enter_on_insert()<CR>
nnoremap <silent> <buffer> <Enter> :call <sid>handle_enter()<CR>

augroup awiwiAutosave
  au!
  au InsertLeave,CursorHold *.md silent w
augroup END

inoremap <silent> <buffer> <C-d> <C-r>=strftime('%F')<CR>
inoremap <silent> <buffer> <C-f> <C-r>=strftime('%H:%M')<CR>

iabbrev :shrug: `¯\_(ツ)_/¯`
iabbrev :arrow: →
iabbrev :check: ✔
iabbrev :cross: ✖
