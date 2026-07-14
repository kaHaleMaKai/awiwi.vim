"""Tests for `awiwi.mdrender`: pre-filters, python-markdown pipeline, and
Pygments source rendering.

Pure text-in/text-out module -- no filesystem/`notes_home` fixture needed.
"""

from __future__ import annotations

from pathlib import Path

from awiwi.checkbox import hash_line
from awiwi.mdrender import RenderedDoc, guess_language, render_file, render_markdown


class TestTitleExtraction:
    def test_extracts_h1_as_title_and_excludes_it_from_body(self):
        doc = render_markdown("# My Journal Entry\n\nSome body text.\n")
        assert doc.title == "My Journal Entry"
        assert "My Journal Entry" not in doc.html
        assert "Some body text." in doc.html

    def test_explicit_title_overrides_and_keeps_h1_in_body(self):
        doc = render_markdown("# My Journal Entry\n\nBody.\n", title="TODO")
        assert doc.title == "TODO"
        assert "My Journal Entry" in doc.html

    def test_no_h1_means_no_title(self):
        doc = render_markdown("Just a paragraph, no heading.\n")
        assert doc.title is None

    def test_returns_rendered_doc(self):
        doc = render_markdown("hello\n")
        assert isinstance(doc, RenderedDoc)


class TestToc:
    def test_toc_lists_headings_with_anchors(self):
        text = "# Title\n\n## Section One\n\nfoo\n\n## Section Two\n\nbar\n"
        doc = render_markdown(text, add_toc=True)
        assert '<div class="toc"' in doc.toc
        assert 'href="#section-one"' in doc.toc
        assert 'href="#section-two"' in doc.toc
        assert "Section One" in doc.toc
        assert "Section Two" in doc.toc

    def test_add_toc_false_suppresses_toc_field(self):
        text = "# Title\n\n## Section One\n\nfoo\n"
        doc = render_markdown(text, add_toc=False)
        assert doc.toc == ""

    def test_toc_never_injected_into_body_html(self):
        # Divergence from legacy: no `[TOC]` token injection / HTML
        # line-scanning -- the toc lives only on RenderedDoc.toc.
        text = "# Title\n\n## Section One\n\nfoo\n"
        doc = render_markdown(text, add_toc=True)
        assert '<div class="toc"' not in doc.html
        assert "[TOC]" not in doc.html


class TestRedaction:
    def test_hides_section_until_same_or_shallower_heading(self):
        text = (
            "# Title\n\n"
            "Intro line.\n\n"
            "## Secret !!redacted\n\n"
            "Hidden paragraph.\n\n"
            "### Even more hidden\n\n"
            "Still hidden.\n\n"
            "## Next Section\n\n"
            "Visible again.\n"
        )
        doc = render_markdown(text)
        assert "Intro line." in doc.html
        assert "…redacted…" in doc.html
        assert "Hidden paragraph." not in doc.html
        assert "Even more hidden" not in doc.html
        assert "Still hidden." not in doc.html
        assert "Next Section" in doc.html
        assert "Visible again." in doc.html

    def test_inline_redaction_with_cause(self):
        doc = render_markdown("Some line !!redacted because of secrets\n")
        assert "redacted (cause: because of secrets)" in doc.html
        assert "secrets" not in doc.html.replace(
            "redacted (cause: because of secrets)", ""
        )

    def test_inline_redaction_without_cause(self):
        doc = render_markdown("!!redacted\n")
        assert "--- redacted ---" in doc.html


class TestCheckboxInjection:
    def test_unchecked_box_gets_input_and_matching_hash(self):
        doc = render_markdown("* [ ] buy milk\n* [x] pay bills\n")
        expected_hash = hash_line("* [ ] buy milk")
        assert 'class="awiwi-checkbox"' in doc.html
        assert f'data-hash="{expected_hash}"' in doc.html
        assert 'data-line-nr="0"' in doc.html
        assert 'id="checkbox-line-0"' in doc.html
        assert "<label" in doc.html
        assert "buy milk" in doc.html

    def test_checked_box_carries_checked_attribute_and_own_hash(self):
        doc = render_markdown("* [ ] buy milk\n* [x] pay bills\n")
        expected_hash = hash_line("* [x] pay bills")
        assert 'data-line-nr="1"' in doc.html
        assert f'data-hash="{expected_hash}"' in doc.html
        assert "checked" in doc.html

    def test_line_numbers_account_for_consumed_title_line(self):
        # Title line (index 0) is consumed by _extract_title; the checkbox
        # line is the file's index 1, and must keep that as its
        # data-line-nr so it lines up with toggle_checkbox's contract.
        doc = render_markdown("# Todos\n\n* [ ] one\n")
        assert 'data-line-nr="2"' in doc.html


class TestMermaid:
    def test_mermaid_fence_becomes_div(self):
        text = "```mermaid\ngraph TD\nA --> B\n```\n"
        doc = render_markdown(text)
        assert '<div class="mermaid">' in doc.html
        assert "graph TD" in doc.html
        assert "A --> B" in doc.html
        assert "</div>" in doc.html

    def test_mermaid_block_not_treated_as_code_fence(self):
        text = "```mermaid\ngraph TD\n```\n"
        doc = render_markdown(text)
        assert "highlight" not in doc.html
        assert "<code>" not in doc.html

    def test_ordinary_fenced_code_not_treated_as_mermaid(self):
        text = "```python\nprint('hi')\n```\n"
        doc = render_markdown(text)
        assert 'class="mermaid"' not in doc.html
        assert '<pre><code class="language-python">' in doc.html


class TestFencedCode:
    """T23.3 (ADR D13): fenced code renders as clean, semantic HTML for
    client-side Shiki highlighting -- no CodeHilite/Pygments markup baked
    in server-side. Every other extension (mermaid, strikethrough, toc,
    etc.) is covered separately and stays byte-identical."""

    def test_fence_with_language_gets_language_class(self):
        text = "```python\nprint('hi')\n```\n"
        doc = render_markdown(text)
        assert "<pre><code class=\"language-python\">print('hi')" in doc.html
        assert "</code></pre>" in doc.html
        assert "highlight" not in doc.html

    def test_fence_without_language_gets_bare_pre_code(self):
        text = "```\nplain block\n```\n"
        doc = render_markdown(text)
        assert "<pre><code>plain block" in doc.html
        assert "language-" not in doc.html

    def test_fence_content_is_html_escaped(self):
        text = "```html\n<script>alert('x')</script>\n```\n"
        doc = render_markdown(text)
        assert "<script>" not in doc.html
        assert "&lt;script&gt;alert" in doc.html


class TestGuessLanguage:
    """T23.3: `guess_language` is the Shiki-id hint for `DocKind.text`
    payloads -- extension map + shared vim-modeline sniff."""

    def test_common_extensions_map_to_shiki_ids(self):
        assert guess_language("script.py") == "python"
        assert guess_language("deploy.sh") == "bash"
        assert guess_language("init.lua") == "lua"
        assert guess_language("plugin.vim") == "vim"
        assert guess_language("app.js") == "javascript"
        assert guess_language("app.ts") == "typescript"
        assert guess_language("data.json") == "json"
        assert guess_language("config.yaml") == "yaml"
        assert guess_language("config.yml") == "yaml"
        assert guess_language("pyproject.toml") == "toml"
        assert guess_language("notes.md") == "markdown"
        assert guess_language("schema.sql") == "sql"

    def test_dockerfile_recognized_by_name(self):
        assert guess_language("Dockerfile") == "dockerfile"
        assert guess_language("dockerfile") == "dockerfile"
        assert guess_language(Path("build") / "Dockerfile.prod") == "dockerfile"

    def test_unknown_extension_returns_none(self):
        assert guess_language("data.unknownext") is None

    def test_modeline_wins_over_filename(self):
        text = "-- vim: ft=sql.\nSELECT 1;\n"
        assert guess_language("notes.txt", text=text) == "sql"

    def test_modeline_lexer_map_alias(self):
        text = "-- vim: ft=pgsql.\nSELECT 1;\n"
        assert guess_language("notes.txt", text=text) == "sql"

    def test_modeline_without_match_falls_back_to_filename(self):
        text = "just some text, no modeline here\n"
        assert guess_language("script.py", text=text) == "python"

    def test_path_object_accepted(self):
        assert guess_language(Path("script.py")) == "python"


class TestStrikethrough:
    def test_strikethrough_becomes_del(self):
        doc = render_markdown("This is ~~old~~ text.\n")
        assert "<del>old</del>" in doc.html


class TestUnicodeRoundtrip:
    def test_umlauts_and_emoji_render_intact(self):
        text = "Über müde Bären feiern mit 🎉 heute.\n"
        doc = render_markdown(text)
        assert "Über müde Bären feiern mit 🎉 heute." in doc.html
        assert ";match(" not in doc.html


class TestOrdinalSuperscript:
    def test_ordinals_get_sup_tags(self):
        text = "The 1st, 2nd, 3rd, 4th and 23rd items.\n"
        doc = render_markdown(text)
        assert "1<sup>st</sup>" in doc.html
        assert "2<sup>nd</sup>" in doc.html
        assert "3<sup>rd</sup>" in doc.html
        assert "4<sup>th</sup>" in doc.html
        assert "23<sup>rd</sup>" in doc.html


class TestTagsAndMentions:
    def test_known_tag_gets_wrapped_span(self):
        doc = render_markdown("See @bug for details.\n")
        assert '<span class="awiwi-bug">@bug</span>' in doc.html

    def test_all_recognized_tag_types(self):
        for tag in ("bug", "change", "incident", "issue"):
            doc = render_markdown(f"An @{tag} happened.\n")
            assert f'<span class="awiwi-{tag}">@{tag}</span>' in doc.html

    def test_mention_gets_wrapped_span(self):
        # Ported verbatim from server.old/app.py's PERSON_TAG_PATTERN, incl.
        # its single-character-capture quirk (`@([^\s,;.)}\]])` only grabs
        # one char after the leading `@`) -- this is live, shipped rendering
        # behavior, not something this rewrite silently fixes.
        doc = render_markdown("cc @@lars.\n")
        assert '<span class="awiwi-mention">@l</span>ars.' in doc.html


class TestRenderFile:
    def test_highlights_by_filename_extension(self):
        doc = render_file("print('hi')\n", filename="foo.py")
        assert 'class="highlight"' in doc.html
        assert doc.toc == ""
        assert doc.title is None

    def test_modeline_sniff_picks_lexer_over_filename(self):
        text = "-- vim: ft=sql.\nSELECT 1;\n"
        doc = render_file(text, filename="notes.txt")
        assert 'class="highlight"' in doc.html
        assert "SELECT" in doc.html

    def test_modeline_lexer_map_alias(self):
        text = "-- vim: ft=pgsql.\nSELECT 1;\n"
        doc = render_file(text, filename=None)
        assert 'class="highlight"' in doc.html

    def test_no_lexer_falls_back_to_plain_text(self):
        text = "just plain content, no lexer here\n"
        doc = render_file(text, filename="data.unknownext")
        assert doc.html == text

    def test_no_filename_and_no_modeline_falls_back_to_plain_text(self):
        text = "no hints at all\n"
        doc = render_file(text)
        assert doc.html == text
