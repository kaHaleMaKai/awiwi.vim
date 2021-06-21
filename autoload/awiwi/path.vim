if exists('g:autoloaded_awiwi_path_vim')
  finish
endif
let g:autoloaded_path_vim = v:true

fun! awiwi#path#join(path, ...) abort
  if !a:0 || a:1 == ""
    if awiwi#str#endswith(a:path, "/")
      return strpart(a:path, 0, len(a:path) - 1)
    else
      return a:path
    end
  endif
  if !awiwi#str#endswith(a:path, "/") && !awiwi#str#startswith(a:1, "/")
    let p = a:path."/".a:1
  elseif awiwi#str#endswith(a:path, "/") && awiwi#str#startswith(a:1, "/")
    let p = a:path.strpart(a:1, 1)
  else
    let p = a:path.a:1
  endif
  let args = [p] + a:000[1:]
  return fn#apply('awiwi#path#join', p, fn#spread(a:000[1:]))
endfun

fun! awiwi#path#absolute(path) abort "{{{
  return fnamemodify(expand(a:path), ':p')
endfun "}}}


fun! awiwi#path#is_absolute(path) abort "{{{
  return awiwi#str#startswith(a:path, '/')
endfun "}}}

fun! awiwi#path#is_relative(path) abort "{{{
  return !awiwi#path#is_absolute(a:path)
endfun "}}}


fun! awiwi#path#split(path) abort "{{{
  let splits = split(a:path, '/')
  if awiwi#path#is_absolute(a:path)
    call insert(splits, '/')
  endif
  return splits
endfun "}}}


fun! awiwi#path#relativize(path, relative_to) abort "{{{
  if awiwi#path#is_absolute(a:path) && awiwi#path#is_relative(a:relative_to)
    return a:path
  endif
  let path = awiwi#path#split(a:path)
  let relative_to = awiwi#path#split(a:relative_to)
  let length = min([len(path), len(relative_to)])
  let start = 0
  for i in range(length)
    let start = i
    if path[i] != relative_to[i]
      break
    endif
  endfor

  let parts = map(relative_to[start:-2], {_ -> '..'}) + path[start:]
  return call(funcref('awiwi#path#join'), parts)
endfun "}}}


fun! awiwi#path#canonicalize(path) abort "{{{
  let parts = awiwi#path#split(a:path)
  let new_parts = []
  for i in range(len(parts))
    let part = parts[i]
    if part == '.' || empty(part)
      continue
    elseif part == '..'
      call remove(new_parts, -1)
    else
      call add(new_parts, part)
    endif
  endfor
  return call('awiwi#path#join', new_parts)
endfun "}}}
