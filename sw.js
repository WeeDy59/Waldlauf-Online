// Waldlauf Service Worker (App-Modus). Version wird bei jedem Build erhöht.
const V='waldlauf-0.67.0',CORE=['spiel.html','manifest.webmanifest','icon-192.png','icon-512.png'];
self.addEventListener('install',e=>{e.waitUntil(caches.open(V).then(c=>c.addAll(CORE)).then(()=>self.skipWaiting()))});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!==V).map(x=>caches.delete(x)))).then(()=>self.clients.claim()))});
self.addEventListener('fetch',e=>{const r=e.request,u=new URL(r.url);if(r.method!=='GET'||u.origin!==location.origin||/\.mp3$/.test(u.pathname))return;
 if(r.mode==='navigate'||/\.html$/.test(u.pathname)){e.respondWith(fetch(r).then(x=>{const c=x.clone();caches.open(V).then(k=>k.put(r,c));return x}).catch(()=>caches.match(r).then(x=>x||caches.match('spiel.html'))));return}
 e.respondWith(caches.match(r).then(x=>x||fetch(r)))});
