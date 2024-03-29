if exists('g:autoloaded_awiwi_cmd')
  finish
endif
let g:autoloaded_awiwi_cmd = v:true

let s:activate_cmd = 'activate'
let s:bookmark_cmd = '!bookmark'
let s:deactivate_cmd = 'deactivate'
let s:journal_cmd = 'journal'
let s:continuation_cmd = 'continue'
let s:entry_cmd = 'entries'
let s:asset_cmd = 'asset'
let s:link_cmd = 'link'
let s:recipe_cmd = 'recipe'
let s:search_cmd = 'search'
let s:serve_cmd = 'serve'
let s:server_cmd = 'server'
let s:redact_cmd = 'redact'
let s:tags_cmd = 'tags'
let s:todo_cmd = 'todo'
let s:store_session_cmd = 'save'
let s:restore_session_cmd = 'restore'
let s:meta_cmd = 'meta'
let s:due_cmd = 'due'
let s:toc_cmd = 'toc'
let s:ask_cmd = 'ask'

let s:new_asset_cmd = 'create'
let s:empty_asset_cmd = 'empty'
let s:url_asset_cmd = 'url'
let s:paste_asset_cmd = 'paste'
let s:copy_asset_cmd = 'copy'

let s:server_start_cmd = 'start'
let s:server_stop_cmd = 'stop'
let s:server_logs_cmd = 'logs'

let s:meta_edit_cmd = 'edit'
let s:meta_delete_cmd = 'delete'

let s:subcommands = [
      \ s:activate_cmd,
      \ s:bookmark_cmd,
      \ s:continuation_cmd,
      \ s:due_cmd,
      \ s:deactivate_cmd,
      \ s:journal_cmd,
      \ s:entry_cmd,
      \ s:asset_cmd,
      \ s:link_cmd,
      \ s:paste_asset_cmd,
      \ s:recipe_cmd,
      \ s:redact_cmd,
      \ s:meta_cmd,
      \ s:restore_session_cmd,
      \ s:store_session_cmd,
      \ s:search_cmd,
      \ s:serve_cmd,
      \ s:server_cmd,
      \ s:tags_cmd,
      \ s:toc_cmd,
      \ s:todo_cmd,
      \ ]

let s:tags_all_cmd = 'all'
let s:tags_due_cmd = 'due'
let s:tags_filter_cmd = 'filter'
let s:tags_urgent_cmd = 'urgent'
let s:tags_onhold_cmd = 'onhold'
let s:tags_question_cmd = 'question'
let s:tags_todo_cmd = 'todo'
let s:tags_incidents_cmd = 'incidents'
let s:tags_changes_cmd = 'changes'
let s:tags_issues_cmd = 'issues'
let s:tags_bugs_cmd = 'bugs'


let s:journal_create_file_cmd = '+create'
let s:journal_new_window_cmd = '+new'
let s:journal_hnew_window_cmd = '+hnew'
let s:journal_vnew_window_cmd = '+vnew'
let s:journal_same_window_cmd = '-new'
let s:journal_new_tab_cmd = '+tab'
let s:journal_options_cmd = [
      \ s:journal_new_window_cmd,
      \ s:journal_hnew_window_cmd,
      \ s:journal_vnew_window_cmd,
      \ s:journal_same_window_cmd,
      \ s:journal_new_tab_cmd,
      \ s:journal_create_file_cmd,
      \ s:bookmark_cmd
      \ ]

let s:journal_height_window_cmd = '+height='
let s:journal_width_window_cmd = '+width='
let s:journal_all_dim_window_cmds = [
      \ s:journal_height_window_cmd,
      \ s:journal_width_window_cmd
      \ ]

let s:tags_subcommands = [
      \ s:tags_all_cmd,
      \ s:tags_due_cmd,
      \ s:tags_filter_cmd,
      \ s:tags_urgent_cmd,
      \ s:tags_onhold_cmd,
      \ s:tags_question_cmd,
      \ s:tags_todo_cmd,
      \ s:tags_incidents_cmd,
      \ s:tags_changes_cmd,
      \ s:tags_issues_cmd,
      \ s:tags_bugs_cmd
      \ ]

let s:todo_inprogress_cmd = 'inprogress'
let s:todo_backlog_cmd = 'backlog'
let s:todo_done_cmd = 'done'
let s:todo_waiting_cmd = 'waiting'
let s:todo_onhold_cmd = 'onhold'
let s:todo_questions_cmd = 'questions'

let s:todo_subcommands = [
      \ s:todo_inprogress_cmd,
      \ s:todo_backlog_cmd,
      \ s:todo_done_cmd,
      \ s:todo_onhold_cmd,
      \ s:todo_questions_cmd
      \ ]

let s:week_days = [
      \ 'Mon',
      \ 'Tue',
      \ 'Wed',
      \ 'Thu',
      \ 'Fri',
      \ 'Sat',
      \ 'Sun'
      \ ]

let s:session_file = awiwi#path#join(g:awiwi_home, 'session.vim')


fun! s:AwiwiCmdError(msg, ...) abort "{{{
  if a:0
    let args = [a:msg]
    call extend(args, a:000)
    let msg = call('printf', args)
  else
    let msg = a:msg
  endif
  return 'AwiwiCmdError: ' . msg
endfun "}}}


fun! awiwi#cmd#store_session() abort "{{{
  exe printf('mksession! %s', s:session_file)
endfun "}}}


fun! awiwi#cmd#restore_session() abort "{{{
  exe printf('source %s', s:session_file)
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


fun! awiwi#cmd#get_cmd(name) abort "{{{
  let name = printf('%s_cmd', a:name)
  if !has_key(s:, name)
    throw s:AwiwiCmdError('command %s does not exist', name)
  endif
  return get(s:, name)
endfun "}}}


fun! s:get_all_recipe_files() abort "{{{
    let prefix_len = awiwi#str#endswith(awiwi#get_recipe_subpath() , '/')
          \ ? strlen(awiwi#get_recipe_subpath()) : strlen(awiwi#get_recipe_subpath())+1
    return sort(
          \ map(
          \   filter(
          \     glob(awiwi#path#join(awiwi#get_recipe_subpath(), '**', '*'), v:false, v:true),
          \     {_, v -> filereadable(v)}),
          \   {_, v -> v[prefix_len:]}))
endfun "}}}


fun! s:need_to_insert_files(current_arg_pos, args, ...) abort "{{{
  let start = get(a:000, 0, 2)
  if a:current_arg_pos == start
    return v:true
  endif
  return (a:current_arg_pos - s:has_new_win_cmd(a:args) - s:has_win_height_cmd(a:args)) == start
        \ ? v:true : v:false
endfun "}}}


fun! s:has_new_win_cmd(args) abort "{{{
  return len(filter(copy(a:args), {_, v -> index(s:journal_options_cmd, v) > -1})) > 0
        \ ? v:true : v:false
endfun "}}}


fun! s:has_win_height_cmd(args) abort "{{{
  return len(filter(copy(a:args), {_, v ->
        \                          awiwi#str#startswith(v, s:journal_height_window_cmd)
        \                          || awiwi#str#startswith(v, s:journal_width_window_cmd) })) > 0
        \ ? v:true : v:false
endfun "}}}


fun! s:insert_win_cmds(li, current_arg_pos, args) abort "{{{
  if a:current_arg_pos == 2
    return a:li
  elseif !s:has_new_win_cmd(a:args)
    call extend(a:li, s:journal_options_cmd)
    return
  elseif !s:has_win_height_cmd(a:args)
    call insert(a:li, s:journal_all_dim_window_cmds)
  endif
  return a:li
endfun "}}}


fun! s:parse_file_and_options(args, ...) abort "{{{
  if len(a:args) == 0 || len(a:args) > 3
    echoerr printf('Awiwi journal: 1 to 3 arguments expected. got %d', len(a:args)-1)
  endif
  if a:0
    let options = copy(a:1)
  else
    let options = {'position': 'auto', 'new_window': v:true, 'new_tab': v:false, 'create_dirs': v:false, 'bookmark': v:false}
  endif
  let file = ''
  for arg in a:args
    if arg =~# '^#'
      let options.anchor = arg[1:]
    elseif arg == s:journal_create_file_cmd
      let options.create_dirs = v:true
    elseif index(s:journal_options_cmd, arg) > -1
      if arg == s:journal_hnew_window_cmd
        let options.position = "bottom"
        let options.new_window = v:true
      elseif arg == s:journal_vnew_window_cmd
        let options.position = "right"
        let options.new_window = v:true
      elseif arg == s:journal_new_window_cmd
        let options.position = 'auto'
        let options.new_window = v:true
      elseif arg == s:journal_same_window_cmd
        let options.new_window = v:false
      elseif arg == s:journal_new_tab_cmd
        let options.new_window = v:false
        let options.new_tab = v:true
      elseif arg == s:bookmark_cmd
        let options.bookmark = v:true
      endif
    elseif awiwi#str#startswith(arg, s:journal_height_window_cmd) || awiwi#str#startswith(arg, s:journal_width_window_cmd)
      let options.height = str2nr(split(arg, '=')[-1])
    else
      let file = arg
    endif
  endfor
  if get(options, 'height') == 0 && awiwi#util#window_split_below()
    let options.height = 20
  endif
  if file == ''
    echoerr 'Awiwi journal: missing file to open'
  endif
  return [file, options]
endfun "}}}


fun! s:get_file_for_command(args) abort "{{{
  let cmd = ''
  let file = ''
  if len(a:args) < 2
    return
  endif

  if a:args[1] == s:link_cmd
    if len(a:args) == 2
      return
    endif
    let cmd = a:args[2]
    let rem = a:args[3:]
  else
    let cmd = a:args[1]
    let rem = a:args[2:]
  endif
  for arg in rem
    if arg !~# '^[-+#]'
      let file = arg
      break
    endif
  endfor
  if empty(cmd)
    return
  endif
  if cmd == s:recipe_cmd
    return printf('%s/%s', awiwi#get_recipe_subpath(), file)
  elseif cmd == s:asset_cmd
    let [date, name] = file->split(':')
    return awiwi#asset#get_asset_path(date, name)
  elseif cmd == s:journal_cmd
    return awiwi#get_journal_file_by_date(file)
  else
    return
  endif
endfun "}}}


fun! s:get_headings_from_file(file) abort "{{{
  return systemlist(['rg', '^#+ ', a:file])
        \->map({_,v -> v
        \  ->tolower()
        \  ->substitute('^#\+\s\+', '', '')
        \  ->substitute('[^-a-zA-Z0-9 ]', '', 'g')
        \  ->substitute('\s\+', '-', 'g')
        \  ->substitute('/', '', 'g')
        \})
endfun "}}}


fun! awiwi#cmd#get_completion(ArgLead, CmdLine, CursorPos) abort "{{{
  let current_arg_pos = awiwi#util#get_argument_number(a:CmdLine[:a:CursorPos])
  if current_arg_pos < 2
    return awiwi#util#match_subcommands(s:subcommands, a:ArgLead)
  endif
  let args = split(a:CmdLine)

  if args[1] == s:tags_cmd && current_arg_pos >= 2
    let matches = awiwi#util#match_subcommands(s:tags_subcommands, a:ArgLead)
    if current_arg_pos == 2
      return matches
    elseif args[2] == s:tags_filter_cmd
      return []
    endif
    let prev_cmds = uniq(args[2:current_arg_pos-1]) + [s:tags_filter_cmd]
    return filter(matches, {_, v -> index(prev_cmds, v) == -1})
  elseif args[1] == s:journal_cmd || (args[1] == s:link_cmd && get(args, 2, '') == s:journal_cmd)
    let start = args[1] == s:journal_cmd ? 2 : 3
    let submatches = []
    if s:need_to_insert_files(current_arg_pos, args[start:], start)
      call extend(submatches, awiwi#get_all_journal_files())
      let todos_idx = index(submatches, 'todos')
      if todos_idx != -1
        call remove(submatches, todos_idx)
      endif
      call extend(submatches, ['todos', 'today', 'next', 'previous'], 0)
    elseif args[1] == s:link_cmd && args->get(current_arg_pos, '') == '#'
      let _file = s:get_file_for_command(args)
      let headings = s:get_headings_from_file(_file)->map({_,v -> '#' .. v})
      if !empty(headings) && headings[0] =~# '^#\s\+2[-0-9]\+\s*$'
        call remove(headings, 0)
      endif
      return headings
    endif
    if args[1] == s:journal_cmd
      call s:insert_win_cmds(submatches, current_arg_pos, args[start:])
    endif
    return awiwi#util#match_subcommands(submatches, a:ArgLead)
  elseif args[1] == s:asset_cmd || (args[1] == s:link_cmd && get(args, 2, '') == s:asset_cmd)
    let submatches = []
    if current_arg_pos > 2 && args[1] == s:asset_cmd && args[2] == s:new_asset_cmd
      return [s:paste_asset_cmd, s:url_asset_cmd, s:copy_asset_cmd]
    endif
    let start = args[1] == s:asset_cmd ? 2 : 3
    if len(args) == 2
      call add(submatches, s:new_asset_cmd)
      call add(submatches, s:paste_asset_cmd)
    endif
    if s:need_to_insert_files(current_arg_pos, args[start:], start)
      let files = map(awiwi#asset#get_all_asset_files(), {_, v -> printf('%s:%s', v.date, v.name)})
      call add(submatches, s:new_asset_cmd)
      call add(submatches, s:paste_asset_cmd)
      call extend(submatches, files)
    elseif args[1] == s:link_cmd && args->get(current_arg_pos, '') == '#'
      let _file = s:get_file_for_command(args)
      return s:get_headings_from_file(_file)->map({_,v -> '#' .. v})
    endif
    if args[1] == s:asset_cmd
      call s:insert_win_cmds(submatches, current_arg_pos, args[start:])
    endif
    return awiwi#util#match_subcommands(submatches, a:ArgLead)
  elseif args[1] == s:recipe_cmd || (args[1] == s:link_cmd && get(args, 2, '') == s:recipe_cmd)
    let start = args[1] == s:recipe_cmd ? 2 : 3
    let submatches = []
    if s:need_to_insert_files(current_arg_pos, args[start:], start)
      call extend(submatches, s:get_all_recipe_files())
    elseif args[1] == s:link_cmd && args->get(current_arg_pos, '') == '#'
      let _file = s:get_file_for_command(args)
      return s:get_headings_from_file(_file)->map({_,v -> '#' .. v})
    endif
    if args[1] == s:recipe_cmd
      call s:insert_win_cmds(submatches, current_arg_pos, args[start:])
    endif
    return awiwi#util#match_subcommands(submatches, a:ArgLead)
  elseif args[1] == s:todo_cmd
    let submatches = copy(s:todo_subcommands)
    call s:insert_win_cmds(submatches, current_arg_pos+1, args[2:])
    return awiwi#util#match_subcommands(submatches, a:ArgLead)
  elseif args[1] == s:meta_cmd
    if current_arg_pos == 2
      let submatches = [s:meta_edit_cmd, s:meta_delete_cmd]
      return awiwi#util#match_subcommands(submatches, a:ArgLead)
    elseif current_arg_pos == 3 && args[2] == s:meta_edit_cmd
      let submatches = ['created', s:due_cmd]
      return awiwi#util#match_subcommands(submatches, a:ArgLead)
    endif
  elseif args[1] == s:due_cmd || args[2:3] == [s:meta_edit_cmd, s:due_cmd]
    let start = args[1] == s:due_cmd ? 2 : 4
    if current_arg_pos == start
      let submatches = [
            \ 'today',
            \ 'tomorrow',
            \ 'next',
            \ 'in',
            \ '+'
            \ ]
      call extend(submatches, s:week_days)
      return awiwi#util#match_subcommands(submatches, a:ArgLead)
    elseif args[start] == 'next' && current_arg_pos == start + 1
      let submatches = copy(s:week_days)
      call extend(submatches, ['day', 'week', 'month', 'year'])
      return awiwi#util#match_subcommands(submatches, a:ArgLead)
    elseif (args[start] == 'in' || args[start] == '+') && current_arg_pos == start + 2
      let submatches = ['day', 'week', 'month', 'year']
      if args[start + 1] != '1'
        let submatches = submatches->copy()->map({_,v -> v . 's'})
      endif
      return awiwi#util#match_subcommands(submatches, a:ArgLead)
    endif
  elseif args[1] == s:server_cmd && current_arg_pos == 2
    let submatches = [awiwi#server#server_is_running() ? s:server_stop_cmd : s:server_start_cmd, s:server_logs_cmd]
    return awiwi#util#match_subcommands(submatches, a:ArgLead)
  elseif args[1] == s:server_cmd && current_arg_pos == 3 && args[2] == s:server_start_cmd
    let submatches = ['localhost', '*']
    return awiwi#util#match_subcommands(submatches, a:ArgLead)
  elseif args[1] == s:server_cmd && current_arg_pos == 3 && args[2] == s:server_logs_cmd
    let submatches = ['stdout', 'stderr', 'exit']
    return awiwi#util#match_subcommands(submatches, a:ArgLead)
  elseif args[1] == s:link_cmd
    let submatches = [s:journal_cmd, s:recipe_cmd, s:asset_cmd]
    return awiwi#util#match_subcommands(submatches, a:ArgLead)
  endif

  return []
endfun "}}}


fun! awiwi#cmd#run(...) abort "{{{
  if !a:0
    throw s:AwiwiCmdError('Awiwi expects 1+ arguments')
  endif
  if a:1 == s:journal_cmd || (a:1 == s:link_cmd && get(a:000, 1, '') == s:journal_cmd)
    if a:000[-1] == s:journal_cmd
      let fzf_opts = fzf#vim#with_preview()
      if a:0 == 1
        return fzf#vim#files(awiwi#get_journal_subpath(), fzf_opts)
      else
        let fzf_opts.source = awiwi#get_all_journal_files({'include_literals': v:true})
        let fzf_opts.sink = funcref('awiwi#insert_journal_link')
        return fzf#run(fzf#wrap(fzf_opts))
      endif
    endif
    let [date, options] = s:parse_file_and_options(a:000[1:], {'new_window': v:false})
    if a:1 == s:link_cmd
      return awiwi#insert_journal_link(date, options)
    " elseif options.bookmark
    else
      call awiwi#edit_journal(date, options)
    endif
  elseif a:1 == s:continuation_cmd
    call awiwi#insert_and_open_continuation()
  elseif a:1 == s:activate_cmd
    call awiwi#activate_current_task()
  elseif a:1 == s:deactivate_cmd
    call awiwi#deactivate_active_task()
  elseif a:1 == s:paste_asset_cmd ||
        \ (a:1 == s:asset_cmd && get(a:000, 1, '') == s:paste_asset_cmd)
    return awiwi#asset#create_asset_here_if_not_exists(s:paste_asset_cmd)
  elseif a:1 == s:asset_cmd || (a:1 == s:link_cmd && get(a:000, 1, '') == s:asset_cmd)
    if a:0 == 1
      "let files = map(awiwi#asset#get_all_asset_files(), {_, v -> printf('%s:%s', v.date, v.name)})
      "return fzf#run(fzf#wrap({'source': files, 'sink': funcref('awiwi#asset#open_asset_sink')}))
      return fzf#vim#files(awiwi#get_asset_subpath(), fzf#vim#with_preview())
    elseif a:0 >= 2 && a:2 == s:copy_asset_cmd
      let link = awiwi#util#get_link_under_cursor()
      if link.type != 'asset'
        echoerr '[ERROR] no asset file under cursor'
        return
      endif
      let dest = awiwi#path#canonicalize(awiwi#path#join(expand('%:p:h'), link.target))
      return awiwi#copy_file(dest)
    elseif a:0 >= 2 && a:2 == s:new_asset_cmd
      if get(a:000, 2, '') == s:url_asset_cmd
        return awiwi#asset#create_asset_here_if_not_exists(s:url_asset_cmd)
      elseif get(a:000, 2, '') == s:paste_asset_cmd
        return awiwi#asset#create_asset_here_if_not_exists(s:paste_asset_cmd)
      else
        let args = [s:empty_asset_cmd, {'suffix': '.md'}]
        call extend(args, a:000[2:])
        let filename = call('awiwi#asset#create_asset_here_if_not_exists', args)
        return awiwi#asset#open_asset(filename, {'new_window': v:true})
      endif
    endif

    let start = a:1 == s:asset_cmd ? 1 : 2
    let [date_file_expr, options] = s:parse_file_and_options(a:000[start:])
    if awiwi#str#contains(date_file_expr, ':')
      let [date, file] = split(date_file_expr, ':')
    else
      let date = awiwi#date#get_own_date()
      let file = date_file_expr
    endif
    if a:1 == s:link_cmd
      return awiwi#asset#insert_asset_link(date, file, options)
    else
      return awiwi#asset#open_asset_by_name(date, file, options)
    endif

  elseif a:1 == s:recipe_cmd || (a:1 == s:link_cmd && get(a:000, 1, '') == s:recipe_cmd)
    if a:000[-1] == s:recipe_cmd
      let fzf_opts = fzf#vim#with_preview()
      if a:0 == 1
        let oshell = &shell
        set shell=/bin/sh
        return fzf#vim#files(awiwi#get_recipe_subpath(), fzf_opts)
      else
        let fzf_opts.sink = funcref('awiwi#insert_recipe_link')
        call fzf#vim#files(awiwi#get_recipe_subpath(), fzf_opts)
        return
      endif
    endif
    let [recipe, options] = s:parse_file_and_options(a:000[1:])
    if !awiwi#str#endswith(recipe, '.md')
      let recipe = recipe . '.md'
    endif
    let options.create_dirs = v:true
    if a:1 == s:recipe_cmd
      let recipe_file = awiwi#path#join(awiwi#get_recipe_subpath(), recipe)
      call awiwi#open_file(recipe_file, options)
    else
      call awiwi#insert_recipe_link(recipe, options)
      return
    endif
  elseif a:1 == s:tags_cmd
    call fn#apply('awiwi#cmd#show_tasks', fn#spread(a:000[1:]))
  elseif a:1 == s:search_cmd
    call call(funcref('awiwi#fuzzy_search'), a:000[1:])
  elseif a:1 == s:serve_cmd
    call awiwi#server#serve()
  elseif a:1 == s:server_cmd
    if a:0 == 1
      echoerr 'Awiwi server command needs further arguments'
      return
    elseif a:2 == s:server_start_cmd
      let host = get(a:000, 2, 'localhost')
      let port = get(a:000, 3, awiwi#server#get_default_port())
      call awiwi#server#start_server(host, port)
    elseif a:2 == s:server_stop_cmd
      call awiwi#server#stop_server()
    elseif a:2 == s:server_logs_cmd
      let log_type = get(a:000, 2, '')
      call awiwi#server#server_logs(log_type)
    endif
  elseif a:1 == s:redact_cmd
    call awiwi#redact()
  elseif a:1 == s:due_cmd
    call awiwi#edit_meta_info({'delete': v:false, 'column': 'due', 'args': copy(a:000[1:])})
    return
  elseif a:1 == s:meta_cmd
    let meta_opts = {}
    if a:2 == s:meta_delete_cmd
      let meta_opts.delete = v:true
    elseif a:2 == s:meta_edit_cmd
      if a:0 >= 3
        let meta_opts.column = a:3
      endif
    else
      echo printf('error: got unknown command: "Awiwi meta %s"', a:2)
      return
    endif
    call awiwi#edit_meta_info(meta_opts)
    return
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
          \   {_, v -> !awiwi#str#is_empty(v)}),
          \ {_, v -> substitute(v, '^\(.\{-}\)\(##\+[[:space:]]\+\)', '\1', '')})

    call fzf#run(fzf#wrap({'source': entries}))
  elseif a:1 == s:todo_cmd
    let cur_dir = expand('%:p:h:t')
    if cur_dir == 'todos'
      let default_opts = {'new_window': v:true, 'position': 'top', 'new_tab': v:false}
    else
      let default_opts = {'new_window': v:false, 'new_tab': v:true}
    endif
    let [file, options] = s:parse_file_and_options(a:000, default_opts)
    let file = file == s:todo_cmd ? 'inprogress' : file
    call awiwi#edit_todo(file, options)
  elseif a:1 == s:store_session_cmd
    return awiwi#cmd#store_session()
  elseif a:1 == s:restore_session_cmd
    return awiwi#cmd#restore_session()
  elseif a:1 == s:toc_cmd
    if a:0 == 1
      let date = awiwi#date#get_own_date()
    else
      let date = a:000[1:]
            \->map({_,v -> v->split('-')})
            \->reduce({acc, v -> acc +v}, [])[:1]->join('-')
    endif
    call awiwi#show_toc_in_qlist({'date': date})
  endif
endfun "}}}


fun! awiwi#cmd#show_tasks(...) abort "{{{
  let markers = []

  if a:0
    let args = a:000
  else
    let args = [s:tags_todo_cmd]
  endif

  if s:contains(args, s:tags_urgent_cmd, s:tags_all_cmd, s:tags_todo_cmd)
    let markers = [awiwi#get_markers('urgent')]
  else
    let markers = []
  endif
  let has_due = v:false
  if s:contains(args, s:tags_todo_cmd, s:tags_all_cmd)
    call add(markers, awiwi#get_markers('todo'))
  endif
  if s:contains(args, s:tags_due_cmd, s:tags_all_cmd)
    let due = awiwi#get_markers('due')
    call add(markers, printf('\(?(%s):?( \S+)*\)?', due))
    let has_due = v:true
  endif
  if s:contains(args, s:tags_onhold_cmd, s:tags_all_cmd)
    call add(markers, awiwi#get_markers('onhold'))
  endif
  if s:contains(args, s:tags_question_cmd, s:tags_all_cmd)
    call add(markers, awiwi#get_markers('question'))
  endif
  if s:contains(args, s:tags_incidents_cmd, s:tags_all_cmd)
    call add(markers, awiwi#get_markers('incident'))
  endif
  if s:contains(args, s:tags_changes_cmd, s:tags_all_cmd)
    call add(markers, awiwi#get_markers('change'))
  endif
  if s:contains(args, s:tags_issues_cmd, s:tags_all_cmd)
    call add(markers, awiwi#get_markers('issue'))
  endif
  if s:contains(args, s:tags_bugs_cmd, s:tags_all_cmd)
    call add(markers, awiwi#get_markers('bug'))
  endif
  if args[0] == s:tags_filter_cmd
    if a:0 == 1
      throw s:AwiwiCmdError('missing argument for "Awiwi tasks filter"')
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
