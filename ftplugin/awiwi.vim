" assert plugins being available
if !exists('g:awiwi_home')
  echoerr 'g:awiwi_home is not defined'
  finish
endif

" don't put too much pressure on the machine
set updatetime=4000
if exists('g:gitgutter_enabled')
  let g:gitgutter_enabled = v:false
  GitGutterDisable
endif

" ++++++++++++++++++++++++++++++++++++++++
" +              commands                +
" ++++++++++++++++++++++++++++++++++++++++

command!
      \ -nargs=+
      \ -complete=customlist,awiwi#cmd#get_completion
      \ Awiwi
      \ call awiwi#cmd#run(<f-args>)

" ++++++++++++++++++++++++++++++++++++++++
" +                maps                  +
" ++++++++++++++++++++++++++++++++++++++++

nnoremap <silent> <buffer> gf :call awiwi#open_link({'new_window': v:true})<CR>
nnoremap <silent> <buffer> <leader>gft :call awiwi#open_link({'new_window': v:false, 'new_tab': v:true})<CR>
nnoremap <silent> <buffer> <leader>gfn :call awiwi#open_link({'new_window': v:true})<CR>
nnoremap <silent> <buffer> gC :Awiwi continue<CR>
nnoremap <silent> <buffer> gT :Awiwi todo<CR>
nnoremap <silent> <buffer> ge :Awiwi journal today<CR>
nnoremap <silent> <buffer> <F12> :Awiwi tasks<CR>
nnoremap <silent> <buffer> gn :Awiwi journal next<CR>
nnoremap <silent> <buffer> gp :Awiwi journal previous<CR>


if awiwi#str#contains(expand('%:h'), '/assets/')
  nnoremap <silent> <buffer> gj :exe printf('e %s', awiwi#asset#get_journal_for_current_asset())<CR>
endif


fun! s:handle_enter_on_insert(mode, above) abort "{{{
  let line = getline('.')
  " is this any kind of list?
  let m = matchlist(line, '^\([[:space:]]*\)\([-*]\)\([[:space:]]\+\)\(\[[ x]\+\]\)\?')
  let o_cmd = printf('normal! %s', a:above ? 'O' : 'o')
  if empty(m)
    if a:mode == 'n'
      exe o_cmd
    else
      let pos = getcurpos()[-1]
      if pos > strlen(line)
        exe 'normal! o'
      else
        exe "normal! i\n"
      endif
    endif
    starti
    return
  endif
  let find_spaces = matchlist(line, '^\([[:space:]]*\)\([-*]\)\([[:space:]]\+\)\(\[[ x]\+\][[:space:]]*\)\?$')
  if !empty(find_spaces)
    let spaces = find_spaces[1]
    if !empty(spaces)
      call setline('.', line[2:])
    else
      call setline('.', spaces)
    endif
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
      exe o_cmd
      starti
      return
    endif
    let text = m[1].m[2].m[3]
    let pos = strlen(text)
  else
    if match(line, '\][[:space:]]*[^[:space:]]') == -1
          \ || match(line, '^[-*][[:space:]]\+\[[x ]\][[:space:]]\+(from [-0-9]\+)[[:space:]]*$') > -1
      call setline('.', '')
      exe o_cmd
      starti
      return
    endif
    let marker = m[1] . m[2] . ' [ ] '
    let pos = strlen(marker) + 1
    if awiwi#str#endswith(&ft, '.todo')
      let text = marker.printf(' (from %s)', strftime('%F'))
      let append = v:false
    else
      let text = marker
    endif
  endif
  let cursor = getcurpos()
  let cursor[2] = pos
  let line_nr = cursor[1]
  if a:above
    call append(line_nr - 1, text)
  else
    let cursor[1] += 1
    call append(line_nr, text)
  endif
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


fun! s:delete_old_tasks() abort "{{{
py3 << EOF
import re
import datetime


today = datetime.date.today()
max_line_nr: int = int(vim.eval("line('$')"))

for line_nr in range(max_line_nr - 1, -1, -1):
    line: str = vim.eval(f"getline('{line_nr}')")
    if line.startswith("* [ ]"):
        continue
    match = re.search("(?:[(]from )([-0-9]{10})(?:[)])", line)
    if not match:
        continue
    date = datetime.date.fromisoformat(match.group(1))
    if (today - date).days <= 30:
        continue
    vim.command(f"{line_nr}d")
EOF
endfun "}}}


nnoremap <silent> <buffer> O :call <sid>handle_enter_on_insert('n', v:true)<CR>
nnoremap <silent> <buffer> o :call <sid>handle_enter_on_insert('n', v:false)<CR>
inoremap <silent> <buffer> <Enter> <C-o>:call <sid>handle_enter_on_insert('i', v:false)<CR>
nnoremap <silent> <buffer> <Enter> :call <sid>handle_enter()<CR>

augroup awiwiAutosave
  au!
  au InsertLeave,CursorHold *.md silent w
augroup END

augroup awiwiDeleteOldTasks
  au!
  au BufEnter,BufWritePre */journal/todos.md call <sid>delete_old_tasks()
augroup END

" inoremap <silent> <buffer> <C-d> <C-r>=strftime('%F')<CR>
inoremap <silent> <buffer> <C-f> <C-r>=strftime('%H:%M')<CR>
nnoremap <silent> <buffer> <C-q> :Awiwi redact<CR>
inoremap <silent> <buffer> <C-q> <C-o>:Awiwi redact<CR>
inoremap <silent> <buffer> <C-v> <C-o>:call awiwi#handle_paste_in_insert_mode()<CR>

exe 'inoremap <buffer> <C-s> <C-o>:Awiwi link '
exe 'inoremap <buffer> <C-b> <C-o>:Awiwi asset create<CR>'

iabbrev :shrug: `¯\_(ツ)_/¯`
iabbrev :arrow: →
iabbrev :check: ✔
iabbrev :cross: ✖

let awiwi_server = get(g:, 'awiwi_autostart_server', '')
if !empty(awiwi_server) && !awiwi#server#server_is_running()
  call awiwi#server#start_server(awiwi_server)
endif
