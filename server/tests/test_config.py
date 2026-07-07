"""Acceptance tests for awiwi.config: Settings (env) and PluginConfig (config.json).

Contract (design brief §Proposed structure, T13 S13.1):
- Settings is pydantic-settings, env_prefix AWIWI_. `home` is required from
  AWIWI_HOME; instantiating without it must fail fast with a clear error.
- PluginConfig parses `<home>/config.json`, extra="ignore" (permissive).
  Missing file -> all defaults, no error. Keys match what
  lua/awiwi/server.lua's `_write_json_config` writes: search_engine, home,
  screensaver, link_color, and <marker>_markers lists for
  todo/onhold/urgent/delegate/question/due.
"""

import json
from pathlib import Path

import pytest
from pydantic import ValidationError

from awiwi.config import PluginConfig, Settings


class TestSettings:
    def test_reads_home_from_env(self, monkeypatch: pytest.MonkeyPatch, tmp_path: Path):
        monkeypatch.setenv("AWIWI_HOME", str(tmp_path))
        # `home` is populated from AWIWI_HOME at runtime by pydantic-settings;
        # static analysis can't see that, hence it flags it as a missing
        # constructor argument.
        settings = Settings()  # pyright: ignore[reportCallIssue]
        assert settings.home == tmp_path

    def test_missing_home_fails_fast(self, monkeypatch: pytest.MonkeyPatch):
        monkeypatch.delenv("AWIWI_HOME", raising=False)
        with pytest.raises(ValidationError):
            _ = Settings()  # pyright: ignore[reportCallIssue]

    def test_settings_ignores_unrelated_env(
        self, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
    ):
        monkeypatch.setenv("AWIWI_HOME", str(tmp_path))
        monkeypatch.setenv("UNRELATED_VAR", "whatever")
        settings = Settings()  # pyright: ignore[reportCallIssue]
        assert settings.home == tmp_path


class TestPluginConfig:
    def test_parses_real_config_json(self, notes_home: Path):
        config = PluginConfig.load(notes_home)
        assert config.search_engine == "rg"
        assert config.home == str(notes_home)
        assert config.screensaver is False
        assert config.link_color == "#0000ff"
        assert config.todo_markers == ["TODO"]
        assert config.onhold_markers == ["ONHOLD"]
        assert config.urgent_markers == ["URGENT"]
        assert config.delegate_markers == ["DELEGATE"]
        assert config.question_markers == ["QUESTION"]
        assert config.due_markers == ["DUE"]

    def test_missing_file_returns_defaults(self, tmp_path: Path):
        # tmp_path has no config.json at all.
        config = PluginConfig.load(tmp_path)
        assert config == PluginConfig()

    def test_extra_keys_are_ignored(self, tmp_path: Path):
        _ = (tmp_path / "config.json").write_text(
            json.dumps({"search_engine": "rg", "some_unknown_future_key": 123})
        )
        config = PluginConfig.load(tmp_path)
        assert config.search_engine == "rg"

    def test_defaults_when_keys_absent(self, tmp_path: Path):
        _ = (tmp_path / "config.json").write_text(json.dumps({}))
        config = PluginConfig()
        loaded = PluginConfig.load(tmp_path)
        assert loaded == config
