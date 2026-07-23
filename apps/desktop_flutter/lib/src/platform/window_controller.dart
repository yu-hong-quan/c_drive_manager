import 'package:flutter/services.dart';

/// Thin Dart bridge for native Windows caption actions used by the custom top bar.
class WindowController {
  static const _channel = MethodChannel('c_drive_manager/window');

  static Future<void> startDrag() => _channel.invokeMethod<void>('startDrag');

  static Future<void> minimize() => _channel.invokeMethod<void>('minimize');

  static Future<void> toggleMaximize() =>
      _channel.invokeMethod<void>('toggleMaximize');

  static Future<void> close() => _channel.invokeMethod<void>('close');
}
