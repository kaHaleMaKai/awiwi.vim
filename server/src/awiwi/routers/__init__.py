"""FastAPI routers for the awiwi viewer.

`app.create_app()` includes these in order — assets, then actions, then
pages — so that `pages`' `/{path:path}` catch-all (the last route in that
module) stays the final route registered on the app.
"""

from awiwi.routers import actions, assets, pages

__all__ = ["actions", "assets", "pages"]
