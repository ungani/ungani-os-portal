const UNGANI_CACHE_NAME = "ungani-os-pwa-cache-v1";

const UNGANI_CORE_ASSETS = [
  "/",
  "/index.html",
  "/login.html",
  "/client.html",
  "/admin-home.html",
  "/manifest.json",
  "/ungani-logo.png",
  "/client-shared.js",
  "/admin-shared.js",
  "/ungani-analytics.js",
  "/ungani-presets.js"
];

const UNGANI_CLIENT_PAGES = [
  "/my-profile.html",
  "/my-overview.html",
  "/my-charts.html",
  "/my-activity.html",
  "/my-calendar.html",
  "/my-money.html",
  "/my-records.html",
  "/my-documents.html",
  "/my-tasks.html",
  "/my-items.html",
  "/my-people.html",
  "/my-support.html",
  "/my-notices.html",
  "/my-chat.html",
  "/my-team-chat.html",
  "/reports.html",
  "/print-report.html"
];

const UNGANI_ADMIN_PAGES = [
  "/admin.html",
  "/admin-home.html",
  "/admin-charts.html",
  "/admin-calendar.html",
  "/admin-profiles.html",
  "/admin-people.html",
  "/admin-reports.html",
  "/admin-health.html",
  "/admin-money.html",
  "/admin-records.html",
  "/admin-documents.html",
  "/admin-tasks.html",
  "/admin-items.html",
  "/users.html",
  "/sections.html",
  "/billing.html",
  "/support.html",
  "/notices.html",
  "/admin-chat.html",
  "/admin-settings.html"
];

const UNGANI_CACHE_ASSETS = [
  ...UNGANI_CORE_ASSETS,
  ...UNGANI_CLIENT_PAGES,
  ...UNGANI_ADMIN_PAGES
];

self.addEventListener("install", function (event) {
  event.waitUntil(
    caches.open(UNGANI_CACHE_NAME)
      .then(function (cache) {
        return cache.addAll(UNGANI_CACHE_ASSETS.map(function (asset) {
          return new Request(asset, { cache: "reload" });
        }));
      })
      .then(function () {
        return self.skipWaiting();
      })
      .catch(function (error) {
        console.warn("UNGANI OS service worker install warning:", error);
      })
  );
});

self.addEventListener("activate", function (event) {
  event.waitUntil(
    caches.keys()
      .then(function (cacheNames) {
        return Promise.all(
          cacheNames.map(function (cacheName) {
            if (cacheName !== UNGANI_CACHE_NAME) {
              return caches.delete(cacheName);
            }

            return null;
          })
        );
      })
      .then(function () {
        return self.clients.claim();
      })
  );
});

self.addEventListener("fetch", function (event) {
  const request = event.request;

  if (request.method !== "GET") {
    return;
  }

  const url = new URL(request.url);

  if (url.origin !== self.location.origin) {
    return;
  }

  if (request.mode === "navigate") {
    event.respondWith(networkFirstPage(request));
    return;
  }

  if (
    url.pathname.endsWith(".js") ||
    url.pathname.endsWith(".css") ||
    url.pathname.endsWith(".png") ||
    url.pathname.endsWith(".jpg") ||
    url.pathname.endsWith(".jpeg") ||
    url.pathname.endsWith(".webp") ||
    url.pathname.endsWith(".svg") ||
    url.pathname.endsWith(".json")
  ) {
    event.respondWith(cacheFirstAsset(request));
    return;
  }

  event.respondWith(networkFirstPage(request));
});

async function networkFirstPage(request) {
  try {
    const freshResponse = await fetch(request);

    const cache = await caches.open(UNGANI_CACHE_NAME);
    cache.put(request, freshResponse.clone());

    return freshResponse;
  } catch (error) {
    const cachedResponse = await caches.match(request);

    if (cachedResponse) {
      return cachedResponse;
    }

    const fallbackLogin = await caches.match("/login.html");

    if (fallbackLogin) {
      return fallbackLogin;
    }

    return new Response(
      buildOfflineHtml(),
      {
        headers: {
          "Content-Type": "text/html"
        }
      }
    );
  }
}

async function cacheFirstAsset(request) {
  const cachedResponse = await caches.match(request);

  if (cachedResponse) {
    return cachedResponse;
  }

  try {
    const freshResponse = await fetch(request);

    const cache = await caches.open(UNGANI_CACHE_NAME);
    cache.put(request, freshResponse.clone());

    return freshResponse;
  } catch (error) {
    return new Response("", {
      status: 408,
      statusText: "Offline asset unavailable"
    });
  }
}

function buildOfflineHtml() {
  return `
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <title>UNGANI OS Offline</title>
      <style>
        :root {
          --navy: #061C3D;
          --gold: #D4A63A;
          --dark: #020617;
          --white: #FFFFFF;
          --muted: #CBD5E1;
        }

        * {
          box-sizing: border-box;
        }

        body {
          margin: 0;
          min-height: 100vh;
          font-family: Inter, Arial, sans-serif;
          background:
            radial-gradient(circle at top right, rgba(212,166,58,0.16), transparent 34%),
            linear-gradient(135deg, #020617, #061C3D);
          color: var(--white);
          display: flex;
          align-items: center;
          justify-content: center;
          padding: 24px;
        }

        .offline-card {
          width: min(520px, 100%);
          background: rgba(255,255,255,0.08);
          border: 1px solid rgba(255,255,255,0.14);
          border-radius: 30px;
          padding: 28px;
          box-shadow: 0 30px 90px rgba(0,0,0,0.32);
          text-align: center;
        }

        img {
          width: 86px;
          height: auto;
          background: white;
          border-radius: 22px;
          padding: 10px;
          margin-bottom: 18px;
        }

        h1 {
          margin: 0 0 10px;
          font-size: 34px;
          letter-spacing: -0.05em;
        }

        p {
          color: var(--muted);
          line-height: 1.55;
          margin: 0 0 18px;
        }

        button {
          border: 0;
          border-radius: 999px;
          padding: 13px 18px;
          background: var(--gold);
          color: var(--navy);
          font-weight: 950;
          cursor: pointer;
        }
      </style>
    </head>

    <body>
      <main class="offline-card">
        <img src="/ungani-logo.png" alt="UNGANI Logo" />
        <h1>UNGANI OS is offline</h1>
        <p>
          Some saved pages can still open from cache, but live data needs internet connection.
          Reconnect and refresh to continue.
        </p>
        <button onclick="window.location.reload()">Try Again</button>
      </main>
    </body>
    </html>
  `;
}
