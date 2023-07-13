if get(b:, 'current_syntax', '') ==# 'awiwi'
  finish
endif

unlet! b:current_syntax
runtime! syntax/markdown.vim

let b:current_syntax = 'awiwi'

hi  awiwiUrgent                      guifg=#d7ff00  guibg=#807000 gui=bold
hi  awiwiDelegate                    guifg=#20e020                gui=italic
hi  awiwiDue                         guifg=#d7ff00                gui=bold
hi  awiwiList1                       guifg=#808000                gui=bold
hi  awiwiList2                       guifg=#0087af                gui=bold
hi  awiwiListBadSpaces               guibg=#626262                gui=bold
hi  awiwiListBadSpacesAfterCheckbox  guibg=#626262                gui=bold
hi  awiwiTaskListOpen1               guifg=#808000                gui=bold
hi  awiwiTaskListOpen2               guifg=#0087af                gui=bold
hi  awiwiFileTypePrefix              guifg=#9e9e9e
hi  awiwiFileType                    guifg=#808000     gui=bold
hi  awiwiLinkPath                    guifg=#9e9e9e
hi  awiwiRedminePath                 guifg=#9e9e9e
hi  awiwiRedactedCause               guifg=#8a8a8a  gui=bold
hi  link                             awiwiRedactedTag  awiwiUrgent

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
  if a:hi =~# '='
    exe printf('hi %s %s', a:name, a:hi)
  else
    exe printf('hi link %s %s', a:name, a:hi)
  endif
endfun "}}}


fun! s:tagInHeader(name, tag, hi, ...) abort "{{{
  let pattern = printf('/\C\([[:space:]]\|^\)\zs\(%s\)\([[:space:]]\|$\)\@=/', a:tag)
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
  let pattern = '/\C\([[:space:]]\|^\)\zs\(%s\)\([[:space:]]\|$\)\@=/'
  let args = [a:name, pattern, a:marker, a:hi]
  call extend(args, a:000)
  return call('s:inHeaderWithMarkers', args)
endfun "}}}

syn region awiwiRedacted
      \ start=/\C!!redacted/
      \ end=/$/
      \ keepend
      \ contains=awiwiRedactedTag,awiwiRedactedCause
      \ containedin=markdownH1,markdownH2,markdownH3,markdownH4,markdownH5,markdownH6,markdownCode

syn match awiwiRedactedTag /\C\!!redacted/ containedin=awiwiRedacted contained
syn match awiwiRedactedCause /[[:space:]]\+.*/ containedin=awiwiRedacted contained

call s:tagInHeader('awiwiChange', '@change', 'awiwiUrgent')
call s:tagInHeader('awiwiIncident', '@incident', 'awiwiUrgent')
call s:tagInHeader('awiwiIssue', '@issue', 'awiwiUrgent')
call s:tagInHeader('awiwiBug', '@bug', 'awiwiUrgent')
call s:inHeaderWithSimpleMarkers('awiwiTodo', 'todo', 'gui=bold guifg=#808000')
call s:inHeaderWithSimpleMarkers('awiwiQuestionn', 'question', 'gui=bold guifg=#808000')
call s:inHeaderWithSimpleMarkers('awiwiOnHole', 'onhold', 'gui=bold guifg=#808000')

let markers = []
let marker_opts = {'escape_mode': 'vim'}

exe printf('syn match awiwiUrgent /\C\<%s\>/ contains=markdownCode,markdownCodeBlock,markdownCodeDelimiter', awiwi#get_markers('urgent', marker_opts))

syn match awiwiDelegate /\C@@[-a-zA-Z.,+_0-9@]\+[a-zA-Z0-9]/

exe printf('syn match awiwiDue /\C\<%s\>/ contains=markdownCode,markdownCodeBlock,markdownCodeDelimiter', awiwi#get_markers('due', marker_opts))

syn clear markdownListMarker
syn match awiwiList1 /\C^[-*] /
syn match awiwiList2 /\C\(^[[:space:]]\{2}\)\zs[-*] /
syn match awiwiCanceledList /\C\(^[[:space:]]\{0,2}\)\zs[-*] \~\~.*/ contains=markdownStrike,markdownStrikeDelimiter

syn match awiwiListBadSpaces /\C\(^[[:space:]]*[-*] \(\[[ x]\] \)\?\)\zs \+/
syn match awiwiListBadSpacesAfterCheckbox /\C\(^[[:space:]]*[-*][[:space:]]\+\[[ x]\] \)\zs \+/

syn match awiwiTaskListOpen1 /\C^\zs[-*] \[ \]/
syn match awiwiTaskListOpen2 /\C\(^[[:space:]]\{2}\)\zs[-*] \[ \]/

if awiwi#str#endswith(&ft, '.todo')
  syn match awiwiTaskDate /\s*{"[^}]\+}$/ conceal
  hi awiwiCreatedDate   guifg=#585858 gui=italic
  hi awiwiFutureDueDate guifg=#5fd700 gui=bold
  hi awiwiNearDueDate   guifg=#d7ff00 gui=bold   guibg=#5f0000
end
hi link awiwiTaskListDone htmlStrike
hi link awiwiCanceledList htmlStrike
syn match awiwiTaskListDone /\C\(^[[:space:]]*\)\zs[-*] \[x\].\{-} \?\ze\s*\({\|$\)/

if get(g:, 'awiwi_highlight_links', v:true)
  syn region awiwiLink
        \ start=/\C\[\([ x]*\]\)\@!/
        \ end=/\C[^)]\zs)/
        \ keepend
        \ oneline
        \ contains=awiwiLinkNameBlock
        \ containedin=markdownH1,markdownH2,markdownH3,markdownH4,markdownH5,markdownH6,awiwiList1,awiwiList2,awiwiTaskListOpen1,awiwiTaskListOpen2,markdownList,markdownListMarker

  syn region awiwiLinkNameBlock
        \ start=/\C\[/
        \ end=/\C\](\@=/
        \ keepend
        \ contained
        \ oneline
        \ contains=awiwiLinkNameStart
        \ nextgroup=awiwiLinkUrlBlock

  syn region awiwiLinkUrlBlock
        \ start=/\C(/
        \ end=/\C)/
        \ keepend
        \ contained
        \ oneline
        \ contains=awiwiLinkUrlStart

  let conceal = get(g:, 'awiwi_conceal_links', v:true)
  if conceal

    fun! s:conceal(char) abort "{{{
      if empty(a:char)
        return 'conceal'
      endif
      return printf('conceal cchar=%s', a:char)
    endfun "}}}

  else

    fun! s:conceal(char) abort "{{{
      return ''
    endfun "}}}

  endif

  let conceal_start_char = get(g:, 'awiwi_conceal_link_start_char', '▶')
  let conceal_end_char = get(g:, 'awiwi_conceal_link_start_char', ' ')
  let conceal_target_char = get(g:, 'awiwi_conceal_link_target_char', '')
  let conceal_internal_target_char = get(g:, 'awiwi_conceal_link_internal_target_char', '…')

  let domain_color = get(g:, 'awiwi_domain_color', '#808080')
  let link_color = get(g:, 'awiwi_link_color', '#afaf00')
  let link_style = get(g:, 'awiwi_link_style', 'underline')

  exe printf('syn match awiwiLinkNameStart /\C\[/ nextgroup=awiwiLinkName oneline contained containedin=awiwiLinkNameBlock %s', s:conceal(conceal_start_char))
  syn match awiwiLinkName /\C[^[\]]\+/ oneline containedin=awiwiLinkNameBlock contained nextgroup=awiwiLinkNameEnd
  exe printf('syn match awiwiLinkNameEnd    /\C]/  oneline contained containedin=awiwiLinkNameBlock %s nextgroup=awiwiLinkUrlBlock', s:conceal(conceal_end_char))

  syn match awiwiLinkUrlStart /(/ oneline contained containedin=awiwiLinkUrlBlock nextgroup=awiwiLinkInternalTarget,awiwiLinkProtocol

  if conceal
    syn match awiwiLinkProtocol _\Chttps\?://\(www\.\)\?_ oneline contained conceal containedin=awiwiLinkUrlBlock nextgroup=awiwiLinkDomain
  else
    syn match awiwiLinkProtocol _\Chttps\?://\(www\.\)\?_ contained containedin=awiwiLinkUrlBlock nextgroup=awiwiLinkDomain
    exe printd('hi awiwiLinkProtocol guifg=%s', domain_color)
  endif
  syn match awiwiLinkDomain _[^/)]\+_ oneline contained nextgroup=awiwiLinkUrlEnd,awiwiLinkPath
  exe printf('syn match awiwiLinkPath  _/[^)]*_ oneline contained containedin=awiwiLinkUrlBlock %s nextgroup=awiwiLinkUrlEnd', s:conceal(conceal_target_char))
  exe printf('syn match awiwiLinkInternalTarget  _[./][^)]\+_  oneline contained containedin=awiwiLink %s nextgroup=awiwiLinkUrlEnd', s:conceal(conceal_internal_target_char))

  syn match awiwiLinkUrlEnd          /)/                                          oneline contained containedin=awiwiLinkUrlBlock

  syn match awiwiRedmineIssue /\(^\|\s\)\zs#[0-9]\{5,}/ oneline containedin=markdownH1,markdownH2,markdownH3,markdownH4,markdownH5,markdownH6,awiwiList1,awiwiList2,awiwiTaskListOpen1,awiwiTaskListOpen2,markdownList,markdownListMarker
  exe printf('hi awiwiRedmineIssue gui=bold guifg=%s', link_color)

  for group in ['Name', 'Start', 'End']
    exe printf('hi awiwiLink%s gui=%s guifg=%s', group, link_style, link_color)
  endfor

  for group in ['Domain', 'UrlStart', 'UrlEnd']
    exe printf('hi awiwiLink%s guifg=%s', group, domain_color)
  endfor
endif

syn match awiwiFileTypeBlock  /\C^[^a-zA-Z0-9_]*vim: ft=[a-z].*$/ contains=awiwiFileTypePrefix,awiwiFileType
syn match awiwiFileTypePrefix /\C\(^[^a-zA-Z0-9_]*\)\zsvim: ft?\( [a-z].*\)\@=/  contained
syn match awiwiFileType       /\C\(^[^a-zA-Z0-9_]*vim: ft=\)\zs[a-z].*$/        contained

exe printf('hi awiwiDateOverlay guifg=%s', link_color)
