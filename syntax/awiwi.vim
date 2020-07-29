let s:types = [
      \ 'todo',
      \ 'onhold',
      \ 'question'
      \ ]

let markers = []
let marker_opts = {'escape_mode': 'vim'}
for type in s:types
  call extend(markers, awiwi#get_markers(type, {'join': v:false, 'escape_mode': 'vim'}))
endfor
syn case match
exe printf('syn match awiwiTodo /\<\(%s\)\([[:space:]]\|$\)\@=/', join(markers, '\|'))

exe printf('syn match awiwiUrgentEnd /\(\<%s\>\)\@<=.\+$/', awiwi#get_markers('urgent', marker_opts))
exe printf('syn match awiwiUrgentStart /^.*\ze\<\(%s\)\>/', awiwi#get_markers('urgent', marker_opts))
exe printf('syn match awiwiUrgent /\<\(%s\)\>/', awiwi#get_markers('urgent', marker_opts))

exe printf('syn match awiwiDelegate /(\?\(%s\)\([[:space:]]\+[^[:space:])]\+\)\{0,2})\?/', awiwi#get_markers('delegate', marker_opts))
syn match awiwiDelegate /@@[-a-zA-Z.,+_0-9@]\+[a-zA-Z0-9]/

let s:due_markers = awiwi#get_markers('due', marker_opts)
exe printf('syn match awiwiDue /\(\~\~\)\@<!\(%s\)\([[:space:]]\+[[:digit:]-.:]\+\)\{0,2}\|(\(%s\)\([[:space:]]\+[^[:space:])]\+\)*)/', s:due_markers, s:due_markers)

hi awiwiTodo cterm=bold ctermfg=3
hi awiwiUrgent cterm=bold ctermfg=190 ctermbg=3
hi awiwiUrgentStart ctermbg=237
hi awiwiUrgentEnd ctermbg=237
hi awiwiDelegate cterm=italic ctermfg=4
hi awiwiDue cterm=bold ctermfg=190

syn clear markdownListMarker
syn match awiwiList1 /^\@<=[-*] /
syn match awiwiList2 /\(^[[:space:]]\{2}\)\@<=[-*] /
hi awiwiList1 cterm=bold ctermfg=3
hi awiwiList2 cterm=bold ctermfg=31

syn match awiwiListBadSpaces /\(^[[:space:]]*[-*] \(\[[ x]\] \)\?\)\@<= \+/
syn match awiwiListBadSpacesAfterCheckbox /\(^[[:space:]]*[-*][[:space:]]\+\[[ x]\] \)\@<= \+/
hi awiwiListBadSpaces cterm=bold ctermbg=241
hi awiwiListBadSpacesAfterCheckbox cterm=bold ctermbg=241

syn match awiwiTaskListOpen1 /^\@<=[-*] \[ \]/
syn match awiwiTaskListOpen2 /\(^[[:space:]]\{2}\)\@<=[-*] \[ \]/
hi awiwiTaskListOpen1 cterm=bold ctermfg=3
hi awiwiTaskListOpen2 cterm=bold ctermfg=31

if str#endswith(&ft, '.todo')
  syn match awiwiTaskListDone /\(^[[:space:]]*\)\@<=[-*] \[x\].*$/
else
  syn match awiwiTaskListDone /\(^[[:space:]]*\)\@<=[-*] \[x\]/
end
hi awiwiTaskListDone ctermfg=241

syn match awiwiTaskDate /\(^[[:space:]]*\)\@<=\([-*] \[ \] .\+\)\@<=(from:\? [-0-9]\+)/
hi awiwiTaskDate cterm=italic ctermfg=247

if get(g:, 'awiwi_highlight_links', v:true)
  syn region awiwiLink
        \ start=/\(^\|[^[]\)\@<=\(^[-*] \+\)\@<!\[\S\@=/
        \ end=/\S\@<=)\($\|[^)]\)\@=/
        \ keepend
        \ contains=awiwiLinkStart,awiwiLinkName,awiwiLinkEnd,awiwiLinkInternalTarget,awiwiLinkProtocol,awiwiLinkDomain ",awiwiLinkTargetStart,awiwiLinkTargetEnd

  let conceal = get(g:, 'awiwi_conceal_links', v:true) ? 'conceal cchar=' : ''
  if conceal != ''
    let conceal_start_char = get(g:, 'awiwi_conceal_link_start_char', '▶')
    let conceal_end_char = get(g:, 'awiwi_conceal_link_start_char', ' ')
    let conceal_target_char = get(g:, 'awiwi_conceal_link_target_char', '…')
  else
    let [conceal_start_char, conceal_end_char, conceal_target_char] = ['', '', '']
  endif

  exe printf('syn match awiwiLinkStart  /\(^\|[^[]\)\@<=\[\(..\{-}]([^)].\{-})\)\@=/ contained %s%s', conceal, conceal_start_char)
  syn match awiwiLinkName   /\[\@<=.\{-}\(]([^)].\{-})\)\@=/
  exe printf('syn match awiwiLinkEnd    /\S\@<=\]\(([^)].\{-})\)\@=/                 contained %s%s', conceal, conceal_end_char)
  "syn match awiwiLinkTargetStart /\]\@<=(\([^)].\{-})\($\|[^)]\)\)\@=/   contained
  "syn match awiwiLinkTargetEnd /\]\@<=([^)].\{-})\($\|[^)]\)\@=/         contained
  if conceal != ''
    syn match awiwiLinkProtocol _\(\](\)\@<=https://\([^)].\{-})\($\|[^)]\)\)\@=_ contained conceal
  endif
  exe printf('syn match awiwiLinkDomain   _\(\](\(https://[^/]\+/\)\)\@<=[^)].\{-}\()$\|)[^)]\)\@=_  contained %s%s', conceal, conceal_target_char)
  exe printf('syn match awiwiLinkInternalTarget   _\(\](\)\@<=[^h)].\{-}\()$\|)[^h)]\)\@=_                   contained %s%s', conceal, conceal_target_char)

  let link_color = get(g:, 'awiwi_link_color', 142)
  let link_style = get(g:, 'awiwi_link_style', 'underline')
  for group in ['Name', 'Start', 'End']
    exe printf('hi awiwiLink%s cterm=%s ctermfg=%d', group, link_style, link_color)
  endfor
endif
