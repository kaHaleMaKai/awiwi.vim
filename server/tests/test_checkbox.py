"""Unit tests for awiwi.checkbox — md5 line-hash contract + in-place toggle.

`hash_line` golden values below were computed once, offline, by running the
exact legacy algorithm from `server.old/app.py:hash_line` against each
sample line (not by importing/reusing our own implementation) — see the
module docstring in checkbox.py for the ported algorithm.
"""

from pathlib import Path

import pytest

from awiwi.checkbox import (
    AlreadyInStateError,
    HashMismatchError,
    LineNotFoundError,
    NotACheckboxLineError,
    hash_line,
    toggle_checkbox,
)


class TestHashLine:
    def test_unchecked_box(self):
        assert hash_line("* [ ] buy milk\n") == "2932499cc7e044bdfca491b1c40c3837"

    def test_checked_box_hashes_same_as_unchecked(self):
        # The box glyph itself is stripped before hashing, so checked and
        # unchecked variants of the same line hash identically — this is
        # the whole point: the hash identifies the *line*, independent of
        # its current checked state.
        assert hash_line("* [x] buy milk\n") == "2932499cc7e044bdfca491b1c40c3837"

    def test_indented_box(self):
        assert hash_line("  * [ ] nested todo\n") == "76662c9128efdff7b56d067a0adbb443"

    def test_no_trailing_newline(self):
        assert hash_line("* [ ] no trailing newline") == (
            "205dafba23f2582d9aa7497a8abfaf05"
        )

    def test_non_checkbox_line(self):
        assert hash_line("not a checkbox line\n") == "9098f8d0a0fc139ff9d642bcda02ffc5"

    def test_dash_bullet_unchecked_box(self):
        # S32.1: dash bullets (stakeholder's notes use `- [ ]`) must strip
        # the box before hashing too, same as asterisk bullets, so toggling
        # doesn't change a dash line's own hash.
        assert hash_line("- [ ] buy milk\n") == hash_line("- [x] buy milk\n")

    def test_dash_and_asterisk_bullet_hash_differ(self):
        # Sanity check: the bullet glyph itself is part of the hashed
        # content -- a dash line and an asterisk line are different lines.
        assert hash_line("- [ ] buy milk\n") != hash_line("* [ ] buy milk\n")


class TestToggleCheckbox:
    def _write(self, tmp_path: Path, lines: list[str]) -> Path:
        p = tmp_path / "todos.md"
        _ = p.write_text("".join(lines))
        return p

    def test_checks_an_unchecked_box(self, tmp_path: Path):
        line = "* [ ] buy milk\n"
        path = self._write(tmp_path, ["# TODO\n", line])
        h = hash_line(line)

        toggle_checkbox(path, 1, True, h)

        assert path.read_text() == "# TODO\n* [x] buy milk\n"

    def test_unchecks_a_checked_box(self, tmp_path: Path):
        line = "* [x] buy milk\n"
        path = self._write(tmp_path, ["# TODO\n", line])
        h = hash_line(line)

        toggle_checkbox(path, 1, False, h)

        assert path.read_text() == "# TODO\n* [ ] buy milk\n"

    def test_preserves_indentation_and_surrounding_lines(self, tmp_path: Path):
        lines = ["# TODO\n", "  * [ ] nested todo\n", "trailer\n"]
        path = self._write(tmp_path, lines)
        h = hash_line(lines[1])

        toggle_checkbox(path, 1, True, h)

        assert path.read_text() == "# TODO\n  * [x] nested todo\ntrailer\n"

    def test_wrong_hash_raises_and_leaves_file_untouched(self, tmp_path: Path):
        line = "* [ ] buy milk\n"
        path = self._write(tmp_path, [line])
        original = path.read_text()

        with pytest.raises(HashMismatchError):
            toggle_checkbox(path, 0, True, "deadbeef")

        assert path.read_text() == original

    def test_already_checked_raises(self, tmp_path: Path):
        line = "* [x] buy milk\n"
        path = self._write(tmp_path, [line])
        h = hash_line(line)

        with pytest.raises(AlreadyInStateError):
            toggle_checkbox(path, 0, True, h)

    def test_already_unchecked_raises(self, tmp_path: Path):
        line = "* [ ] buy milk\n"
        path = self._write(tmp_path, [line])
        h = hash_line(line)

        with pytest.raises(AlreadyInStateError):
            toggle_checkbox(path, 0, False, h)

    def test_line_beyond_eof_raises_line_not_found(self, tmp_path: Path):
        path = self._write(tmp_path, ["only one line\n"])

        # Legacy crash case: server.old/app.py's update_checkbox_in_file
        # reads an empty string past EOF and then crashes on `line[-1]`
        # (IndexError -> uncaught 500). Assessed behavior: raise a distinct,
        # catchable error instead.
        with pytest.raises(LineNotFoundError):
            toggle_checkbox(path, 5, True, "irrelevant")

    def test_checks_an_unchecked_dash_bullet_box(self, tmp_path: Path):
        # S32.1: dash bullets must round-trip through toggle_checkbox the
        # same way asterisk bullets do.
        line = "- [ ] buy milk\n"
        path = self._write(tmp_path, ["# TODO\n", line])
        h = hash_line(line)

        toggle_checkbox(path, 1, True, h)

        assert path.read_text() == "# TODO\n- [x] buy milk\n"

    def test_preserves_indentation_for_dash_bullet(self, tmp_path: Path):
        lines = ["# TODO\n", "  - [ ] nested todo\n", "trailer\n"]
        path = self._write(tmp_path, lines)
        h = hash_line(lines[1])

        toggle_checkbox(path, 1, True, h)

        assert path.read_text() == "# TODO\n  - [x] nested todo\ntrailer\n"

    def test_non_checkbox_line_raises(self, tmp_path: Path):
        line = "just prose, no checkbox\n"
        path = self._write(tmp_path, [line])
        h = hash_line(line)

        with pytest.raises(NotACheckboxLineError):
            toggle_checkbox(path, 0, True, h)

    def test_missing_file_raises_file_not_found(self, tmp_path: Path):
        missing = tmp_path / "nope.md"

        with pytest.raises(FileNotFoundError):
            toggle_checkbox(missing, 0, True, "irrelevant")
