fun! s:add_code_block_textobject() abort "{{{
  vnoremap <buffer> aP :<C-u>call awiwi#util#select_code_block(v:true)<CR>
  vnoremap <buffer> iP :<C-u>call awiwi#util#select_code_block(v:false)<CR>
  onoremap <buffer> aP V:<C-u>call awiwi#util#select_code_block(v:true)<CR>
  onoremap <buffer> iP V:<C-u>call awiwi#util#select_code_block(v:false)<CR>
endfun "}}}


fun! s:add_awiwi_filetype(type, ...) abort "{{{
  let suffix = a:type
  if empty(&ft)
    let ft = a:0 ? printf('%s.%s', a:1, suffix) : suffix
  elseif &ft == 'markdown'
    let ft = printf('%s.%s', &ft, suffix)
  else
    return
  endif
  exe printf('setlocal ft=%s', ft)
endfun "}}}


augroup awiwiFtDetect
  au!
  au BufRead *.md call s:add_code_block_textobject()
  exe printf('au BufWinEnter %s/journal/**/*.md    call <sid>add_awiwi_filetype("awiwi")', g:awiwi_home)
  exe printf('au BufWinEnter %s/assets/**/*        call <sid>add_awiwi_filetype("awiwi.asset",  "markdown")', g:awiwi_home)
  exe printf('au BufWinEnter %s/recipes/*          call <sid>add_awiwi_filetype("awiwi-recipe", "markdown")', g:awiwi_home)
  exe printf('au BufWinEnter %s/recipes/**/*       call <sid>add_awiwi_filetype("awiwi-recipe", "markdown")', g:awiwi_home)
  exe printf('au BufWinEnter %s/journal/todos.md   call <sid>add_awiwi_filetype("awiwi.todo")', g:awiwi_home)
augroup END
