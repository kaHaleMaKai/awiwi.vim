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
  elseif a:date == 'yesterday'
    let date = s:get_yesterday(strftime('%F'))
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
    if !s:is_date(a:date)
      throw s:AwiwiDateError('%s is not a valid date', a:date)
    endif
    let date = a:date
  endif
  return date
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
