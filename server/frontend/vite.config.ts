/// <reference types="vitest/config" />
import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'

// https://vite.dev/config/
export default defineConfig({
  base: '/_app/',
  plugins: [svelte()],
  // Under vitest only, resolve Svelte's browser build so mount()/actions run in
  // happy-dom. Left off otherwise so the production build keeps Vite's default
  // conditions (an explicit list would replace them, not extend them).
  ...(process.env.VITEST ? { resolve: { conditions: ["browser"] } } : {}),
  server: {
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:5823',
        ws: true,
      },
    },
  },
  test: {
    environment: 'happy-dom',
    globals: false,
  },
})
