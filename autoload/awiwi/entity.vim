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
  if a:url == v:null || a:url == ''
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
  let e.class_fields = [
        \ '__ids__', '__names__', '__new__',
        \ 'subclass', 'get_all', 'get_by_id',
        \ 'get_by_name', 'class_fields',
        \ 'slurp_from_db', 'get_all_names',
        \ 'get_all_ids', 'get_next_id'
        \ ]
  return e
endfun "}}}

fun! s:Entity.__new__() abort dict "{{{
  let e = copy(self)
  for attr in self.class_fields
    unlet e[attr]
  endfor
  let e.id = v:null
  return e
endfun "}}}


fun! s:Entity.__register__() abort dict "{{{
  if has_key(self.__class__.__names__, self.name)
    throw s:AwiwiEntityError('%s of name "%s" already exists',
          \ self.get_type(), self.name)
  endif
  if self.id == v:null
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
  if self.id == v:null
    echoerr 'trying to delete entity that has not been created yet'
    return
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
let awiwi#entity#Tag = s:Entity.subclass('tag')
let awiwi#entity#Urgency = s:Entity.subclass('urgency')
let awiwi#entity#Task = s:Entity.subclass('task')

let s:_state = awiwi#entity#State
let s:_tag = awiwi#entity#Tag
let s:_urgency = awiwi#entity#Urgency
let s:_task = awiwi#entity#Task

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
  call s:_state.slurp_from_db('SELECT id@n, name@s FROM task_state')
  call s:_tag.slurp_from_db('SELECT id@n, name@s FROM tag')
  call s:_urgency.slurp_from_db('SELECT id@n, name@s, value@n FROM urgency')
endfun "}}}

fun! awiwi#entity#init_test_data() abort "{{{
  call awiwi#util#empty_resources_cache()
  let s:db = '/tmp/awiwi-test.db'
  if filewritable(s:db) == 1
    call delete(s:db)
  endif
  call awiwi#entity#init()
endfun "}}}


fun! awiwi#entity#Task.new(
      \ title, date, backlink, project, issue,
      \ urgency, tags) abort dict "{{{
  let t = self.__new__()
  let t.title = a:title
  let t.state = s:_state.get_by_name('started')
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
  let t.tags = s:unique(t.project.tags, a:tags)
  call t.__register__()
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
    t.exec('UPDATE task SET forwardlink = ? WHERE id = ?',
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
  if self.backlink != v:null
    call t.exec('UPDATE task SET forwardlink = NULL WHERE id = ?',
          \ self.backlink.id)
  endif
  let res = t.commit()
  if !res
    throw s:AwiwiEntityError('could not delete task %s', self.title)
  endif
  if self.backlink != v:null
    let self.__class__.__ids__[self.backlink.id].forwardlink = v:null
  endif
  return self.__delete__()
endfun "}}}
