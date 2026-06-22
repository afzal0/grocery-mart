import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Admin portal dev server on 5174. API base via VITE_API_BASE_URL (default :8080).
export default defineConfig({
  plugins: [react()],
  server: { port: 5174, strictPort: true },
});
