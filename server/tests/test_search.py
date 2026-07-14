"""Unit tests for awiwi.search — rg arg-list builder + output parsing.

No subprocess is ever spawned here: `parse_search_output` is exercised
against a canned `file:line:col:text` string shaped exactly like real
`rg --column --line-number --no-heading` output. The actual subprocess
invocation is out of scope for this pure leaf module (wired up, with a
skipif-no-rg acceptance test, in T16 per the design brief).
"""

from awiwi.search import SearchHit, build_rg_args, parse_search_output, sort_hits


class TestBuildRgArgs:
    def test_matches_legacy_flags(self):
        assert build_rg_args("needle") == [
            "rg",
            "-i",
            "-U",
            "--multiline-dotall",
            "--color=never",
            "--column",
            "--line-number",
            "--no-heading",
            "-g",
            "!awiwi*",
            "needle",
        ]


class TestBuildRgArgsExtended:
    """S23.2: `build_rg_args` grows keyword-only `fixed`/`scopes` params for
    the new `/api/search` route. Existing positional-only callers (the
    legacy `POST /search/content` action route) must keep getting the exact
    same argv as before -- so `fixed` defaults to `False` (no `-F`), not
    `True`; the API router itself defaults its own `mode` query param to
    "fixed" and passes `fixed=True` explicitly. See T23.2 handover."""

    def test_default_unchanged_for_legacy_callers(self):
        assert build_rg_args("needle") == [
            "rg",
            "-i",
            "-U",
            "--multiline-dotall",
            "--color=never",
            "--column",
            "--line-number",
            "--no-heading",
            "-g",
            "!awiwi*",
            "needle",
        ]

    def test_fixed_true_adds_dash_F(self):
        args = build_rg_args("needle", fixed=True)
        assert "-F" in args
        # pattern stays the trailing element
        assert args[-1] == "needle"

    def test_fixed_false_omits_dash_F(self):
        assert "-F" not in build_rg_args("needle", fixed=False)

    def test_single_scope_adds_glob(self):
        args = build_rg_args("needle", scopes=["journal"])
        assert "journal/**" in args
        idx = args.index("journal/**")
        assert args[idx - 1] == "-g"

    def test_multiple_scopes_add_multiple_globs(self):
        args = build_rg_args("needle", scopes=["journal", "assets"])
        assert "journal/**" in args
        assert "assets/**" in args
        assert "recipes/**" not in args

    def test_no_scopes_means_no_extra_globs(self):
        args = build_rg_args("needle")
        assert "journal/**" not in args
        assert "assets/**" not in args
        assert "recipes/**" not in args

    def test_pattern_always_trails_even_with_fixed_and_scopes(self):
        args = build_rg_args("needle", fixed=True, scopes=["recipes"])
        assert args[-1] == "needle"


class TestParseSearchOutput:
    def test_journal_hit(self):
        output = "journal/2026/07/2026-07-01.md:3:5:buy milk today\n"
        hits = parse_search_output(output)
        assert hits == [
            SearchHit(
                target="/journal/2026-07-01",
                name="2026-07-01",
                line=3,
                col=5,
                type="journal",
                text="buy milk today",
            )
        ]

    def test_todo_hit(self):
        # Legacy server.old/app.py:format_search_hits compares against the
        # literal (nonexistent) filename "journal/todo.md" — a typo bug that
        # never matches the real todo file, "journal/todos.md" — so todo
        # hits fell through to the generic "journal" branch and linked to
        # the wrong place (/journal/todos instead of /todo). Assessed fix:
        # compare against the real filename.
        output = "journal/todos.md:1:1:* [ ] buy milk\n"
        hits = parse_search_output(output)
        assert hits == [
            SearchHit(
                target="/todo",
                name="todo",
                line=1,
                col=1,
                type="todo",
                text="* [ ] buy milk",
            )
        ]

    def test_asset_hit(self):
        output = "assets/2026/07/01/x.txt:2:1:some asset content\n"
        hits = parse_search_output(output)
        assert hits == [
            SearchHit(
                target="/assets/2026-07-01/x.txt",
                name="2026-07-01/x.txt",
                line=2,
                col=1,
                type="asset",
                text="some asset content",
            )
        ]

    def test_recipe_hit(self):
        output = "recipes/cooking/pasta.md:4:1:boil water\n"
        hits = parse_search_output(output)
        assert hits == [
            SearchHit(
                target="recipes/cooking/pasta.md",
                name="recipes – cooking/pasta.md",
                line=4,
                col=1,
                type="recipe",
                text="boil water",
            )
        ]

    def test_text_containing_colons_preserved(self):
        output = "recipes/cooking/pasta.md:4:1:ratio 3:2:1 water:salt\n"
        hits = parse_search_output(output)
        assert hits[0].text == "ratio 3:2:1 water:salt"

    def test_blank_lines_ignored(self):
        output = "journal/2026/07/2026-07-01.md:3:5:buy milk\n\n"
        hits = parse_search_output(output)
        assert len(hits) == 1

    def test_unrecognized_top_level_dir_is_skipped(self):
        # Assessed fix: server.old/app.py's format_search_hits has no final
        # else branch for an unrecognized top-level type, so `target`/`name`
        # are left unbound and it crashes with UnboundLocalError. Skip
        # instead of crashing.
        output = "static/js/common.js:1:1:something\n"
        hits = parse_search_output(output)
        assert hits == []

    def test_multiple_hits_in_one_output(self):
        output = (
            "journal/todos.md:1:1:* [ ] buy milk\n"
            "recipes/cooking/pasta.md:4:1:boil water\n"
        )
        hits = parse_search_output(output)
        assert len(hits) == 2


class TestSortHits:
    def test_orders_by_type_then_name(self):
        hits = [
            SearchHit(
                target="recipes/z.md", name="z", line=1, col=1, type="recipe", text=""
            ),
            SearchHit(target="/assets/x", name="x", line=1, col=1, type="asset", text=""),
            SearchHit(
                target="/journal/b", name="b", line=1, col=1, type="journal", text=""
            ),
            SearchHit(target="/todo", name="todo", line=1, col=1, type="todo", text=""),
            SearchHit(
                target="/journal/a", name="a", line=1, col=1, type="journal", text=""
            ),
        ]
        ordered = sort_hits(hits)
        assert [h.type for h in ordered] == [
            "todo",
            "journal",
            "journal",
            "asset",
            "recipe",
        ]
        # journal entries sorted by name among themselves
        journal_names = [h.name for h in ordered if h.type == "journal"]
        assert journal_names == ["a", "b"]
