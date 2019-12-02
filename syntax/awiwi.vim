syn match awiwiTodo '\<\(TODO\|ASK\|CALL\|MAIL\|MAILTO\)\>'
syn match awiwiFixmeStart '^.*\ze\<FIXME\>'
syn match awiwiFixmeEnd '\(\<FIXME\>\)\@<=.\+$'
syn match awiwiFixme '\<FIXME\>'
syn match awiwiDelegate '(\?@todo [a-zA-Z0-9_-]\+)\?'
hi awiwiTodo cterm=bold ctermfg=3
hi awiwiFixme cterm=bold ctermfg=190 ctermbg=3
hi awiwiFixmeStart ctermbg=237
hi awiwiFixmeEnd ctermbg=237
hi awiwiDelegate cterm=italic ctermfg=4
