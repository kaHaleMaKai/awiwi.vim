" if exists('g:autoloaded_awiwi_task')
"   finish
" endif
" let g:autoloaded_awiwi_task = v:true

let s:ids = {}
let s:tables = ['urgency', 'tag', 'task', 'task_tags', 'setting', 'task_log', 'project']
let s:duration_increment = get(g:, 'awiwi_task_update_frequency', 30) " FIXME set to 30
let s:timer = 0
let s:previous_timer_run =

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


let s:urgencies = {}
let s:Urgency = s:Entity.__prototype__('urgency', s:urgencies)
call extend(s:urgencies, awiwi#sql#select_as_dict('name', s:Urgency, s:db, 'SELECT id@n, name@s, value@n FROM urgency'))


let s:projects = {}
let s:Project = s:Entity.__prototype__('project', s:projects)

fun! s:Project.__new__(name, url) abort dict "{{{
  let p = copy(s:Project)
  let p.name = self.__validate__(a:name)
  let p.url = a:url
  call p.use_next_id()
  return p
endfun "}}}

fun! s:Project.create() abort dict "{{{
  let query = awiwi#util#get_resource('db', 'create-project.sql')
  let res = awiwi#sql#ddl(s:db, query, self.id, self.name, self.url)
  if !res
    throw s:AwiwiTaskError("could not create project %s", self.name)
  endif
  let s:projects[self.name] = self
endfun "}}}
call extend(s:projects, awiwi#sql#select_as_dict('name', s:Project, s:db, 'SELECT id@n, name@s, url@s FROM project'))


fun! awiwi#task#add_project(name, url) abort "{{{
  let p = s:Project.__new__(a:name, a:url)
  call p.create()
  return p
endfun "}}}


let s:tasks = {}
let s:Task = s:Entity.__prototype__('task', s:tasks)

fun! s:Task.__new__(title, date, state, urgency, project, issue_id, tags) abort dict "{{{
  let t = copy(s:Task)
  let t.title = a:title
  let t.date = a:date
  let t.state = a:state
  let t.urgency = a:urgency
  let t.project = a:project
  let t.issue_id = a:issue_id
  let t.tags = copy(a:tags)
  call t.use_next_id()
endfun "}}}

fun! awiwi#task#get_all_tasks() abort "{{{
  let query = awiwi#util#get_resource('db', 'get-all-tasks.sql')
  let tasks = awiwi#sql#select_as_dict('id', s:Task, s:db, query)
  for t in tasks
    let t.state = s:states[t.state]
    let t.urgency = s:urgencies[t.urgency]
    if t.project != v:null
      let t.project = s:projects[t.project]
    endif
    if t.backlink_id != v:null
      let t.backlink = projects[t.backlink_id]
    endif
    if t.forwardlink_id != v:null
      let t.forwardlink = projects[t.forwardlink_id]
    endif
endfun "}}}


fun! s:start_timer(...) abort "{{{
  if get(a:000, 0, v:false)
    let s:previous_timer_run = awiwi#util#get_epoch_seconds()
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
  let query = awiwi#util#get_resource('db', 'get-active-task.sql')
  let res = awiwi#sql#select(s:db, query)
  let s:active_task = empty(res) ? {} : res[0]
  if !empty(s:active_task)
    call s:start_timer()
  endif
  return s:active_task
endfun "}}}
" TODO: fix and reactivate this
" let s:active_task = awiwi#task#get_active_task()


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
  let now = awiwi#util#get_epoch_seconds()
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


fun! awiwi#task#get_tag_id(tag) abort "{{{
  return awiwi#task#get_all_tags()[a:tag]
endfun "}}}


fun! awiwi#task#get_task_tags_by_title(title) abort "{{{
  let query = awiwi#util#get_resource('db', 'get-task-tags-by-title.sql')
  return awiwi#sql#select(s:db, query, a:title)
endfun "}}}


fun! awiwi#task#is_screensaver() abort "{{{
  return split(system(s:screensaver_cmd))[1] == 'true'
endfun "}}}


fun! awiwi#task#get_tasks_by_title(title) abort "{{{
  let query = awiwi#util#get_resource('db', 'get-tasks-by-title.sql')
  return awiwi#sql#select(s:db, query, a:title)
endfun "}}}


fun! awiwi#task#get_most_recent_task_by_title(title) abort "{{{
  let query = awiwi#util#get_resource('db', 'get-most-recent-task-by-title.sql')
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
