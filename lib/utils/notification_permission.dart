import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Requests the Android 13+ (API 33+) POST_NOTIFICATIONS permission so that
/// the media player card, lock screen controls, and OnePlus Dynamic Island
/// (Aqua Dynamics / Live Alerts) operate reliably on real devices.
Future<bool> requestNotificationPermissionIfNeeded() async {
  if (kIsWeb || !Platform.isAndroid) return true;

  try {
    final status = await Permission.notification.status;
    if (status.isGranted) return true;

    final result = await Permission.notification.request();
    return result.isGranted;
  } catch (e) {
    debugPrint('Notification permission error: $e');
    return false;
  }
}

