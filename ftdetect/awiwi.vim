fun! s:add_code_block_textobject() abort "{{{
  vnoremap <buffer> aP :<C-u>call awiwi#util#select_code_block(v:true)<CR>
  vnoremap <buffer> iP :<C-u>call awiwi#util#select_code_block(v:false)<CR>
  onoremap <buffer> aP V:<C-u>call awiwi#util#select_code_block(v:true)<CR>
  onoremap <buffer> iP V:<C-u>call awiwi#util#select_code_block(v:false)<CR>
endfun "}}}


augroup awiwiFtDetect
  au!

  au BufRead *.md call s:add_code_block_textobject()

  exe printf('au BufWinEnter %s/journal/**/*.md setlocal filetype=markdown.awiwi', g:awiwi_home)

  let s:au_assets = [
        \ printf('au BufWinEnter %s/assets/**/*', g:awiwi_home),
        \ 'if !empty(&filetype) && !str#endswith(&filetype, ".awiwi")',
        \ '  | exe "setlocal filetype=".&filetype.".awiwi"',
        \ '| else',
        \ '  | exe "setlocal filetype=awiwi"',
        \ '| endif'
        \ ]
  exe join(s:au_assets, ' ')

  exe printf('au BufWinEnter %s/journal/todos.md setlocal filetype=markdown.awiwi.todo', g:awiwi_home)
augroup END
