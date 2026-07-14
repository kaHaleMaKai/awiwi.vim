# awiwi frontend

Svelte 5 + TypeScript + Vite SPA for the awiwi note viewer. Talks to the FastAPI
backend in `server/` over `/api/*` (see
`handovers/server-rewrite/T23.2-api-routes.md` for the contract).

Conventions, router/theme/api surface, and how this fits into the rest of the
rewrite: `handovers/server-rewrite/T25.1-scaffold.md`.

```sh
npm install
npm run dev      # vite dev server, proxies /api -> 127.0.0.1:5823
npm run build    # -> dist/ (committed at integration time, see T26)
npx svelte-check
npx vitest run
```
