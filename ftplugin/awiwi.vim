" if exists("b:did_ftplugin")
"   finish
" endif
" let b:did_ftplugin = 1

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


fun! s:get_line_start(prefix_space, list_char, infix_space, is_checklist) abort "{{{
  let line = [a:prefix_space, a:list_char]
  if a:is_checklist
    call extend(line, [a:infix_space, '[ ]'])
  endif
  if !empty(a:list_char)
    call add(line, ' ')
  endif
  return join(line, '')
endfun "}}}


fun! s:pad(length, ...) abort "{{{
  let content = a:0 ? a:1 : ''
  return printf('%' . a:length . 's%s', '', content)
endfun "}}}


fun! s:handle_enter_on_insert(mode, above, continue_paragraph) abort "{{{
  let line = getline('.')
  let cursor = getcurpos()
  let line_nr = cursor[1]
  let pos = cursor[2]
  let m = matchlist(line, '^\([[:space:]]*\)\(\([-*]\)\([[:space:]]\+\)\)\?\(\(\[[ x]\+\]\)\([[:space:]]*\)\)\?\([^[:space:]].*$\)\?')
  let o_cmd = printf('normal! %s', a:above ? 'O' : 'o')
  let is_trailing_cursor = cursor[-1] > strlen(line)

  let prefix_space = m[1]
  let [list_char, infix_space] = m[3:4]
  let [checkbox, postfix_space, actual_content] = m[6:8]
  let is_checklist = !empty(checkbox)
  let is_list = !empty(list_char)

  " handle regular insert. this is no list, check-list etc.
  if !len(line)
    if a:mode == 'n'
      exe o_cmd
    elseif a:above
      call append(line_nr - 1, '')
    else
      call append(line_nr, '')
      let cursor[1] += 1
      call setpos('.', cursor)
    endif
    return
  endif

  " this is some kind of list, but apart from the list indicator, it has no
  " content
  if empty(actual_content)
    " we want to de-indent by 2 chars when on a line like
    " *
    "   *
    " * [ ]
    "   * [ ]
    if !empty(prefix_space)
      let new_line = line[2:]
    " if we don't have anything to de-indent, then we'll use
    " a blank line instead
    elseif is_list
      let new_line = ' ' . line[1:]
    else
      let new_line = ''
    endif
    call setline('.', new_line)
    starti
    return
  endif

  " we will define 4 vars in each block:
  "   this_text: text for the current line
  "   next_next: text for the next line
  "   new_pos:   position to start on in next line
  "   append:    whether to append at the end of the line

  " when at the end of a line, we can simply start a new list item
  " in the next line
  let marker = s:get_line_start(prefix_space, list_char, infix_space, is_checklist)
  if is_trailing_cursor || a:mode == 'n'
    " for todo-entries, we want to append a date
    if awiwi#str#endswith(&ft, '.todo')
      let this_text = line
      let next_text = printf('%s (from %s)', marker, strftime('%F'))
      let new_pos = strlen(marker) + 1
      let append = v:false
    else
      let this_text = line
      let next_text = a:continue_paragraph ? s:pad(strlen(marker)) : marker
      let new_pos = strlen(next_text)
      let append = v:true
    endif

  " now we need to handle the case of breaking a line into the next
  " first, we deal with lists
  else
    " when at the start of a line (pos==1), then we want to paste the complete
    " content to the next line. this is hardly possible w/o branching, since
    " vim slices are end-inclusive
    if pos == 1
      let this_text = ''
      let marker_len = 0
    else
      let this_text = line[:pos-2]
      let marker_len = strlen(marker)
    endif
    let start_pos = max([0, pos - 1])
    let next_text = s:pad(marker_len, line[start_pos:])
    if is_list && get(g:, 'awiwi_jump_to_end', v:false)
      let new_pos = strlen(next_text) + 1
    else
      let new_pos = marker_len + 1
    endif
    let append = v:false
  endif

  " for performance reason: don't re-set the text, if it's the same
  if this_text != line
    call setline('.', this_text)
  endif

  let cursor[2] = new_pos
  if a:above
    call append(line_nr - 1, next_text)
  else
    let cursor[1] += 1
    call append(line_nr, next_text)
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


nnoremap <silent> <buffer> O :call <sid>handle_enter_on_insert('n', v:true, v:false)<CR>
nnoremap <silent> <buffer> o :call <sid>handle_enter_on_insert('n', v:false, v:false)<CR>
inoremap <silent> <buffer> <Enter> <Cmd>call <sid>handle_enter_on_insert('i', v:false, v:false)<CR>
inoremap <silent> <buffer> <C-j>   <Cmd>call <sid>handle_enter_on_insert('i', v:false, v:true)<CR>
nnoremap <silent> <buffer> <Enter> :call <sid>handle_enter()<CR>
exe 'inoremap <silent> <buffer> <C-y> * [ ] '


augroup awiwiAutosave
  au!
  au InsertLeave,CursorHold *.md silent w
augroup END

augroup awiwiDeleteOldTasks
  au!
  au BufEnter,BufWritePre */todos/*.md call <sid>delete_old_tasks()
augroup END


" inoremap <silent> <buffer> <C-d> <C-r>=strftime('%F')<CR>
inoremap <silent> <buffer> <C-f> <C-r>=strftime('%H:%M')<CR>
nnoremap <silent> <buffer> <C-q> :Awiwi redact<CR>
inoremap <silent> <buffer> <C-q> <C-o>:Awiwi redact<CR>
inoremap <silent> <buffer> <C-v> <Cmd>:call awiwi#handle_paste_in_insert_mode()<CR>

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


fun! s:folding(lnum) abort "{{{
  let line = getline(a:lnum)
  if line =~ '^\s*$'
    return '-1'
  endif
  let level = strlen(matchstr(line, '^#*'))
  if level > 0
    return '>' . string(level - 1)
  else
    return '='
  endif
endfun "}}}


" don't put too much pressure on the machine
set updatetime=4000
setlocal foldmethod=expr
setlocal nowrap
exe printf('setlocal foldexpr=%s(v:lnum)', function('s:folding'))


fun! s:split_screen(direction) abort "{{{
  if getcmdtype() != ':'
    return
  endif
  let words = split(getcmdline())
  if match(words[0], '^Aw\%[iwi]$') == 1
    return
  endif
  let args = words[1:]
  if a:direction == 'h'
    let cmd = '+hnew'
  else
    let cmd = '+vnew'
  endif
  return ' ' . cmd
endfun "}}}

cnoremap <silent> <C-x> <C-r>=<sid>split_screen('h')<CR><CR>
cnoremap <silent> <C-v> <C-r>=<sid>split_screen('v')<CR><CR>

doautocmd User AwiwiInitPost
