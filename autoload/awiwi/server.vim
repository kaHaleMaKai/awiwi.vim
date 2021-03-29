let s:server_started = v:false
let s:server_host = ''
let s:server_port = ''
let s:server_job_id = -1
let s:server_logs = {"stdout": [], "stderr": [], "exit": []}
let s:default_port = '5823'


fun! awiwi#server#get_default_port() abort "{{{
  return s:default_port
endfun "}}}


fun! s:write_json_config() abort "{{{
  let config_file = awiwi#path#join(g:awiwi_home, 'config.json')
  let conf = {
        \ 'search_engine': g:awiwi_search_engine,
        \ 'home': g:awiwi_home,
        \ 'screensaver': g:awiwi_screensaver,
        \ 'link_color': g:awiwi_link_color,
        \ }
  for marker in ['todo', 'onhold', 'urgent', 'delegate', 'question', 'due']
    let m = printf('%s_markers', marker)
    let conf[m] = awiwi#get_markers(marker, {"join": v:false})
  endfor
  let content = [json_encode(conf)]
  call writefile(content, config_file)
endfun "}}}


fun! awiwi#server#server_logs(...) abort "{{{
  let key = get(a:000, 0, '')
  if empty(key)
    let log = []
    call extend(log, s:server_logs.stdout)
    call extend(log, s:server_logs.stderr)
  else
    let log = s:server_logs[key]
  endif
  if empty(log)
    echoerr 'no logs received'
  else
    echo join(log, "\n")
  endif
endfun "}}}


fun! awiwi#server#stop_server() abort "{{{
  if awiwi#server#server_is_running()
    echo printf('stopping server on %s:%s', s:server_host, s:server_port)
    if s:server_job_id > 0
      try
        call jobstop(s:server_job_id)
      catch /E900/
        echoerr 'no server running. dropping job id'
      endtry
      let s:server_job_id = -1
    endif
    let s:server_started = v:false
    let s:server_host = ''
    let s:server_port = ''
  endif
endfun "}}}


fun! awiwi#server#server_is_running() abort "{{{
  return s:server_started
endfun "}}}


fun! awiwi#server#start_server(host, ...) abort "{{{
  let port = get(a:000, 0, get(g:, 'awiwi_server_port', s:default_port))
  if awiwi#server#server_is_running()
    echoerr printf('server already running on %s:%s', s:server_host, s:server_port)
    return
  endif
  if a:host == '*' || a:host == 'all'
    let host = '0.0.0.0'
  elseif a:host == '' || a:host == '127.0.0.1' || a:host == '::1'
    let host = 'localhost'
  else
    let host = a:host
  endif
  let flask = awiwi#path#join(awiwi#get_code_root(), 'server', '.venv', 'bin', 'flask')
  let app = awiwi#path#join(awiwi#get_code_root(), 'server', 'app.py')
  let $FLASK_APP = app
  let $FLASK_ROOT = g:awiwi_home
  let $FLASK_ENV = 'development'
  let $FLASK_HOST = host
  let $FLASK_PORT = port
  let host_arg = printf('--host=%s', host)
  let port_arg = printf('--port=%s', port)
  let job_args = [flask, 'run', host_arg, port_arg]
  echo printf('serving on %s:%s', host, port)
  call s:write_json_config()
  let opts = {}
  let opts.on_stdout = { id, data, event -> extend(s:server_logs.stdout, data) }
  let opts.on_stderr = { id, data, event -> extend(s:server_logs.stderr, data) }
  let opts.on_exit =   { id, data, event -> add(s:server_logs.exit, data) }
  for k in keys(s:server_logs)
    let s:server_logs[k] = []
  endfor
  let s:server_job_id = jobstart(job_args, opts)
  let s:server_host = host
  let s:server_port = port
  let s:server_started = v:true
endfun "}}}


fun! awiwi#server#serve() abort "{{{
  if !awiwi#server#server_is_running()
    call awiwi#server#start_server('localhost', s:default_port)
    call system('sleep 0.5')
  endif
  let dir = g:awiwi_home[-1] == '/' ? g:awiwi_home[:-1] : g:awiwi_home
  let current_file = expand('%:p')[len(dir)+1:]
  if awiwi#str#endswith(current_file, 'journal/todos.md')
    let target = '/todo'
  elseif awiwi#str#startswith(current_file, 'journal')
    let target = 'journal/' . fnamemodify(current_file, ':t')[:-4]
  else
    let target = current_file
  endif
  let host_arg = printf('http://%s:%s/%s', s:server_host, s:server_port, target)
  call jobstart(['xdg-open', host_arg])
endfun "}}}
