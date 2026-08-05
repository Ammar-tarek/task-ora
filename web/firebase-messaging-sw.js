// web/firebase-messaging-sw.js
// Firebase Cloud Messaging Service Worker for background web push notifications

importScripts('https://www.gstatic.com/firebasejs/9.22.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.22.1/firebase-messaging-compat.js');

// Initialize Firebase in the service worker
firebase.initializeApp({
  apiKey: "AIzaSyDZCsd-frVD0GTSHYpMLR3cnhTM7M-t1Ic",
  authDomain: "taskora-ab918.firebaseapp.com",
  projectId: "taskora-ab918",
  storageBucket: "taskora-ab918.firebasestorage.app",
  messagingSenderId: "140024409514",
  appId: "1:140024409514:web:fcf60a381852c8929c4fd3"
});

const messaging = firebase.messaging();

// Background message handler
messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Received background message: ', payload);
  
  const title = payload.notification?.title || payload.data?.title || 'CashBack Notification';
  const options = {
    body: payload.notification?.body || payload.data?.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/favicon.png',
    data: payload.data || {}
  };

  return self.registration.showNotification(title, options);
});

// Notification click handler — focus or open app window
self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windowClients) => {
      // If a window tab is already open, focus it
      for (let i = 0; i < windowClients.length; i++) {
        const client = windowClients[i];
        if (client.url && 'focus' in client) {
          return client.focus();
        }
      }
      // If no window tab is open, open a new one
      if (clients.openWindow) {
        return clients.openWindow('/');
      }
    })
  );
});
