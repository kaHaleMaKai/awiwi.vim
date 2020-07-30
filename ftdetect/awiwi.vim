augroup awiwiFtDetect
  au!
  exe printf('au! BufWinEnter %s/journal/**/*.md setlocal filetype=markdown.awiwi', g:awiwi_home)
  let s:au_assets = [
        \ printf('au! BufWinEnter %s/assets/**/*', g:awiwi_home),
        \ 'echoerr expand("%:p") . " " . getfsize(expand("%:p")) . " " . !empty(&filetype) . " " . !str#endswith(&filetype, ".awiwi")',
        \ 'if !empty(&filetype) && !str#endswith(&filetype, ".awiwi")',
        \ 'exe "setlocal filetype=".&filetype.".awiwi"',
        \ 'endif'
        \ ]
  exe join(s:au_assets, ' | ')
  exe printf('au! BufWinEnter %s/journal/todos.md setlocal filetype=markdown.awiwi.todo', g:awiwi_home)
augroup END
