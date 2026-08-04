// lib/core/services/web_notification/web_notification_web.dart
import 'dart:js_interop';

@JS('Notification')
extension type JSNotificationOptions._(JSObject _) implements JSObject {
  external factory JSNotificationOptions({JSString? body, JSString? icon});
}

@JS('Notification')
extension type JSNotification._(JSObject _) implements JSObject {
  external factory JSNotification(JSString title, [JSNotificationOptions options]);
  external static JSString get permission;
  external static JSPromise<JSString> requestPermission();
}

void requestWebNotificationPermission() {
  try {
    if (JSNotification.permission.toDart != 'granted') {
      JSNotification.requestPermission();
    }
  } catch (_) {}
}

void showWebNotification({required String title, required String body}) {
  try {
    final perm = JSNotification.permission.toDart;
    if (perm == 'granted') {
      JSNotification(
        title.toJS,
        JSNotificationOptions(
          body: body.toJS,
          icon: 'favicon.png'.toJS,
        ),
      );
    } else if (perm != 'denied') {
      JSNotification.requestPermission().toDart.then((value) {
        if (value.toDart == 'granted') {
          JSNotification(
            title.toJS,
            JSNotificationOptions(
              body: body.toJS,
              icon: 'favicon.png'.toJS,
            ),
          );
        }
      });
    }
  } catch (_) {}
}
