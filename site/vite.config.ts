import { defineConfig } from 'vite'
import pandacss from '@pandacss/vite'
import react from '@vitejs/plugin-react'

// Served from https://p-dim-popov.github.io/recover-secrets/
export default defineConfig({
  base: '/recover-secrets/',
  plugins: [pandacss(), react()],
})
