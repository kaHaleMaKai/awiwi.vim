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
exe printf('syn match AwiwiTodo /\<\(%s\)\([[:space:]]\|$\)\@=/', join(markers, '\|'))

exe printf('syn match awiwiUrgentEnd /\(\<%s\>\)\@<=.\+$/', awiwi#get_markers('urgent', marker_opts))
exe printf('syn match awiwiUrgentStart /^.*\ze\<\(%s\)\>/', awiwi#get_markers('urgent', marker_opts))
exe printf('syn match awiwiUrgent /\<\(%s\)\>/', awiwi#get_markers('urgent', marker_opts))

exe printf('syn match awiwiDelegate /(\?\(%s\)\([[:space:]]\+[^[:space:])]\+\)\{0,2})\?/', awiwi#get_markers('delegate', marker_opts))

let s:due_markers = awiwi#get_markers('due', marker_opts)
exe printf('syn match awiwiDue /\(\~\~\)\@<!\(%s\)\([[:space:]]\+[[:digit:]-.:]\+\)\{0,2}\|(\(%s\)\([[:space:]]\+[^[:space:])]\+\)*)/', s:due_markers, s:due_markers)

hi awiwiTodo cterm=bold ctermfg=3
hi awiwiUrgent cterm=bold ctermfg=190 ctermbg=3
hi awiwiUrgentStart ctermbg=237
hi awiwiUrgentEnd ctermbg=237
hi awiwiDelegate cterm=italic ctermfg=4
hi awiwiDue cterm=bold ctermfg=190

syn match awiwiTaskListOpen /^[-*] \[ \]$\@!/
hi awiwiTaskListOpen cterm=bold ctermfg=3

if str#endswith(&ft, '.todo')
  syn match awiwiTaskListDone /^[-*] \[x\].*$/
  hi awiwiTaskListDone ctermfg=241
else
  syn match awiwiTaskListDone /^[-*] \[x\]$\@!/
  hi awiwiTaskListDone ctermfg=241
end

syn match awiwiTaskDate /\(^[-*] \[ \] .\+\)\@<=(from:\? [-0-9]\+)/
hi awiwiTaskDate cterm=italic ctermfg=247

if get(g:, 'awiwi_highlight_links', v:true)
  syn region awiwiLink
        \ start=/\(^\|[^[]\)\@<=\(^[-*] \+\)\@<!\[\S\@=/
        \ end=/\S\@<=)\($\|[^)]\)\@=/
        \ keepend
        \ contains=awiwiLinkStart,awiwiLinkName,awiwiLinkEnd,awiwiLinkTarget,awiwiLinkStart,awiwiLinkEnd

  let conceal = get(g:, 'awiwi_conceal_links', v:true) ? 'conceal cchar=' : ''
  if conceal != ''
    let conceal_start_char = get(g:, 'awiwi_conceal_link_start_char', '▶')
    let conceal_end_char = get(g:, 'awiwi_conceal_link_start_char', ' ')
    let conceal_target_char = get(g:, 'awiwi_conceal_link_target_char', '…')
  else
    let [conceal_start_char, conceal_end_char, conceal_target_char] = ['', '', '']
  endif

  exe printf('syn match awiwiLinkStart  /\(^\|[^[]\)\@<=\[\(..\{-}]([^h)].\{-})\)\@=/ contained %s%s', conceal, conceal_start_char)
  syn match awiwiLinkName   /\[\@<=.\{-}\(]([^h)].\{-})\)\@=/
  exe printf('syn match awiwiLinkEnd    /\S\@<=\]\(([^h)].\{-})\)\@=/                 contained %s%s', conceal, conceal_end_char)
  syn match awiwiLinkTargetStart /\]\@<=(\([^h)].\{-})\($\|[^)]\)\)\@=/   contained
  syn match awiwiLinkTargetEnd /\]\@<=([^h)].\{-})\($\|[^)]\)\@=/         contained
  exe printf('syn match awiwiLinkTarget /\(\](\)\@<=[^h)].\{-}\()$\|)[^)]\)\@=/       contained %s%s', conceal, conceal_target_char)

  let link_color = get(g:, 'awiwi_link_color', 142)
  let link_style = get(g:, 'awiwi_link_style', 'underline')
  for group in ['Name', 'Start', 'End']
    exe printf('hi awiwiLink%s cterm=%s ctermfg=%d', group, link_style, link_color)
  endfor
endif
