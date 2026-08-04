// =========================================================
// UNGANI OS Service Worker
// PWA install + safe cache refresh
// =========================================================

const CACHE_NAME = "ungani-os-cache-v2";

const CORE_ASSETS = [
  "/",
  "/login.html",
  "/manifest.json",
  "/ungani-logo.png"
];

self.addEventListener("install", (event) => {
  self.skipWaiting();

  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(CORE_ASSETS).catch(() => true);
    })
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys
          .filter((key) => key !== CACHE_NAME)
          .map((key) => caches.delete(key))
      );
    }).then(() => self.clients.claim())
  );
});

// Push payload is always JSON (sent by /api/send-push.js), with a plain-
// text fallback in case a payload ever arrives some other way. icon/badge
// default to existing manifest.json assets so every push looks branded
// even if the sender didn't specify them.
self.addEventListener("push", (event) => {
  let payload = {};

  try {
    payload = event.data ? event.data.json() : {};
  } catch (error) {
    payload = { title: "UNGANI OS", body: event.data ? event.data.text() : "You have a new UNGANI OS notification." };
  }

  const title = payload.title || "UNGANI OS";
  const options = {
    body: payload.body || "You have a new UNGANI OS notification.",
    icon: payload.icon || "/ungani-icon-192.png",
    badge: payload.badge || "/ungani-icon-96.png",
    data: { url: payload.url || "/" },
    tag: payload.tag || undefined,
    renotify: Boolean(payload.tag)
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

// Focuses an already-open tab on the target URL instead of always opening
// a new one - if none of the open windows match, falls back to opening a
// fresh one.
self.addEventListener("notificationclick", (event) => {
  event.notification.close();

  const targetUrl = (event.notification.data && event.notification.data.url) || "/";

  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((windowClients) => {
      for (const client of windowClients) {
        if (client.url.indexOf(targetUrl) !== -1 && "focus" in client) {
          return client.focus();
        }
      }

      if (self.clients.openWindow) {
        return self.clients.openWindow(targetUrl);
      }
    })
  );
});

self.addEventListener("fetch", (event) => {
  const request = event.request;

  if (request.method !== "GET") return;

  const url = new URL(request.url);

  if (url.origin !== self.location.origin) return;

  event.respondWith(
    fetch(request)
      .then((response) => {
        const responseClone = response.clone();

        caches.open(CACHE_NAME).then((cache) => {
          cache.put(request, responseClone).catch(() => true);
        });

        return response;
      })
      .catch(() => {
        return caches.match(request).then((cached) => {
          return cached || caches.match("/login.html");
        });
      })
  );
});
