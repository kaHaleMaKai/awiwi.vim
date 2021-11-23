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
hi awiwiRedactedTag ctermfg=190 ctermbg=3
syn match awiwiRedactedCause /[[:space:]]\+.*/ containedin=awiwiRedacted contained
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
syn match awiwiList1 /\C^[-*] /
syn match awiwiList2 /\C\(^[[:space:]]\{2}\)\zs[-*] /
hi awiwiList1 cterm=bold ctermfg=3
hi awiwiList2 cterm=bold ctermfg=31

syn match awiwiListBadSpaces /\C\(^[[:space:]]*[-*] \(\[[ x]\] \)\?\)\zs \+/
syn match awiwiListBadSpacesAfterCheckbox /\C\(^[[:space:]]*[-*][[:space:]]\+\[[ x]\] \)\zs \+/
hi awiwiListBadSpaces cterm=bold ctermbg=241
hi awiwiListBadSpacesAfterCheckbox cterm=bold ctermbg=241

syn match awiwiTaskListOpen1 /\C^\zs[-*] \[ \]/
syn match awiwiTaskListOpen2 /\C\(^[[:space:]]\{2}\)\zs[-*] \[ \]/
hi awiwiTaskListOpen1 cterm=bold ctermfg=3
hi awiwiTaskListOpen2 cterm=bold ctermfg=31

if awiwi#str#endswith(&ft, '.todo')
  syn match awiwiTaskDate /\s\+{"[^}]\+}$/ conceal
  hi awiwiCreatedDate   ctermfg=240 cterm=italic
  hi awiwiFutureDueDate ctermfg=76  cterm=bold
  hi awiwiNearDueDate   ctermfg=190 cterm=bold   ctermbg=52
end
hi awiwiTaskListDone ctermfg=241 cterm=strikethrough
syn match awiwiTaskListDone /\C\(^[[:space:]]*\)\zs[-*] \[x\].\{-}\ze\s\+\({\|$\)/

if get(g:, 'awiwi_highlight_links', v:true)
  syn region awiwiLink
        \ start=/\C\[\([ x]*\]\)\@!/
        \ end=/\C[^)]\zs)/
        \ keepend
        \ contains=awiwiLinkNameBlock
        \ containedin=markdownH1,markdownH2,markdownH3,markdownH4,markdownH5,markdownH6,awiwiList1,awiwiList2,awiwiTaskListOpen1,awiwiTaskListOpen2,markdownList,markdownListMarker

  syn region awiwiLinkNameBlock
        \ start=/\C\[/
        \ end=/\C\]/
        \ keepend
        \ contained
        \ containedin=awiwiLink
        \ contains=awiwiLinkNameStart
        \ nextgroup=awiwiLinkUrlBlock

  syn region awiwiLinkUrlBlock
        \ start=/\C(/
        \ end=/\C)/
        \ keepend
        \ contained
        \ containedin=awiwiLink
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

  let domain_color = get(g:, 'awiwi_domain_color', 244)
  let link_color = get(g:, 'awiwi_link_color', 142)
  let link_style = get(g:, 'awiwi_link_style', 'underline')

  exe printf('syn match awiwiLinkNameStart /\C\[/ nextgroup=awiwiLinkName contained containedin=awiwiLinkNameBlock %s', s:conceal(conceal_start_char))
  syn match awiwiLinkName /\C[^[\]]\+/ containedin=awiwiLinkNameBlock contained nextgroup=awiwiLinkNameEnd
  exe printf('syn match awiwiLinkNameEnd    /\C]/  contained containedin=awiwiLinkNameBlock %s nextgroup=awiwiLinkUrlBlock', s:conceal(conceal_end_char))

  syn match awiwiLinkUrlStart /(/ contained containedin=awiwiLinkUrlBlock nextgroup=awiwiLinkInternalTarget,awiwiLinkProtocol

  if conceal
    syn match awiwiLinkProtocol _\Chttps\?://\(www\.\)\?_ contained conceal containedin=awiwiLinkUrlBlock nextgroup=awiwiLinkDomain
  else
    syn match awiwiLinkProtocol _\Chttps\?://\(www\.\)\?_ contained containedin=awiwiLinkUrlBlock nextgroup=awiwiLinkDomain
    exe printd('hi awiwiLinkProtocol ctermfg=%s', domain_color)
  endif
  syn match awiwiLinkDomain _[^/)]\+_ contained nextgroup=awiwiLinkUrlEnd,awiwiLinkPath
  exe printf('syn match awiwiLinkPath  _/[^)]*_ contained containedin=awiwiLinkUrlBlock %s nextgroup=awiwiLinkUrlEnd', s:conceal(conceal_target_char))
  exe printf('syn match awiwiLinkInternalTarget  _[./][^)]\+_  contained containedin=awiwiLink %s nextgroup=awiwiLinkUrlEnd', s:conceal(conceal_internal_target_char))

  syn match awiwiLinkUrlEnd          /)/                                          contained containedin=awiwiLinkUrlBlock

  syn match awiwiRedmineIssue /\(^\|\s\)\zs#[0-9]\{5,}/ containedin=markdownH1,markdownH2,markdownH3,markdownH4,markdownH5,markdownH6,awiwiList1,awiwiList2,awiwiTaskListOpen1,awiwiTaskListOpen2,markdownList,markdownListMarker
  exe printf('hi awiwiRedmineIssue cterm=bold ctermfg=%s', link_color)

  for group in ['Name', 'Start', 'End']
    exe printf('hi awiwiLink%s cterm=%s ctermfg=%d', group, link_style, link_color)
  endfor

  for group in ['Domain', 'UrlStart', 'UrlEnd']
    exe printf('hi awiwiLink%s   ctermfg=%d', group, domain_color)
  endfor
endif

syn match awiwiFileTypeBlock  /\C^[^a-zA-Z0-9_]*vim: ft=[a-z].*$/ contains=awiwiFileTypePrefix,awiwiFileType
syn match awiwiFileTypePrefix /\C\(^[^a-zA-Z0-9_]*\)\zsvim: ft?\( [a-z].*\)\@=/  contained
syn match awiwiFileType       /\C\(^[^a-zA-Z0-9_]*vim: ft=\)\zs[a-z].*$/        contained
hi awiwiFileTypePrefix ctermfg=247
hi awiwiFileType       ctermfg=3   cterm=bold
hi awiwiLinkPath       ctermfg=247
hi awiwiRedminePath    ctermfg=247
