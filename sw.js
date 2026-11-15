/* Family Hub 서비스워커 — 앱 설치 + 휴대폰 알림(웹 푸시) + 아이콘 배지
   데이터는 캐시하지 않고 항상 최신으로 불러옵니다. */
const META = 'fh-meta';
async function getCount() { const c = await caches.open(META); const r = await c.match('/__badge'); return r ? +(await r.text()) || 0 : 0; }
async function setCount(n) { const c = await caches.open(META); await c.put('/__badge', new Response(String(n))); }

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', e => {
  if (e.request.mode !== 'navigate') return;
  e.respondWith(fetch(e.request).catch(() => new Response(
    '<meta charset="utf-8"><meta name="viewport" content="width=device-width"><div style="font-family:sans-serif;padding:48px 24px;text-align:center"><h3>🏡 오프라인이에요</h3><p>인터넷 연결을 확인한 뒤 다시 열어 주세요.</p></div>',
    { headers: { 'Content-Type': 'text/html; charset=utf-8' } })));
});
self.addEventListener('push', e => {
  let d = {}; try { d = e.data ? e.data.json() : {}; } catch (er) { d = { body: e.data && e.data.text() }; }
  e.waitUntil((async () => {
    const wins = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    wins.forEach(w => { try { w.postMessage({ type: 'fh-push', data: d }); } catch (er) {} });
    const n = (await getCount()) + 1; await setCount(n);
    try { if (self.navigator.setAppBadge) await self.navigator.setAppBadge(n); } catch (er) {}
    await self.registration.showNotification(d.title || '🏡 Family Hub', {
      body: d.body || '', icon: 'icons/fh-192.png', badge: 'icons/badge.png',
      tag: 'fh-' + Date.now(), data: { url: d.url || './' }, vibrate: [80, 40, 80]
    });
  })());
});
self.addEventListener('notificationclick', e => {
  e.notification.close();
  const url = new URL((e.notification.data && e.notification.data.url) || './', self.registration.scope).href;
  e.waitUntil((async () => {
    await setCount(0);
    const wins = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const w of wins) { if (w.url.startsWith(self.registration.scope)) { await w.focus(); try { await w.navigate(url); } catch (er) {} return; } }
    await self.clients.openWindow(url);
  })());
});
self.addEventListener('message', e => { if (e.data && e.data.type === 'clear-badge') e.waitUntil(setCount(0)); });
