import os
import re
import sys
import json
import calendar
import datetime
import threading
import atexit
import mimetypes
import hashlib
from typing import Callable, Optional, Union, Tuple
from pathlib import Path
from flask import Flask, make_response, request, render_template, redirect, session, abort, Response, jsonify
from functools import lru_cache, wraps
import itertools
import markdown
from markdown.extensions.fenced_code import FencedCodeExtension
from markdown.extensions.tables import TableExtension
from markdown.extensions.codehilite import  CodeHiliteExtension
from markdown.extensions.def_list import DefListExtension
from markdown.extensions.footnotes import FootnoteExtension
from markdown.extensions.meta import MetaExtension
from markdown.extensions.nl2br import Nl2BrExtension
from markdown.extensions.sane_lists import SaneListExtension
from markdown.extensions.toc import TocExtension
from markdown_strikethrough.extension import StrikethroughExtension
from pygments import highlight
from pygments.lexers import get_lexer_for_filename, get_lexer_by_name
from pygments.formatters import HtmlFormatter
from pygments.util import ClassNotFound
from urllib.parse import urlparse
from passlib.hash import sha512_crypt
from threading import Lock
import subprocess


checkclock_path = Path("~/.config/qtile/widgets").expanduser().absolute()
sys.path.insert(1, str(checkclock_path))
from checkclock import ReadOnlyCheckclock, as_time, as_hours_and_minutes


checkclock = ReadOnlyCheckclock(Path("~/.config/qtile/checkclock.sqlite").expanduser(), working_days="Tue-Fri")


ordinal_pattern = re.compile(r"\b([0-9]{1,2})(st|nd|rd|th)\b")
md = markdown.Markdown(output_format="html5",
        extensions=[
            FencedCodeExtension(),
            CodeHiliteExtension(css_class="highlight", guess_lang=False),
            DefListExtension(),
            FootnoteExtension(),
            MetaExtension(),
            Nl2BrExtension(),
            SaneListExtension(),
            TocExtension(),
            StrikethroughExtension(),
            TableExtension()
            ]
)

download_extensions = [".ods", ".odt"]
lexer_map = {"pgsql": "sql"}

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


def hash_line(line: str):
    if re.match("\s*\* \[[x ]\] ", line):
        line = re.sub("\[[ x]\]", "", line, 1)
    if line[-1] == "\n":
        line = line[:-1]
    return hashlib.md5(line.encode()).hexdigest()


def is_localhost():
    host = request.host.rsplit(":", 1)[0]
    return host in ('localhost', '127.0.0.1', '::1')


def is_logged_in():
    return session.get("logged_in", False)


def secured_route(path: str, methods=("GET",)):

    def inner(route: Callable):

        @app.route(path, methods=methods)
        @wraps(route)
        def f(*args, **kwargs):
            if is_localhost() or is_logged_in():
                return route(*args, **kwargs)
            else:
                return redirect("/login")

        return f

    return inner


def filter_body(lines: list, offset: int):
    redaction_pattern = "!!redacted"
    hide = False
    # we only have h1…h6 – using 7 is safe here
    marker_depth = 7
    for line_no, line in enumerate(lines, start=offset):
        if hide:
            if (m := re.match('^(?P<marker>##+) ', line)):
                current_depth = len(m.group("marker"))
                if current_depth <= marker_depth:
                    hide = False
            else:
                continue
        elif redaction_pattern in line:
            if (m := re.match('^(?P<marker>##+) ', line)):
                marker_depth = len(m.group("marker"))
                hide = True
            else:
                rem = line.split(redaction_pattern)[-1].strip()
                if rem:
                    yield f" --- redacted (cause: {rem}) --- "
                else:
                    yield " --- redacted --- "
            continue
        elif (m := re.match("^(\s*\* )(\[[x ]\])( .*$)", line)):
            hash = hash_line(line)
            box = m.group(2)
            checked = "checked" if "x" in box else ""
            line = (f'{m.group(1)}<input type="checkbox" id="checkbox-line-{line_no}" {checked} data-line-nr="{line_no}" ' +
                    f'class="awiwi-checkbox" data-hash="{hash}"> <label for="checkbox-line-{line_no}"><span>{m.group(3)}</span></label>')
        yield replace_date_ordinal(line).replace("\n", "")


def get_file_for_endpoint(path: str) -> Path:
    if path.startswith("/journal"):
        rem, date = path.rsplit("/", 1)
        year, month, _ = date.split("-")
        return content_root/f"journal/{year}/{month}/{date}.md"
    elif path.startswith("/todo"):
        return content_root/"journal/todos.md"
    else:
        raise ValueError("not implemented yet")


def replace_date_ordinal(text: str):
    return ordinal_pattern.sub(r'\1<sup>\2</sup>', text)


def format_markdown(file, template, add_toc=True, title=None, **kwargs):
    with open(file) as f:
        lines = f.readlines()
    parts = []
    start = 0
    if not title and lines[0].startswith("# "):
        title = heading = re.sub(r"^[#\s]+", "", lines[0]).strip()
        try:
            date = datetime.date.fromisoformat(title)
            title = date
        except ValueError:
            pass
        start = 1
    body = filter_body(lines[start:], offset=start)
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
            theme_mode=get_theme_from_cookie(),
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


def get_prev_and_next_journal(path: Path) -> Tuple[Optional[str], Optional[str]]:
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


def is_binary(file: Path):
    textchars = bytearray({7,8,9,10,12,13,27} | set(range(0x20, 0x100)) - {0x7f})
    with open(file, "rb") as f:
        return bool(f.read(1024).translate(None, textchars))


def render_non_journal(file: Path):
    is_secret = re.search("^secrets?-|-secrets?[-.]|-secrets?$", file.stem)
    if is_secret and not is_localhost():
        return render_template(
                "non-journal.html.j2",
                breadcrumbs=make_breadcrumbs(file),
                content="",
                theme_mode=get_theme_from_cookie(),
                is_secret=True,
                is_localhost=False
                )

    name, ext = os.path.splitext(file)
    mime_type = mimetypes.guess_type(file)[0]

    if not ext:
        with open(file, "r") as f:
            return f.read()
    elif ext == ".md":
        return format_markdown(
                file,
                title=file.stem,
                template="non-journal",
                breadcrumbs=make_breadcrumbs(file),
                is_secret=is_secret,
                is_localhost=is_localhost(),
                highlight_article=is_secret,
                )
    elif mime_type and mime_type.startswith("image"):
        with open(file, "rb") as f:
            img = f.read()
        resp = Response(img, mimetype=mime_type)
        return resp
    with open(file, "r") as f:
        text = f.read()

    m = re.search(r"(?:vim: ft=)(\S+?)([\s.])", text)
    if m:
        lexer_name = m.group(1)
        lexer = get_lexer_by_name(lexer_map.get(lexer_name, lexer_name))
    else:
        try:
            lexer = get_lexer_for_filename(file)
        except ClassNotFound:
            lexer = None
    if lexer:
        content = highlight(text, lexer, HtmlFormatter(style="solarized-light", cssclass="highlight"))
    else:
        content = "\n".join(text.split("\n"))
    return render_template(
            "non-journal.html.j2",
            breadcrumbs=make_breadcrumbs(file),
            content=content,
            theme_mode=get_theme_from_cookie(),
            is_localhost=is_localhost(),
            is_secret=is_secret,
            highlight_article=is_secret,
            )


@secured_route("/./<path:path>")
def remove_current_dir(path: str):
    return redirect(f"/{path}")


@secured_route("/../<path:path>")
def redirect_to_parent(path: str):
    return redirect(f"/{path}")


@secured_route("/assets/<year>/<month>/<day>/<file>")
def asset_redirect(year: str, month: str, day: str, file: str):
    date = f"{year}-{month}-{day}"
    return redirect(f"/assets/{date}/{file}")


def as_downloadable_file(path: Path, mime_type: Optional[str] = None):
    if not mime_type:
        mime_type = mimetypes.guess_type(str(path))[0]
    size = os.path.getsize(path)
    with open(path, "rb") as f:
        headers = {
                "Content-Description": "File Transfer",
                "Content-Transfer-Encoding": "binary",
                "Expires": "0",
                "Cache-Control": "must-revalidate",
                "Pragma": "public",
                "Content-Length": str(size),
                }
        return Response(f.read(), mimetype=mime_type, content_type="application/octet-stream", direct_passthrough=True, headers=headers)


@secured_route("/assets/<date>/<file>")
def asset(date: str, file: str):
    try:
        datetime.date.fromisoformat(date)
    except ValueError:
        raise FileNotFoundError(f"not a valid date: '{date}'")
    path = content_root/f"assets/{date.replace('-', '/')}/{file}"
    mime_type = mimetypes.guess_type(str(path))[0]
    if mime_type and "application" in mime_type:
        return as_downloadable_file(path, mime_type)
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


@secured_route("/journal/<year>/<month>/<file>")
def journal_redirect(year: str, month: str, file: str):
    return redirect(f"/journal/{file.replace('.md', '')}")


def parse_date(date: str) -> datetime.date:
    date = date.lower()
    if date == "today":
        return datetime.date.today()
    elif date == "yesterday":
        return datetime.date.today() - datetime.timedelta(days=1)
    elif date in ("previous", "prev"):
        today = datetime.date.today()
        year_month = today.strftime("%Y/%m")
        iso_date = today.strftime("%Y-%m-%d")
        file = Path(f"{content_root}/journal/{year_month}/{iso_date}.md")
        prev, _ = get_prev_and_next_journal(file)
        return datetime.date.fromisoformat(prev)
    else:
        return datetime.date.fromisoformat(date)


def get_schedule(checkclock, days_back):
    if not days_back:
        for start, end in checkclock.merge_durations(0):
            diff = end - start
            time = diff.total_seconds()
            yield start.strftime("%H:%M"), end.strftime("%H:%M"), time
    else:
        for start, end, duration in checkclock.get_backlog(days_back):
            yield start.strftime("%H:%M"), end.strftime("%H:%M"), duration


@secured_route("/journal/<date>")
def journal(date: str):
    if date.endswith(".md"):
        return redirect(f"/journal/{date.replace('.md', '')}")
    date = parse_date(date).isoformat()
    year, month, _ = date.split("-")
    file = Path(f"{content_root}/journal/{year}/{month}/{date}.md")

    prev, next = get_prev_and_next_journal(file)

    args = dict(
            template="journal",
            breadcrumbs=make_breadcrumbs(file),
            prev=prev,
            next=next,
            )

    days_back = (datetime.date.today() - parse_date(date)).days
    schedule = list(get_schedule(checkclock, days_back))
    if schedule:
        balance = checkclock.get_balance(days_back)
        args["good_balance"] = balance >= 0
        args["total"] = as_time(int(sum(duration for _, _, duration in schedule))).strftime("%k:%M")
    args["schedule"] = [(start, end, as_time(duration).strftime("%k:%M")) for start, end, duration in schedule]

    return format_markdown(file, **args)


@app.template_filter("calendar_week")
def calendar_week(date: Union[datetime.date, str]):
    if isinstance(date, str):
        date = datetime.date.fromisoformat(date)
    return int(date.strftime("%W")) % 5


@app.template_filter("beautify_if_date")
def beautify_if_date(date: Union[datetime.date, str], format: str = None):
    if isinstance(date, str):
        try:
            date = datetime.date.fromisoformat(date)
        except ValueError:
            return date
    days = date.strftime("%d")
    if days.endswith("1"):
        suffix = "st"
    elif days.endswith("2"):
        suffix = "nd"
    elif days.endswith("3"):
        suffix = "rd"
    else:
        suffix = "th"
    month_year = "" if not format else f" {format}"
    return date.strftime(f"%a, %-d<sup>{suffix}</sup>{month_year}")


def sidebar(path: Path, include_cur_dir: bool = False):
    breadcrumbs = make_breadcrumbs(path, include_cur_dir)


def dir_index(dirs: str = ''):
    if dirs.endswith("/"):
        dirs = dirs[:-1]
    splits = dirs.split("/")
    type = splits[0]
    path = content_root/type
    if len(splits) > 1:
        path = path.joinpath(*splits[1:])
    paths = sorted(os.listdir(path))
    breadcrumbs = make_breadcrumbs(content_root/dirs, include_cur_dir=True)
    entries = []
    first_week = None
    for p in paths:
        if p.startswith("."):
            continue
        entry = {}
        if content_root.joinpath(dirs, p).is_dir():
            entry["target"] = f"/dir/{dirs}/{p}"
            if type in ("journal", "assets"):
                if len(splits) <= 1:
                    entry["name"] = p
                elif len(splits) == 2:
                    entry["name"] = calendar.month_name[int(p)]
                else:
                    date = datetime.date.isoformat("-".join([*splits[-2:], p]))
                    entry["name"] = date
                    week = int(date.strftime("%W"))
                    if first_week is None:
                        first_week = week
                    entry["class"] = f"week{week - first_week}"
            else:
                entry["name"] = p
        elif p == "todos.md":
            entry["name"] = "todo"
            entry["target"] = "/todo"
        elif type == "journal":
            basename = p.replace(".md", "")
            date = datetime.date.fromisoformat(basename)
            entry["name"] = date
            entry["target"] = f"/journal/{basename}"
            week = int(date.strftime("%W"))
            if first_week is None:
                first_week = week
            entry["class"] = f"week{week - first_week}"
        elif type == "assets":
            entry["name"] = p
            _, year, month, day = dirs.split("/")
            entry["target"] = f"/assets/{year}-{month}-{day}/{p}"
        elif type == "recipes":
            parts = list(dirs.split("/", 1)[1:])
            parts.append(p)
            recipe_path = "/".join(parts)
            entry["target"] = f"/recipes/{recipe_path}"
            entry["name"] = p
        else:
            continue
        entries.append(entry)


    return render_template(
        "dir.html.j2",
        breadcrumbs=breadcrumbs,
        entries=entries,
        theme_mode=get_theme_from_cookie(),
        )


@secured_route("/dir/<path:dirs>")
def dir_subdir(dirs: str = ''):
    return dir_index(dirs)


@secured_route("/")
def index():
    return dir_index()


@app.errorhandler(FileNotFoundError)
def page_not_found(error):
    mode = get_theme_from_cookie()
    return render_template("404.html", theme_mode=mode), 404


def get_theme_from_cookie():
    mode = request.cookies.get(theme_mode_key)
    if not mode or mode == "light":
        return "light"
    return "dark"


@secured_route("/change-mode")
def change_mode():
    mode = get_theme_from_cookie()
    if request.referrer:
        target = urlparse(request.referrer)
    else:
        target = "/"
    resp = make_response(redirect(target))
    resp.set_cookie(key=theme_mode_key, value=mode, max_age=9999999999)
    return resp


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "GET":
        mode = get_theme_from_cookie()
        return render_template("login.html.j2", theme_mode=mode)
    user = request.form.get("user")
    password = request.form.get("password")
    if not user or not password:
        abort(401)
    if file_auth.authenticate(user.strip(), password.strip()):
        session["logged_in"] = True
        return redirect("/")
    else:
        abort(403)


def format_search_hits(fd):
    for line in fd.readlines():
        file, line_no, col, text = line.split(":", 3)
        if file == "journal/todo.md":
            target = "/todo"
            name = "todo"
            type = "todo"
        else:
            parts = file.split("/")
            type = parts[0]
            if type == "journal":
                journal_name = parts[-1].replace('.md', '')
                target = f"/journal/{journal_name}"
                name = f"{journal_name}"
            elif type == "assets":
                type = "asset"
                date = "-".join(parts[1:4])
                asset_name = parts[-1]
                target = f"/assets/{date}/{asset_name}"
                name = f"{date}/{asset_name}"
            elif type == "recipes":
                target = file
                name = file.replace("/", " – ", 1)
                type = "recipe"
        yield dict(
                target=target,
                name=name,
                line=int(line_no),
                col=int(col),
                type=type,
                text=text.strip())


def server_search_content(pattern: str):
    cmd = ['rg', '-i', '-U', '--multiline-dotall', '--color=never',
         '--column', '--line-number', '--no-heading',
         '-g', '!awiwi*', pattern]

    proc = subprocess.Popen(args=cmd, stdout=subprocess.PIPE, cwd=content_root, text=True)
    try:
        proc.wait(10)
    except subprocess.TimeoutExpired as e:
        return str(e), 500

    def sortable(key: dict):
        types = {"todo": 0, "journal": 1, "asset": 2, "recipe": 3}
        t = types[key["type"]]
        return f"{t}{key['name']}"

    return sorted(format_search_hits(proc.stdout), key=sortable)


@secured_route("/search/content", methods=["POST"])
def search_content():
    pattern = request.form.get("search-content")
    if not pattern:
        return "no pattern given", 400
    content = server_search_content(pattern)
    return render_template(
            "search-content.html.j2",
            title="search content",
            theme_mode=get_theme_from_cookie(),
            content=content)


@app.route("/logout")
def logout():
    session["logged_in"] = False
    return "", 200


def json_response(data: dict, status: int = 200):
    # return jsonify(data, status=status, content_type="application/json; chartset=UTF-8")
    return jsonify(data), status


@secured_route("/checkbox", methods=["PATCH"])
def update_checkbox():
    """
    body: {"line_nr": N, "path": "/some/end/point", "check": true|false, "hash": "hexdigest"}
    """
    data = request.json
    line_nr = data["line_nr"]
    endpoint = data["path"]
    check = data["check"]
    hash = data["hash"]
    path = get_file_for_endpoint(endpoint)

    if not path.exists():
        return json_response({"success": False, "msg": f"path {endpoint} does not exist"}, 404)
    try:
        update_checkbox_in_file(path, line_nr, check, hash)
    except ValueError as e:
        return json_response({"success": False, "msg": str(e)}, 409)
    return json_response({"success": True})


def update_checkbox_in_file(path: Path, line_nr: int, check: bool, hash: str) -> None:
    check_char = "x" if check else " "
    with open(path, "r+") as f:
        for i in range(line_nr):
            f.readline()
        pos = f.tell()
        line = f.readline()
        if line[-1] == "\n":
            line = line[:-1]
        if hash != (this_hash := hash_line(line)):
            raise ValueError(f"hashes don't match. exp: '{this_hash}. got: '{hash}'")
        m = re.match("(\s*\* \[)([ x])", line)
        is_checked = m.group(2) == "x"
        if is_checked == check:
            raise ValueError(f"checkbox is already {'un' if not is_checked else ''}checked")
        offset = m.end() - 1
        f.seek(pos + offset)
        f.write(check_char)


if __name__ == "__main__":
    app.run(host=listen_address, debug=True)
