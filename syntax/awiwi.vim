let s:types = [
      \ 'todo',
      \ 'onhold',
      \ 'question'
      \ ]

let markers = []
for type in s:types
  call extend(markers, awiwi#get_markers(type, v:false))
endfor
exe printf('syn match AwiwiTodo /\<\(%s\)\>/', join(markers, '\|'))

exe printf('syn match awiwiUrgentEnd /\(\<%s\>\)\@<=.\+$/', join(awiwi#get_markers('urgent', v:false), '\'))
exe printf('syn match awiwiUrgentStart /^.*\ze\<\(%s\)\>/', join(awiwi#get_markers('urgent', v:false), '\|'))
exe printf('syn match awiwiUrgent /\<\(%s\)\>/', join(awiwi#get_markers('urgent', v:false), '\|'))

exe printf('syn match awiwiDelegate /(\?\(%s\)\( \S\+\)\{0,2})\?/', join(awiwi#get_markers('delegate', v:false), '\|'))
exe printf('syn match awiwiDue /(\?\(%s\)\([[:space:]]\+\S\+\)*)\?/', join(awiwi#get_markers('due', v:false), '\|'))


hi awiwiTodo cterm=bold ctermfg=3
hi awiwiUrgent cterm=bold ctermfg=190 ctermbg=3
hi awiwiUrgentStart ctermbg=237
hi awiwiUrgentEnd ctermbg=237
hi awiwiDelegate cterm=italic ctermfg=4
hi awiwiDue cterm=bold ctermfg=190
