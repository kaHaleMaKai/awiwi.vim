"""FastAPI routers for the awiwi viewer.

`app.create_app()` includes these in order — `api`, then `redirects` — so
the `api` router (with its own `/api/{rest:path}` JSON-404 catch-all) resolves
anything under `/api/*` before the `redirects` router's app-wide
`/{path:path}` SPA catch-all (its last route) can see it.

The legacy template routers (`pages`, `assets`, `actions`) were dropped in
the T26 cutover; their modules still exist on disk (deleted in T27) but are
no longer imported or registered.
"""

from awiwi.routers import api, redirects

__all__ = ["api", "redirects"]
