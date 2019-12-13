let s:types = [
      \ 'todo',
      \ 'onhold',
      \ 'question'
      \ ]

let markers = []
for type in s:types
  call extend(markers, awiwi#get_markers(type, v:false))
endfor
syn case match
exe printf('syn match AwiwiTodo /\<\(%s\)\>/', join(markers, '\|'))

exe printf('syn match awiwiUrgentEnd /\(\<%s\>\)\@<=.\+$/', join(awiwi#get_markers('urgent', v:false), '\|'))
exe printf('syn match awiwiUrgentStart /^.*\ze\<\(%s\)\>/', join(awiwi#get_markers('urgent', v:false), '\|'))
exe printf('syn match awiwiUrgent /\<\(%s\)\>/', join(awiwi#get_markers('urgent', v:false), '\|'))

exe printf('syn match awiwiDelegate /(\?\(%s\)\([[:space:]]\+[^[:space:])]\+\)\{0,2})\?/', join(awiwi#get_markers('delegate', v:false), '\|'))

let s:due_markers = join(awiwi#get_markers('due', v:false), '\|')
exe printf('syn match awiwiDue /\(%s\)\([[:space:]]\+[[:digit:]-.:]\+\)\{0,2}\|(\(%s\)\([[:space:]]\+[^[:space:])]\+\)*)/', s:due_markers, s:due_markers)

syn region awiwiLink
      \ start=/\(^\|[^[]\)\@<=\[\S\@=/
    \ end=/\S\@<=)\($\|[^)]\)\@=/
      \ keepend
      \ contains=awiwiLinkStart,awiwiLinkName,awiwiLinkEnd,awiwiLinkTarget
syn match awiwiLinkStart  /\(^\|[^[]\)\@<=\[\S\@=/           contained conceal cchar=<
syn match awiwiLinkName   /\[\@<=.\{-}\]\@=/
syn match awiwiLinkEnd    /\S\@<=\](\@=/                     contained conceal cchar=>
syn match awiwiLinkTarget /\]\@<=([^h)].\{-})\($\|[^)]\)\@=/ contained conceal

hi awiwiTodo cterm=bold ctermfg=3
hi awiwiUrgent cterm=bold ctermfg=190 ctermbg=3
hi awiwiUrgentStart ctermbg=237
hi awiwiUrgentEnd ctermbg=237
hi awiwiDelegate cterm=italic ctermfg=4
hi awiwiDue cterm=bold ctermfg=190

hi awiwiLinkName cterm=bold ctermfg=142
hi awiwiLinkStart cterm=bold ctermfg=142
hi awiwiLinkEnd cterm=bold ctermfg=142
