" if exists('g:autoloaded_awiwi_dao')
"   finish
" endif
" let g:autoloaded_awiwi_dao = v:true

let s:db = path#join(g:awiwi_home, 'task.db')

fun! s:AwiwiDaoError(msg, ...) abort "{{{
  if a:0
    let args = [a:msg]
    call extend(args, a:000)
    let msg = call('printf', args)
  else
    let msg = a:msg
  endif
  return 'AwiwiDaoError: ' . msg
endfun "}}}


fun! awiwi#dao#check_url(url, ...) abort "{{{
  if awiwi#util#is_null(a:url) || a:url == ''
    return v:null
  elseif (type(a:url) == v:t_number && a:url > 10000) || match(a:url, '^#\?[1-9][0-9]\{4,}$') > -1
    let url = type(a:url) == v:t_number ?
          \ string(a:url) : matchstr(a:url, '[0-9]\+')
    return printf('https://redmine.pmd5.org/issues/%s', url)
  elseif match(a:url, '^https://\(gitlab.pmd5.org\|github.com\|redmine.pmd5.org\)') > -1
    return a:url
  else
    if a:0 && a:1 == v:true
      return v:null
    endif
    echoerr s:AwiwiDaoError('got unknown project url: %s', a:url)
    return a:url
  endif
endfun "}}}


let s:Entity = {
      \ 'name_pattern': ''
      \ }

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

fun! s:Entity.subclass(table, ...) abort dict "{{{
  let table = a:table
  let e = copy(self)
  let e.__table__ = table
  let e.__ids__ = {}
  let e.__names__ = {}
  let e.__class__ = e
  if a:0
    let e.class_name = a:1
  else
    let e.class_name = toupper(table[0]) . substitute(table[1:], '\(_\+\)\([a-z]\)', '\u\2', 'g')
  endif
  let e.__class_fields__ = [
        \ '__ids__', '__names__', '__new__',
        \ 'subclass', 'get_all', 'get_by_id',
        \ 'get_by_name', '__class_fields__',
        \ 'slurp_from_db', 'get_all_names',
        \ 'get_all_ids', 'get_next_id',
        \ 'add_class_field', 'id_exists',
        \ 'name_exists', 'validate_identifier'
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
  call self.__class__.validate_identifier(self.name)
  if self.__class__.name_exists(self.name)
    throw s:AwiwiDaoError('%s of name "%s" already exists',
          \ self.get_type(), self.name)
  endif
  if awiwi#util#is_null(self.id)
    let self.id = self.__class__.get_next_id()
  endif
  if self.__class__.id_exists(self.id)
    let self.__old_id__ = self.id
    let self.id = v:null
    throw s:AwiwiDaoError('%s of id %d (name "%s") already exists',
          \ self.get_type(), self.id, self.name)
  endif
  let self.__class__.__ids__[self.id] = self
  let self.__class__.__names__[self.name] = self
  unlet self.__register__
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
  if awiwi#util#is_null(self.id)
    throw 'trying to delete dao that has not been created yet'
  endif
  let res = awiwi#sql#ddl(
        \ s:db, 'DELETE FROM ? WHERE id = ?',
        \ {'type': 'table', 'value': self.__table__}, self.id)
  if !res
    throw s:AwiwiDaoError('could not delete %s %s', self.get_type(), self.name)
  endif
  unlet self.__class__.__ids__[self.id]
  unlet self.__class__.__names__[self.name]
  let self.__old_id__ = self.id
  let self.id = v:null
endfun "}}}
" this can be overridden by subclasses
let s:Entity.delete = s:Entity.__delete__


fun! s:Entity.update_attribute(attr, value, ...) abort dict "{{{
  let use_transaction = a:0
  let args = []
  if !use_transaction
    call add(args, s:db)
  endif

  call extend(args, [
        \ 'UPDATE ? SET ? = ? WHERE id = ?',
        \ {'type': 'table', 'value': self.__table__},
        \ {'type': 'table', 'value': a:attr},
        \ a:value,
        \ self.id
        \ ])
  if use_transaction
    let t = a:000[0]
    call call(t.exec, args)
    return v:true
  endif

  let res = call('awiwi#sql#ddl', args)
  if !res
    throw s:AwiwiDaoError('could not update %s.%s to value "%s" for id=%d',
          \ self.__table__, a:attr, a:value, self.id)
  endif
endfun "}}}


fun! s:Entity.name_exists(name) abort dict "{{{
  return has_key(self.__names__, a:name)
endfun "}}}


fun! s:Entity.id_exists(id) abort dict "{{{
  return has_key(self.__ids__, a:id)
endfun "}}}

fun! s:Entity.validate_identifier(name) abort "{{{
  if trim(a:name) == ''
    throw s:AwiwiDaoError('got empty identifier')
  endif
  if self.name_pattern != '' && match(a:name, self.name_pattern) == -1
    throw s:AwiwiDaoError('name "%s" includes characters out of range %s', a:name, self.name_pattern)
  endif
endfun "}}}


let s:TitleBasedEntity = s:Entity.subclass(v:null, 'TitleBasedEntity')
let s:TitleBasedEntity.date_pattern = '[0-9]\{4}-[0-9]\{2}-[0-9]\{2}'
let s:TitleBasedEntity.title_pattern = '[a-zA-Z].\+'
let s:TitleBasedEntity.title_pattern = printf('^%s:%s', s:TitleBasedEntity.date_pattern, s:TitleBasedEntity.title_pattern)

fun! s:TitleBasedEntity.set_title(title) abort dict "{{{
  let name = printf('%s:%s', t.date, t.title)
  if self.__class__.name_exists(name)
    throw s:AwiwiDaoError('cannot rename %s "%s:%s". name "%s" already in use', self.__table__, self.name, name)
  endif
  call self.__class__.validate_identifier(a:name)
  call self.update_attribute('title', a:title)
  let self.title = a:title
endfun "}}}

fun! s:TitleBasedEntity.join_date_and_name(date, name) abort dict "{{{
  return printf('%s:%s', a:date, a:name)
endfun "}}}

fun! s:TitleBasedEntity.date_and_name_exist(date, name) abort "{{{
  return self.name_exists(self.join_date_and_name(a:date, a:name))
endfun "}}}

call s:TitleBasedEntity.add_class_field(
      \ 'join_date_and_name',
      \ 'date_and_name_exist'
      \ )


let g:awiwi#dao#TaskState = s:Entity.subclass('task_state')
let g:awiwi#dao#TaskLogState = s:Entity.subclass('task_log_state')
let g:awiwi#dao#Tag = s:Entity.subclass('tag')
let g:awiwi#dao#Urgency = s:Entity.subclass('urgency')
call g:awiwi#dao#Urgency.add_class_field('value_exists')
let g:awiwi#dao#ChecklistEntry = s:TitleBasedEntity.subclass('checklist', 'ChecklistEntry')
let g:awiwi#dao#Project = s:Entity.subclass('project')
let g:awiwi#dao#Task = s:TitleBasedEntity.subclass('task')
call g:awiwi#dao#Task.add_class_field(
      \ 'get_active_task', 'has_active_task', '__active_task__')
let g:awiwi#dao#Task.__active_task__ = v:null

let g:awiwi#dao#Tag.name_pattern = '^[-a-zA-Z0-9_]\+$'
let g:awiwi#dao#Urgency.name_pattern = '^[a-z]\+$'

fun! g:awiwi#dao#Tag.new(name) abort dict "{{{
  let t = self.__new__()
  let t.name = a:name
  call t.__register__()
  return t
endfun "}}}


fun! g:awiwi#dao#Tag.persist() abort dict "{{{
  let query = awiwi#util#get_resource('db', 'create-tag.sql')
  let res = awiwi#sql#ddl(s:db, query, self.id, self.name)
  if !res
    throw s:AwiwiDaoError('could not create tag %s', self.name)
  endif
  return self
endfun "}}}

fun! g:awiwi#dao#Tag.delete() abort dict "{{{
  let rows = awiwi#sql#select(s:db,
        \ 'SELECT task_id AS id@n FROM task_tags WHERE tag_id = ?', self.id)
  let t = awiwi#sql#start_transaction(s:db)
  call t.exec('DELETE FROM project_tags WHERE tag_id = ?', self.id)
  call t.exec('DELETE FROM task_tags WHERE tag_id = ?', self.id)
  let res = t.commit()
  if !res
    throw s:AwiwiDaoError('could not delete tag %s', self.name)
  endif
  for row in rows
    let tags = g:awiwi#dao#Task.__ids__[row.id].tags
    for i in range(len(tags))
      if tags[i].id == self.id
        unlet tags[i]
        break
      endif
    endfor
  endfor
  return self.__delete__()
endfun "}}}


fun! g:awiwi#dao#Urgency.new(name, value) abort dict "{{{
  let t = self.__new__()
  let t.name = a:name
  if a:value < -1 || a:value > 10
      throw s:AwiwiDaoError('urgency value %d out of range [0, 10]', a:value)
  endif
  for v in values(self.__class__.__ids__)
    if v.value == a:value
      throw s:AwiwiDaoError('urgency value %d already used in %s', a:value, v.name)
    endif
  endfor
  let t.value = a:value
  call t.__register__()
  return t
endfun "}}}

fun! g:awiwi#dao#Urgency.persist() abort dict "{{{
  let query = awiwi#util#get_resource('db', 'create-urgency.sql')
  let res = awiwi#sql#ddl(s:db, query, self.id, self.name, self.value)
  if !res
    throw s:AwiwiUrgencyError('could not create urgency %s', self.name)
  endif
  return self
endfun "}}}

fun! g:awiwi#dao#Urgency.value_exists(value) abort dict "{{{
  let values = map(copy(self.get_all()), {_, v -> v.value })
  for val in values
    if val == a:value
      return v:true
    endif
  endfor
  return v:false
endfun "}}}


fun! g:awiwi#dao#Project.new(name, url, tags) abort dict "{{{
  let t = self.__new__()
  if len(trim(a:name)) == 0
    throw s:AwiwiDaoError('project name is empty')
  endif
  let t.name = a:name
  let t.url = awiwi#dao#check_url(a:url)
  let t.tags = a:tags
  call t.__register__()
  return t
endfun "}}}


fun! g:awiwi#dao#Project.persist() abort dict "{{{
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
    throw s:AwiwiDaoError('could not create project %s', self.name)
  endif
  return self
endfun "}}}


fun! g:awiwi#dao#Project.delete() abort dict "{{{
  let rows = awiwi#sql#select(s:db,
        \ 'SELECT id@n FROM task WHERE project_id = ?', self.id)
  let t = awiwi#sql#start_transaction(s:db)
  call t.exec('DELETE FROM project_tags WHERE project_id = ?', self.id)
  call self.update_attribute(project_id, v:null, t)
  let res = t.commit()
  if !res
    throw s:AwiwiDaoError('could not delete project %s', self.name)
  endif
  for row in rows
    let g:awiwi#dao#Task.__ids__[row.id].project = v:null
  endfor
  return self.__delete__()
endfun "}}}


fun! g:awiwi#dao#Project.add_tag(tag) abort dict "{{{
  let has_el = awiwi#util#has_element(self.tags, a:tag)
  if has_el
    return v:false
  endif
  let res = awiwi#sql#ddl(s:db,
        \ 'INSERT INTO project_tags (project_id, tag_id) VALUES (?, ?)',
        \ self.id, a:tag.id)
  if !res
    throw s:AwiwiDaoError('could not add tag %s to project %s', a:tag.name, self.name)
  endif
  call add(self.tags, a:tag)
  return v:true
endfun "}}}


fun! g:awiwi#dao#Project.set_url(url) abort dict "{{{
  let url = awiwi#dao#check_url(a:url)
  if self.url == url
    return v:false
  endif
  try
    call self.update_attribute('url', url)
  catch /AwiwiDaoError/
    throw s:AwiwiDaoError('could not set url to "%s" for project %s', url, self.name)
  endtry
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


fun! awiwi#dao#init() abort "{{{
  call s:create_db(s:db)
  call g:awiwi#dao#TaskState.slurp_from_db('SELECT id@n, name@s FROM task_state')
  call g:awiwi#dao#Tag.slurp_from_db('SELECT id@n, name@s FROM tag')
  call g:awiwi#dao#Urgency.slurp_from_db('SELECT id@n, name@s, value@n FROM urgency')
  call g:awiwi#dao#TaskLogState.slurp_from_db('SELECT id@n, name@s FROM task_log_state')
  call g:awiwi#dao#ChecklistEntry.slurp_from_db('SELECT id@n, file@s, title@s, checked@b, created@s FROM checklist')
endfun "}}}


fun! awiwi#dao#init_test_data(file) abort "{{{
  call awiwi#util#empty_resources_cache()
  let s:db = a:file
  if filewritable(s:db) == 1
    call delete(s:db)
  endif
  call awiwi#dao#init()
endfun "}}}


fun! g:awiwi#dao#Task.get_active_task() abort dict "{{{
  return self.__active_task__
endfun "}}}


fun! g:awiwi#dao#Task.has_active_task() abort dict "{{{
  return !awiwi#util#is_null(self.get_active_task())
endfun "}}}


fun! g:awiwi#dao#Task.set_active_task(task) abort dict "{{{
  if self.has_active_task()
    throw s:AwiwiDaoError('cannot activate task %s. %s already started',
          \ a:task.name, self.get_active_task().name)
  endif
  let self.__active_task__ = a:task
endfun "}}}


fun! g:awiwi#dao#Task.deactive_active_task() abort dict "{{{
  let self.__active_task__ = v:null
endfun "}}}


fun! g:awiwi#dao#Task.new(
      \ title, date, backlink, project, issue,
      \ urgency, tags) abort dict "{{{
  if self.has_active_task()
    throw s:AwiwiDaoError('cannot create task. "%s" is already started',
          \ self.get_active_task().name)
  endif
  let t = self.__new__()
  let t.title = a:title
  let t.state = g:awiwi#dao#TaskState.get_by_name('started')
  let t.date = a:date
  " use this for lookups
  let t.name = self.join_date_and_name(t.date, t.title)
  let t.start = awiwi#util#get_iso_timestamp()
  let t.backlink = a:backlink
  let t.forwardlink = v:null
  let t.project = a:project
  let t.issue_link = awiwi#dao#check_url(a:issue)
  let t.urgency = a:urgency
  let t.duration = 0
  let backlink_tags = awiwi#util#is_null(a:backlink) ? [] : a:backlink.tags
  let project_tags = awiwi#util#is_null(a:project) ? [] : a:project.tags
  let t.tags = awiwi#util#unique(project_tags, backlink_tags, a:tags)
  call t.__register__()
  call self.set_active_task(t)
  return t
endfun "}}}


fun! g:awiwi#dao#Task.persist() abort dict "{{{
  let query = awiwi#util#get_resource('db', 'create-task.sql')
  let t = awiwi#sql#start_transaction(s:db)
  call t.exec(query,
        \ self.id, self.title, self.state.id, self.date, self.start,
        \ awiwi#util#id_or_null(self.backlink), awiwi#util#id_or_null(self.project),
        \ self.issue_link, self.urgency.id, self.id)
  for tag in self.tags
    call t.exec('INSERT INTO task_tags (task_id, tag_id) VALUES (?, ?)',
          \ self.id, tag.id)
  endfor
  if !awiwi#util#is_null(self.backlink)
    call self.update_attribute('forwardlink', self.backlink.id, t)
  endif
  let res = t.commit()
  if res
    if !awiwi#util#is_null(self.backlink)
      let self.backlink['forwardlink'] = self
    endif
    return self
  endif
  call self.delete()
  throw s:AwiwiDaoError('could not create task "%s"', self.title)
endfun "}}}


fun! g:awiwi#dao#Task.delete() abort dict "{{{
  let t = awiwi#sql#start_transaction(s:db)
  call t.exec('DELETE FROM task_tags WHERE task_id = ?', self.id)
  call t.exec('DELETE FROM task_log WHERE task_id = ?', self.id)
  if !awiwi#util#is_null(self.backlink)
    call t.exec('UPDATE task SET forwardlink = NULL WHERE id = ?',
          \ self.backlink.id)
  endif
  let res = t.commit()
  if !res
    throw s:AwiwiDaoError('could not delete task %s', self.title)
  endif
  if !awiwi#util#is_null(self.backlink)
    let self.__class__.__ids__[self.backlink.id].forwardlink = v:null
  endif
  return self.__delete__()
endfun "}}}


fun! g:awiwi#dao#Task.set_state(state) abort dict "{{{
  if self.state.id == a:state.id
    return v:false
  endif
  if a:state.name == 'started'
    call self.__class__.set_active_task(self)
    let log_state = g:awiwi#dao#:TaskLogState.get_by_name('restarted')
  else
    call self.__class__.deactive_active_task()
    let log_state = g:awiwi#dao#:TaskLogState.get_by_name(a:state.name)
  endif
  let t = awiwi#sql#start_transaction(s:db)
  call self.update_attribute('task_state_id', a:state.id, t)
  call t.exec(
        \ 'INSERT INTO task_log (task_id, state_id) VALUES (?, ?)', self.id, log_state.id)
  let res = t.commit()
  if !res
    throw s:AwiwiDaoError('could not change state for task %s to %s',
          \ self.title, a:state.name)
  endif
  let self.state = a:state
  return v:true
endfun "}}}


fun! g:awiwi#dao#Task.pause(...) abort dict "{{{
  return self.set_state(g:awiwi#dao#:TaskState.get_by_name('paused'))
endfun "}}}


fun! g:awiwi#dao#Task.done() abort dict "{{{
  return self.set_state(g:awiwi#dao#:TaskState.get_by_name('done'))
endfun "}}}


fun! g:awiwi#dao#Task.restart(...) abort dict "{{{
  if get(a:000, 0, v:false) &&
        \ self.__class__.has_active_task() &&
        \ self.__class__.get_active_task().id != self.id
    call self.__class__.get_active_task().set_state(g:awiwi#dao#:TaskState.get_by_name('paused'))
  endif
  return self.set_state(g:awiwi#dao#:TaskState.get_by_name('started'))
endfun "}}}


fun! g:awiwi#dao#Task.set_urgency(urgency) abort dict "{{{
  if self.urgency.id == a:urgency.id
    return v:false
  endif
  let log_state = g:awiwi#dao#:TaskLogState.get_by_name('urgency_changed')
  let t = awiwi#sql#start_transaction(s:db)
  call self.update_attribute('urgency_id', a:urgency.id, t)
  call t.exec(
        \ 'INSERT INTO task_log (task_id, state_id) VALUES (?, ?)', self.id, log_state.id)
  let res = t.commit()
  if !res
    throw s:AwiwiDaoError('could not change urgency for task %s to %s',
          \ self.title, a:urgency.name)
  endif
  let self.urgency = a:urgency
  return v:true
endfun "}}}


fun! g:awiwi#dao#ChecklistEntry.new(file, title) abort dict "{{{
  let t = self.__new__()
  let t.file = a:file
  let t.title = a:title
  let t.checked = v:false
  let t.created = awiwi#util#get_iso_timestamp()
  let t.name = self.join_date_and_name(t.file, t.title)
  call t.__register__()
  return t
endfun "}}}


fun! g:awiwi#dao#ChecklistEntry.persist() abort dict "{{{
  let query = awiwi#util#get_resource('db', 'create-checklist.sql')
  let res = awiwi#sql#ddl(s:db, query, self.id, self.file, self.title, self.created)
  if !res
    call self.delete()
    throw s:AwiwiDaoError('could not create checklist entry %s', self.title)
  endif
  return self
endfun "}}}


fun! g:awiwi#dao#ChecklistEntry.set_checked(val) abort dict "{{{
  if self.checked == a:val
    let state = self.checked ? 'checked' : 'unchecked'
    throw s:AwiwiDaoError('checklist entry "%s" already %s', self.title, state)
  endif
  call self.update_attribute('checked', a:val)
  let self.checked = a:val
endfun "}}}


fun! g:awiwi#dao#ChecklistEntry.check() abort dict "{{{
  call self.set_checked(v:true)
endfun "}}}


fun! g:awiwi#dao#ChecklistEntry.uncheck() abort dict "{{{
  call self.set_checked(v:false)
endfun "}}}
