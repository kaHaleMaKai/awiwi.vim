"""Tests for `awiwi.mdrender`: pre-filters and the python-markdown pipeline.

Pure text-in/text-out module -- no filesystem/`notes_home` fixture needed.
"""

from __future__ import annotations

from pathlib import Path

from awiwi.checkbox import hash_line
from awiwi.mdrender import RenderedDoc, guess_language, render_markdown


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


class TestRedactionEmbed:
    """S23.4: `embed_redacted=True` keeps redacted content in the output,
    HTML-escaped and wrapped in a single `class="redacted"` -- the exact
    class the T22 mockups' CSS contract (`.redacted { ... }`) obscures by
    default and the frontend toggles `.is-revealed` on. Default (False,
    the implicit default exercised throughout `TestRedaction` above) stays
    byte-identical to the legacy stripping behavior."""

    def test_default_is_byte_identical_to_stripped_behavior(self):
        text = (
            "# Title\n\nIntro.\n\n## Secret !!redacted\n\nHidden body.\n\n"
            "## Next\n\nTail.\n"
        )
        stripped_default = render_markdown(text).html
        stripped_explicit = render_markdown(text, embed_redacted=False).html
        assert stripped_default == stripped_explicit
        assert "Hidden body." not in stripped_default

    def test_inline_embed_wraps_value_and_keeps_placeholder_wording(self):
        doc = render_markdown(
            "api key: sk-123 !!redacted because of secrets\n", embed_redacted=True
        )
        assert '<span class="redacted">api key: sk-123</span>' in doc.html
        assert "redacted (cause: because of secrets)" in doc.html

    def test_inline_embed_without_cause_keeps_plain_placeholder(self):
        doc = render_markdown("sk-123 !!redacted\n", embed_redacted=True)
        assert '<span class="redacted">sk-123</span>' in doc.html
        assert "--- redacted ---" in doc.html

    def test_inline_embed_value_is_html_escaped(self):
        doc = render_markdown("a <secret> & more !!redacted\n", embed_redacted=True)
        assert "a &lt;secret&gt; &amp; more" in doc.html
        assert "<secret>" not in doc.html

    def test_inline_embed_value_is_not_markdown_re_rendered(self):
        # A revealed secret must read back character-for-character: markdown
        # punctuation inside the hidden value (emphasis, code spans,
        # strikethrough) must NOT be re-rendered -- `pass*word*123` revealing
        # as "pass<em>word</em>123" would silently drop characters from the
        # value.
        doc = render_markdown("pass*word*123 `x` ~~y~~ !!redacted\n", embed_redacted=True)
        assert '<span class="redacted">pass*word*123 `x` ~~y~~</span>' in doc.html
        assert "<em>" not in doc.html
        assert "<code>" not in doc.html
        assert "<del>" not in doc.html

    def test_section_embed_wraps_whole_hidden_body_in_one_div(self):
        text = (
            "# Title\n\n"
            "## Secret !!redacted\n\n"
            "Hidden paragraph.\n\n"
            "### Even more hidden\n\n"
            "Still hidden.\n\n"
            "## Next Section\n\n"
            "Visible again.\n"
        )
        doc = render_markdown(text, embed_redacted=True)
        # Placeholder heading unchanged from stripping mode.
        assert "…redacted…" in doc.html
        assert doc.html.count('<div class="redacted">') == 1
        # Whole hidden body embedded as escaped plain text, in one wrapper --
        # nested markdown NOT re-rendered (the `###` heading stays literal).
        assert "Hidden paragraph." in doc.html
        assert "### Even more hidden" in doc.html
        assert "Still hidden." in doc.html
        assert "<h3" not in doc.html
        # The section still ends where it always did.
        assert "Next Section" in doc.html
        assert "Visible again." in doc.html

    def test_section_embed_escapes_html_in_hidden_body(self):
        text = "## S !!redacted\n\n<script>alert('x')</script>\n\n## T\n\nok\n"
        doc = render_markdown(text, embed_redacted=True)
        assert "<script>" not in doc.html
        assert "&lt;script&gt;alert" in doc.html

    def test_section_embed_at_end_of_document_still_flushes(self):
        text = "# T\n\n## Secret !!redacted\n\nHidden tail.\n"
        doc = render_markdown(text, embed_redacted=True)
        assert '<div class="redacted">' in doc.html
        assert "Hidden tail." in doc.html


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
        # T28.0: fixed a bug ported from server.old/app.py's
        # PERSON_TAG_PATTERN (`@([^\s,;.)}\]])`), which only captured one
        # char after the leading `@` (`@@lars` -> `<span ...>@l</span>ars`).
        # The whole `@@word` token now lands inside one span.
        doc = render_markdown("cc @@lars.\n")
        assert '<span class="awiwi-mention">@@lars</span>.' in doc.html

    def test_mention_with_hyphen_gets_wrapped_span(self):
        doc = render_markdown("cc @@lars-w, thanks.\n")
        assert '<span class="awiwi-mention">@@lars-w</span>,' in doc.html

    def test_hashtag_gets_wrapped_span(self):
        doc = render_markdown("Filed under #project-awiwi today.\n")
        assert '<span class="awiwi-tag">#project-awiwi</span>' in doc.html

    def test_path_style_hashtag_gets_wrapped_span(self):
        doc = render_markdown("See #recipes/sourdough-starter for the method.\n")
        assert '<span class="awiwi-tag">#recipes/sourdough-starter</span>' in doc.html

    def test_heading_marker_is_not_mistaken_for_a_hashtag(self):
        doc = render_markdown("# Title\n\n## Section\n\nBody text.\n", title="X")
        assert "awiwi-tag" not in doc.html

    def test_markdown_link_href_is_not_mistaken_for_a_hashtag(self):
        doc = render_markdown("See [the section](#section-one) above.\n")
        assert "awiwi-tag" not in doc.html

    def test_hashtag_inside_inline_code_span_is_untouched(self):
        doc = render_markdown("Use `#project-awiwi` as a literal example.\n")
        assert "awiwi-tag" not in doc.html
        assert "<code>#project-awiwi</code>" in doc.html

    def test_mention_inside_inline_code_span_is_untouched(self):
        doc = render_markdown("Type `@@lars` literally.\n")
        assert "awiwi-mention" not in doc.html
        assert "<code>@@lars</code>" in doc.html

    def test_tag_and_hashtag_inside_fenced_code_block_are_untouched(self):
        text = (
            "```python\n# a comment with @bug and #project-awiwi and @@lars\nx = 1\n```\n"
        )
        doc = render_markdown(text)
        assert "awiwi-bug" not in doc.html
        assert "awiwi-tag" not in doc.html
        assert "awiwi-mention" not in doc.html
        assert "# a comment with @bug and #project-awiwi and @@lars" in doc.html
