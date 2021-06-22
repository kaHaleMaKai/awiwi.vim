if exists('g:autoloaded_awiwi')
  finish
endif
let g:autoloaded_awiwi = v:true

" {{{1 variables

let s:journal_subpath = awiwi#path#join(g:awiwi_home, 'journal')
let s:todos_subpath = awiwi#path#join(g:awiwi_home, 'todos')
let s:asset_subpath = awiwi#path#join(g:awiwi_home, 'assets')
let s:recipe_subpath = awiwi#path#join(g:awiwi_home, 'recipes')
let s:awiwi_data_dir = awiwi#path#join(g:awiwi_home, 'data')
let s:code_root_dir = expand('<sfile>:p:h:h')


let s:xdg_open_exts = ['ods', 'odt', 'drawio']

for dir in [s:awiwi_data_dir, s:journal_subpath, s:asset_subpath, s:recipe_subpath, s:todos_subpath]
  if !filewritable(dir)
    if !mkdir(dir, 'p')
      echoerr printf('cannot create data directory %s', dir)
      finish
    endif
  endif
endfor


let s:log_file = awiwi#path#join(s:awiwi_data_dir, 'awiwi.log')
let s:task_log_file = awiwi#path#join(s:awiwi_data_dir, 'task.log')
if !filereadable(s:task_log_file)
  if writefile([], s:task_log_file) != 0
    echoerr printf('could not create task log file "%s"', s:task_log_file)
    finish
  endif
endif

let s:log_file_size = get(g:, 'awiwi_history_length', 10000)
let s:history = []

let s:active_task = {}

let s:todo_markers = ['TODO', '@todo']
let s:onhold_markers = [
      \ 'ONHOLD',
      \ 'HOLD',
      \ '@onhole',
      \ '@onhold'
      \ ]
let s:urgent_markers = [
      \ 'FIXME',
      \ 'CRITICAL',
      \ 'URGENT',
      \ 'IMPORTANT',
      \ '@fixme',
      \ '@critical',
      \ '@urgent',
      \ '@important'
      \ ]
let s:delegate_markers = ['@@']
let s:question_markers = ['QUESTION', 'q?', 'Q?']
let s:due_markers = ['DUE', 'DUE TO', 'UNTIL', '@until', '@due']
let s:incident_markers = ['@incident']

" 1}}}

fun! s:AwiwiError(msg, ...) abort "{{{
  if a:0
    let args = [a:msg]
    call extend(args, a:000)
    let msg = call('printf', args)
  else
    let msg = a:msg
  endif
  return 'AwiwiError: ' . msg
endfun "}}}


fun! awiwi#get_code_root() abort "{{{
  return s:code_root_dir
endfun "}}}


fun! awiwi#get_data_dir() abort "{{{
  return s:awiwi_data_dir
endfun "}}}


fun! awiwi#get_asset_subpath() abort "{{{
  return s:asset_subpath
endfun "}}}


fun! awiwi#get_journal_subpath() abort "{{{
  return s:journal_subpath
endfun "}}}


fun! awiwi#get_recipe_subpath() abort "{{{
  return s:recipe_subpath
endfun "}}}


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
    let task_list = '\(^[[:space:]]*\)\zs[-*][[:space:]]+\[[[:space:]]+\]'
    call add(result, task_list)
  endif
  if options.join
    let join_char = options.escape_mode == 'vim' ? '\|' : '|'
    return join(result, join_char)
  else
    return result
  endif
endfun "}}}


fun! s:open_fuzzy_match(line) abort "{{{
  let [file, line, col] = split(a:line, ':')[:2]
  exe printf('e +%s %s', line, file)
  exe printf('normal! %s|', col)
endfun "}}}


fun! awiwi#fuzzy_search(...) abort "{{{
  if !a:0
    echoerr 'Awiwi search: no pattern given'
  endif
  let pattern = join(map(copy(a:000), {_, v -> awiwi#util#escape_pattern(v)}), '.*?')
  let rg_cmd = [
        \ 'rg', '-i', '-U', '--multiline-dotall', '--color=never',
        \ '--column', '--line-number', '--no-heading',
        \ '-g', '!awiwi*', pattern
        \ ]
  let matches = filter(systemlist(rg_cmd), {_, v -> !awiwi#str#is_empty(v)})
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


fun! s:add_link(title, target, ...) abort "{{{
  if a:0 > 0
    let target = awiwi#util#relativize(a:target, a:1)
  else
    let target = awiwi#util#relativize(a:target)
  endif
  return printf('[%s](%s)', a:title, target)
endfun "}}}


fun! awiwi#get_journal_file_by_date(date) abort "{{{
  let date = awiwi#date#parse_date(a:date)
  let [year, month, day] = split(date, '-')
  return awiwi#path#join(s:journal_subpath, year, month, date.'.md')
endfun "}}}


fun! s:escape_rg_pattern(pattern) abort "{{{
  return escape(a:pattern, ".*?\\\[\]")
endfun "}}}


fun! awiwi#open_file(file, options) abort "{{{
  if get(a:options, 'new_window', v:false)
    let height = str2nr(get(a:options, 'height', get(a:options, 'width', 0)))
    let position = get(a:options, 'position', 'auto')
    if position == 'auto'
      let position = awiwi#util#window_split_below() ? 'bottom' : 'right'
    endif
    let prefix = ''
    if position == 'left'
      let win_cmd == 'vnew'
      let prefix = 'left'
    elseif position == 'right'
      let win_cmd = 'vnew'
    elseif position == 'top'
      let prefix = 'lefta'
      let win_cmd = 'new'
    else
      let win_cmd = 'new'
    " bottom is the default case
      if position != 'bottom'
        echoerr printf('wrong position for awiwi#open_file() specified: "%s"', position)
      endif
    endif
    let cmd = printf('%s %s%s', prefix, height ? height : '', win_cmd)
  elseif get(a:options, 'new_tab', v:false)
    let cmd = 'tabnew'
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
  let date = awiwi#date#parse_date(a:date)
  try
    let own_date = awiwi#date#get_own_date()
    if date == own_date
      echom printf("journal page '%s' already open", date)
      return
    endif
  catch /AwiwiDateError/
    echo "hello"
  endtry
  let file = awiwi#get_journal_file_by_date(date)
  call awiwi#open_file(file, options)
endfun "}}}


fun! awiwi#edit_todo(name, options) abort "{{{
  let filename = printf('%s.md', a:name)
  let file = awiwi#path#join(s:todos_subpath, filename)
  call awiwi#open_file(file, a:options)
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


fun! s:get_current_task(only_main) abort "{{{
  let result = {'marker': '', 'title': '', 'tags': {}, 'bare_title': ''}
  let title = ''
  let task_marker = a:only_main ? '2' : '2,4'
  for line_nr in range(line('.'), 1, -1)
    let line = getline(line_nr)
     let matches = matchlist(line, printf('^\(#\{%s}\)[[:space:]]\+\([^[:space:]].*\)', task_marker))
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
  let own_date = awiwi#date#get_own_date()
  let today = awiwi#date#parse_date('today')
  if own_date == today
    throw "AwiwiError: already on today's journal"
  endif
  let today_file = awiwi#get_journal_file_by_date(today)
  let link = s:add_link(printf('continued on %s', today), today_file)
  let current_task = s:get_current_task(v:true)
  " get the task name
  if current_task.title == ''
    throw 'AwiwiError: could not find task title'
  endif

  let own_file = awiwi#get_journal_file_by_date(own_date)
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


fun! awiwi#get_all_journal_files(...) abort "{{{
  let files =sort(map(
        \ split(glob(awiwi#path#join(g:awiwi_home, 'journal', '**', '*.md'))),
        \ {_, v -> fnamemodify(v, ':t:r')}))
  if get(a:000, 0, v:false)
    call extend(files, ['previous day', 'next day', 'yesterday', 'today'])
  endif
  return files
endfun "}}}


fun! awiwi#insert_link_here(link) abort "{{{
  let pos = getcurpos()
  let [line_nr, col] = [pos[1], pos[2]]
  let offset = pos[-1] - col
  let line = getline(line_nr)
  let new_line = [line[:col - 1]]
  let ch = line[col - 1]
  if ! empty(ch) && match(ch, '[[:space:]]') == -1
    call add(new_line, ' ')
  endif
  call extend(new_line, [a:link, ' '])
  call add(new_line, line[col:])
  let new_content = join(new_line, '')
  let length = strlen(new_content) - strlen(line[col:])
  let pos[2] = length
  let pos[-1] = length + offset
  call setline(line_nr, new_content)
  call setpos('.', pos)
endfun "}}}


fun! awiwi#download_file(filename, url) abort "{{{
  let ret = trim(system(['curl', '--no-progress-meter', a:url, '-o', a:filename]))
  if v:shell_error
    echoerr printf('[ERROR] could not download "%s" to "%s": %s', a:url, a:filename, ret)
    return v:false
  endif
  return v:true
endfun "}}}


fun!awiwi#guess_selection_mime_type() abort "{{{
  let cmd = 'xclip -selection clipboard -o -t %s | file --mime-type -'
  for t in ['text/plain', 'image/jpg', 'image/png', 'image/gif', 'image/bmp']
    let type = split(systemlist(printf(cmd, t))[-1])[-1]
    if stridx(type, 'empty') == -1
      break
    else
      let type = ''
    endif
  endfor
  return type
endfun "}}}


fun! awiwi#paste_file(filename) abort "{{{
  let type = awiwi#guess_selection_mime_type()
  if empty(type)
    echoerr '[ERROR] cannot guess mime-type from selection'
  endif
  let cmd = ['xclip', '-selection', 'clipboard', '-t', type]
  call extend(cmd, ['-o', '>', shellescape(a:filename)])
  let ret = trim(system(join(cmd, ' ')))
  if v:shell_error
    echoerr printf('[ERROR] could not paste to "%s": %s', a:filename, ret)
    return v:false
  endif
  return v:true
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
  let current_task = s:get_current_task(v:true)
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


fun! awiwi#open_link(options, ...) abort "{{{
  if a:0
    let link = awiwei#util#determine_link_type(awiwi#util#as_link(a:1))
  else
    let link = awiwi#util#get_link_under_cursor()
  endif
  if empty(link.type)
    echoerr printf('cannot open link: "%s"', link.target)
  endif
  if link.type == 'browser' || link.type == 'external'
    let cmd = ['xdg-open', link.target]
    call system(cmd)
  elseif link.type == 'asset' || link.type == 'journal' || link.type == 'recipe'
    let dest = awiwi#path#canonicalize(awiwi#path#join(expand('%:p:h'), link.target))
    let extension = fnamemodify(dest, ':e')
    if index(s:xdg_open_exts, extension) > -1
      let cmd = ['xdg-open', dest]
      call jobstart(cmd)
    else
      call awiwi#open_file(dest, a:options)
    endif
  elseif link.type == 'image'
    let date = join(split(fnamemodify(link.target, ':h:t'), '-'), '/')
    let file = fnamemodify(link.target, ':t')
    let dest = awiwi#path#join(g:awiwi_home, 'assets', date, file)
    call system(['xdg-open', dest])
  else
    echoerr printf('cannot open unknown link type "%s"', link.type)
  endif
endfun "}}}


fun! awiwi#redact() abort "{{{
  let line = getline('.')
  let pos = getcurpos()
  " go to the end of the line, definitely
  let pos[2] = 2000
  let pos[-1] = 2000
  if match(line, '!!redacted') == -1
    let space = empty(line) || awiwi#str#endswith(line, ' ')
          \ ? '' : ' '
    let tag = space . '!!redacted'
    let new_line = line . tag
  else
    let new_line = substitute(line, ' *!!redacted', '', 'g')
  endif
  call setline(line('.'), new_line)
  call setpos('.', pos)
endfun "}}}


fun! awiwi#copy_file(path) abort "{{{
  let cmd = ['xclip', '-selection', 'clipboard', '-r', a:path]
  let ret = trim(system(cmd))
  if !v:shell_error
    echo printf('[INFO] copied file %s to clipboard', fnamemodify(a:path, ':h'))
    return v:true
  else
    echo printf('[ERROR] could not copy file %s to clipboard', fnamemodify(a:path, ':h'))
    return v:false
  endif
endfun "}}}


fun! awiwi#insert_recipe_link(recipe) abort "{{{
  let recipe_file = awiwi#path#join(s:recipe_subpath, a:recipe)
  let parts = split(recipe_file, '/')
  for i in range(len(parts)-1, 0, -1)
    if parts[i] == 'recipes'
      let start = i + 1
      break
    endif
  endfor

  let file_name = call('awiwi#path#join', parts[start:])
  let path = awiwi#util#relativize(recipe_file)
  let link = printf('[recipe %s](%s)', file_name, path)
  call awiwi#insert_link_here(link)
endfun "}}}


fun! awiwi#insert_journal_link(date) abort "{{{
  let date = awiwi#date#parse_date(a:date)
  let file = awiwi#util#relativize(awiwi#get_journal_file_by_date(date))
  let link = printf('[journal for %s](%s)', date, file)
  call awiwi#insert_link_here(link)
endfun "}}}


fun! awiwi#handle_paste_in_insert_mode() abort "{{{
  let type = awiwi#guess_selection_mime_type()
  if empty(type)
    return
  elseif type == 'text/plain'
    normal! "+p
  else
    call awiwi#asset#create_asset_here_if_not_exists(awiwi#cmd#get_cmd('paste_asset'))
    normal! f)la
  endif
endfun "}}}
