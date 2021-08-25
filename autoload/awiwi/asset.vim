if exists('g:autoloaded_awiwi_asset')
  finish
endif
let g:autoloaded_awiwi_asset = v:true

if !exists('s:get_random_string_is_defined')
  let s:get_random_string_is_defined = v:false
endif


fun! s:get_random_string(length) abort "{{{
  if !s:get_random_string_is_defined
    pyx << EOF
def get_random_string(length):
    import random
    import base64
    return base64.encodebytes(random.randbytes(length)).decode()[:length]
EOF
  let s:get_random_string_is_defined = v:true
  return pyxeval(printf('get_random_string(%d)', a:length))
endfun "}}}


fun! s:get_file_template(extension) abort "{{{
  if a:extension == 'drawio'
      return [
      \ '<mxfile host="Electron" type="device">',
      \    printf('<diagram id="%s" name="Page-1">', s:get_random_string(20)),
      \      'ddHNEoIgEADgp+GOUk53s7p08tCZkU2YQddBGqmnTwfIGOvE8u3C8kNY2bmz4YO8ogBNciocYUeS51lRZPOwyNPLYb/z0BolQtEKtXpBQBr0oQSMSaFF1FYNKTbY99DYxLgxOKVld9Rp14G3sIG64XqrNyWsjLegq19AtTJ2zmjIdDwWBxglFzh9EasIKw2i9VHnStDL48V38etOf7Kfgxno7Y8Fc7DuPU+SH2LVGw==',
      \     '</diagram>',
      \ '</mxfile>'
      \ ]
    else
      return []
    endif
endfun "}}}


fun! awiwi#asset#create_asset_here_if_not_exists(type, ...) abort "{{{
  let opts = get(a:000, 0, {})
  if a:type == awiwi#cmd#get_cmd('paste_asset')
    let opts.suffix = '.jpg'
  endif
  let [name, filename, link] = call('awiwi#asset#create_asset_link', [opts])
  let path = s:get_asset_path(awiwi#date#get_own_date(), filename)
  if !filereadable(path)
    let ret = s:create_asset(a:type, path)
    if ret
      echo printf('asset %s created', filename)
    else
      echoerr printf('[ERROR] could not create asset "%s"', filename)
      return
    endif
  endif
  if match(filename, '\.\(jpe\?g\|gif\|png\|bmp\)$') > -1
    let date = awiwi#date#get_own_date()
    let link = printf('![%s](/assets/%s/%s)', name, date, filename)
  endif
  call awiwi#insert_link_here(link)
  return filename
endfun "}}}


fun! s:create_asset(type, path) abort "{{{
  let dir = fnamemodify(a:path, ':h')
  if !filewritable(dir)
    call mkdir(dir, 'p')
  endif
  if a:type == awiwi#cmd#get_cmd('empty_asset')
    let extension = fnamemodify(a:path, ':e')
    let template = s:get_file_template(extension)
    call writefile(template, a:path)
  elseif a:type == awiwi#cmd#get_cmd('url_asset')
    let url = awiwi#util#input('url: ')
    if empty(url)
      return v:false
    endif
    return awiwi#download_file(a:path, url)
  elseif a:type == awiwi#cmd#get_cmd('paste_asset')
    return awiwi#paste_file(a:path)
  endif
  return v:true
endfun "}}}


fun! awiwi#asset#create_asset_link(...) abort "{{{
  let opts = get(a:000, 0, {})
  let name = get(opts, 'name', '')
  if empty(name)
    let name = awiwi#util#input('asset name: ')
  endif
  if empty(name)
    echo '[INFO] no asset created'
    return ['', '', '']
  endif

  let default_suffix = get(opts, 'suffix', '')
  let default_filename =
        \ substitute(
        \   substitute(
        \     substitute(name, '[A-Z]\+', '\L&', 'g'),
        \     '[[:space:]]\+',
        \     '-',
        \     'g'),
        \   '[^-a-z0-9.:+]\+',
        \   '', 'g'
        \ )

  let filename = awiwi#util#input('asset file: ', {'default': default_filename . default_suffix})
  if filename == ''
    echo '[INFO] no asset created'
    return ['', '', '']
  endif

  let date = awiwi#date#get_own_date()
  let asset_file = s:get_asset_path(date, filename)
  let rel_path = awiwi#util#relativize(asset_file, expand('%:p'))

  let link_text = printf('[%s](%s)',
        \ substitute(name, '[\[\]]', '\\&', 'g'),
        \ rel_path)

  return [name, filename, link_text]
endfun "}}}


fun! awiwi#asset#get_journal_for_current_asset() abort "{{{
  let date = join(awiwi#path#split(expand('%:p:h'))[-3:], '-')
  return awiwi#get_journal_file_by_date(date)
endfun "}}}


fun! awiwi#asset#insert_asset_link(date, name) abort "{{{
  let path = awiwi#util#relativize(s:get_asset_path(a:date, a:name))
  let link = printf('[asset %s, %s](%s)', a:name, a:date, path)
  call awiwi#insert_link_here(link)
endfun "}}}


fun! s:get_asset_path(date, name) abort "{{{
  let [year, month, day] = split(a:date, '-')
  return awiwi#path#join(awiwi#get_asset_subpath(), year, month, day, a:name)
endfun "}}}


" FIXME likely deprecated
fun! s:get_asset_under_cursor(accept_date) abort "{{{
  let empty_result = ['', '']
  let line = getline('.')
  " correct to zero-offset
  let pos = getcurpos()[2]

  let open_bracket_pos = -1
  for i in range(pos, 0, -1)
    let char = line[i]
    if char == '['
      let open_bracket_pos = i
      break
    endif
  endfor

  if !open_bracket_pos == -1
    return empty_result
  endif
  let match = matchlist(line, '\(.\{-}\)\(\]\)\((.\{-})\)\?', open_bracket_pos+1)

  if len(match) < 2
    return empty_result
  endif
  let name = match[1]
  let link = match[3]
  if a:accept_date
    let date = matchstr(name, '^\(continued\|started\) on \zs[0-9]\{4}-[0-9]\{2}-[0-9]\{2}$')
  else
    let date = ''
  endif

  " found an asset link
  if date != ''
    return [date, link]
  elseif name != ''
    return [name, link]
  else
    return empty_result
  endif
endfun "}}}


fun! awiwi#asset#open_asset(name, ...) abort "{{{
  let date = awiwi#date#get_own_date()
  let args = [date, a:name]
  call extend(args, a:000)
  call call(function('awiwi#asset#open_asset_by_name'), args)
endfun "}}}


fun! awiwi#asset#open_asset_by_name(date, name, ...) abort "{{{
  let options = get(a:000, 0, {})
  let date = awiwi#date#parse_date(a:date)
  let path = s:get_asset_path(date, a:name)
  let dir = fnamemodify(path, ':h')
  if !filewritable(dir)
    call mkdir(dir, 'p')
  endif
  call awiwi#open_file(path, options)
  write
endfun "}}}


fun! awiwi#asset#open_asset_sink(expr) abort "{{{
  let [date, name] = split(a:expr, ':')
  call awiwi#asset#open_asset_by_name(date, name)
endfun "}}}


fun! awiwi#asset#get_all_asset_files() abort "{{{
    return map(
          \  map(
          \    filter(
          \      glob(awiwi#path#join(g:awiwi_home, 'assets', '2*', '**'), v:false, v:true),
          \      {_, v -> filereadable(v)}),
          \    {_, v -> split(v, '/')[-4:]}),
          \  {_, v -> {'date': join(v[:2], '-'), 'name': v[-1]}})
endfun "}}}
