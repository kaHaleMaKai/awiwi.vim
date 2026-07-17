# awiwi frontend

Svelte 5 + TypeScript + Vite SPA for the awiwi note viewer. Talks to the FastAPI
backend in `server/` over `/api/*` (see
`handovers/server-rewrite/T23.2-api-routes.md` for the contract).

`dist/` is gitignored (ADR D25) — after checking out this repo, run `npm install && npm run build`
before starting the server, and rebuild after every change under `server/frontend/`.

Conventions, router/theme/api surface, and how this fits into the rest of the
rewrite: `handovers/server-rewrite/T25.1-scaffold.md`.

```sh
npm install
npm run dev      # vite dev server, proxies /api -> 127.0.0.1:5823
npm run build    # -> dist/ (gitignored — rebuild after checkout and after any frontend change, see D20)
npx svelte-check
npx vitest run
```
