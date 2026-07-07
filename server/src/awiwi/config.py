"""Server configuration.

Two distinct, deliberately separate sources:

- `Settings` — process-level configuration read from the environment
  (`AWIWI_*`), via pydantic-settings. Only `home` (the notes root) lives
  here today; host/port are launcher/uvicorn concerns (see
  `lua/awiwi/server.lua`'s `default_cmd_builder`), not the app's.
- `PluginConfig` — user-facing preferences the Neovim plugin writes to
  `<home>/config.json` on every `:Awiwi serve` (see
  `lua/awiwi/server.lua`'s `_write_json_config`). Parsed permissively
  (`extra="ignore"`) since the plugin may add/rename keys independently of
  the server; a missing file yields all-defaults rather than an error,
  since the plugin only (re)writes it when a server actually starts.
"""

from __future__ import annotations

from pathlib import Path

from typing import ClassVar

import logging

from pydantic import BaseModel, ConfigDict, ValidationError
from pydantic_settings import BaseSettings, SettingsConfigDict

CONFIG_FILENAME = "config.json"


class Settings(BaseSettings):
    """Process-level settings, read from `AWIWI_*` environment variables."""

    model_config: ClassVar[SettingsConfigDict] = SettingsConfigDict(env_prefix="AWIWI_")

    home: Path
    """Notes root directory (`AWIWI_HOME`). Required: fails fast if unset."""

    allow_remote: bool = False
    """Admit non-localhost clients (`AWIWI_ALLOW_REMOTE`). Off by default
    per user decision: localhost-only unless explicitly configured."""


class PluginConfig(BaseModel):
    """User preferences from `<home>/config.json`, written by the plugin.

    Every field has a default so a missing or partial config.json still
    yields a usable, fully-populated config.
    """

    model_config: ClassVar[ConfigDict] = ConfigDict(extra="ignore")

    search_engine: str = "rg"
    home: str = ""
    screensaver: str | bool = False
    """`vim.g.awiwi_screensaver` verbatim — a screensaver *name* string in
    real configs (e.g. "cinnamon"), false-y when unset."""
    link_color: str = ""
    todo_markers: list[str] = []
    onhold_markers: list[str] = []
    urgent_markers: list[str] = []
    delegate_markers: list[str] = []
    question_markers: list[str] = []
    due_markers: list[str] = []

    @classmethod
    def load(cls, home: Path) -> PluginConfig:
        """Load `<home>/config.json`; defaults if missing or unparseable.

        Preferences must never prevent boot: a config.json the model can't
        digest (stale format, hand-edited garbage) logs a warning and yields
        defaults. The plugin rewrites the file on every `:Awiwi serve`, so a
        healthy launcher self-heals the file anyway.
        """
        config_path = Path(home) / CONFIG_FILENAME
        if not config_path.is_file():
            return cls()
        try:
            return cls.model_validate_json(config_path.read_text())
        except (ValidationError, OSError) as exc:
            logging.getLogger(__name__).warning(
                "ignoring unparseable %s, using defaults: %s", config_path, exc
            )
            return cls()
