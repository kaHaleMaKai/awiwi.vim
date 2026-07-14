/// <reference types="vitest/config" />
import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'

// https://vite.dev/config/
export default defineConfig({
  base: '/_app/',
  plugins: [svelte()],
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
