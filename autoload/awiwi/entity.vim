let s:db = path#join(g:awiwi_home, 'task.db')

fun! s:AwiwiEntityError(msg, ...) abort "{{{
  if a:0
    let args = [a:msg]
    call extend(args, a:000)
    let msg = call('printf', args)
  else
    let msg = a:msg
  endif
  return 'AwiwiEntityError: ' . msg
endfun "}}}


fun! s:has_element(list, el) abort "{{{
  for el in a:list
    if el.id == a:el.id
      return v:true
    endif
  endfor
  return v:false
endfun "}}}


fun! s:unique(list, ...) abort "{{{
  let set = {}
  let li = []
  for el in a:list
    if !has_key(set, el.id)
      call add(li, el)
    endif
  endfor
  for list in a:000
    for el in list
      if !has_key(set, el.id)
        call add(li, el)
      endif
    endfor
  endfor
  return li
endfun "}}}


fun! s:is_null(obj) abort "{{{
  return type(a:obj) == type(v:null)
endfun "}}}


fun! s:id_or_null(el) abort "{{{
  if s:is_null(a:el)
    return v:null
  endif
  return a:el.id
endfun "}}}


fun! s:check_url(url) abort "{{{
  if s:is_null(a:url) || a:url == ''
    return v:null
  elseif type(a:url) == v:t_number || match(a:url, '^#\?[1-9][0-9]\{4,}$') > -1
    let url = type(a:url) == v:t_number ?
          \ string(a:url) : matchstr(a:url, '[0-9]\+')
    return printf('https://redmine.pmd5.org/issues/%s', url)
  elseif match(a:url, '^https://\(gitlab.pmd5.org\|github.com\)') > -1
    return a:url
  else
    echoerr s:AwiwiEntityError('got unknown project url: %s', a:url)
    return a:url
  endif
endfun "}}}


let s:Entity = {}

fun! s:Entity.get_next_id() abort dict "{{{
  let ids = self.get_all_ids()
  let len = len(ids)
  if !len || ids[-1] == len
    return len + 1
  endif

  let prev = 0
  for id in ids
    if id > prev + 1
      return prev + 1
    endif
    let prev = id
  endfor
endfun "}}}

fun! s:Entity.subclass(table) abort dict "{{{
  let e = copy(self)
  let e.__table__ = a:table
  let e.__ids__ = {}
  let e.__names__ = {}
  let e.__class__ = e
  let e.__class_fields__ = [
        \ '__ids__', '__names__', '__new__',
        \ 'subclass', 'get_all', 'get_by_id',
        \ 'get_by_name', '__class_fields__',
        \ 'slurp_from_db', 'get_all_names',
        \ 'get_all_ids', 'get_next_id',
        \ 'add_class_field'
        \ ]
  return e
endfun "}}}

fun! s:Entity.__new__() abort dict "{{{
  let e = copy(self)
  for attr in self.__class_fields__
    if has_key(e, attr)
      unlet e[attr]
    endif
  endfor
  let e.id = v:null
  return e
endfun "}}}


fun! s:Entity.add_class_field(field, ...) abort dict "{{{
  call add(self.__class_fields__, a:field)
  for field in a:000
    call add(self.__class_fields__, field)
  endfor
endfun "}}}


fun! s:Entity.__register__() abort dict "{{{
  if has_key(self.__class__.__names__, self.name)
    throw s:AwiwiEntityError('%s of name "%s" already exists',
          \ self.get_type(), self.name)
  endif
  if s:is_null(self.id)
    let self.id = self.__class__.get_next_id()
  endif
  if has_key(self.__class__.__ids__, self.id)
    let self.__old_id__ = self.id
    let self.id = v:null
    throw s:AwiwiEntityError('%s of id %d (name "%s") already exists',
          \ self.get_type(), self.id, self.name)
  endif
  let self.__class__.__ids__[self.id] = self
  let self.__class__.__names__[self.name] = self
endfun "}}}


fun! s:Entity.get_type() abort dict "{{{
  return self.__table__
endfun "}}}

fun! s:Entity.get_table() abort dict "{{{
  return self.__table__
endfun "}}}

fun! s:Entity.slurp_from_db(query, ...) abort dict "{{{
  for row in awiwi#sql#select(s:db, a:query)
    let e = self.__new__()
    call extend(e, row)
    call e.__register__()
  endfor
endfun "}}}

fun! s:Entity.get_all() abort dict "{{{
  return values(self.__ids__)
endfun "}}}

fun! s:Entity.get_all_names() abort dict "{{{
  return keys(self.__names__)
endfun "}}}

fun! s:Entity.get_all_ids() abort dict "{{{
  return sort(map(keys(self.__ids__), {_, v -> str2nr(v)}))
endfun "}}}


fun! s:Entity.get_by_id(id) abort dict "{{{
  return self.__ids__[a:id]
endfun "}}}

fun! s:Entity.get_by_name(name) abort dict "{{{
  return self.__names__[a:name]
endfun "}}}

fun! s:Entity.__delete__() abort dict "{{{
  if s:is_null(self.id)
    throw 'trying to delete entity that has not been created yet'
  endif
  let res = awiwi#sql#ddl(
        \ s:db, 'DELETE FROM ? WHERE id = ?',
        \ {'type': 'table', 'value': self.__table__}, self.id)
  if !res
    throw s:AwiwiEntityError('could not delete %s %s', self.get_type(), self.name)
  endif
  unlet self.__class__.__ids__[self.id]
  unlet self.__class__.__names__[self.name]
  let self.__old_id__ = self.id
  let self.id = v:null
endfun "}}}
" this can be overridden by subclasses
let s:Entity.delete = s:Entity.__delete__


let awiwi#entity#State = s:Entity.subclass('task_state')
let awiwi#entity#TaskLogState = s:Entity.subclass('task_state')
let awiwi#entity#Tag = s:Entity.subclass('tag')
let awiwi#entity#Urgency = s:Entity.subclass('urgency')
let awiwi#entity#Task = s:Entity.subclass('task')
call awiwi#entity#Task.add_class_field(
      \ 'get_active_task', 'has_active_task', '__active_task__')
let awiwi#entity#Task.__active_task__ = v:null

let s:State = awiwi#entity#State
let s:Tag = awiwi#entity#Tag
let s:Urgency = awiwi#entity#Urgency
let s:Task = awiwi#entity#Task
let s:TaskLogState = awiwi#entity#TaskLogState

fun! awiwi#entity#Tag.new(name) abort dict "{{{
  let t = self.__new__()
  let t.name = a:name
  call t.__register__()
  return t
endfun "}}}

fun! awiwi#entity#Tag.persist() abort dict "{{{
  let query = awiwi#util#get_resource('db', 'create-tag.sql')
  let res = awiwi#sql#ddl(s:db, query, self.id, self.name)
  if !res
    throw s:AwiwiEntityError('could not create tag %s', self.name)
  endif
  return self
endfun "}}}

fun! awiwi#entity#Tag.delete() abort dict "{{{
  let rows = awiwi#sql#select(s:db,
        \ 'SELECT task_id AS id@n FROM task_tags WHERE tag_id = ?', self.id)
  let t = awiwi#sql#start_transaction(s:db)
  call t.exec('DELETE FROM project_tags WHERE tag_id = ?', self.id)
  call t.exec('DELETE FROM task_tags WHERE tag_id = ?', self.id)
  let res = t.commit()
  if !res
    throw s:AwiwiEntityError('could not delete tag %s', self.name)
  endif
  for row in rows
    let tags = awiwi#entity#Task.__ids__[row.id].tags
    for i in range(len(tags))
      if tags[i].id == self.id
        unlet tags[i]
        break
      endif
    endfor
  endfor
  return self.__delete__()
endfun "}}}


fun! awiwi#entity#Urgency.new(name, value) abort dict "{{{
  let t = self.__new__()
  let t.name = a:name
  for v in values(self.__class__.__ids__)
    if v.value == a:value
      throw s:AwiwiEntityError('urgency value %d already used in %s', a:value, v.name)
    endif
  endfor
  let t.value = a:value
  call t.__register__()
  return t
endfun "}}}

fun! awiwi#entity#Urgency.persist() abort dict "{{{
  let query = awiwi#util#get_resource('db', 'create-urgency.sql')
  let res = awiwi#sql#ddl(s:db, query, self.id, self.name, self.value)
  if !res
    throw s:AwiwiUrgencyError('could not create urgency %s', self.name)
  endif
  return self
endfun "}}}

let awiwi#entity#Project = s:Entity.subclass('project')

fun! awiwi#entity#Project.new(name, url, tags) abort dict "{{{
  let t = self.__new__()
  let t.name = a:name
  let t.url = s:check_url(a:url)
  let t.tags = a:tags
  call t.__register__()
  return t
endfun "}}}


fun! awiwi#entity#Project.persist() abort dict "{{{
  let query = awiwi#util#get_resource('db', 'create-project.sql')
  let t = awiwi#sql#start_transaction(s:db)
  call t.exec(query, self.id, self.name, self.url)
  for tag in self.tags
    call t.exec('INSERT INTO project_tags (project_id, tag_id) VALUES (?, ?)',
          \ self.id, tag.id)
  endfor
  let res = t.commit()
  if !res
    call self.delete()
    throw s:AwiwiEntityError('could not create project %s', self.name)
  endif
  return self
endfun "}}}


fun! awiwi#entity#Project.delete() abort dict "{{{
  let rows = awiwi#sql#select(s:db,
        \ 'SELECT id@n FROM task WHERE project_id = ?', self.id)
  let t = awiwi#sql#start_transaction(s:db)
  call t.exec('DELETE FROM project_tags WHERE project_id = ?', self.id)
  call t.exec('UPDATE task SET project_id = NULL WHERE project_id = ?', self.id)
  let res = t.commit()
  if !res
    throw s:AwiwiEntityError('could not delete project %s', self.name)
  endif
  for row in rows
    let awiwi#entity#Task.__ids__[row.id].project = v:null
  endfor
  return self.__delete__()
endfun "}}}


fun! awiwi#entity#Project.add_tag(tag) abort dict "{{{
  let has_el = s:has_element(self.tags, a:tag)
  if has_el
    return v:false
  endif
  let res = awiwi#sql#ddl(s:db,
        \ 'INSERT INTO project_tags (project_id, tag_id) VALUES (?, ?)',
        \ self.id, a:tag.id)
  if !res
    throw s:AwiwiEntityError('could not add tag %s to project %s', a:tag.name, self.name)
  endif
  call add(self.tags, a:tag)
  return v:true
endfun "}}}


fun! awiwi#entity#Project.set_url(url) abort dict "{{{
  let url = s:check_url(a:url)
  if self.url == url
    return v:false
  endif
  let res = awiwi#sql#ddl(s:db,
        \ 'UPDATE project SET url = ? WHERE id = ?',
        \ url, self.id)
  if !res
    throw s:AwiwiEntityError('could not set url to "%s" for project %s', url, self.name)
  endif
  return v:true
endfun "}}}


fun! s:create_db(path) abort "{{{
  let parent = fnamemodify(a:path, ':h')
  if filewritable(parent) != 2 && !mkdir(parent, 'p')
    echoerr printf('could not create parent dir for sqlite db: "%s"', parent)
    return v:false
  endif
  if filewritable(a:path)
    return v:true
  endif
  let init_queries = awiwi#util#get_resource('db', 'init.sql')
  let success = awiwi#sql#ddl(a:path, init_queries)
  if !success
    call delete(a:path)
    call delete(a:path . '-journal')
    echoerr printf('could not init sqlite db "%s"', a:path)
    return v:false
  endif
  return v:true
endfun "}}}


" scoping issue: awiwi#entity#State is unknown inside of
" function awiwi#entity#init for some reason

fun! awiwi#entity#init() abort "{{{
  call s:create_db(s:db)
  call s:State.slurp_from_db('SELECT id@n, name@s FROM task_state')
  call s:Tag.slurp_from_db('SELECT id@n, name@s FROM tag')
  call s:Urgency.slurp_from_db('SELECT id@n, name@s, value@n FROM urgency')
  call s:TaskLogState.slurp_from_db('SELECT id@n, name@s FROM task_log_state')
endfun "}}}

fun! awiwi#entity#init_test_data() abort "{{{
  call awiwi#util#empty_resources_cache()
  let s:db = '/tmp/awiwi-test.db'
  if filewritable(s:db) == 1
    call delete(s:db)
  endif
  call awiwi#entity#init()
endfun "}}}


fun! awiwi#entity#Task.get_active_task() abort dict "{{{
  return self.__active_task__
endfun "}}}


fun! awiwi#entity#Task.has_active_task() abort dict "{{{
  return !s:is_null(self.get_active_task())
endfun "}}}


fun! awiwi#entity#Task.set_active_task(task) abort dict "{{{
  if self.has_active_task()
    throw s:AwiwiEntityError('cannot activate task %s. %s already started',
          \ a:task.name, self.get_active_task().name)
  endif
  let self.__active_task__ = a:task
endfun "}}}


fun! awiwi#entity#Task.deactive_active_task() abort dict "{{{
  let self.__active_task__ = v:null
endfun "}}}


fun! awiwi#entity#Task.new(
      \ title, date, backlink, project, issue,
      \ urgency, tags) abort dict "{{{
  if self.has_active_task()
    throw s:AwiwiEntityError('cannot create task. "%s" is already started',
          \ self.get_active_task().name)
  endif
  let t = self.__new__()
  let t.title = a:title
  let t.state = s:State.get_by_name('started')
  let t.date = a:date
  " use this for lookups
  let t.name = printf('%s:%s', t.date, t.title)
  let t.start = awiwi#util#get_iso_timestamp()
  let t.backlink = a:backlink
  let t.forwardlink = v:null
  let t.project = a:project
  let t.issue_link = s:check_url(a:issue)
  let t.urgency = a:urgency
  let t.duration = 0
  let backlink_tags = s:is_null(a:backlink) ? [] : a:backlink.tags
  let t.tags = s:unique(t.project.tags, backlink_tags, a:tags)
  call t.__register__()
  call self.set_active_task(t)
  return t
endfun "}}}


fun! awiwi#entity#Task.persist() abort dict "{{{
  let query = awiwi#util#get_resource('db', 'create-task.sql')
  let t = awiwi#sql#start_transaction(s:db)
  call t.exec(query,
        \ self.id, self.title, self.state.id, self.date, self.start,
        \ s:id_or_null(self.backlink), s:id_or_null(self.project),
        \ self.issue_link, self.urgency.id, self.id)
  for tag in self.tags
    call t.exec('INSERT INTO task_tags (task_id, tag_id) VALUES (?, ?)',
          \ self.id, tag.id)
  endfor
  if !s:is_null(self.backlink)
    call t.exec('UPDATE task SET forwardlink = ? WHERE id = ?',
          \ self.id, self.backlink.id)
  endif
  let res = t.commit()
  if res
    if !s:is_null(self.backlink)
      let self.backlink['forwardlink'] = self
    endif
    return self
  endif
  call self.delete()
  throw s:AwiwiEntityError('could not create task "%s"', self.title)
endfun "}}}


fun! awiwi#entity#Task.delete() abort dict "{{{
  let t = awiwi#sql#start_transaction(s:db)
  call t.exec('DELETE FROM task_tags WHERE task_id = ?', self.id)
  call t.exec('DELETE FROM task_log WHERE task_id = ?', self.id)
  if !s:is_null(self.backlink)
    call t.exec('UPDATE task SET forwardlink = NULL WHERE id = ?',
          \ self.backlink.id)
  endif
  let res = t.commit()
  if !res
    throw s:AwiwiEntityError('could not delete task %s', self.title)
  endif
  if !s:is_null(self.backlink)
    let self.__class__.__ids__[self.backlink.id].forwardlink = v:null
  endif
  return self.__delete__()
endfun "}}}


fun! awiwi#entity#Task.set_state(state) abort dict "{{{
  if self.state.id == a:state.id
    return v:false
  endif
  if a:state.name == 'started'
    call self.__class__.set_active_task(self)
    let log_state = s:TaskLogState.get_by_name('restarted')
  else
    call self.__class__.deactive_active_task()
    let log_state = s:TaskLogState.get_by_name(a:state.name)
  endif
  let t = awiwi#sql#start_transaction(s:db)
  call t.exec(
        \ 'UPDATE task SET task_state_id = ? WHERE id = ?',
        \ a:state.id, self.id)
  call t.exec(
        \ 'INSERT INTO task_log (task_id, state_id) VALUES (?, ?)', self.id, log_state.id)
  let res = t.commit()
  if !res
    throw s:AwiwiEntityError('could not change state for task %s to %s',
          \ self.title, a:state.name)
  endif
  let self.state = a:state
  return v:true
endfun "}}}


fun! awiwi#entity#Task.pause(...) abort dict "{{{
  return self.set_state(s:State.get_by_name('paused'))
endfun "}}}


fun! awiwi#entity#Task.done() abort dict "{{{
  return self.set_state(s:State.get_by_name('done'))
endfun "}}}


fun! awiwi#entity#Task.restart(...) abort dict "{{{
  if get(a:000, 0, v:false) &&
        \ self.__class__.has_active_task() &&
        \ self.__class__.get_active_task().id != self.id
    call self.__class__.get_active_task().set_state(s:State.get_by_name('paused'))
  endif
  return self.set_state(s:State.get_by_name('started'))
endfun "}}}


fun! awiwi#entity#Task.set_urgency(urgency) abort dict "{{{
  if self.urgency.id == a:urgency.id
    return v:false
  endif
  let log_state = s:TaskLogState.get_by_name('urgency_changed')
  let t = awiwi#sql#start_transaction(s:db)
  call t.exec(
        \ 'UPDATE task SET urgency_id = ? WHERE id = ?',
        \ a:urgency.id, self.id)
  call t.exec(
        \ 'INSERT INTO task_log (task_id, state_id) VALUES (?, ?)', self.id, log_state.id)
  let res = t.commit()
  if !res
    throw s:AwiwiEntityError('could not change urgency for task %s to %s',
          \ self.title, a:urgency.name)
  endif
  let self.urgency = a:urgency
  return v:true
endfun "}}}
