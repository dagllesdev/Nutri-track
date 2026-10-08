const CACHE='nutritrack-v3'; const ASSETS=['./','./app.js','./config.js','./styles.css','./manifest.webmanifest'];
self.addEventListener('install', e=>e.waitUntil(caches.open(CACHE).then(c=>c.addAll(ASSETS))));
self.addEventListener('activate', e=>e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', e=>{ if(e.request.method==='GET') e.respondWith(fetch(e.request).catch(()=>caches.match(e.request))); });
