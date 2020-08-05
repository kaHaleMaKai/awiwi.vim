import os
import re
import sys
import datetime
import threading
import atexit
from typing import Callable, Optional
from pathlib import Path
from flask import Flask, Response, render_template, redirect
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

server_root = Path(os.path.abspath(os.path.dirname(__file__)))
content_root = Path(os.environ.get('FLASK_ROOT', '.'))
listen_address = os.environ.get("FLASK_HOST")
app = Flask(__name__,
        root_path=str(content_root),
        static_url_path=str(server_root/"static"),
        template_folder=str(server_root/"html"))


# inotify_thread = threading.Thread(name="inotify-thread")


@lru_cache
def get_css_links():
    css_files = [
            "/static/css/default.css",
            # "/static/css/lovelace.css",
            "/static/css/pygments.css",
            ]
    return "\n".join(f'<link rel="stylesheet" href="{f}">' for f in css_files) + "\n"


def add_css(route: Callable):

    @wraps(route)
    def f(*args, **kwargs):
        content = route(*args, **kwargs)
        return get_css_links() + "\n" + content

    return f


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


def make_header(title: str):
    return tag(tag(title, "h1"), "header")


def format_markdown(file, crumbs=None, toc=True, title=None, links=None):
    with open(file) as f:
        lines = f.readlines()
    parts = []
    if title:
        parts.append(make_header(title))
        start = 0
    elif lines[0].startswith("# "):
        title = heading = re.sub(r"^[#\s]+", "", lines[0]).strip()
        try:
            date = datetime.date.fromisoformat(title)
            title = beautify_date(date, only_day=False)
        except ValueError:
            pass
        parts.append(make_header(title))
        start = 1
    else:
        start = 0
    parts.append('<div class="container">')
    body = filter_body(lines[start:])
    if toc:
        md_text = "\n[TOC]\n" + "\n".join(body)
    else:
        md_text = "\n".join(body)
    html = md.convert(md_text)
    insert_article_div = False
    if toc:
        for line in html.splitlines():
            if '<div class="toc"' in line:
                insert_article_div = True
                parts.append('<div class="aside">')
                parts.append(crumbs)
                if title:
                    parts.append(tag(tag(title, "span"), "div", "title-aside"))
                parts.append(line)
            elif "</div>" in line and insert_article_div:
                parts.append(line)
                parts.append('</div>')
                parts.append('<div class="article">')
                insert_article_div = False
            else:
                parts.append(line)
        if links:
            parts.append(links)
        parts.append("</div>")
    else:
        parts.append(crumbs)
        parts.append(html)
        parts.append(links)

    return "".join(parts)


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


@app.route("/static/<path:path>")
def css(path: str):
    type = path.split("/", 1)[0]
    mode = "rb" if type == "img" else "r"
    with open(server_root/"static"/path,mode) as f:
        return f.read()


@add_css
def render_non_journal(file: Path):
    name, ext = os.path.splitext(file)
    if not ext:
        with open(file, "r") as f:
            return f.read()
    elif ext == ".md":
        return format_markdown(file, crumbs=make_breadcrumbs(file))
    with open(file, "r") as f:
        text = f.read()

    m = re.search(r"(?:vim: ft=)(\S+)", text)
    if m:
        lexer_name = m.group(1)
        lexer = get_lexer_by_name(lexer_name)
    else:
        lexer = get_lexer_for_filename(file)
    return make_breadcrumbs(file) + highlight(text, lexer, HtmlFormatter(style="solarized-light", cssclass="highlight"))


@app.route("/assets/<date>/<file>")
def asset(date: str, file: str):
    try:
        datetime.date.fromisoformat(date)
    except ValueError:
        raise FileNotFoundError(f"not a valid date: '{date}'")
    path = content_root/f"assets/{date.replace('-', '/')}/{file}"
    return render_non_journal(path)


@app.route("/recipes/<path:path>")
def recipes(path: str):
    file = content_root/f"recipes/{path}"
    return render_non_journal(file)


@app.route("/todo")
@add_css
def todo():
    file = content_root/f"journal/todos.md"
    return format_markdown(file, crumbs=make_breadcrumbs(file), toc=False, title="TODO")


def make_breadcrumbs(path: Path, include_cur_dir=False):
    links = []
    p = path.relative_to(content_root)
    if not include_cur_dir:
        p = p.parent
    while p != Path('.'):
        links.append(f'<a class="breadcrumbs-link" href="/dir/{p}">{p.stem}</a>')
        p = p.parent
    links.append('<a class="breadcrumbs-link" href="/awiwi">awīwī</a>')

    crumbs = '<div class="breadcrumbs">' + " > ".join(links[::-1]) + '</div>'
    return crumbs


@app.route("/journal/<date>")
@add_css
def journal(date: str):
    year, month, _ = date.split("-")
    file = Path(f"{content_root}/journal/{year}/{month}/{date}.md")

    p, n = get_prev_and_next_journal(file)
    links = ['', '<hr>', '<div class="prevnext-journal">']
    if p:
        links.append(f"""<a class="prev-journal" href="/journal/{p}">« previous</a>""")
    if n:
        links.append(f"""<a class="next-journal" href="/journal/{n}">next »</a>""")
    links.append('</div>')

    return format_markdown(file, links="\n".join(links), crumbs=make_breadcrumbs(file))


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
    crumbs = make_breadcrumbs(path, include_cur_dir)


@add_css
def dir_index(dirs: str = ''):
    splits = dirs.split("/")
    type = splits[0]
    path = content_root/type
    if len(splits) > 1:
        path = path.joinpath(*splits[1:])
    paths = sorted(os.listdir(path))
    crumbs = make_breadcrumbs(content_root/dirs, include_cur_dir=True)
    header = ['<div class="dir-listing">', crumbs]
    links = []
    for p in paths:
        if p.startswith("."):
            continue
        if content_root.joinpath(dirs, p).is_dir():
            dest = f"/dir/{dirs}/{p}"
            name = p
        elif p == "todos.md":
            name = "todo"
            dest = "/todo"
        elif type == "journal":
            basename = p.replace(".md", "")
            name = beautify_date(datetime.date.fromisoformat(basename))
            dest = f"/journal/{basename}"
        elif type == "assets":
            name = p
            _, year, month, day = dirs.split("/")
            dest = f"/assets/{year}-{month}-{day}/{name}"
        elif type == "recipes":
            parts = list(dirs.split("/", 1)[1:])
            parts.append(p)
            recipe_path = "/".join(parts)
            dest = f"/recipes/{recipe_path}"
            name = p
        else:
            continue
        link = f'<ul><a href="{dest}">{name}</a></ul>'
        links.append(link)

    return "\n".join(itertools.chain(header, links, ['</dir>']))


@app.route("/dir/<path:dirs>")
def dir_subdir(dirs: str = ''):
    return dir_index(dirs)


@app.route("/")
def index():
    return redirect("/awiwi")


@app.route("/awiwi")
def dir_root_dir():
    return dir_index()


@app.errorhandler(FileNotFoundError)
def page_not_found(error):
    return render_template("404.html"), 404


if __name__ == "__main__":
    app.run(host=listen_address, debug=True)
