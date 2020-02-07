" if exists('g:autoloaded_awiwi_task')
"   finish
" endif
" let g:autoloaded_awiwi_task = v:true

let s:db = path#join(awiwi#get_data_dir(), 'task.db')
call awiwi#sql#create_db(s:db, v:true)

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


fun! awiwi#task#get_urgencies() abort "{{{
  if exists('s:urgencies')
    return copy(s:urgencies)
  endif
  let res = awiwi#sql#select(s:db, 'SELECT id@n, name@s, value@n FROM urgency')
  let s:urgencies = {}
  for row in res
    let s:urgencies[row.name] = row
  endfor
  return copy(s:urgencies)
endfun "}}}


fun! awiwi#task#get_urgency(urgency) abort "{{{
  let urgencies = awiwi#task#get_urgencies()
  return urgencies[a:urgency]
endfun "}}}


fun! awiwi#task#get_all_tags() abort "{{{
  if exits('s:tags')
    return copy(s:tags)
  endif

  let res = awiwi#sql#select(s:db, 'SELECT id@n, name@s FROM tags')
  let s:tags = {}
  for tag in res
    let s:tags[tag.name] = tag.id
  endif
  return copy(s:tags)
endfun "}}}


fun! awiwi#task#add_tag(tag) abort "{{{
  let tags = awiwi#task#get_all_tags()
  if has_key(tags, a:tag)
    return v:true
  endif
  let res = awiwi#sql#insert(s:db, 'INSERT INTO tag (`name`) VALUES (?)', a:tag)
  if res
    let id = s:get_max_id('tag')
    let s:tags[a:tag] = id
  endif
endfun "}}}


fun! awiwi#task#get_tags_by_title(title) abort "{{{
  let query =
        \ 'SELECT tag.id@n, tag.name@s FROM tag JOIN task_tags '
        \ . 'ON (tag.id = task_tags.tag_id) '
        \ . 'WHERE task_tags.task_id = (SELECT Max(id) FROM task WHERE title = ?)'
  return awiwi#sql#select(s:db, query, a:title)
endfun "}}}


fun! awiwi#task#get_screensaver_state() abort "{{{
  return split(system(s:screensaver_cmd))[1] == 'true'
endfun "}}}


fun! awiwi#task#get_active_task() abort "{{{
  let col_def = [{'name': 'id', 'type': v:t_number}, 'title']
  let query =  "SELECT id@n, title@s FROM task WHERE state = 'started'"
  let res = awiwi#sql#select(s:db, query)
  if empty(res)
    return {}
  endif
  return res[0]
endfun "}}}


fun! awiwi#task#get_tasks_by_title(title) abort "{{{
  let query =  "SELECT id@n, title@s, date@s, state@s FROM task WHERE title = ? ORDER BY id"
  let res = awiwi#sql#select(s:db, query, a:title)
  return res
endfun "}}}


fun! s:get_max_id(table) abort "{{{
  let res = awiwi#sql#select(s:db, 'SELECT Max(id) as id@n FROM ?', {'value': a:table, 'type': 'table'})
  if empty(res)
    return v:null
  else
    return res[0].id
  endif
endfun "}}}


fun! awiwi#task#add_task(title, date, urgency, tags) abort "{{{
  let activate_task = awiwi#task#get_active_task()
  let queries = ['BEGIN']
  let params = []
  if !empty(activate_task)
    call add(queries, 'UPDATE task SET state = ? WHERE id = ?')
    call extend(params, ['paused', activate_task.id])
  endif
  " check if task is already known
  let prev_tasks = awiwi#task#get_tasks_by_title(a:title)
  if empty(prev_tasks)
    let prev_task = v:false
    let prev_task_id = v:null
  else
    let prev_task = prev_tasks[0]
    let prev_task_id = prev_task.id
  endif

  let new_query = 'INSERT INTO task (title, `date`, backlink, urgency_id) VALUES (?, ?, ?, ?)'
  call add(queries, new_query)
  let urgency_id = awiwi#task#get_urgency(a:urgency).id
  call extend(params, [a:title, a:date, prev_task_id, urgency_id])

  let max_task_id = s:get_max_id('task')
  let next_id = max_task_id ? max_task_id + 1 : 1

  if prev_task
    let next_id = s:get_max_id('task') + 1
    call add(queries, 'UPDATE task SET forwardlink = ? WHERE id = ?')
    call extend(params, [next_id, prev_task.id])
    let tags = map(awiwi#task#get_tags_by_title(prev_task.title),
          \ {_, v -> v.name })
  else
    let tags = []
  endif
  call extend(tags, map(a:tags, {_, v -> tolower(v)}))
  let tags = uniq(tags)

  if !empty(a:tags)
    for tag in a:tags
      awiwi#task#add_tag(tolower(tag))
    endfor
  endif

  let tag_query = 'INSERT INTO task_tags (tag_id, task_id) SELECT tag.id, ? FROM tag WHERE tag.name = ?'
  for tag in tags
    call add(queries, tag_query)
    call extend(params, [next_id, tag])
  endfor
  call add(queries, 'COMMIT')
  let query = join(queries, '; ')
  let args = [s:db, query]
  call extend(args, params)
  return call(funcref('awiwi#sql#insert'), args)
endfun "}}}
