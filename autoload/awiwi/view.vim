"if exists('g:autoloaded_awiwi_view')
 "finish
"endif
"let g:autoloaded_awiwi_view = v:true

if !exists('g:autoloaded_awiwi_view')
  call awiwi#dao#init_test_data('/tmp/awiwi-test.db')
  for tag in ['nifi', 'gcp', 'ansible']
    call g:awiwi#dao#Tag.new(tag).persist()
  endfor
  let g:autoloaded_awiwi_view = v:true
endif

let s:all_tags = []
let s:input_highlight_defaults = {
      \ 'mark_spaces': v:true,
      \ 'pattern': v:false,
      \ 'func': v:false,
      \ 'bad_char_pattern': '[^-_a-zA-Z0-9]'
      \ }


fun! awiwi#view#_complete_tags(ArgLead, CmdLine, CursorPos) abort "{{{
  return awiwi#util#match_subcommands(s:all_tags, a:ArgLead)
endfun "}}}


fun! s:highlight_bad_urgency_value(cmdLine, ExistsFn) abort "{{{
  let words = split(a:cmdLine, '[,[:space:]]\+')
  let matches = []
  for word in words
    if match('^[0]$\|^[1][0-9]$')
    let pattern = printf('\<%s\>', awiwi#util#escape_pattern(word))
    let m = matchstrpos(a:cmdLine, pattern)
    if m[1] > -1
      call add(matches, [m[1], m[2], 'ErrorMsg'])
    endif
  endfor
  let len = len(a:cmdLine)
  let start = 0
  while start < len
    let m = matchstrpos(a:cmdLine, s:input_highlight_defaults.bad_char_pattern . '\+', start)
    if m[1] == -1
      break
    endif
    let start = m[2]
    call add(matches, [m[1], m[2], 'Substitute'])
  endwhile
  return sort(matches, {x, y -> x[0] < y[0] ? -1 : (x[0] == y[0] ? 0 : 1)})
endfun "}}}


fun! s:highlight_bad_input(cmdLine, ExistsFn, ...) abort "{{{
  let options = copy(s:input_highlight_defaults)
  call extend(options, get(a:000, 0, {}))
  let words = split(a:cmdLine, '[,[:space:]]\+')
  let matches = []
  let funcs = [{ t -> !a:ExistsFn(t)}]
  if options.pattern != v:false
    call add(funcs, { t -> match(t, options.pattern) > -1})
  endif
  if options.func != v:false
    call add(funcs, options.func)
  endif

  for word in words
    let do_continue = v:true
    for Func in funcs
      let do_continue = and(do_continue, Func(word))
    endfor
    if do_continue
      continue
    endif
    let pattern = printf('\<%s\>', awiwi#util#escape_pattern(word))
    let m = matchstrpos(a:cmdLine, pattern)
    if m[1] > -1
      call add(matches, [m[1], m[2], 'ErrorMsg'])
    endif
  endfor
  let len = len(a:cmdLine)
  let start = 0
  while start < len
    let m = matchstrpos(a:cmdLine,options.bad_char_pattern, start)
    if m[1] == -1
      break
    endif
    let start = m[2]
    if options.mark_spaces
      call add(matches, [m[1], m[2], 'Substitute'])
    endif
  endwhile
  return sort(matches, {x, y -> x[0] < y[0] ? -1 : (x[0] == y[0] ? 0 : 1)})
endfun "}}}


fun! awiwi#view#_highlight_bad_tag(cmdLine) abort "{{{
  return s:highlight_bad_input(a:cmdLine, g:awiwi#dao#Tag.name_exists)
endfun "}}}


fun! awiwi#view#_highlight_good_tags(cmdLine) abort "{{{
  return s:highlight_bad_input(a:cmdLine, { t -> !g:awiwi#dao#Tag.name_exists(t) }, {'mark_spaces': v:false, 'bad_char_pattern': '[^a-zA-Z0-9,[:space:]]'})
endfun "}}}


fun! awiwi#view#_highlight_bad_urgency(cmdLine) abort "{{{
  return s:highlight_bad_input(a:cmdLine, g:awiwi#dao#Urgency.name_exists)
endfun "}}}


fun! awiwi#view#_highlight_bad_project_name(cmdLine) abort "{{{
  return s:highlight_bad_input(a:cmdLine, g:awiwi#dao#Project.name_exists)
endfun "}}}


fun! awiwi#view#_highlight_bad_project_url(cmdLine) abort "{{{
  return s:highlight_bad_input(a:cmdLine, {t -> trim(t) != '' && awiwi#dao#check_url(t, v:true) == v:null}, {'bad_char_pattern': '[[:space:\\]]'})
endfun "}}}


fun! s:is_bad_urgency_value(val) abort "{{{
  if match(a:val, '^\([0-9]\|10\)$') == -1
    return v:false
  endif
  let val = str2nr(a:val)
  if 0 < val || val > 10
    return v:false
  endif
  for u in g:awiwi#dao#Urgency.get_all()
    if u.value == val
      return v:false
    endif
  endfor
  return v:true
endfun "}}}


fun! awiwi#view#_highlight_bad_urgency_value(cmdLine) abort "{{{
  return s:highlight_bad_input(a:cmdLine, g:awiwi#dao#Urgency.value_exists, '^[0-9]$')
endfun "}}}


fun! awiwi#view#create_tag(...) abort "{{{
  if a:0
    let tag_name = a:1
  else
    let tag_name = trim(awiwi#util#input('tag name: ', {'highlight': 'awiwi#view#_highlight_bad_tag'}))
  endif
  let error_msg = []
  let tag = s:call_and_log_traceback(error_msg, { t -> g:awiwi#dao#Tag.new(t).persist() }, [tag_name], 'could not create tag "%s" ✖')
  if !s:has_error(error_msg)
    echo printf('tag "%s" created ✔', tag.name)
  endif
endfun "}}}


fun! awiwi#view#create_urgency(...) abort "{{{
  let error_msg = []
  if a:0
    let name = a:1
  else
    let name = trim(awiwi#util#input('urgency name: ', {'highlight': 'awiwi#view#_highlight_bad_urgency'}))
  endif

  if g:awiwi#dao#Urgency.name_exists(name)
    echoerr printf('could not create urgency. name "%s" already exists ✖', name)
    return
  endif
  call s:call_and_log_traceback(error_msg, g:awiwi#dao#Urgency.validate_identifier, [name], 'could not create urgency. name "%s" is not valide ✖')
  if s:has_error(error_msg)
    return
  endif
  let value_ = trim(awiwi#util#input('urgency value: ', {'highlight': 'awiwi#view#_highlight_bad_urgency_value'}))
  let value = str2nr(value_)
  if value == 0
    echoerr printf('got bad value as urgency value: "%s" is not a number ✖', value_)
    return
  endif
  if g:awiwi#dao#Urgency.value_exists(value)
    echoerr printf('could not create urgency. urgency value %d already exists ✖', value)
    return
  endif

  let urgency = s:call_and_log_traceback(error_msg, { n, v -> g:awiwi#dao#Urgency.new(n, v).persist() }, [name, value], 'could not create urgency "%s" with value %d ✖')
  if !s:has_error(error_msg)
    echo printf('urgency "%s" created ✔', urgency.name)
  endif
endfun "}}}


fun! awiwi#view#create_project(...) abort "{{{
  let error_msg = []
  if a:0
    let project_name = a:1
  else
    let project_name = trim(awiwi#util#input('project name: ', {'highlight': 'awiwi#view#_highlight_bad_project_name'}))
  endif
  if g:awiwi#dao#Project.name_exists(project_name)
    echoerr printf('could not create project. name "%s" already exists ✖', project_name)
    return
  endif
  call s:call_and_log_traceback(error_msg, g:awiwi#dao#Project.validate_identifier, [project_name], 'could not create project. name "%s" is not valide ✖')
  if s:has_error(error_msg)
    return
  endif

  let url = trim(awiwi#util#input('project url: ', {'highlight': 'awiwi#view#_highlight_bad_project_url'}))
  if url != '' && awiwi#dao#check_url(url, v:true) == v:null
    echoerr printf('could not create project. url "%s" is invalid ✖', url)
    return
  endif

  let s:all_tags = g:awiwi#dao#Tag.get_all_names()
  let tags = map(
        \ split(trim(awiwi#util#input('project tags: ', {'highlight': 'awiwi#view#_highlight_good_tags', 'completion': 'awiwi#view#_complete_tags'})), '[,[:space:]]\+'),
        \ { _, t -> g:awiwi#dao#Tag.get_by_name(t) })

  let project = s:call_and_log_traceback(error_msg,
        \ { p, u, t -> g:awiwi#dao#Project.new(p, u, t).persist() },
        \ [project_name, url, tags],
        \ 'could not create project "%s" with url "%s" and tags "%s" ✖')
  if !s:has_error(error_msg)
    echo printf('project "%s" created ✔', project.name)
  endif
endfun "}}}


fun! s:call_and_log_traceback(error_msg, Fn, args, msg) abort "{{{
  try
    return call(a:Fn, a:args)
  catch /AwiwiDaoError/
    let error_args = [a:msg]
    call extend(error_args, a:args)
    call add(a:error_msg, call('printf', error_args))
    call add(a:error_msg, ' ')
    call add(a:error_msg, printf('caused by: %s in %s', v:exception, v:throwpoint))
  endtry
endfun "}}}


fun! s:has_error(error_msg) abort "{{{
  if empty(a:error_msg)
    return v:false
  endif

  if !empty(a:error_msg)
    for line in a:error_msg
      echoerr line
    endfor
  endif
  return v:true
endfun "}}}
