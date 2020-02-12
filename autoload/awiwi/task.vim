" if exists('g:autoloaded_awiwi_task')
"   finish
" endif
" let g:autoloaded_awiwi_task = v:true

let s:script = expand('<sfile>:p')
let s:db = path#join(g:awiwi_home, 'task.db')
let s:ids = {}
let s:tables = ['urgency', 'tag', 'task', 'task_tags', 'setting', 'task_log']
let s:duration_increment = get(g:, 'awiwi_task_update_frequency', 30) " FIXME set to 30
let s:resources = {}
let s:timer = 0
let s:previous_timer_run = str2nr(strftime('%s'))


let s:screensavers = {
      \ 'gnome': 'org.gnome.ScreenSaver',
      \ 'cinnamon': 'org.cinnamon.ScreenSaver',
      \ 'kde': 'org.kde.screensaver',
      \ 'freedesktop': 'org.freedesktop.ScreenSaver'
      \ }

let s:screensaver = get(g:, 'awiwi_screensaver', 'freedesktop')
if !has_key(s:screensavers, s:screensaver)
  echoerr printf('got unknown screensaver "%s"', s:screensaver)
  finish
endif
let s:screensaver = s:screensavers[s:screensaver]

let s:screensaver_cmd = [
      \ 'dbus-send', '--session', '--print-reply=literal',
      \ printf('--dest=%s', s:screensaver),
      \ '/' .. tr(s:screensaver, '.', '/'),
      \ printf('%s.GetActive', s:screensaver)
      \ ]


fun! s:AwiwiTaskError(msg, ...) abort "{{{
  if a:0
    let args = [a:msg]
    call extend(args, a:000)
    let msg = call('printf', args)
  else
    let msg = a:msg
  endif
  return 'AwiwiTaskError: ' . msg
endfun "}}}


fun! s:get_current_timestamp() abort "{{{
  return strftime('%F %T')
endfun "}}}


fun! s:get_resource(path, ...) abort "{{{
  let paths = [fnamemodify(s:script, ':h:h:h'), 'resources', a:path]
  call extend(paths, a:000)
  let resource_path = call(funcref('path#join'), paths)
  if has_key(s:resources, resource_path)
    return s:resources[resource_path]
  endif
  if !filereadable(resource_path)
    throw s:AwiwiTaskError('resource does not exist: "%s"', resource_path)
  endif
  let content = join(readfile(resource_path, ''), "\n")
  let s:resources[resource_path] = content
  return s:resources[resource_path]
endfun "}}}


fun! s:start_timer(...) abort "{{{
  if get(a:000, 0, v:false)
    let s:previous_timer_run = str2nr(strftime('%s'))
  endif
  let s:timer = timer_start(
        \ s:duration_increment * 1000,
        \ 'awiwi#task#update_duration_handler',
        \ {'repeat': -1})
endfun "}}}


fun! s:stop_timer() abort "{{{
  if s:timer > 0
    call timer_stop(s:timer)
    let s:timer = 0
  endif
  call awiwi#task#update_duration_handler()
endfun "}}}


fun! awiwi#task#get_active_task() abort "{{{
  if exists('s:active_task')
    return s:active_task
  endif
  let query = s:get_resource('db', 'get-active-task.sql')
  let res = awiwi#sql#select(s:db, query)
  let s:active_task = empty(res) ? {} : res[0]
  if !empty(s:active_task)
    call s:start_timer()
  endif
  return s:active_task
endfun "}}}
let s:active_task = awiwi#task#get_active_task()


fun! s:create_db(path) abort "{{{
  let parent = fnamemodify(a:path, ':h')
  if filewritable(parent) != 2 && !mkdir(parent, 'p')
    echoerr printf('could not create parent dir for sqlite db: "%s"', parent)
    return v:false
  endif
  if filewritable(a:path)
    return v:true
  endif
  let init_queries = s:get_resource('db', 'init.sql')
  let success = awiwi#sql#ddl(a:path, init_queries)
  if !success
    call delete(a:path)
    call delete(a:path . '-journal')
    echoerr printf('could not init sqlite db "%s"', a:path)
    return v:false
  endif
  return v:true
endfun "}}}
call s:create_db(s:db)


fun! s:get_id(table) abort "{{{
  if has_key(s:ids, a:table)
    return s:ids[a:table]
  endif
  let res = awiwi#sql#select(s:db, 'SELECT IfNull(Max(id), 0) as id@n FROM ?', {'value': a:table, 'type': 'table'})
  return res[0].id
  endif
endfun "}}}


for table in s:tables
  let s:ids[table] = s:get_id(table)
endfor


fun! s:increment_and_get_id(table, ...) abort "{{{
  let id = s:ids[a:table]
  let s:ids[a:table] += get(a:000, 0, 1)
  return id + 1
endfun "}}}


fun! awiwi#task#update_duration_handler(...) abort "{{{
  let now = str2nr(strftime('%s'))
  try
    call s:update_duration_helper(now - s:previous_timer_run)
  finally
    let s:previous_timer_run = now
  endtry
endfun


fun! s:update_duration_helper(diff) abort "{{{
  if awiwi#task#is_screensaver()
    return
  endif

  let task = awiwi#task#get_active_task()
  if empty(task)
    return
  endif

  let t = awiwi#sql#start_transaction(s:db)
  call t.exec(
        \ 'UPDATE task SET duration = duration + ? WHERE id = ?',
        \ a:diff, task.id)
  return t.commit()
endfun "}}}


fun! awiwi#task#get_urgencies() abort "{{{
  if exists('s:urgencies')
    return s:urgencies
  endif
  let res = awiwi#sql#select(s:db, 'SELECT id@n, name@s, value@n FROM urgency')
  let s:urgencies = {}
  for row in res
    let s:urgencies[row.name] = row
  endfor
  return s:urgencies
endfun "}}}


fun! awiwi#task#get_urgency(urgency) abort "{{{
  let urgencies = awiwi#task#get_urgencies()
  return urgencies[a:urgency]
endfun "}}}


fun! awiwi#task#get_all_tags() abort "{{{
  if exists('s:tags')
    return s:tags
  endif

  let res = awiwi#sql#select(s:db, 'SELECT id@n, name@s FROM tag')
  let s:tags = {}
  for tag in res
    let s:tags[tag.name] = tag.id
  endfor
  return s:tags
endfun "}}}


fun! awiwi#task#get_tag_id(tag) abort "{{{
  return awiwi#task#get_all_tags()[a:tag]
endfun "}}}


fun! awiwi#task#add_tag(tag) abort "{{{
  let tags = awiwi#task#get_all_tags()
  if has_key(tags, a:tag)
    return v:false
  endif
  let next_id = s:increment_and_get_id('tag')
  let res = awiwi#sql#ddl(s:db, 'INSERT INTO tag (`id`, `name`) VALUES (?, ?)', next_id, a:tag)
  if res
    let s:tags[a:tag] = next_id
  else
    call s:increment_and_get_id('tag', -1)
  endif
  return v:true
endfun "}}}


fun! awiwi#task#get_task_tags_by_title(title) abort "{{{
  let query = s:get_resource('db', 'get-task-tags-by-title.sql')
  return awiwi#sql#select(s:db, query, a:title)
endfun "}}}


fun! awiwi#task#is_screensaver() abort "{{{
  return split(system(s:screensaver_cmd))[1] == 'true'
endfun "}}}


fun! awiwi#task#get_tasks_by_title(title) abort "{{{
  let query = s:get_resource('db', 'get-tasks-by-title.sql')
  return awiwi#sql#select(s:db, query, a:title)
endfun "}}}


fun! awiwi#task#get_most_recent_task_by_title(title) abort "{{{
  let query = s:get_resource('db', 'get-most-recent-task-by-title.sql')
  let res = awiwi#sql#select(s:db, query, a:title)
  return empty(res) ? {} : res[0]
endfun "}}}


fun! awiwi#task#activate_task(title, ...) abort "{{{
  let stop_active_task = get(a:000, 0, v:false)
  return s:activate_task(a:title, stop_active_task, v:false)
endfun "}}}


fun! awiwi#task#force_activate_task(title, ...) abort "{{{
  let stop_active_task = get(a:000, 0, v:false)
  return s:activate_task(a:title, stop_active_task, v:true)
endfun "}}}


fun! s:activate_task(title, stop_active_task, force) abort "{{{
  let task = awiwi#task#get_active_task()
  let next_task = awiwi#task#get_most_recent_task_by_title(a:title)
  if !a:force && next_task.state == 'done'
    throw s:AwiwiTaskError('task "%s" is already finished. use awiwi#task#force_activate_task instead', a:title)
  endif
  if empty(next_task)
    throw s:AwiwiTaskError('task "%s" does not exist', a:title)
  endif
  let t = awiwi#sql#start_transaction(s:db)
  if !empty(task)
      if task.id == next_task.id
        return v:false
      endif
    if !a:force
      throw s:AwiwiTaskError('task "%s" already active', task.title)
    else
      let new_state = a:stop_active_task ? 'done' : 'paused'
      call t.exec('UPDATE task SET state = ? WHERE id = ?', new_state, task.id)
      call t.exec('INSERT INTO task_log (task_id, change) VALUES (?, ?)', task.id, new_state)
    endif
  endif
  call t.exec('UPDATE task SET state = ? WHERE id = ?', 'started', next_task.id)
  call t.exec('INSERT INTO task_log (task_id, change) VALUES (?, ?)', next_task.id, 'restarted')
  let success = t.commit()
  if !success
    throw s:AwiwiTaskError('could not activate task "%s"', a:title)
  endif
  let s:active_task = next_task
  return v:true
endfun "}}}


fun! awiwi#task#pause_active_task() abort "{{{
  return s:stop_active_task('paused')
endfun "}}}


fun! awiwi#task#finish_active_task() abort "{{{
  return s:stop_active_task('done')
endfun "}}}


fun! s:stop_active_task(state) abort "{{{
  let task = awiwi#task#get_active_task()
  if empty(task)
    return v:false
  endif
  call s:stop_timer()
  let t = awiwi#sql#start_transaction(s:db)
  call t.exec('UPDATE task SET state = ? WHERE id = ?', a:state, task.id)
  call t.exec('INSERT INTO task_log (task_id, change) VALUES (?, ?)', task.id, a:state)
  let success = t.commit()
  if success
    let s:active_task = {}
    return v:true
  else
    call s:start_timer()
    return v:false
  endif
endfun "}}}


fun! awiwi#task#add_task(title, date, stop_active_task, urgency, tags) abort "{{{
  let active_task = awiwi#task#get_active_task()
  let t = awiwi#sql#start_transaction(s:db)
  if !empty(active_task)
    call s:stop_timer()
    let new_state = a:stop_active_task ? 'done' : 'paused'
    if a:stop_active_task
      call t.exec(
            \ 'UPDATE task SET state = ?, updated = CURRENT_TIMESTAMP WHERE id = ?',
            \ new_state,
            \ active_task.id)
    else
      let q = 'UPDATE task SET state = ?, updated = CURRENT_TIMESTAMP, '
            \ .'end = CURRENT_TIMESTAMP WHERE id = ?'
      call t.exec(q, new_state, active_task.id)
    endif
    call t.exec(
          \ 'INSERT INTO task_log (task_id, change) VALUES (?, ?)',
          \ active_task.id,
          \ new_state)
  endif
  " check if task is already known
  let prev_tasks = awiwi#task#get_tasks_by_title(a:title)
  if empty(prev_tasks)
    let prev_task = {}
    let prev_task_id = v:null
  else
    let prev_task = prev_tasks[0]
    let prev_task_id = prev_task.id
  endif

  let urgency_id = awiwi#task#get_urgency(a:urgency).id
  let id = s:increment_and_get_id('task')
  call t.exec(
        \ 'INSERT INTO task (`id`, `title`, `date`, `backlink`, `urgency_id`) VALUES (?, ?, ?, ?, ?)',
        \ id, a:title, a:date, prev_task_id, urgency_id)
  call t.exec(
        \ 'INSERT INTO task_log (task_id, change) VALUES (?, ?)',
        \ id, 'created')

  if !empty(prev_task)
    let q = 'UPDATE task SET forwardlink = ?, updated = CURRENT_TIMESTAMP WHERE id = ?'
    call t.exec(q, id, prev_task.id)
    let tags = map(awiwi#task#get_task_tags_by_title(prev_task.title),
          \ {_, v -> v.name })
    call t.exec(
          \ 'INSERT INTO task_log (task_id, change) VALUES (?, ?)',
          \ prev_task.id, 'forwardlink_added')
    call t.exec(
          \ 'INSERT INTO task_log (task_id, change) VALUES (?, ?)',
          \ id, 'backlink_added')
  else
    let tags = []
  endif
  call extend(tags, map(a:tags, {_, v -> tolower(v)}))
  let tags = uniq(tags)

  if !empty(a:tags)
    for tag in a:tags
      call awiwi#task#add_tag(tolower(tag))
    endfor
  endif

  let tag_query = 'INSERT INTO task_tags (id, task_id, tag_id) VALUES (?, ?, ?)'
  for tag in tags
    let tag_id = awiwi#task#get_tag_id(tag)
    call t.exec(tag_query, s:increment_and_get_id('task_tags'), id, tag_id)
  endfor
  let success = t.commit()
  if !success
    " rollback all id changes
    call s:increment_and_get_id('task_tags', -len(tags))
    call s:increment_and_get_id('task', -1)
    echoerr 'could not create new task'
    call s:start_timer()
    return v:false
  endif
  let s:active_task = {'id': id, 'title': a:title, 'tags': tags, 'date': a:date, 'state': 'started'}
  call s:start_timer(v:true)
  return v:true
endfun "}}}
