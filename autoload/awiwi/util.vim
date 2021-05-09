if exists('g:autoloaded_awiwi_util')
  finish
endif
let g:autoloaded_awiwi_util = v:true

let s:search_engine_plain = 'plain'
let s:search_engine_regex = 'regex'
let s:search_engine_fuzzy = 'fuzzy'

let s:resources = {}
let s:script = expand('<sfile>:p')

fun! awiwi#util#escape_pattern(pattern) abort "{{{
  return escape(a:pattern, " \t.*\\\[\]")
endfun "}}}


fun! awiwi#util#get_search_engine() abort "{{{
  let search_engine = get(g:, 'awiwi_search_engine', 'plain')
  if index([s:search_engine_regex, s:search_engine_fuzzy], search_engine) > -1
    return search_engine
  endif
  return s:search_engine_plain
endfun "}}}


fun! awiwi#util#get_argument_number(expr) abort "{{{
  return len(split(a:expr, '[[:space:]]\+', v:true)) - 1
endfun "}}}


fun! awiwi#util#match_subcommands(subcommands, ArgLead) abort "{{{
  let subcommands = copy(a:subcommands)
  if a:ArgLead == ''
    return subcommands
  endif
  let search_engine = awiwi#util#get_search_engine()
  if search_engine == s:search_engine_plain
    return filter(subcommands, {_, v -> awiwi#str#startswith(v, a:ArgLead)})
  elseif search_engine == s:search_engine_regex
    return filter(subcommands, {_, v -> match(v, a:ArgLead) > -1})
  endif
  let chars = map(range(strlen(a:ArgLead)), {i -> a:ArgLead[i]})
  let pattern = join(map(chars, {_, v -> awiwi#util#escape_pattern(v)}), '.\{-}')

  let all_items = map(
        \ copy(subcommands),
        \ {_, v -> {'name': v, 'match': matchstrpos(v, pattern)}})
  let filtered_items = filter(
        \ all_items,
        \ {_, v -> v.match[0] != '' })
  let normalized_items = map(
        \ filtered_items,
        \ {_, v -> {'name': v.name, 'score': v.match[2] - v.match[1]}})
  let sorted_items = sort(
        \ normalized_items,
        \ {x, y -> x.score > y.score ? 1 : (x.score < y.score ? -1 : (x.name >= y.name ? 1 : -1))})
  return map(sorted_items, {_, v -> v.name})
endfun "}}}


fun! s:AwiwiUtilError(msg, ...) abort "{{{
  if a:0
    let args = [a:msg]
    call extend(args, a:000)
    let msg = call('printf', args)
  else
    let msg = a:msg
  endif
  return 'AwiwiUtilError: ' . msg
endfun "}}}


fun! awiwi#util#get_resource(path, ...) abort "{{{
  let paths = [fnamemodify(s:script, ':h:h:h'), 'resources', a:path]
  call extend(paths, a:000)
  let resource_path = call(funcref('awiwi#path#join'), paths)
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


fun! awiwi#util#empty_resources_cache() abort "{{{
  let s:resources = {}
endfun "}}}


fun! awiwi#util#get_iso_timestamp() abort "{{{
  return strftime('%F %T')
endfun "}}}


fun! awiwi#util#get_iso_timestamp() abort "{{{
  return strftime('%F %T')
endfun "}}}


fun! awiwi#util#get_epoch_seconds() abort "{{{
  return str2nr(strftime('%s'))
endfun "}}}


fun! s:has_element(list, el) abort "{{{
  for el in a:list
    if el.id == a:el.id
      return v:true
    endif
  endfor
  return v:false
endfun "}}}


fun! awiwi#util#unique(list, ...) abort "{{{
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


fun! awiwi#util#is_null(obj) abort "{{{
  return type(a:obj) == type(v:null)
endfun "}}}


fun! awiwi#util#id_or_null(el) abort "{{{
  if awiwi#util#is_null(a:el)
    return v:null
  endif
  return a:el.id
endfun "}}}


fun! awiwi#util#input(prompt, ...) abort "{{{
  let opts = get(a:000, 0, {})
  let opts.prompt = a:prompt
  if has_key(opts, 'completion')
    if !awiwi#str#startswith(opts.completion, 'customlist')
      let opts.completion = printf('customlist,%s', opts.completion)
    endif
  endif
  call inputsave()
  try
    let text = input(opts)
  catch /Interrupted/
  finally
    redr
    call inputrestore()
  endtry
  return text
endfun "}}}


fun! awiwi#util#window_split_below() abort "{{{
  return winwidth('%') / (1.0 * winheight('%')) < 3 ? v:true : v:false
endfun "}}}


fun! awiwi#util#get_link_under_cursor() abort "{{{
  let link = awiwi#util#as_link('')
  let line = getline('.')
  let col = col('.') - 1
  let open_bracket = strridx(line[:col], '[')
  if open_bracket == -1
    let col += 1
    let open_bracket = strridx(line[:col], '[')
  endif
  if open_bracket == -1
    return link
  endif

  let closing_parens = stridx(line, ')', col)
  if closing_parens == -1
    return link
  endif
  let closing_bracket = stridx(line[:closing_parens], ']', open_bracket)
  if closing_bracket == -1
    return link
  endif
  if open_bracket > closing_bracket
        \ || line[closing_bracket+1] != '('
        \ || closing_parens < closing_bracket
    return link
  endif
  if open_bracket > 0 && line[open_bracket - 1] == '!'
    let link.type = 'image'
  endif
  let link.target = line[closing_bracket+2:closing_parens-1]
  return awiwi#util#determine_link_type(link)
endfun "}}}


fun! awiwi#util#as_link(link) abort "{{{
  if type(a:link) == v:t_dict
    return copy(a:link)
  endif
  return {'target': a:link, 'type': ''}
endfun "}}}


fun! awiwi#util#determine_link_type(link) abort "{{{
  let link = copy(a:link)
  if link.type == 'image'
    return link
  elseif match(link.target, '^https\?://') > -1
    let link.type = 'browser'
  elseif match(link.target, '^[a-z]\+://') > -1
    let link.type = 'external'
  elseif match(link.target, '\..*/recipes/.*') > -1
    let link.type = 'recipe'
  elseif match(link.target, '\..*/assets/.*') > -1
    let link.type = 'asset'
  elseif match(link.target, '/\(journal/\)\?\([0-9]\{4}/\)\?\([0-9]\{2}/\)\?\d\{4}-\d\{2}-\d\{2}.md$')
    let link.type = 'journal'
  endif
  return link
endfun "}}}


fun! awiwi#util#get_visual_selection() abort "{{{
  echoerr mode()
  if mode() !=? 'v'
    return ''
  endif
  let line0, col0 = getpos("'<")[1:2]
  let line1, col1 = getpos("'>")[1:2]
  let lines = []
  if mode == 'V'
    for line in range(line0, line1)
      call add(lines, getline(line))
    endfor
  elseif line0 == line1
    call add(lines, getline(line0)[col0:col1])
  else
    for line in range(line0, line1)
      let text = getline(line)
      if line == line0
        let text = text[col0:]
      elseif line == line1
        let text = text[:col1]
      endif
      call add(lines, text)
    endfor
  endif
  return join(lines, "\n")
endfun "}}}


fun! awiwi#util#get_code_block_lines(inclusive) abort "{{{
  let bad_result = [-1, -1]
  let current_line = line('.')
  let triple_ticks = '```'
  if awiwi#str#startswith(getline(current_line), triple_ticks)
    echoerr '[ERROR] not inside of a code block'
    return bad_result
  endif
  let block_start = -1
  let block_end = -1

  for line in range(current_line - 1, 1, -1)
    if awiwi#str#startswith(getline(line), triple_ticks)
      let block_start = line
      break
    endif
  endfor
  if block_start == -1
    echoerr '[ERROR] not inside of a code block'
    return bad_result
  endif

  for line in range(current_line + 1, line('$'))
    if awiwi#str#startswith(getline(line), triple_ticks)
      let block_end = line
      break
    endif
  endfor
  if block_end == -1
    echoerr '[ERROR] cannot find end of code block'
    return bad_result
  endif

  let offset = a:inclusive ? 0 : 1
  return [block_start + offset, block_end - offset]
endfun "}}}


fun! awiwi#util#copy_code_block(inclusive) abort "{{{
  let [start, end] = awiwi#util#get_code_block_lines(a:inclusive)
  if start == -1
    return
  endif
  exe printf('%d,%dyank', start, end)
endfun "}}}


fun! awiwi#util#select_code_block(inclusive) abort "{{{
  let [start, end] = awiwi#util#get_code_block_lines(a:inclusive)
  if start == -1
    return
  endif
  exe printf('normal! %dggV%dgg', start, end)
endfun "}}}


fun! awiwi#util#relativize(path, ...) abort "{{{
  if a:0 > 0
    let other_file = awiwi#path#absolute(a:1)
  else
    let other_file = awiwi#path#absolute(expand('%'))
  endif
  return awiwi#path#relativize(a:path, other_file)
endfun "}}}
