" if exists('g:autoloaded_awiwi_sql')
"   finish
" endif
" let g:autoloaded_awiwi_sql = v:true

let s:col_sep = nr2char(1)
let s:null_value = '\N'
let s:char_map = {"\t": '\t', "\n": '\n', "\0": '\0', "\b": '\b', '\': '\\', s:col_sep: '\1'}
let s:escape_map = {'t': '\t', 'n': '\n', '0': '\0', 'b': '\b', '1': '\1'}
let s:reverse_escape_map = {'t': "\t", 'n': "\n", '0': "\0", 'b': "\b", '\': '\'}


fun! s:escape_string_param(param, ...) abort "{{{
  let got_backslash = v:false
  let is_table = get(a:000, 0, v:false)
  let quote_char = is_table ? '`' : "'"
  let p = [quote_char]

  for i in range(0, strlen(a:param) - 1)
    let ch = a:param[i]
    if ch == '\' && !got_backslash
      let got_backslash = v:true
    elseif ch == '`' && is_table
      call add(p, '\`')
      let got_backslash = v:false
    elseif ch == "'" && !is_table
      call add(p, "''")
      let got_backslash = v:false
    elseif has_key(s:char_map, ch)
      if got_backslash
        call add(p, '\\')
        let got_backslash = v:false
      endif
      call add(p, s:char_map[ch])
    elseif got_backslash && has_key(s:escape_map, ch)
      call add(p, s:escape_map[ch])
      let got_backslash = v:false
    elseif got_backslash
      call add(p, '\\')
      call add(p, ch)
      let got_backslash = v:false
    else
      call add(p, ch)
    endif
  endfor
  if got_backslash
    call add(p, '\\')
  endif
  call add(p, quote_char)
  return join(p, '')
endfun "}}}


fun! s:escape_dict(param) abort "{{{
  let t = a:param.type
  return s:escape_string_param(a:param.value, t == 'table')
endfun "}}}


fun! awiwi#sql#escape_query(query, ...) abort "{{{
  let args = [v:false, a:query]
  call extend(args, a:000)
  return call(funcref('s:escape_query'), args)
endfun


fun! awiwi#sql#escape_query_with_type_hints(query, ...) abort "{{{
  let args = [v:true, a:query]
  call extend(args, a:000)
  return call(funcref('s:escape_query'), args)
endfun


fun! s:parse_type_hints(query) abort "{{{
  let hints = []
  let element_types = '[jinfdtTsb]'
  let hint_pattern = printf(
        \ '\<[a-zA-Z_][a-zA-Z_0-9]*@\(%s\|l%s\?\)\>',
        \ element_types, element_types)
  let query_parts = []
  let start_pos = 0
  while v:true
    let m = matchstrpos(a:query, hint_pattern, start_pos, 1)
    if m[0] == ''
      call add(query_parts, a:query[start_pos:])
      break
    endif

    let [col, t] = split(m[0], '@')
    " we should use 'n' for 'number' – vi-like – instead of 'i' for 'int'
    if t == 'i'
      let t = 'n'
    elseif t == 'li'
      let t = 'ln'
    endif
    call add(hints, {'name': col, 'type': t})
    let end = m[-1]
    " account for length of type hint @l\?[infdtTsbl] -> -3
    let colname_end = end - 2 - len(t)
    call add(query_parts, a:query[start_pos:colname_end])
    let start_pos = end
  endwhile
  return [hints, join(query_parts, '')]
endfun "}}}


fun! s:escape_param(param, ...) abort "{{{
  let is_nested = a:0 != 0
  let p = a:param
  let t = type(p)
  if t == type(v:null)
    return 'NULL'
  elseif t == v:t_bool
    return p ? 'True' : 'False'
  elseif t == v:t_float || t == v:t_number
    return p
  elseif t == v:t_string
    return s:escape_string_param(p)
  elseif t == v:t_dict
    if is_nested
      throw 'AwiwiSqlError: cannot use nested list-param'
    endif
    return s:escape_dict(p)
  elseif t == v:t_list
    if is_nested
      throw 'AwiwiSqlError: cannot use nested list-param'
    endif
    return map(copy(p), {_, v -> s:escape_param(v, v:true)})
  else
    throw printf('AwiwiSQLError: got bad parameter type: %s', t)
  endif
endfun "}}}


fun! s:escape_query(use_type_hints, query, ...) abort "{{{
  let [hints, query] = a:use_type_hints ? s:parse_type_hints(a:query) : [[], a:query]

  if !a:0
    if a:use_type_hints
      return [hints, query]
    else
      return query
    endif
  endif

  let params = map(copy(a:000), {_, v -> s:escape_param(v)})

  let quotation_mark_pattern = '\(?\)\@<!' . '?' . '\(?\)\@!'
  let parts = split(query, quotation_mark_pattern, v:true)
  if len(parts) != len(params) + 1
    throw printf('AwiwiSqlError: wrong number of parameters for query. got %d placeholder(s) and %d parameter(s)', len(parts)-1, len(params))
  endif
  let query_parts = []
  for i in range(len(params))
    let query_part = substitute(parts[i], '??', '?', 'g')
    call add(query_parts, query_part)
    let p = params[i]
    if type(p) == v:t_list
      if match(query_part[-1], '(\s*$') == -1
        call add(query_parts, '(')
      endif
      for j in range(len(p) - 1)
        call add(query_parts, p[j])
        call add(query_parts, ', ')
      endfor
      call add(query_parts, p[-1])
      if match(query_parts[i+1], '^\s*)') == -1
        call add(query_parts, ')')
      endif
    else
      call add(query_parts, p)
    endif
  endfor
  call add(query_parts, substitute(parts[-1], '??', '?', 'g'))
  let result = join(query_parts, '')
  if a:use_type_hints
    return [hints, result]
  else
    return result
  endif
endfun "}}}


let s:output = {}
let s:ddl_opts = {'stdout_buffered': v:true, 'stderr_buffered': v:true}

fun! s:ddl_opts.on_stderr(id, data, name) abort dict "{{{
  let s:output[a:id] = a:data
endfun "}}}


fun! s:ddl_opts.on_exit(id, rc, e) abort dict "{{{
  if a:rc == 0
    return
  endif
  echoerr printf("ddl-statement got rc=%d: %s", a:rc, join(s:output[a:id][:-2], "\n"))
  unlet s:output[a:id]
endfun "}}}


fun! awiwi#sql#ddl(db, query, ...) abort "{{{
  let params = [a:db, v:false, a:query]
  call extend(params, a:000)
  return call('s:exec_ddl', params)
endfun


fun! awiwi#sql#ddl_async(db, query, ...) abort "{{{
  let params = [a:db, v:true, a:query]
  call extend(params, a:000)
  return call('s:exec_ddl', params)
endfun


fun! s:exec_ddl(db, async, query, ...) abort "{{{
  let params = [a:query]
  call extend(params, a:000)
  let query = call(funcref('awiwi#sql#escape_query'), params)

  let command = ['sqlite3', '-nullvalue', s:null_value, a:db, query]
  if a:async
    call jobstart(command, s:ddl_opts)
    return v:true
  endif

  let msg = system(command)
  if v:shell_error == 0
    return v:true
  endif
  echoerr printf("ddl-statement got rc=%d: %s", v:shell_error, msg[:-2])
  return v:false
endfun "}}}


fun! s:convert_string_back(param) abort "{{{
  if a:param == s:null_value
    return v:null
  endif
  let p = []
  let param = a:param
  let got_backslash = v:false
  for i in range(0, strlen(a:param) - 1)
    let ch = a:param[i]
    if got_backslash && has_key(s:reverse_escape_map, ch)
      call add(p, s:reverse_escape_map[ch])
      let got_backslash = v:false
    elseif !got_backslash && ch == '\'
      let got_backslash = v:true
    elseif got_backslash
      echoerr printf('found backslash were none was expected: %s', a:param)
    else
      call add(p, ch)
    endif
  endfor
  return join(p, '')
endfun "}}}


fun! s:split_cols(row) abort "{{{
  return map(split(a:row, s:col_sep, v:true), {_, v -> s:convert_string_back(v)})
endfun "}}}


fun! s:convert_type(value, type) abort "{{{
  if a:value == s:null_value
    return v:null
  endif
  if a:type == 'n'
    return str2nr(a:value)
  elseif a:type == 'f'
    return str2float(a:value)
  elseif a:type == 'b'
    return a:value == '1' ? v:true : v:false
  elseif a:type == 'l'
    return split(a:value, '\s*,\s*', v:true)
  elseif a:type == 'j'
    return json_decode(a:value)
  elseif a:type == 's'
    return s:convert_string_back(a:value)
  " we got a list with element-types specified
  elseif len(a:type) == 2
    let t = a:type[1]
    let elements = split(a:value, '\s*,\s*', v:true)
    return map(elements, {_, v -> s:convert_type(v, t)})
  else
    throw printf('AwiwiSqlError: got unknown type hint: "%s"', a:type)
  endif
endfun "}}}


fun! awiwi#sql#select(db, query, ...) abort "{{{
  let params = [a:query]
  call extend(params, a:000)
  let [hints, query] = call(funcref('awiwi#sql#escape_query_with_type_hints'), params)
  let command = ['sqlite3', '-separator', s:col_sep, '-nullvalue', s:null_value, a:db, query]
  let result = systemlist(command)
  if v:shell_error == 0
    let rows = map(result, {_, v -> split(v, s:col_sep, v:true)})
    if empty(hints)
      return map(rows, {_, v -> map(v, {__, w -> s:convert_string_back(w)})})
    endif
    let new_result = []
    for row in rows
      let r = {}
      for i in range(0, len(row) - 1)
        let col = hints[i]
        let r[col.name] = s:convert_type(row[i], col.type)
      endfor
      call add(new_result, r)
    endfor
    return new_result
  endif
  throw printf("AwiwiSqlError: select-command got rc=%d: %s", v:shell_error, join(result, "\n")[:-2])
endfun "}}}


let s:Transaction = {}


fun! s:Transaction.begin(db) abort "{{{
  let t = copy(s:Transaction)
  let t.db = a:db
  let t.queries = []
  return t
endfun "}}}


fun! s:Transaction.exec(query, ...) abort "{{{
  let query = [a:query]
  call extend(query, a:000)
  call add(self.queries, query)
  return self
endfun "}}}


fun! s:Transaction.commit() abort "{{{
  let queries = []
  for entry in self.queries
    let query = call(funcref('awiwi#sql#escape_query'), entry)
    call add(queries, query)
  endfor
  return awiwi#sql#ddl(self.db, join(queries, '; '))
endfun "}}}


fun! s:Transaction.commit_as_select() abort "{{{
  let queries = []
  for i in range(len(self.queries) - 1)
    let query = call(funcref('awiwi#sql#escape_query'), self.queries[i])
    call add(queries, query)
  endfor
  let query = self.queries[-1][0]
  let params = self.queries[-1][1:]
  call add(queries, query)
  let args = [self.db, join(queries, '; ')]
  call extend(args, params)
  return call(funcref('awiwi#sql#select'), args)
endfun "}}}


fun! awiwi#sql#start_transaction(db) abort "{{{
  return s:Transaction.begin(a:db)
endfun "}}}
