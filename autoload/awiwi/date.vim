if exists('g:autoloaded_awiwi_date')
  finish
endif
let g:autoloaded_awiwi_date = v:true

let s:date_pattern = '^[0-9]\{4}-[0-9]\{2}-[0-9]\{2}$'


fun! s:AwiwiDateError(msg, ...) abort "{{{
  if a:0
    let args = [a:msg]
    call extend(args, a:000)
    let msg = call('printf', args)
  else
    let msg = a:msg
  endif
  return 'AwiwiDateError: ' . msg
endfun "}}}


fun! awiwi#date#get_today() abort "{{{
  return strftime('%F')
endfun "}}}


fun! awiwi#date#to_tuple(date) abort "{{{
  return map(split(a:date, '-'), {_,v -> str2nr(v)})
endfun "}}}


fun! s:is_leap_year(year) abort "{{{
  return a:year % 400 == 0 || (a:year % 4 == 0 && a:year % 100 != 0)
endfun "}}}


fun! awiwi#date#parse_date(date, ...) abort "{{{
  let options = get(a:000, 0, {})
  if a:date == 'today'
    return strftime('%F')
  elseif a:date == 'prev' || a:date == 'previous' || a:date == 'previous date' || a:date == 'previous day'
    try
      let date = s:get_offset_date(awiwi#date#get_own_date(), -1, options)
    catch /AwiwiDateError/
      let date = s:get_offset_date(awiwi#date#get_today(), -1, options)
    endtry
  elseif a:date == 'next' || a:date == 'next date' || a:date == 'next day'
    try
      let date = s:get_offset_date(awiwi#date#get_own_date(), +1, options)
    catch /AwiwiDateError/
      let date = s:get_offset_date(awiwi#date#get_today(), +1, options)
    endtry
  else
    " FIXME check if s:is_date(a:date), or raise exception
    let date = awiwi#date#to_iso_date(a:date)
    if !s:is_date(date)
      throw s:AwiwiDateError('%s is not a valid date', date)
    endif
  endif
  return date
endfun "}}}


fun! awiwi#date#to_iso_date(date) abort "{{{
  if a:date =~# '^[0-9]\{4}-[0-9]\{2}-[0-9]\{2}$'
    return a:date
  elseif a:date =~# '^[0-9]\{2}\.[0-9]\{2}\.\?$'
    let [day, month] = a:date->split('\.')[0:1]
    let year = strftime('%Y')
    return printf('%s-%s-%s', year, month, day)
  else
    let pattern = '\<in\ze[[:space:]0-9]'
    if a:date =~# pattern
      let date = substitute(a:date, pattern, ' + ', '')
    else
      let date = a:date
    endif
    return systemlist(['date', '--date', date, '+%F'])[0]
  endif
endfun "}}}


fun! s:get_yesterday(date) abort "{{{
  let [year, month, day] = awiwi#date#to_tuple(a:date)
  " not 1st of month
  if str2nr(day) > 1
    return s:ints_to_date(year, month, day - 1)
  endif
  " date is 1st of month
  let num_days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  " no switch to Feb. of Dec.
  if month == 2 || month >= 3
    return s:ints_to_date(year, month - 1, num_days[month - 1])
  " switch to Feb.
  elseif month == 3
    " check for leap year
    if s:is_leap_year(year)
      let day = 29
    else
      let day = 28
    endif
    return s:ints_to_date(year, 2, day)
  " switch from Jan. back to Dec.
  else
    return s:ints_to_date(year - 1, 12, 31)
  endif
endfun "}}}


fun! s:get_offset_date(date, offset, options) abort "{{{
  let files = awiwi#get_all_journal_files()
  let idx = index(files, a:date)
  if idx == -1
    if awiwi#date#parse_date('today') == a:date
      return a:date
    endif
    throw s:AwiwiDateError('date %s not found', a:date)
  elseif a:offset <= 0 && idx + a:offset <= 0
    throw s:AwiwiDateError('no date found before %s', a:date)
  elseif a:offset >= 0 && idx + a:offset >= len(files)
    if get(a:options, 'create_dirs', v:false)
      return a:date
    else
      throw s:AwiwiDateError('no date found after %s', a:date)
    endif
  endif
  return files[idx + a:offset]
endfun "}}}


fun! s:ints_to_date(year, month, day) abort "{{{
  return printf('%04d-%02d-%02d', a:year, a:month, a:day)
endfun "}}}


fun! awiwi#date#get_own_date() abort "{{{
  let name = expand('%:t:r')
  if !s:is_date(name)
    let name = join(awiwi#path#split(expand('%:p'))[-4:-2], '-')
    if !s:is_date(name)
      throw s:AwiwiDateError('not on journal or asset page')
    endif
  endif
  return name
endfun "}}}


fun! s:is_date(expr) abort "{{{
  return match(a:expr, s:date_pattern) > -1
endfun "}}}
