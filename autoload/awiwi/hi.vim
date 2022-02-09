if ! exists('s:ns')
  let s:ns = nvim_create_namespace('awiwi-todo-dates')
endif

fun! s:get_date_diff(date1, date2) abort "{{{
  if a:date1 == a:date2
    return 0
  endif

  let [year1, month1, day1] = awiwi#date#to_tuple(a:date1)
  let [year2, month2, day2] = awiwi#date#to_tuple(a:date2)
  return luaeval(
        \ printf('os.time{year=%d,month=%d,day=%d} - os.time{year=%d,month=%d,day=%d}',
        \ year1, month1, day1, year2, month2, day2)) / 86400
endfun


fun! s:format_days(days) abort "{{{
  if a:days == 0
    return ['TODAY', 'awiwiUrgent']
  endif
  let w = abs(a:days) / 7
  let d = abs(a:days) % 7
  if w > 0
    if d > 0
      let message = printf('%dw, %dd', w, d)
    else
      let message = printf('%dw', w)
    endif
  else
    let message = printf('%dd', d)
  endif

  if a:days < 0
    return [printf('[ %s ago ]', message), 'awiwiUrgent']
  else
    return [printf('[ in %s ]', message), w > 0 ? 'awiwiFutureDueDate' : 'awiwiNearDueDate']
  endif
endfun "}}}


fun! awiwi#hi#draw_due_dates() abort "{{{
  let today = strftime('%Y-%m-%d')
  for lineno in range(0, line('$') - 1)
    let line = getline(lineno + 1)
    let m = matchstr(line, '{[^{]\+}$')
    if empty(m) || match(line, '^\s*\* \[ \] ') == -1
      continue
    endif
    try
      let meta = json_decode(m)
    catch /E474/
      continue
    endtry
    let text = []

    if has_key(meta, 'due')
      try
        let due_in = s:format_days(s:get_date_diff(meta.due, today))
        call add(text, due_in)
      catch /.*/
        let err = printf('bad meta info: %s', v:exception)
        call add(text, [err, 'awiwiUrgent'])
      endtry
    elseif has_key(meta, 'created')
      let text = [[meta.created, 'awiwiCreatedDate']]
    endif
    call nvim_buf_set_virtual_text(0, s:ns, lineno, text, {})
  endfor
endfun "}}}


fun! awiwi#hi#clear_due_dates() abort "{{{
  call nvim_buf_clear_namespace(0, s:ns, 0, -1)
endfun "}}}


fun! awiwi#hi#redraw_due_dates(...) abort "{{{
  let force_redraw = a:0 ? a:1 : v:false
  if force_redraw || &modified || get(w:, 'last_redraw', 0) < getftime(expand('%:p'))
    call awiwi#hi#clear_due_dates()
    call awiwi#hi#draw_due_dates()
    let w:last_redraw = str2nr(strftime('%s'))
  endif
endfun "}}}
