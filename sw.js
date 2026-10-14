// Waldlauf Service Worker (App-Modus). Version wird bei jedem Build erhöht.
const V='waldlauf-0.81.2',CORE=['spiel.html','manifest.webmanifest','icon-192.png','icon-512.png'];
self.addEventListener('install',e=>{e.waitUntil(caches.open(V).then(c=>c.addAll(CORE)).then(()=>self.skipWaiting()))});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!==V).map(x=>caches.delete(x)))).then(()=>self.clients.claim()))});
self.addEventListener('fetch',e=>{const r=e.request,u=new URL(r.url);if(r.method!=='GET'||u.origin!==location.origin||/\.mp3$/.test(u.pathname))return;
 if(r.mode==='navigate'||/\.html$/.test(u.pathname)){e.respondWith(fetch(r).then(x=>{const c=x.clone();caches.open(V).then(k=>k.put(r,c));return x}).catch(()=>caches.match(r).then(x=>x||caches.match('spiel.html'))));return}
 e.respondWith(caches.match(r).then(x=>x||fetch(r)))});
// Benachrichtigungen
self.addEventListener('push',e=>{let d={};try{d=e.data?e.data.json():{}}catch(_){d={body:e.data?e.data.text():''}}
 e.waitUntil(self.registration.showNotification(d.title||'Waldlauf',{body:d.body||'',icon:'icon-192.png',badge:'icon-192.png',tag:d.tag||'waldlauf',renotify:true,data:{url:d.url||'spiel.html'}}))});
self.addEventListener('notificationclick',e=>{e.notification.close();const url=new URL((e.notification.data&&e.notification.data.url)||'spiel.html',self.registration.scope).href;
 e.waitUntil(clients.matchAll({type:'window',includeUncontrolled:true}).then(L=>{for(const c of L){if(c.url.startsWith(self.registration.scope)&&'focus' in c)return c.focus()}return clients.openWindow(url)}))});
