import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { VitePWA } from 'vite-plugin-pwa'

export default defineConfig({
  base: process.env.VITE_BASE_PATH || '/',
  build: { rollupOptions: { output: { manualChunks: { react: ['react', 'react-dom'], motion: ['motion/react'], supabase: ['@supabase/supabase-js'] } } } },
  plugins: [react(), VitePWA({
    registerType: 'autoUpdate',
    includeAssets: ['favicon.svg', 'icon-192.png', 'icon-512.png', 'melo-push-sw.js'],
    manifest: {
      name: 'Melo — мессенджер', short_name: 'Melo', description: 'Быть ближе — просто',
      theme_color: '#f8f6ff', background_color: '#f8f6ff', display: 'standalone', lang: 'ru',
      icons: [{ src: 'icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' }, { src: 'icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' }]
    },
    workbox: { importScripts: ['melo-push-sw.js'], globPatterns: ['**/*.{js,css,html,svg,woff2}'], navigateFallback: 'index.html', navigateFallbackDenylist: [/\/api\//], runtimeCaching: [] }
  })]
})
