# dog food

## `Awiwi journal previous|next`

When `journal/2026/03/2026-06-03.md` is open, running `Awiwi journal previous` or `next` both fail:

```lua
Lua :command callback: AwiwiDateError: date 2026-06-23 not found
stack traceback:
        [C]: in function 'error'
        ...wi.vim/.claude/worktrees/lua-port-t10/lua/awiwi/date.lua:38: in function 'date_error'
        ...wi.vim/.claude/worktrees/lua-port-t10/lua/awiwi/date.lua:214: in function 'parse_date'
        ...wi.vim/.claude/worktrees/lua-port-t10/lua/awiwi/init.lua:222: in function 'edit_journal'
        ...iwi.vim/.claude/worktrees/lua-port-t10/lua/awiwi/cmd.lua:600: in function 'run'
        ...wi.vim/.claude/worktrees/lua-port-t10/ftplugin/awiwi.lua:30: in function <...wi.vim/.claude/worktrees/lua-port-t10/ftplugin/awiwi.lua:29>
```
`gn` or `gp` produce this error

## shortcuts that work

- `gC`
- `gT`
- `ge`
- `<F12>`

## syn hi

- todo list → end date works
- `redacted!!` - works only after executing `set ft=awiwi` manually, although on opening the journal file, the ft had already set to `awiwi` automatically
- fences don't work
- markers don't work

## other

- `set updatetime` and autosave on idle work
