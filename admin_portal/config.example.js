// Rafik Admin Portal Configuration Template
// In production (Vercel, Netlify, Cloudflare Pages), populate this during build/deploy from environment variables.
window.RAFIK_CONFIG = {
  // 1. Firebase Cloud Engine (Firestore, Auth, Real-time streams)
  FIREBASE: {
    apiKey: "AIzaSyDemoDummyApiKeyForRafikEcosystem2026",
    authDomain: "rafik-app-2026.firebaseapp.com",
    projectId: "rafik-app-2026",
    storageBucket: "rafik-app-2026.appspot.com",
    messagingSenderId: "100000000000",
    appId: "1:100000000000:web:abcdef1234567890abcdef"
  },
  // 2. Supabase (Legacy fallback)
  SUPABASE_URL: "https://your-project-id.supabase.co",
  SUPABASE_ANON_KEY: "sb_publishable_your_anon_key_here"
};
