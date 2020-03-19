if exists('g:autoloaded_awiwi')
  finish
endif
let g:autoloaded_awiwi = v:true

" {{{1 variables

let s:date_pattern = '^[0-9]\{4}-[0-9]\{2}-[0-9]\{2}$'
let s:activate_cmd = 'activate'
let s:deactivate_cmd = 'deactivate'
let s:journal_cmd = 'journal'
let s:continuation_cmd = 'continue'
let s:entry_cmd = 'entries'
let s:link_cmd = 'link'
let s:asset_cmd = 'asset'
let s:recipe_cmd = 'recipe'
let s:search_cmd = 'search'
let s:show_cmd = 'show'
let s:tasks_cmd = 'tasks'
let s:todo_cmd = 'todo'

let s:new_asset_cmd = 'create'

let s:journal_subpath = path#join(g:awiwi_home, 'journal')
let s:asset_subpath = path#join(g:awiwi_home, 'assets')
let s:recipe_subpath = path#join(g:awiwi_home, 'recipes')

if exists('g:awiwi_data_dir')
  let s:awiwi_data_dir = g:awiwi_data_dir
elseif exists('$XDG_DATA_DIR')
  let s:awiwi_data_dir = path#join($XDG_DATA_DIR, 'awiwi')
else
  let s:awiwi_data_dir = path#join(g:awiwi_home, 'data')
endif

for dir in [s:awiwi_data_dir, s:journal_subpath, s:asset_subpath, s:recipe_subpath]
  if !filewritable(dir)
    if !mkdir(dir, 'p')
      echoerr printf('cannot create data directory %s', dir)
      finish
    endif
  endif
endfor


fun! awiwi#get_data_dir() abort "{{{
  return s:awiwi_data_dir
endfun "}}}


let s:log_file = path#join(s:awiwi_data_dir, 'awiwi.log')
let s:task_log_file = path#join(s:awiwi_data_dir, 'task.log')
if !filereadable(s:task_log_file)
  if writefile([], s:task_log_file) != 0
    echoerr printf('could not create task log file "%s"', s:task_log_file)
    finish
  endif
endif

let s:log_file_size = get(g:, 'awiwi_history_length', 10000)
let s:history = []

let s:active_task = {}

let s:subcommands = [
      \ s:activate_cmd,
      \ s:continuation_cmd,
      \ s:deactivate_cmd,
      \ s:journal_cmd,
      \ s:entry_cmd,
      \ s:link_cmd,
      \ s:asset_cmd,
      \ s:recipe_cmd,
      \ s:search_cmd,
      \ s:show_cmd,
      \ s:tasks_cmd,
      \ s:todo_cmd,
      \ ]

let s:tasks_all_cmd = 'all'
let s:tasks_delegate_cmd = 'delegate'
let s:tasks_due_cmd = 'due'
let s:tasks_filter_cmd = 'filter'
let s:tasks_urgent_cmd = 'urgent'
let s:tasks_onhold_cmd = 'onhold'
let s:tasks_question_cmd = 'question'
let s:tasks_todo_cmd = 'todo'

let s:journal_new_window_cmd = '+new'
let s:journal_height_window_cmd = '+height='

let s:tasks_subcommands = [
      \ s:tasks_all_cmd,
      \ s:tasks_delegate_cmd,
      \ s:tasks_due_cmd,
      \ s:tasks_filter_cmd,
      \ s:tasks_urgent_cmd,
      \ s:tasks_onhold_cmd,
      \ s:tasks_question_cmd,
      \ s:tasks_todo_cmd
      \ ]

let s:todo_markers = ['TODO']
let s:onhold_markers = [
      \ 'ONHOLD',
      \ 'HOLD'
      \ ]
let s:urgent_markers = [
      \ 'FIXME',
      \ 'CRITICAL',
      \ 'URGENT',
      \ 'IMPORTANT'
      \ ]
let s:delegate_markers = ['@todo']
let s:question_markers = ['QUESTION']
let s:due_markers = ['DUE', 'DUE TO', 'UNTIL', '@until', '@due']

" 1}}}

fun! s:get_empty_task() abort "{{{
  return {'title': '', 'marker': '', 'type': v:false, 'activity': [], 'state': 'inactive', 'created': 0, 'updated': 0, 'duration': 0}
endfun "}}}


fun! s:get_epoch() abort "{{{
  return str2nr(strftime('%s'))
endfun "}}}


fun! s:get_current_timestamp() abort "{{{
  return strftime('%F %T')
endfun "}}}


fun! s:log(level, msg, ...) abort "{{{
  let ts = s:get_current_timestamp()
  let level = toupper(a:level)
  if a:0
    let params = ['[%s] %-5s - ' . a:msg, ts, level] + a:000
    let msg = call('printf', params)
  else
    let msg = printf('[%s] %-5s - %s', ts, level, a:msg)
  endif
  return writefile([msg], s:log_file, "a") == 0
        \ ? v:true : v:false
endfun "}}}


fun! s:info(msg, ...) abort "{{{
  if a:0
    return call('s:log', ['INFO', a:msg] + a:000)
  else
    return s:log('INFO', a:msg)
  endif
endfun "}}}


fun! s:warn(msg, ...) abort "{{{
  if a:0
    return call('s:log', ['WARN', a:msg] + a:000)
  else
    return s:log('WARN', a:msg)
  endif
endfun "}}}


fun! s:error(msg, ...) abort "{{{
  if a:0
    return call('s:log', ['ERROR', a:msg] + a:000)
  else
    return s:log('ERROR', a:msg)
  endif
endfun "}}}

fun! s:log_task_action(task, action) abort "{{{
  if a:action != 'activate' && a:action != 'deactivate'
    echoerr printf('action must be either of ("activate", "deactivate"). got: "%s"', a:action)
    return
  endif

  call s:info('%s task "%s"', a:action, a:task.title)
  return writefile([string(a:task)], s:task_log_file, "a") == 0
        \ ? v:true : v:false
endfun "}}}


fun! awiwi#get_markers(type, ...) abort "{{{
  let options = {'join': v:true, 'escape_mode': 'rg'}
  call extend(options, get(a:000, 0, {}))

  if !exists(printf('s:%s_markers', a:type))
    throw printf('AwiwiError: type %s does not exist', a:type)
  endif

  let custom_markers = get(g:, printf('awiwi_custom_%s_markers', a:type), [])
  let markers = copy(get(s:, a:type.'_markers')) + custom_markers
  if options.escape_mode == 'rg'
    let result = uniq(map(markers, {_, v -> s:escape_rg_pattern(v)}))
  else
    let result = uniq(map(markers, {_, v -> awiwi#util#escape_pattern(v)}))
  endif
  if a:type == 'todo' && options.escape_mode == 'rg'
    let task_list = '^[-*][[:space:]]+\[[[:space:]]+\]'
    call add(result, task_list)
  endif
  if options.join
    let join_char = options.escape_mode == 'vim' ? '\|' : '|'
    return join(result, join_char)
  else
    return result
  endif
endfun "}}}


fun! s:contains(li, el, ...) abort "{{{
  if !a:0
    return index(a:li, a:el) > -1 ? v:true : v:false
  endif

  let els = [a:el] + a:000
  for x in a:li
    if index(els, x) > -1
      return v:true
    endif
  endfor
  return v:false
endfun "}}}


fun! awiwi#show_tasks(...) abort "{{{
  let markers = []

  if a:0
    let args = a:000
  else
    let args = [s:tasks_todo_cmd]
  endif

  if s:contains(args, s:tasks_urgent_cmd, s:tasks_all_cmd, s:tasks_todo_cmd)
    let markers = [awiwi#get_markers('urgent')]
  else
    let markers = []
  endif
  let has_due = v:false
  if s:contains(args, s:tasks_todo_cmd, s:tasks_all_cmd)
    call add(markers, awiwi#get_markers('todo'))
  endif
  if s:contains(args, s:tasks_delegate_cmd, s:tasks_all_cmd)
    let delegates = awiwi#get_markers('delegate')
    call add(markers, printf('\(?(%s):?( \S+){0,2}\)?', delegates))
  endif
  if s:contains(args, s:tasks_due_cmd, s:tasks_all_cmd)
    let due = awiwi#get_markers('due')
    call add(markers, printf('\(?(%s):?( \S+)*\)?', due))
    let has_due = v:true
  endif
  if s:contains(args, s:tasks_onhold_cmd, s:tasks_all_cmd)
    call add(markers, awiwi#get_markers('onhold'))
  endif
  if s:contains(args, s:tasks_question_cmd, s:tasks_all_cmd)
    call add(markers, awiwi#get_markers('question'))
  endif
  if args[0] == s:tasks_filter_cmd
    if a:0 == 1
      throw 'AwiwiError: missing argument for "Awiwi tasks filter"'
    endif
    call extend(markers, a:000[1:])
  endif

  let pattern = join(markers, '|')
  let rg_cmd = [
        \ 'rg', '-u', '--column', '--line-number',
        \ '--no-heading', '--color=always',
        \ '-g', shellescape('!awiwi*'), shellescape(pattern)]
  if has_due
    let anti_pattern = printf('0m:[*-] +\[x\] |~~.{20}(%s)', pattern)
    call extend(rg_cmd, ['|', 'rg', '-v', '--color=always', shellescape(anti_pattern)])
  endif
  let with_preview = fzf#vim#with_preview('right:50%:hidden', '?')
  call fzf#vim#grep(join(rg_cmd, ' '), 1, with_preview, 0)

endfun "}}}


fun! s:open_fuzzy_match(line) abort "{{{
  let [file, line, col] = split(a:line, ':')[:2]
  exe printf('e +%s %s', line, file)
  exe printf('normal! %s|', col)
endfun "}}}


fun! s:open_asset_sink(expr) abort "{{{
  let [date, name] = split(a:expr, ':')
  call s:open_asset_by_name(date, name)
endfun "}}}


fun! awiwi#fuzzy_search(...) abort "{{{
  if !a:0
    echoerr 'Awiwi search: no pattern given'
  endif
  let pattern = join(map(copy(a:000), {_, v -> awiwi#util#escape_pattern(v)}), '.*?')
  let rg_cmd = [
        \ 'rg', '-U', '--multiline-dotall', '--color=never',
        \ '--column', '--line-number', '--no-heading',
        \ '-g', '!awiwi*', pattern
        \ ]
  let matches = filter(systemlist(rg_cmd), {_, v -> !str#is_empty(v)})
  if a:0 > 1
    let start = printf('\<%s\>', awiwi#util#escape_pattern(a:1))
    let matches = filter(matches, {_, v -> match(v, start) > -1})
  endif
  call fzf#run(fzf#wrap({'source': matches, 'sink': funcref('s:open_fuzzy_match')}))
endfun "}}}


fun! s:format_search_result(start, ...) abort "{{{
  let end = !a:0 ? '' : a:1
  let start_len = strlen(start.content)
  let end_len = strlen(end)
  let max_len = 80
  let total_len = start_len + end_len
  if total_len <= max_len
    let line = prinft('%s...%s', start.content, end)
  elseif start_len >= max_len/2 && end_len >= max_len/2
    let line = prinft('%s...%s', start.content[:max_len/2-1], end[-(max_len/2-1):])
  elseif start_len < max_len/2
    let line = prinft('%s...%s', start.content, end[-(max_len/2-1):])
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
  let files = s:get_all_journal_files()
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


fun! s:open_asset_by_name(date, name, ...) abort "{{{
  let options = get(a:000, 0, {})
  let date = s:parse_date(a:date)
  let path = s:get_asset_path(date, a:name)
  let dir = fnamemodify(path, ':h')
  if !filewritable(dir)
    call mkdir(dir, 'p')
  endif
  call s:open_file(path, options)
  write
endfun "}}}

fun! s:get_own_date() abort "{{{
  let name = expand('%:t:r')
  if match(name, s:date_pattern) == -1
    throw 'AwiwiError: not on journal page'
  endif
  return name
endfun "}}}


fun! s:escape_rg_pattern(pattern) abort "{{{
  return escape(a:pattern, ".*?\\\[\]")
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
  let name_pattern = awiwi#util#escape_pattern(printf('[%s]', name))
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
  if a:0
    let name = a:1
  else
    let name = awiwi#add_asset_link()
  endif
  let date = s:get_own_date()
  call s:open_asset_by_name(date, name)
endfun "}}}


fun! s:is_date(expr) abort "{{{
  return match(a:expr, '^[0-9]\{4}-[0-9]\{2}-[0-9]\{2}$') == 0
endfun "}}}


fun! awiwi#open_journal_or_asset(...) abort "{{{
  if a:0
    call awiwi#open_asset()
  endif
  let [name, rem] = s:get_asset_under_cursor(v:true)
  if name == ''
    normal! gf
  elseif s:is_date(name)
    call awiwi#edit_journal(name)
  else
    call awiwi#open_asset()
  endif
endfun "}}}


fun! s:get_today() abort "{{{
  return strftime('%F')
endfun "}}}


fun! s:open_file(file, options) abort "{{{
  if get(a:options, 'new_window', v:false)
    let height = str2nr(get(a:options, 'height', 0))
    let position = get(a:options, 'position', 'bottom')
    if position == 'left'
      let win_cmd == 'left vnew'
    elseif position == 'right'
      let win_cmd = 'vnew'
    elseif position == 'top'
      let win_cmd = 'lefta new'
    else
      let win_cmd = 'new'
    " bottom is the default case
      if position != 'bottom'
        echoerr printf('wrong position for s:open_file() specified: "%s"', position)
      endif
    endif
    let cmd = printf('%s%s', height ? height : '', win_cmd)
  else
    let cmd = 'e'
  endif
  if get(a:options, 'create_dirs', v:false)
    let dir = fnamemodify(a:file, ':p:h')
    call mkdir(dir, 'p')
  endif
  let jump_mod = get(a:options, 'last_line', v:false)
        \ ? '+' : ''
  exe printf('%s %s %s', cmd, jump_mod, a:file)
endfun "}}}


fun! awiwi#edit_journal(date, ...) abort "{{{
  let options = get(a:000, 0, {})
  let options.last_line = v:true
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
  call s:open_file(file, options)
endfun "}}}


fun! s:get_title_and_tags(title) abort "{{{
  let result = {'title': a:title, 'bare_title': '', 'tags': {}}
  if a:title == ''
    return result
  endif

  let splits = split(a:title, ' (cont. ', v:false)
  if len(splits) == 1
    let result.bare_title = a:title
  else
    let result.bare_title = splits[0]
    let result.tags.cont = '(cont. ' . splits[1]
  endif
  return result
endfun "}}}


fun! s:get_current_task() abort "{{{
  let result = {'marker': '', 'title': '', 'tags': {}, 'bare_title': ''}
  let title = ''
  for line_nr in range(line('.'), 1, -1)
    let line = getline(line_nr)
     let matches = matchlist(line, '^\(#\{2,4}\)[[:space:]]\+\([^[:space:]].*\)')
     if matches != []
       let [marker, title] = matches[1:2]
       let result = {'marker': marker, 'title': title, 'tags': {}, 'bare_title': ''}
       break
     endif
  endfor

  let values = s:get_title_and_tags(title)
  call extend(result, values)
  return result
endfun "}}}


fun! awiwi#insert_and_open_continuation() abort "{{{
  let own_date = s:get_own_date()
  let today = s:parse_date('today')
  if own_date == today
    throw "AwiwiError: already on today's journal"
  endif
  let today_file = s:get_journal_file_by_date(today)
  let link = s:add_link(printf('continued on %s', today), today_file)
  let current_task = s:get_current_task()
  " get the task name
  if current_task.title == ''
    throw 'AwiwiError: could not find task title'
  endif

  let own_file = s:get_journal_file_by_date(own_date)
  let back_link = s:add_link(printf('started on %s', own_date), own_file, today_file)

  call append(line('.'), link)
  " move to the next line
  +
  w
  call awiwi#edit_journal(today, {'new_window': v:true, 'position': 'top'})
  let lines = [
        \ '',
        \ printf('%s %s (cont. from %s)', current_task.marker, current_task.title, own_date),
        \ back_link,
        \ '',
        \ ]
  call append(line('$'), lines)
  normal! G
endfun "}}}


fun! s:get_all_journal_files() abort "{{{
    return sort(map(
          \ split(glob(path#join(g:awiwi_home, 'journal', '**', '*.md'))),
          \ {_, v -> fnamemodify(v, ':t:r')}))
endfun "}}}


fun! s:get_all_asset_files() abort "{{{
    return map(
          \  map(
          \    filter(
          \      glob(path#join(g:awiwi_home, 'assets', '2*', '**'), v:false, v:true),
          \      {_, v -> filereadable(v)}),
          \    {_, v -> split(v, '/')[-4:]}),
          \  {_, v -> {'date': join(v[:2], '-'), 'name': v[-1]}})
endfun "}}}


fun! s:get_all_recipe_files() abort "{{{
    let prefix_len = str#endswith(s:recipe_subpath , '/')
          \ ? strlen(s:recipe_subpath) : strlen(s:recipe_subpath)+1
    return sort(
          \ map(
          \   filter(
          \     glob(path#join(s:recipe_subpath, '**', '*'), v:false, v:true),
          \     {_, v -> filereadable(v)}),
          \   {_, v -> v[prefix_len:]}))
endfun "}}}


fun! s:need_to_insert_files(current_arg_pos, args) abort "{{{
  if a:current_arg_pos == 2
    return v:true
  endif
  return (a:current_arg_pos - s:has_new_win_cmd(a:args) - s:has_win_height_cmd(a:args)) == 2
        \ ? v:true : v:false
endfun "}}}


fun! s:has_new_win_cmd(args) abort "{{{
  return len(filter(copy(a:args), {_, v -> v == s:journal_new_window_cmd})) > 0
        \ ? v:true : v:false
endfun "}}}


fun! s:has_win_height_cmd(args) abort "{{{
  return len(filter(copy(a:args), {_, v -> str#startswith(v, s:journal_height_window_cmd)})) > 0
        \ ? v:true : v:false
endfun "}}}


fun! s:insert_win_cmds(li, current_arg_pos, args) abort "{{{
  if a:current_arg_pos == 2
    return a:li
  elseif !s:has_new_win_cmd(a:args)
    call insert(a:li, s:journal_new_window_cmd)
    return
  elseif !s:has_win_height_cmd(a:args)
    call insert(a:li, s:journal_height_window_cmd)
  endif
  return a:li
endfun "}}}


fun! awiwi#_get_completion(ArgLead, CmdLine, CursorPos) abort "{{{
  let current_arg_pos = awiwi#util#get_argument_number(a:CmdLine[:a:CursorPos])
  if current_arg_pos < 2
    return awiwi#util#match_subcommands(s:subcommands, a:ArgLead)
  endif
  let args = split(a:CmdLine)

  if args[1] == s:tasks_cmd && current_arg_pos >= 2
    let matches = awiwi#util#match_subcommands(s:tasks_subcommands, a:ArgLead)
    if current_arg_pos == 2
      return matches
    elseif args[2] == s:tasks_filter_cmd
      return []
    endif
    let prev_cmds = uniq(args[2:current_arg_pos-1]) + [s:tasks_filter_cmd]
    return filter(matches, {_, v -> index(prev_cmds, v) == -1})
  elseif args[1] == s:journal_cmd
    let submatches = []
    if s:need_to_insert_files(current_arg_pos, args[2:])
      call extend(submatches, s:get_all_journal_files())
      let todos_idx = index(submatches, 'todos')
      if todos_idx != -1
        call remove(submatches, todos_idx)
      endif
      call extend(submatches, ['todos', 'today', 'next', 'previous'], 0)
    endif
    call s:insert_win_cmds(submatches, current_arg_pos, args[2:])
    return awiwi#util#match_subcommands(submatches, a:ArgLead)
  elseif args[1] == s:asset_cmd
    let submatches = []
    if current_arg_pos > 2 && args[2] == s:new_asset_cmd
      return []
    endif
    if s:need_to_insert_files(current_arg_pos, args[2:])
      let files = map(s:get_all_asset_files(), {_, v -> printf('%s:%s', v.date, v.name)})
      call extend(submatches, files)
    endif
    call s:insert_win_cmds(submatches, current_arg_pos, args[2:])
    if current_arg_pos == 2
      call insert(submatches, s:new_asset_cmd)
    endif
    return awiwi#util#match_subcommands(submatches, a:ArgLead)
  elseif args[1] == s:recipe_cmd
    let submatches = []
    if s:need_to_insert_files(current_arg_pos, args[2:])
      call extend(submatches, s:get_all_recipe_files())
    endif
    call s:insert_win_cmds(submatches, current_arg_pos, args[2:])
    return awiwi#util#match_subcommands(submatches, a:ArgLead)
  endif

  return []
endfun "}}}


fun! s:parse_file_and_options(args) abort "{{{
    if len(a:args) == 0 || len(a:args) > 3
      echoerr printf('Awiwi journal: 1 to 3 arguments expected. got %d', len(a:args)-1)
    endif
    let options = {}
    let file = ''
    for arg in a:args
      if arg == s:journal_new_window_cmd
        let options.new_window = v:true
      elseif str#startswith(arg, s:journal_height_window_cmd)
        let options.height = str2nr(split(arg, '=')[-1])
      else
        let file = arg
      endif
    endfor
    if file == ''
      echoerr 'Awiwi journal: missing file to open'
    endif
    return [file, options]
endfun "}}}


fun! s:get_most_recent_task_from_file() abort "{{{
  if filereadable(s:task_log_file)
    let lines = readfile(s:task_log_file, '', -1)
    if empty(lines)
      return s:get_empty_task()
    endif
    return eval(lines[0])
  else
    return s:get_empty_task()
  endif
endfun "}}}


fun! s:get_most_recent_task_activty(title) abort "{{{
  let task = s:get_empty_task()
  if !filereadable(s:task_log_file)
    return task
  endif
  for line in readfile(s:task_log_file)
    let t = eval(line)
    if t.title == a:title
      let task = t
    endif
  endfor
  return task
endfun "}}}


fun! s:get_active_task() abort "{{{
  if get(s:active_task, 'state', 'inactive') == 'active'
    return s:active_task
  endif
  return s:get_empty_task()
endfun "}}}


fun! awiwi#activate_current_task() abort "{{{
  let current_task = s:get_current_task()
  if current_task.bare_title == ''
    echoerr 'not in a task section'
    return
  endif
  let active_task = s:get_active_task()
  if active_task.state == 'active'
    if active_task.title == current_task.bare_title
      echo 'task is already active'
      return
    else
      echoerr printf('you must deactive the active task "%s"', active_task.title)
      return
    endif
  endif

  let recent_task = s:get_most_recent_task_from_file()
  if recent_task.title == current_task.bare_title
    let task = recent_task
  else
    let task = s:get_most_recent_task_activty(current_task.bare_title)
  endif

  if task.title == ''
    let task.title = current_task.bare_title
    let task.marker = current_task.marker
  endif
  let ts = s:get_epoch()
  let task.state = 'active'
  let task.updated = ts
  call add(task.activity, {'action': 'activate', 'ts': ts})
  call s:log_task_action(task, 'activate')
  let s:active_task = task
  let g:awiwi_active_task = deepcopy(task)
endfun "}}}


fun! awiwi#deactivate_active_task() abort "{{{
  let task = s:get_active_task()
  if task.state != 'active'
    echo "no task active"
    return
  endif

  let ts = s:get_epoch()
  let start_ts = task.activity[-1]['ts']
  let duration = ts - start_ts
  call add(task.activity, {'action': 'deactivate', 'ts': ts})
  let task.state = 'inactive'
  let task.updated = ts
  let task.duration = task.duration + duration
  call s:log_task_action(task, 'deactivate')
  if exists('g:awiwi_active_task')
    unlet g:awiwi_active_task
  endif
endfun "}}}


fun! awiwi#run(...) abort "{{{
  if !a:0
    throw 'AwiwiError: Awiwi expects 1+ arguments'
  endif
  if a:1 == s:journal_cmd
    let [date, options] = s:parse_file_and_options(a:000[1:])
    call awiwi#edit_journal(date, options)
  elseif a:1 == s:continuation_cmd
    call awiwi#insert_and_open_continuation()
  elseif a:1 == s:activate_cmd
    call awiwi#activate_current_task()
  elseif a:1 == s:deactivate_cmd
    call awiwi#deactivate_active_task()
  elseif a:1 == s:link_cmd
    call awiwi#add_asset_link()
  elseif a:1 == s:asset_cmd
    if a:0 == 1
      "let files = map(s:get_all_asset_files(), {_, v -> printf('%s:%s', v.date, v.name)})
      "return fzf#run(fzf#wrap({'source': files, 'sink': funcref('s:open_asset_sink')}))
      return fzf#vim#files(s:asset_subpath)
    elseif a:0 == 2 && a:2 == s:new_asset_cmd
      return awiwi#open_journal_or_asset()
    endif
    let [date_file_expr, options] = s:parse_file_and_options(a:000[1:])
    if str#contains(date_file_expr, ':')
      let [date, file] = split(date_file_expr, ':')
    else
      let date = s:get_own_date()
      let file = date_file_expr
    endif
    call s:open_asset_by_name(date, file, options)
  elseif a:1 == s:recipe_cmd
    if a:0 == 1
      return fzf#vim#files(s:recipe_subpath)
    endif
    let [recipe, options] = s:parse_file_and_options(a:000[1:])
    let options.create_dirs = v:true
    let recipe_file = path#join(s:recipe_subpath, recipe)
    call s:open_file(recipe_file, options)
  elseif a:1 == s:tasks_cmd
    call func#apply(funcref('awiwi#show_tasks'), func#spread(a:000[1:]))
  elseif a:1 == s:show_cmd
    echoerr 'Awiwi show: should render markdown in browser, but has not been implemented that'
  elseif a:1 == s:search_cmd
    call call(funcref('awiwi#fuzzy_search'), a:000[1:])
  elseif a:1 == s:entry_cmd
    let pattern = '^#{2,}[[:space:]]+.*$'
    let rg_cmd = [
          \ 'rg', '-u', '--column', '--line-number',
          \ '--no-heading', '--color=never',
          \ '-g', '!awiwi*', pattern
          \ ]
    let rg_result = systemlist(rg_cmd)
    let entries = map(
          \ filter(
          \   rg_result,
          \   {_, v -> !str#is_empty(v)}),
          \ {_, v -> substitute(v, '^\(.\{-}\)\(##\+[[:space:]]\+\)', '\1', '')})

    call fzf#run(fzf#wrap({'source': entries}))
  elseif a:1 == s:todo_cmd
    call awiwi#edit_journal('todo', {'new_window': v:true, 'height': 10})
  endif
endfun "}}}

let task = s:get_most_recent_task_from_file()
if task.state == 'active'
  let s:active_task = task
  let g:awiwi_active_task = s:active_task
endif
unlet task

if exists('g:airline_section_x')
  fun! awiwi#add_active_task_to_airline() abort "{{{
    if exists('g:awiwi_active_task') && g:awiwi_active_task.state == 'active'
      let t = g:awiwi_active_task
      let now = str2nr(strftime('%s'))
      let duration = t.duration + now - t.activity[-1].ts
      if duration < 60
        let format = printf('%ds', duration)
      elseif duration < 3600
        let format = strftime('%Mm %Ss', duration)
      elseif duration < 86400
        let format = strftime('%Hh %Mm', duration)
      else
        let format = strftime('%dd %Hh', duration)
      endif
      return printf('[ %s (%s) ]', g:awiwi_active_task.title, format)
    else
      return ''
    endif
  endfun "}}}

  hi awiwiAirlineTask cterm=bold ctermfg=160 ctermbg=232

  let g:airline_section_b = ''
  let g:airline_section_x = '%#awiwiAirlineTask#%{awiwi#add_active_task_to_airline()}'
  let g:airline_section_y = ''
endif
