import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    port: 5173,
    proxy: {
      '/api': 'http://localhost:5178',
    },
  },
  build: {
    // `npm run build` drops the SPA straight into the API's wwwroot,
    // so `dotnet run` alone serves the whole app in production.
    outDir: '../backend/Skarb.Api/wwwroot',
    emptyOutDir: true,
  },
})
