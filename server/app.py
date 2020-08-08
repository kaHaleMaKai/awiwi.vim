import os
import re
import sys
import datetime
import threading
import atexit
from typing import Callable, Optional
from pathlib import Path
from flask import Flask, make_response, request, render_template, redirect, session, abort, Response
from functools import lru_cache, wraps
import itertools
import markdown
import markdown.extensions.fenced_code
import markdown.extensions.tables
import markdown.extensions.codehilite
import markdown.extensions.tables
import markdown.extensions.def_list
import markdown.extensions.footnotes
import markdown.extensions.meta
import markdown.extensions.nl2br
import markdown.extensions.sane_lists
import markdown.extensions.toc
from pygments import highlight
from pygments.lexers import get_lexer_for_filename, get_lexer_by_name
from pygments.formatters import HtmlFormatter
from urllib.parse import urlparse
from passlib.hash import sha512_crypt
from threading import Lock


md = markdown.Markdown(output_format="html5",
        extensions=[
            "fenced_code",
            "tables",
            "codehilite",
            "tables",
            "def_list",
            "footnotes",
            "meta",
            "nl2br",
            "sane_lists",
            "toc",
            ],
        extension_configs={
            "codehilite": {
                "css_class": "highlight",
                "guess_lang": False,
                }
            }
)

theme_mode_key = "theme-mode"
default_theme_mode = "light"
server_root = Path(os.path.abspath(os.path.dirname(__file__)))
content_root = Path(os.environ.get('FLASK_ROOT', '.'))
listen_address = os.environ.get("FLASK_HOST")
auth_cache_file = content_root/"auth"
flask_secret_file = content_root/"flask-secret"


app = Flask(__name__,
        root_path=str(content_root),
        static_url_path=str(server_root/"static"),
        template_folder=str(server_root/"html"))
app.secret_key = os.urandom(12)

# inotify_thread = threading.Thread(name="inotify-thread")


class AuthBackend:

    def authenticate(user: str, password: str):
        pass


class FileBasedAuthBackend(AuthBackend):

    def __init__(self, file: Path, sep: str = ":"):
        self.file = file
        self.mtime = 0  # gets overwritten by self.fill_cache()
        self.cache = {}
        self.sep = sep
        self.fill_cache()

    def get_mtime(self):
        return os.path.getmtime(self.file)

    def fill_cache(self):
        mtime = self.get_mtime()
        if mtime == self.mtime:
            return
        with Lock():
            mtime = self.get_mtime()
            if mtime == self.mtime:
                return
            cache = {}
            with open(self.file, "r") as f:
                for line in f:
                    if not line:
                        continue
                    user, hash = line.split(self.sep)
                    cache[user] = hash.strip()
            self.mtime = mtime
            self.cache = cache


    def authenticate(self, user: str, password: str):
        self.fill_cache()
        if not user in self.cache:
            return False
        return sha512_crypt.verify(password, self.cache[user])


file_auth = FileBasedAuthBackend(auth_cache_file)


def secured_route(path: str):

    def inner(route: Callable):

        @app.route(path)
        @wraps(route)
        def f(*args, **kwargs):
            host = request.host.rsplit(":", 1)[0]
            if host in ('localhost', '127.0.0.1', '::1') or session.get("logged_in", False):
                return route(*args, **kwargs)
            else:
                return redirect("/login")

        return f

    return inner



def filter_body(lines: list):
    hide = False
    for line in lines:
        if hide:
            if line.startswith("## "):
                hide = False
                yield line
            else:
                continue
        elif "<!---redacted-->" in line:
            hide = True
            continue
        else:
            yield line


def tag(text: str, element: str, cssclass: Optional[str] = None):
    if cssclass:
        return f'<{element} class="{cssclass}">{text}</{element}>'
    else:
        return f'<{element}>{text}</{element}>'


def format_markdown(file, template, add_toc=True, title=None, **kwargs):
    with open(file) as f:
        lines = f.readlines()
    parts = []
    start = 0
    if not title and lines[0].startswith("# "):
        title = heading = re.sub(r"^[#\s]+", "", lines[0]).strip()
        try:
            date = datetime.date.fromisoformat(title)
            title = beautify_date(date, only_day=False)
        except ValueError:
            pass
        start = 1
    body = filter_body(lines[start:])
    if add_toc:
        md_text = "\n[TOC]\n" + "\n".join(body)
    else:
        md_text = "\n".join(body)
    html = md.convert(md_text)
    toc = []
    extracing_toc = False

    if add_toc:
        for line in html.splitlines():
            if '<div class="toc"' in line:
                extracing_toc = True
                toc.append(line)
            elif extracing_toc:
                toc.append(line)
                if "</div" in line:
                    extracing_toc = False
            else:
                parts.append(line)
    else:
        parts.append(html)

    return render_template(
            f"{template}.html.j2",
            toc="\n".join(toc),
            content="\n".join(parts),
            title=title,
            **kwargs
            )


def find_min_max_paths(path: Path, max_depth: int):

    def fun(p: Path, fn: Callable, max_depth: int, level: int = 0):
        if os.path.isfile(p) or level == max_depth:
            return p
        predicate = os.path.isdir if level+1 < max_depth else os.path.isfile
        entries = [f for f in sorted(os.listdir(p)) if not f.startswith(".") and predicate(p/f)]
        child = p / fn(entries)
        return fun(child, fn, max_depth, level+1)

    return fun(path, min, max_depth), fun(path, max, max_depth)


def get_adjacent_journal_file(current_date: datetime.date, diff: int):
    journal_root = Path(content_root, "journal")
    sign = 1 if diff > 0 else -1
    for i in range(1, abs(diff) + 1):
        d = current_date + datetime.timedelta(days=sign * i)
        date = d.isoformat()
        year, month, day = date.split("-")
        p = journal_root / year / month / (date + ".md")
        if p.exists():
            return p.stem.replace(".md", "")


def get_prev_and_next_journal(path: Path):
    journal_root = Path(content_root, "journal")
    paths = find_min_max_paths(journal_root, 3)
    min_, max_ = [datetime.date.fromisoformat(d.stem.replace(".md", "")) for d in paths]
    current_date = datetime.date.fromisoformat(path.stem.replace(".md", ""))
    lo_diff, hi_diff = (min_ - current_date).days, (max_ - current_date).days
    prev = get_adjacent_journal_file(current_date, lo_diff)
    next = get_adjacent_journal_file(current_date, hi_diff)
    return prev, next


@secured_route("/static/<type>/<path:path>")
def statics(type: str, path: str):
    mode = "rb" if type == "img" else "r"
    with open(server_root/"static"/type/path, mode) as f:
        content = f.read()
    if type == "css":
        mime = "text/css"
    elif type == "js":
        mime = "text/javascript"
    else:
        mime = "text"
    return Response(content, mimetype=mime)


def render_non_journal(file: Path):
    name, ext = os.path.splitext(file)
    if not ext:
        with open(file, "r") as f:
            return f.read()
    elif ext == ".md":
        return format_markdown(
                file,
                title=file.stem,
                template="non-journal",
                breadcrumbs=make_breadcrumbs(file),
                )
    with open(file, "r") as f:
        text = f.read()

    m = re.search(r"(?:vim: ft=)(\S+)", text)
    if m:
        lexer_name = m.group(1)
        lexer = get_lexer_by_name(lexer_name)
    else:
        lexer = get_lexer_for_filename(file)
    content = highlight(text, lexer, HtmlFormatter(style="solarized-light", cssclass="highlight"))
    return render_template(
            "non-journal.html.j2",
            breadcrumbs=make_breadcrumbs(file),
            content=content)


@secured_route("/assets/<date>/<file>")
def asset(date: str, file: str):
    try:
        datetime.date.fromisoformat(date)
    except ValueError:
        raise FileNotFoundError(f"not a valid date: '{date}'")
    path = content_root/f"assets/{date.replace('-', '/')}/{file}"
    return render_non_journal(path)


@secured_route("/recipes/<path:path>")
def recipes(path: str):
    file = content_root/f"recipes/{path}"
    return render_non_journal(file)


@secured_route("/todo")
def todo():
    file = content_root/f"journal/todos.md"
    return format_markdown(file, template="todo", breadcrumbs=make_breadcrumbs(file), add_toc=False, title="TODO")


def make_breadcrumbs(path: Path, include_cur_dir=False):
    p = path.relative_to(content_root)
    if not include_cur_dir:
        p = p.parent
    breadcrumbs = []
    while p != Path('.'):
        breadcrumbs.append({"name": p.stem, "target": f"/dir/{p}"})
        p = p.parent
    return breadcrumbs[::-1]


@secured_route("/journal/<date>")
def journal(date: str):
    year, month, _ = date.split("-")
    file = Path(f"{content_root}/journal/{year}/{month}/{date}.md")

    prev, next = get_prev_and_next_journal(file)
    breadcrumbs = make_breadcrumbs(file)
    title = beautify_date(datetime.date.fromisoformat(date))

    return format_markdown(file, template="journal", breadcrumbs=breadcrumbs, prev=prev, next=next)


def beautify_date(date: datetime.date, only_day=True):
    days = date.strftime("%d")
    if days.endswith("1"):
        suffix = "st"
    elif days.endswith("2"):
        suffix = "nd"
    elif days.endswith("3"):
        suffix = "rd"
    else:
        suffix = "th"
    month_year = "" if only_day else " %B %Y"
    return date.strftime(f"%a, %-d<sup>{suffix}</sup>{month_year}")


def sidebar(path: Path, include_cur_dir: bool = False):
    breadcrumbs = make_breadcrumbs(path, include_cur_dir)


def dir_index(dirs: str = ''):
    splits = dirs.split("/")
    type = splits[0]
    path = content_root/type
    if len(splits) > 1:
        path = path.joinpath(*splits[1:])
    paths = sorted(os.listdir(path))
    breadcrumbs = make_breadcrumbs(content_root/dirs, include_cur_dir=True)
    entries = []
    for p in paths:
        if p.startswith("."):
            continue
        if content_root.joinpath(dirs, p).is_dir():
            target = f"/dir/{dirs}/{p}"
            name = p
        elif p == "todos.md":
            name = "todo"
            target = "/todo"
        elif type == "journal":
            basename = p.replace(".md", "")
            name = beautify_date(datetime.date.fromisoformat(basename))
            target = f"/journal/{basename}"
        elif type == "assets":
            name = p
            _, year, month, day = dirs.split("/")
            target = f"/assets/{year}-{month}-{day}/{name}"
        elif type == "recipes":
            parts = list(dirs.split("/", 1)[1:])
            parts.append(p)
            recipe_path = "/".join(parts)
            target = f"/recipes/{recipe_path}"
            name = p
        else:
            continue
        entries.append({"target": target, "name": name})

    return render_template(
        "dir.html.j2",
        breadcrumbs=breadcrumbs,
        entries=entries,
        )


@secured_route("/dir/<path:dirs>")
def dir_subdir(dirs: str = ''):
    return dir_index(dirs)


@secured_route("/")
def index():
    return dir_index()


@app.errorhandler(FileNotFoundError)
def page_not_found(error):
    return render_template("404.html"), 404


@secured_route("/change-mode")
def change_mode():
    mode = request.cookies.get(theme_mode_key)
    if not mode or mode == "light":
        new_mode = "dark"
    elif mode == "dark":
        new_mode = "light"
    if request.referrer:
        target = urlparse(request.referrer)
    else:
        target = "/"
    resp = make_response(redirect(target))
    resp.set_cookie(key=theme_mode_key, value=new_mode, max_age=9999999999)
    return resp


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "GET":
        return render_template("login.html.j2")
    user = request.form.get("user")
    password = request.form.get("password")
    if not user or not password:
        abort(401)
    if file_auth.authenticate(user.strip(), password.strip()):
        session["logged_in"] = True
        return redirect("/")
    else:
        abort(403)


@app.route("/logout")
def logout():
    session["logged_in"] = False
    return "", 200


if __name__ == "__main__":
    app.run(host=listen_address, debug=True)
