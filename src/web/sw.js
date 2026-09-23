// Backplane's service worker: the app shell from cache, so a reload on a
// poor connection shows the page (and the cached log) at once. Hashed
// chunks never change under their name (cache first); the page itself is
// fetched fresh when the network answers, else served from cache. The
// socket and MCP never pass through here.

const SHELL = "backplane-shell-v1";

self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (e) => e.waitUntil(self.clients.claim()));

self.addEventListener("fetch", (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== "GET" || url.origin !== location.origin) return;
  if (url.pathname.startsWith("/ws") || url.pathname.startsWith("/mcp")) return;
  if (url.pathname.startsWith("/chunk-")) {
    e.respondWith(caches.open(SHELL).then(async (c) => {
      const hit = await c.match(e.request);
      if (hit) return hit;
      const r = await fetch(e.request);
      if (r.ok) c.put(e.request, r.clone());
      return r;
    }));
    return;
  }
  e.respondWith(caches.open(SHELL).then(async (c) => {
    try {
      const r = await fetch(e.request);
      if (r.ok) c.put(e.request, r.clone());
      return r;
    } catch {
      return (await c.match(e.request)) ?? (await c.match("/")) ?? Response.error();
    }
  }));
});
