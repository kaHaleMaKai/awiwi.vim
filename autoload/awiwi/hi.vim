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
  if a:days < 0
    return [printf('%dw, %dd ago', w, d), 'awiwiUrgent']
  endif
  if w > 0
    return [printf('in %dw, %dd', w, d), 'awiwiFutureDueDate']
  else
    return [printf('in %dd', d), 'awiwiNearDueDate']
endfun "}}}


fun! awiwi#hi#draw_due_dates() abort "{{{
  let today = strftime('%Y-%m-%d')
  for lineno in range(0, line('$') - 1)
    let line = getline(lineno + 1)
    let m = matchstr(line, '{[^{]\+}$')
    if empty(m) || match(line, '^\s*\* \[ \] ') == -1
      continue
    endif
    let meta = json_decode(m)
    let text = [[meta.created, 'awiwiCreatedDate']]
    if has_key(meta, 'due')
      call add(text, [', ', 'awiwiCreatedDate'])
      let due_in = s:get_date_diff(meta.due, today)
      call add(text, s:format_days(due_in))
    endif
    call nvim_buf_set_virtual_text(0, s:ns, lineno, text, {})
  endfor
endfun "}}}


fun! awiwi#hi#clear_due_dates() abort "{{{
  call nvim_buf_clear_namespace(0, s:ns, 0, -1)
endfun "}}}


fun! awiwi#hi#redraw_due_dates() abort "{{{
  call awiwi#hi#clear_due_dates()
  call awiwi#hi#draw_due_dates()
endfun "}}}
