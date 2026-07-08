const CACHE_NAME = "ungani-os-pwa-cache-v5";

const CORE_ASSETS = [
  "/",
  "/index.html",
  "/login.html",
  "/client.html",
  "/admin-home.html",
  "/admin-notifications.html",
  "/client-notifications.html",
  "/manifest.json",
  "/ungani-logo.png"
];

const CLIENT_PAGE_ASSETS = [
  "/client.html",
  "/client-notifications.html",
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

const ADMIN_PAGE_ASSETS = [
  "/admin-home.html",
  "/admin-notifications.html",
  "/admin.html",
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

const SCRIPT_ASSETS = [
  "/pwa-register.js",
  "/client-shared.js",
  "/admin-shared.js",
  "/ungani-analytics.js",
  "/ungani-presets.js"
];

self.addEventListener("install", function (event) {
  self.skipWaiting();

  event.waitUntil(
    caches.open(CACHE_NAME).then(function (cache) {
      return cache.addAll([
        ...CORE_ASSETS,
        ...CLIENT_PAGE_ASSETS,
        ...ADMIN_PAGE_ASSETS,
        ...SCRIPT_ASSETS
      ]);
    })
  );
});

self.addEventListener("activate", function (event) {
  event.waitUntil(
    caches
      .keys()
      .then(function (keys) {
        return Promise.all(
          keys
            .filter(function (key) {
              return key !== CACHE_NAME;
            })
            .map(function (key) {
              return caches.delete(key);
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
    url.pathname.endsWith(".json")
  ) {
    event.respondWith(networkFirstAsset(request));
    return;
  }

  if (
    url.pathname.endsWith(".png") ||
    url.pathname.endsWith(".jpg") ||
    url.pathname.endsWith(".jpeg") ||
    url.pathname.endsWith(".webp") ||
    url.pathname.endsWith(".svg")
  ) {
    event.respondWith(cacheFirstAsset(request));
    return;
  }

  event.respondWith(networkFirstAsset(request));
});

async function networkFirstPage(request) {
  try {
    const freshResponse = await fetch(request, {
      cache: "no-store"
    });

    const cache = await caches.open(CACHE_NAME);
    cache.put(request, freshResponse.clone());

    return freshResponse;
  } catch (error) {
    const cachedResponse = await caches.match(request);

    if (cachedResponse) {
      return cachedResponse;
    }

    const loginFallback = await caches.match("/login.html");

    if (loginFallback) {
      return loginFallback;
    }

    return offlineFallback();
  }
}

async function networkFirstAsset(request) {
  try {
    const freshResponse = await fetch(request, {
      cache: "no-store"
    });

    const cache = await caches.open(CACHE_NAME);
    cache.put(request, freshResponse.clone());

    return freshResponse;
  } catch (error) {
    const cachedResponse = await caches.match(request);

    if (cachedResponse) {
      return cachedResponse;
    }

    return new Response("", {
      status: 404,
      statusText: "Offline asset not found"
    });
  }
}

async function cacheFirstAsset(request) {
  const cachedResponse = await caches.match(request);

  if (cachedResponse) {
    return cachedResponse;
  }

  try {
    const freshResponse = await fetch(request);

    const cache = await caches.open(CACHE_NAME);
    cache.put(request, freshResponse.clone());

    return freshResponse;
  } catch (error) {
    return new Response("", {
      status: 404,
      statusText: "Offline image not found"
    });
  }
}

function offlineFallback() {
  return new Response(
    `
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <title>UNGANI OS Offline</title>
        <style>
          body {
            margin: 0;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            background: #061C3D;
            color: white;
            font-family: Arial, sans-serif;
            padding: 24px;
          }

          .box {
            max-width: 460px;
            background: rgba(255,255,255,0.08);
            border: 1px solid rgba(255,255,255,0.15);
            border-radius: 24px;
            padding: 24px;
            text-align: center;
          }

          img {
            width: 82px;
            height: 82px;
            object-fit: contain;
            background: white;
            border-radius: 20px;
            padding: 10px;
            margin-bottom: 16px;
          }

          h1 {
            margin: 0 0 8px;
            color: #D4A63A;
          }

          p {
            color: rgba(255,255,255,0.76);
            line-height: 1.5;
          }
        </style>
      </head>
      <body>
        <div class="box">
          <img src="/ungani-logo.png" alt="UNGANI Logo" />
          <h1>UNGANI OS</h1>
          <p>You are offline. Some saved pages may still open, but live business data needs internet connection.</p>
        </div>
      </body>
    </html>
    `,
    {
      headers: {
        "Content-Type": "text/html"
      }
    }
  );
}
