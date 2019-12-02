augroup awiwi
  au!
  exe printf('au! BufEnter %s/journal/**/*.md setlocal filetype=markdown.awiwi', g:awiwi_home)
  let s:au_assets = [
        \ printf('au! BufEnter %s/assets/**/*', g:awiwi_home),
        \ 'if !str#endswith(&filetype, ".awiwi")',
        \ 'exe "setlocal filetype=".&filetype.".awiwi"',
        \ 'endif'
        \ ]
  exe join(s:au_assets, ' | ')
  exe printf('au! BufEnter %s/journal/todos.md setlocal filetype=markdown.awiwi.todo', g:awiwi_home)
augroup END
