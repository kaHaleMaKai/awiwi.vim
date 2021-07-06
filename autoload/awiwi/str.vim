if exists('g:autoloaded_awiwi_str')
  finish
endif
let g:autoloaded_awiwi_str = v:true

fun! awiwi#str#startswith(str, prefix) abort
  if a:str == "" && a:prefix == ""
    return v:true
  elseif len(a:str) < len(a:prefix)
    return v:false
  else
    return strpart(a:str, 0, len(a:prefix)) == a:prefix
  endif
endfun

fun! awiwi#str#endswith(str, suffix) abort
  if a:str == "" && a:suffix == ""
    return v:true
  elseif len(a:str) < len(a:suffix)
    return v:false
  else
    return strpart(a:str, len(a:str) - len(a:suffix)) == a:suffix
  endif
endfun

fun! awiwi#str#contains(str, part) abort "{{{
  return stridx(a:str, a:part) > -1
endfun "}}}


fun! awiwi#str#is_empty(str) abort "{{{
  return strlen(trim(a:str)) == 0
endfun "}}}
