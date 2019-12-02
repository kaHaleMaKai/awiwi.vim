if exists('g:autoloaded_awiwi')
  finish
endif
let g:autoloaded_awiwi = v:true

let s:date_pattern = '^[0-9]\{4}-[0-9]\{2}-[0-9]\{2}$'
let s:journal_cmd = 'journal'
let s:continuation_cmd = 'continue'
let s:link_cmd = 'link'
let s:open_asset_cmd = 'open-asset'
let s:show_cmd = 'show'
let s:tasks_cmd = 'tasks'

let s:journal_subpath = path#join(g:awiwi_home, 'journal')
let s:asset_subpath = path#join(g:awiwi_home, 'assets')

let s:search_engine_plain = 'plain'
let s:search_engine_regex = 'regex'
let s:search_engine_fuzzy = 'fuzzy'

let s:subcommands = [
      \ s:continuation_cmd,
      \ s:journal_cmd,
      \ s:link_cmd,
      \ s:open_asset_cmd,
      \ s:show_cmd,
      \ s:tasks_cmd,
      \ ]

let s:tasks_all_cmd = 'all'
let s:tasks_delegates_cmd = 'delegates'
let s:tasks_filter_cmd = 'filter'
let s:tasks_fixme_cmd = 'fixme'
let s:tasks_onhold_cmd = 'onhold'
let s:tasks_todo_cmd = 'todo'

let s:journal_new_window_cmd = '+new'

let s:tasks_subcommands = [
      \ s:tasks_all_cmd,
      \ s:tasks_delegates_cmd,
      \ s:tasks_filter_cmd,
      \ s:tasks_fixme_cmd,
      \ s:tasks_onhold_cmd,
      \ s:tasks_todo_cmd
      \ ]

fun! awiwi#ShowTasks(...) abort "{{{
  let markers = []
  if !a:0 || a:1 == s:tasks_todo_cmd || a:1 == s:tasks_all_cmd
    let awiwi_todo_markers = get(g:, 'awiwi_todo_markers', ['TODO', 'FIXME'])
    let idx = index(awiwi_todo_markers, 'FIXME')
    if idx > -1
      let awiwi_todo_markers[idx] = '.*FIXME.*'
    endif
    call add(markers, '\b'. join(awiwi_todo_markers, '|') . '\b')
  elseif a:1 == s:tasks_fixme_cmd || a:1 == s:tasks_all_cmd
    call add(markers, '\bFIXME\b')
  elseif a:1 == s:tasks_delegates_cmd || a:1 == s:tasks_all_cmd
    call add(markers, '\(?@todo( [a-zA-Z-]+){0,2}\]?')
  elseif a:1 == s:tasks_onhold_cmd || a:1 == s:tasks_all_cmd
    call extend(markers, ['ONHOLD', 'HOLD'])
  elseif a:1 == s:tasks_filter_cmd
    if a:0 == 1
      throw 'AwiwiError: missing argument for "Awiwi tasks filter"'
    endif
    call extend(markers, a:000[1:])
  endif

  let pattern = join(markers, '|')
  let rg_cmd = [
        \ 'rg', '-u', '--column', '--line-number',
        \ '--no-heading', '--color=always',
        \ '-g', shellescape('!awiwi*'), shellescape(pattern), '|' , 'sort -r'
        \ ]
  let with_preview = fzf#vim#with_preview('right:50%:hidden', '?')
  call fzf#vim#grep(join(rg_cmd, ' '), 1, with_preview, 0)

endfun "}}}


fun! s:ints_to_date(year, month, day) abort "{{{
  return printf('%04d-%02d-%02d', a:year, a:month, a:day)
endfun "}}}


fun! s:get_yesterday(date) abort "{{{
  let [year, month, day] = map(split(a:date, '-'), {_, v -> str2nr(v)})
  " not 1st of month
  if str2nr(day) > 1
    return s:ints_to_date(year, month, day - 1)
  endif
  " date is 1st of month
  let num_days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  " no switch to Feb. of Dec.
  if month == 2 || month >= 3
    return s:ints_to_date(year, month - 1, num_days[month - 1])
  " switch to Feb.
  elseif month == 3
    " check for leap year
    if year % 400 == 0 || (year % 4 == 0 && year % 100 != 0)
      let day = 29
    else
      let day = 28
    endif
    return s:ints_to_date(year, 2, day)
  " switch from Jan. back to Dec.
  else
    return s:ints_to_date(year - 1, 12, 31)
  endif
endfun "}}}


fun! s:is_date(expr) abort "{{{
  return match(a:expr, s:date_pattern) > -1
endfun "}}}


fun! s:get_offset_date(date, offset) abort "{{{
  let files = s:get_all_files()
  let idx = index(files, a:date)
  if idx == -1
    throw printf('AwiwiError: date %s not found', a:date)
  elseif a:offset <= 0 && idx + a:offset <= 0
    throw printf('AwiwiError: no date found before %s', a:date)
  elseif a:offset >= 0 && idx + a:offset >= len(files) - 1
    throw printf('AwiwiError: no date found after %s', a:date)
  endif
  return files[idx + a:offset]
endfun "}}}


fun! s:parse_date(date) abort "{{{
  if a:date == 'today'
    return strftime('%F')
  elseif a:date == 'yesterday'
    let date = s:get_yesterday(strftime('%F'))
  elseif a:date == 'previous'
    let date = s:get_previous_date(strftime('%F'))
  elseif a:date == 'next'
    let date = s:get_next_date(strftime('%F'))
  else
    let date = a:date
  endif
  return date
endfun "}}}


fun! s:add_link(title, target, ...) abort "{{{
  if a:0 > 0
    let target = s:relativize(a:target, a:1)
  else
    let target = s:relativize(a:target)
  endif
  return printf('[%s](%s)', a:title, target)
endfun "}}}


fun! s:relativize(path, ...) abort "{{{
  if a:0 > 0
    let other_file = path#absolute(a:1)
  else
    let other_file = path#absolute(expand('%'))
  endif
  return path#relativize(a:path, other_file)
endfun "}}}


fun! s:get_journal_file_by_date(date) abort "{{{
  if a:date == 'todo' || a:date == 'todos'
    return path#join(s:journal_subpath, 'todos.md')
  endif
  let date = s:parse_date(a:date)
  let [year, month, day] = split(date, '-')
  return path#join(s:journal_subpath, year, month, date.'.md')
endfun "}}}


fun! s:get_asset_path(date, name) abort "{{{
  let [year, month, day] = split(a:date, '-')
  return path#join(s:asset_subpath, year, month, day, a:name)
endfun "}}}


fun! s:open_asset_by_name(date, name) abort "{{{
  let date = s:parse_date(a:date)
  let path = s:get_asset_path(date, a:name)
  let dir = fnamemodify(path, ':h')
  if !filewritable(dir)
    call mkdir(dir, 'p')
  endif
  exe 'new '.path
  write
endfun "}}}

fun! s:get_own_date() abort "{{{
  let name = expand('%:t:r')
  if match(name, s:date_pattern) == -1
    throw 'AwiwiError: not on journal page'
  endif
  return name
endfun "}}}


fun! s:escape_pattern(pattern) abort "{{{
  return escape(a:pattern, " \t.*\\\[\]\-")
endfun "}}}


fun! s:get_asset_under_cursor(accept_date) abort "{{{
  let empty_result = ['', '']
  let line = getline('.')
  " correct to zero-offset
  let pos = getcurpos()[2]

  let open_bracket_pos = -1
  for i in range(pos, 0, -1)
    let char = line[i]
    if char == '['
      let open_bracket_pos = i
      break
    endif
  endfor

  if !open_bracket_pos == -1
    return empty_result
  endif
  let match = matchlist(line, '\(.\{-}\)\(\]\)\((.\{-})\)\?', open_bracket_pos+1)

  if len(match) < 2
    return empty_result
  endif
  let name = match[1]
  let link = match[3]
  if a:accept_date
    let date = matchstr(name, '^\(continued\|started\) on \zs[0-9]\{4}-[0-9]\{2}-[0-9]\{2}$')
  else
    let date = ''
  endif

  " found an asset link
  if date != ''
    return [date, link]
  elseif name != ''
    return [name, link]
  else
    return empty_result
  endif
endfun "}}}


fun! awiwi#add_asset_link() abort "{{{
  let [name, rem] = s:get_asset_under_cursor(v:false)
  let name_pattern = s:escape_pattern(printf('[%s]', name))
  if name == ''
    throw AwiwiError "no asset under cursor"
  endif

  let date = s:get_own_date()
  let asset_file = s:get_asset_path(date, name)
  let rel_path = s:relativize(asset_file, expand('%:p'))

  if len(rem) == 0 || rem[0] != '('
    let line_nr = line('.')
    let line = getline(line_nr)
    let end = matchend(line, name_pattern)
    let line_start = line[:end]
    let line_rem = line[end+1:]
    let new_text = printf('%s(%s)%s', line_start, rel_path, line_rem)
    call setline(line_nr, new_text)
  endif

  return name

endfun "}}}


fun! awiwi#open_asset(...) abort "{{{
  if len(a:000) > 0
    let name = a:0
  else
    let name = awiwi#add_asset_link()
  endif
  let date = s:get_own_date()
  call s:open_asset_by_name(date, name)
endfun "}}}


fun! s:is_date(expr) abort "{{{
  return match(a:expr, '^[0-9]\{4}-[0-9]\{2}-[0-9]\{2}$') == 0
endfun "}}}


fun! awiwi#open_file_or_asset() abort "{{{
  let [name, rem] = s:get_asset_under_cursor(v:true)
  if name == ''
    normal! gf
  elseif s:is_date(name)
    call awiwi#edit_journal(name, v:false)
  else
    call awiwi#open_asset()
  endif
endfun "}}}


fun! s:get_today() abort "{{{
  return strftime('%F')
endfun "}}}


fun! awiwi#edit_journal(date, new_window) abort "{{{
  if a:date == 'previous'
    try
      let date = s:get_offset_date(s:get_own_date(), -1)
    catch /AwiwiError/
      let date = s:get_offset_date(s:get_today(), -1)
    endtry
  elseif a:date == 'next'
    try
      let date = s:get_offset_date(s:get_own_date(), +1)
    catch /AwiwiError/
      let date = s:get_offset_date(s:get_today(), +1)
    endtry
  else
    let date = s:parse_date(a:date)
  endif
  try
    let own_date = s:get_own_date()
  catch /AwiwiError/
    let own_date = 'todos'
  endtry
  if date == own_date
    echom printf("journal page '%s' already open", date)
    return
  endif
  let file = s:get_journal_file_by_date(date)
  if a:new_window
    let cmd = 'new'
  else
    let cmd = 'e'
  endif
  exe printf('%s %s', cmd, file)
endfun "}}}


fun! awiwi#insert_and_open_continuation() abort "{{{
  let own_date = s:get_own_date()
  let today = s:parse_date('today')
  if own_date == today
    throw "AwiwiError: already on today's journal"
  endif
  let today_file = s:get_journal_file_by_date(today)
  let link = s:add_link(printf('continued on %s', today), today_file)

  " get the task name
  let title = ''
  for line_nr in range(line('.'), 1, -1)
    let line = getline(line_nr)
     let matches = matchlist(line, '^\(#\{1,4}\)[[:space:]]\+\([^[:space:]].*\)')
     if matches != []
       let [marker, title] = matches[1:2]
       break
     endif
  endfor
  if title == ''
    throw 'AwiwiError: could not find task title'
  endif

  let own_file = s:get_journal_file_by_date(own_date)
  let back_link = s:add_link(printf('started on %s', own_date), own_file, today_file)

  call append(line('.'), link)
  " move to the next line
  +
  call awiwi#edit_journal(today, v:true)
  let lines = [
        \ '',
        \ printf('%s %s (cont. from %s)', marker, title, own_date),
        \ '',
        \ back_link,
        \ '',
        \ ]
  call append(line('$'), lines)
  normal! G
endfun "}}}


fun! s:get_argument_number(expr) abort "{{{
  return len(split(a:expr, '[[:space:]]\+', v:true)) - 1
endfun "}}}


fun! s:get_search_engine() abort "{{{
  let search_engine = get(g:, 'awiwi_search_engine', 'plain')
  if index([s:search_engine_regex, s:search_engine_fuzzy], search_engine) > -1
    return search_engine
  endif
  return s:search_engine_plain
endfun "}}}


fun! s:match_subcommands(subcommands, ArgLead) abort "{{{
  if a:ArgLead == ''
    return a:subcommands
  endif
  let subcommands = copy(a:subcommands)
  let search_engine = s:get_search_engine()
  if search_engine == s:search_engine_plain
    return filter(subcommands, {_, v -> str#startswith(v, a:ArgLead)})
  elseif search_engine == s:search_engine_regex
    return filter(subcommands, {_, v -> match(v, a:ArgLead) > -1})
  endif
  let chars = map(range(strlen(a:ArgLead)), {i -> a:ArgLead[i]})
  let pattern = join(map(chars, {_, v -> s:escape_pattern(v)}), '.\{-}')

  let all_items = map(
        \ copy(subcommands),
        \ {_, v -> {'name': v, 'match': matchstrpos(v, pattern)}})
  let filtered_items = filter(
        \ all_items,
        \ {_, v -> v.match[0] != '' })
  let normalized_items = map(
        \ filtered_items,
        \ {_, v -> {'name': v.name, 'score': v.match[2] - v.match[1]}})
  let sorted_items = sort(
        \ normalized_items,
        \ {x, y -> x.score > y.score ? 1 : (x.score < y.score ? -1 : (x.name >= y.name ? 1 : -1))})
  return map(sorted_items, {_, v -> v.name})
endfun "}}}


fun! s:get_all_files() abort "{{{
    return sort(map(
          \ split(glob(path#join(g:awiwi_home, '**', '*.md'))),
          \ {_, v -> fnamemodify(v, ':t:r')}))
endfun "}}}


fun! awiwi#_get_completion(ArgLead, CmdLine, CursorPos) abort "{{{
  let current_arg_pos = s:get_argument_number(a:CmdLine[:a:CursorPos])
  if current_arg_pos < 2
    return s:match_subcommands(s:subcommands, a:ArgLead)
  endif
  let args = split(a:CmdLine)

  if args[1] == s:tasks_cmd && current_arg_pos == 2
    return s:match_subcommands(s:tasks_subcommands, a:ArgLead)
  elseif args[1] == s:journal_cmd && (current_arg_pos == 2 || (current_arg_pos == 3 && args[2] == s:journal_new_window_cmd))
    let files = s:get_all_files()
    let todos_idx = index(files, 'todos')
    if todos_idx != -1
      call remove(files, todos_idx)
    endif
    call extend(files, ['todos', 'today', 'next', 'previous'], 0)
    if current_arg_pos == 2
      call insert(files, s:journal_new_window_cmd)
    endif
    return s:match_subcommands(files, a:ArgLead)
  elseif args[1] == s:journal_cmd && current_arg_pos == 3 && args[2] != s:journal_new_window_cmd
    return [s:journal_new_window_cmd]
  endif

  return []
endfun "}}}


fun! awiwi#run(...) abort "{{{
  if !a:0
    throw 'AwiwiError: Awiwi expects 1+ arguments'
  endif
  if a:1 == s:journal_cmd
    if a:0 == 1 || a:0 > 3
      echoerr printf('Awiwi journal: 1 or 2 arguments expected. got %d', a:0-1)
    endif
    if a:2 == s:journal_new_window_cmd
      let new_window = v:true
      let date = a:3
    elseif a:3 == s:journal_new_window_cmd
      let new_window = v:true
      let date = a:2
    else
      let new_window = v:false
      let date = a:2
    endif
    call awiwi#edit_journal(date, new_window)
  elseif a:1 == s:continuation_cmd
    call awiwi#insert_and_open_continuation()
  elseif a:1 == s:link_cmd
    call awiwi#add_asset_link()
  elseif a:1 == s:open_asset_cmd
    call awiwi#open_file_or_asset()
  elseif a:1 == s:tasks_cmd
    call func#apply(funcref('awiwi#ShowTasks'), func#spread(a:000[1:]))
  elseif a:1 == s:show_cmd
    echoerr 'Awiwi show: should render markdown in browser, but has not been implemented that'
  endif
endfun "}}}
