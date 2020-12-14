let s:headers = join(map(range(1, 6), {_, v -> printf('markdownH%d', v)}), ',')

fun! s:inHeader(name, pattern, hi, ...) abort "{{{
  let cmd = ['syn', 'match', '%s', '%s', 'containedin=%s']
  for arg in a:000
    call add(cmd, '%s')
  endfor
  let args = [join(cmd, ' ')]
  call extend(args, [a:name, a:pattern, copy(s:headers)])
  call extend(args, a:000)
  exe call('printf', args)
  exe printf('hi %s %s', a:name, a:hi)
endfun "}}}


fun! s:tagInHeader(name, tag, hi, ...) abort "{{{
  let pattern = printf('/\C\([[:space:]]\|^\)\@<=\(%s\)\([[:space:]]\|$\)\@=/', a:tag)
  let args = [a:name, pattern, a:hi]
  call extend(args, a:000)
  return call('s:inHeader', args)
endfun "}}}


fun! s:tagsInHeader(name, tags, hi, ...) abort "{{{
  let tag = join(a:tags, '\|')
  let args = [a:name, tag, a:hi]
  call extend(args, a:000)
  return call('s:tagInHeader', args)
endfun


fun! s:inHeaderWithMarkers(name, pattern, marker, hi, ...) abort "{{{
  let marker_opts = {'escape_mode': 'vim'}
  let args = [a:pattern]
  call add(args, awiwi#get_markers(a:marker, marker_opts))
  let pattern = call('printf', args)
  let fn_args = [a:name, pattern, a:hi]
  call extend(fn_args, a:000)
  return call('s:inHeader', fn_args)
endfun "}}}


fun! s:inHeaderWithSimpleMarkers(name, marker, hi, ...) abort "{{{
  let pattern = '/\C\([[:space:]]\|^\)\@<=\(%s\)\([[:space:]]\|$\)\@=/'
  let args = [a:name, pattern, a:marker, a:hi]
  call extend(args, a:000)
  return call('s:inHeaderWithMarkers', args)
endfun "}}}

syn match awiwiRedacted /\C\([[:space:]]\|^\)\@<=\(!!redacted\)\([[:space:]]\|$\)\@=/ containedin=markdownH1,markdownH2,markdownH3,markdownH4,markdownH5,markdownH6,markdownCode
hi awiwiRedacted ctermfg=190 ctermbg=3
syn match awiwiRedactedCause /\C\(\([[:space:]]\|^\)!!redacted[[:space:]]\+\)\@<=.*$/ containedin=markdownH1,markdownH2,markdownH3,markdownH4,markdownH5,markdownH6,markdownCode
hi awiwiRedactedCause cterm=bold ctermfg=245

call s:tagInHeader('awiwiIncident', '@incident', 'ctermfg=190 ctermbg=3')
call s:tagInHeader('awiwiIncident', '@incident', 'ctermfg=190 ctermbg=3')
call s:inHeaderWithSimpleMarkers('awiwiTodo', 'todo', 'cterm=bold ctermfg=3')
call s:inHeaderWithSimpleMarkers('awiwiQuestionn', 'question', 'cterm=bold ctermfg=3')
call s:inHeaderWithSimpleMarkers('awiwiOnHole', 'onhold', 'cterm=bold ctermfg=3')

let markers = []
let marker_opts = {'escape_mode': 'vim'}

exe printf('syn match awiwiUrgent /\C\<%s\>/ contains=markdownCode,markdownCodeBlock,markdownCodeDelimiter', awiwi#get_markers('urgent', marker_opts))

syn match awiwiDelegate /\C@@[-a-zA-Z.,+_0-9@]\+[a-zA-Z0-9]/

exe printf('syn match awiwiDue /\C\<%s\>/ contains=markdownCode,markdownCodeBlock,markdownCodeDelimiter', awiwi#get_markers('due', marker_opts))

hi awiwiUrgent cterm=bold ctermfg=190 ctermbg=3
hi awiwiDelegate cterm=italic ctermfg=4
hi awiwiDue cterm=bold ctermfg=190

syn clear markdownListMarker
syn match awiwiList1 /\C^\@<=[-*] /
syn match awiwiList2 /\C\(^[[:space:]]\{2}\)\@<=[-*] /
hi awiwiList1 cterm=bold ctermfg=3
hi awiwiList2 cterm=bold ctermfg=31

syn match awiwiListBadSpaces /\C\(^[[:space:]]*[-*] \(\[[ x]\] \)\?\)\@<= \+/
syn match awiwiListBadSpacesAfterCheckbox /\C\(^[[:space:]]*[-*][[:space:]]\+\[[ x]\] \)\@<= \+/
hi awiwiListBadSpaces cterm=bold ctermbg=241
hi awiwiListBadSpacesAfterCheckbox cterm=bold ctermbg=241

syn match awiwiTaskListOpen1 /\C^\@<=[-*] \[ \]/
syn match awiwiTaskListOpen2 /\C\(^[[:space:]]\{2}\)\@<=[-*] \[ \]/
hi awiwiTaskListOpen1 cterm=bold ctermfg=3
hi awiwiTaskListOpen2 cterm=bold ctermfg=31

if str#endswith(&ft, '.todo')
  syn match awiwiTaskListDone /\C\(^[[:space:]]*\)\@<=[-*] \[x\].*$/
else
  syn match awiwiTaskListDone /\C\(^[[:space:]]*\)\@<=[-*] \[x\]/
end
hi awiwiTaskListDone ctermfg=241

syn match awiwiTaskDate /\C\(^[[:space:]]*\)\@<=\([-*] \[ \] .\+\)\@<=(from:\? [-0-9]\+)/
hi awiwiTaskDate cterm=italic ctermfg=247

if get(g:, 'awiwi_highlight_links', v:true)
  syn region awiwiLink
        \ start=/\C\(^\|[^[]\)\@<=\(^[-*] \+\)\@<!\[\S\@=/
        \ end=/\C\S\@<=)\($\|[^)]\)\@=/
        \ keepend
        \ contains=awiwiLinkStart,awiwiLinkName,awiwiLinkEnd,awiwiLinkInternalTarget,awiwiLinkProtocol,awiwiLinkDomain ",awiwiLinkTargetStart,awiwiLinkTargetEnd
        \ containedin=markdownH1,markdownH2,markdownH3,markdownH4,markdownH5,markdownH6

  let conceal = get(g:, 'awiwi_conceal_links', v:true) ? 'conceal cchar=' : ''
  if conceal != ''
    let conceal_start_char = get(g:, 'awiwi_conceal_link_start_char', '▶')
    let conceal_end_char = get(g:, 'awiwi_conceal_link_start_char', ' ')
    let conceal_target_char = get(g:, 'awiwi_conceal_link_target_char', '…')
  else
    let [conceal_start_char, conceal_end_char, conceal_target_char] = ['', '', '']
  endif

  exe printf('syn match awiwiLinkStart  /\C\(^\|[^[]\)\@<=\[\(..\{-}]([^)].\{-})\)\@=/ contained containedin=%s %s%s', s:headers, conceal, conceal_start_char)
  syn match awiwiLinkName   /\C\[\@<=.\{-}\(]([^)].\{-})\)\@=/ containedin=markdownH1,markdownH2,markdownH3,markdownH4,markdownH5,markdownH6
  exe printf('syn match awiwiLinkEnd    /\C\S\@<=\]\(([^)].\{-})\)\@=/                 contained containedin=%s %s%s', s:headers, conceal, conceal_end_char)
  "syn match awiwiLinkTargetStart /\C\]\@<=(\([^)].\{-})\($\|[^)]\)\)\@=/   contained
  "syn match awiwiLinkTargetEnd /\C\]\@<=([^)].\{-})\($\|[^)]\)\@=/         contained
  if conceal != ''
    syn match awiwiLinkProtocol _\C\(\](\)\@<=https\?://\([^)].\{-})\($\|[^)]\)\)\@=_ contained conceal containedin=markdownH1,markdownH2,markdownH3,markdownH4,markdownH5,markdownH6
  endif
  " FIXME for redmine, it would be great only to show the issue id with a hashtag in front
  " exe printf('syn match awiwiLinkDomain   _\(\](https://redmine.pmd5.org/issues/\)\@<=[0-9]\+\()$\|)[^)]\)\@=_  contained containedin=%s %s%s', s:headers, conceal, conceal_target_char)
  exe printf('syn match awiwiLinkDomain   _\C\(\](\(https://[^/]\+/\)\)\@<=[^)].\{-}\()$\|)[^)]\)\@=_  contained containedin=%s %s%s', s:headers, conceal, conceal_target_char)
  exe printf('syn match awiwiLinkInternalTarget   _\C\(\](\)\@<=[^h)].\{-}\()$\|)[^h)]\)\@=_           contained containedin=%s %s%s', s:headers, conceal, conceal_target_char)

  let link_color = get(g:, 'awiwi_link_color', 142)
  let link_style = get(g:, 'awiwi_link_style', 'underline')
  for group in ['Name', 'Start', 'End']
    exe printf('hi awiwiLink%s cterm=%s ctermfg=%d', group, link_style, link_color)
  endfor
endif

syn match awiwiFileTypeBlock  /\C^[^a-zA-Z0-9_]*vim: ft=[a-z].*$/ contains=awiwiFileTypePrefix,awiwiFileType
syn match awiwiFileTypePrefix /\C\(^[^a-zA-Z0-9_]*\)\@<=vim: ft?\( [a-z].*\)\@=/  contained
syn match awiwiFileType       /\C\(^[^a-zA-Z0-9_]*vim: ft=\)\@<=[a-z].*$/        contained
hi awiwiFileTypePrefix ctermfg=247
hi awiwiFileType       ctermfg=3   cterm=bold
