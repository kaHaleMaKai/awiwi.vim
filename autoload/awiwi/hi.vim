if exists('g:autoloaded_awiwi_hi')
  finish
endif
let g:autoloaded_awiwi_hi = v:true

let s:ns_todo_dates = nvim_create_namespace('awiwi-todo-dates')
let s:ns_hlines = nvim_create_namespace('awiwi-horizontal-lines')

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


fun! awiwi#hi#get_meta_and_pos(line) abort "{{{
  let [m, start, end] = matchstrpos(a:line, '{[^{]\+}$')
  if empty(m) || match(a:line, '^\s*\* \[ \] ') == -1
    return [{}, -1, -1]
  endif
  try
    return [json_decode(m), start, end]
  catch /E474/
    return [{}, -1, -1]
  endtry
endfun "}}}



fun! awiwi#hi#draw_due_dates() abort "{{{
  let today = strftime('%Y-%m-%d')
  for lineno in range(0, line('$') - 1)
    let line = getline(lineno + 1)
    let meta = awiwi#hi#get_meta_and_pos(line)[0]
    if empty(meta)
      continue
    endif
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
    call nvim_buf_set_virtual_text(0, s:ns_todo_dates, lineno, text, {})
  endfor
endfun "}}}


fun! awiwi#hi#clear_due_dates() abort "{{{
  call nvim_buf_clear_namespace(0, s:ns_todo_dates, 0, -1)
endfun "}}}


fun! awiwi#hi#redraw_due_dates(...) abort "{{{
  let force_redraw = a:0 ? a:1 : v:false
  if force_redraw || &modified || get(w:, 'last_redraw', 0) < getftime(expand('%:p'))
    call awiwi#hi#clear_due_dates()
    call awiwi#hi#draw_due_dates()
    let w:last_redraw = str2nr(strftime('%s'))
  endif
endfun "}}}


fun! awiwi#hi#draw_horizontal_lines() abort "{{{
  let is_code_block = v:false
  let width = nvim_win_get_width(0)
  call nvim_buf_clear_namespace(0, s:ns_hlines, 0, -1)
  for lineno in range(1, line('$'))
    let line = getline(lineno)
    if line =~# '^```'
      let is_code_block = !is_code_block
      continue
    elseif is_code_block
      continue
    elseif line =~# '^#\+\s'
      let rem = width - strlen(line) - 2
      if rem <= 0
        continue
      endif
      let level = strlen(split(line, '\s')[0])
      let char = level <= 2 ? '━' :  '─'
      let hline = ' ' . range(rem)->map({_,v -> char})->join('')
      let hi = printf('markdownH%d', level)
      call nvim_buf_set_virtual_text(0, s:ns_hlines, lineno - 1, [[hline, hi]], {})
    endif
  endfor
endfun "}}}


fun! awiwi#hi#get_recipe_title() abort "{{{
  let title = expand('%:p')
  let rel_path = awiwi#path#relativize(expand('%:p'), awiwi#get_recipe_subpath())
  return rel_path->awiwi#path#split()[1:]->join('/')[:-4]
endfun "}}}


fun! awiwi#hi#get_asset_title() abort "{{{
  let title = expand('%:p')->awiwi#path#split()[-4:]
  let date = title[:2]->join('-')
  let name = title[-1]
  if name->awiwi#str#endswith('.md')
    let name = name[:-4]
  endif
  return printf('%s [%s]', name, date)
endfun "}}}


fun! awiwi#hi#get_journal_title() abort "{{{
  return awiwi#date#to_nice_date(awiwi#date#get_own_date())
endfun "}}}
