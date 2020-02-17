" if exists('g:autoloaded_awiwi_util')
"   finish
" endif
" let g:autoloaded_awiwi_util = v:true

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


fun! awiwi#util#match_subcommands(subcommands, ArgLead) abort "{{{
  if a:ArgLead == ''
    return copy(a:subcommands)
  endif
  let subcommands = copy(a:subcommands)
  let search_engine = awiwi#util#get_search_engine()
  if search_engine == s:search_engine_plain
    return filter(subcommands, {_, v -> str#startswith(v, a:ArgLead)})
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
  return 'AwiwiTaskError: ' . msg
endfun "}}}


fun! awiwi#util#get_resource(path, ...) abort "{{{
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
