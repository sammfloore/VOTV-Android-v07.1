import 'package:flutter/services.dart';

class PlatformService {
  PlatformService._();

  static const MethodChannel _channel = MethodChannel('mx.avotv/platform');
  static Future<void> Function(String action)? _pipActionHandler;
  static void Function(bool isInPictureInPicture)? _pipModeHandler;
  static Object? _pipHandlerOwner;
  static Future<void> Function()? _playbackStateChangedHandler;
  static Future<void> Function(String payload)? _playerReplacementHandler;
  static Object? _playerReplacementOwner;
  static bool _handlerInstalled = false;

  static void setPictureInPictureHandlers({
    required Object owner,
    Future<void> Function(String action)? onAction,
    void Function(bool isInPictureInPicture)? onModeChanged,
  }) {
    _pipHandlerOwner = owner;
    _pipActionHandler = onAction;
    _pipModeHandler = onModeChanged;
    _installMethodHandler();
  }

  static void setPlaybackStateChangedHandler(
    Future<void> Function()? handler,
  ) {
    _playbackStateChangedHandler = handler;
    _installMethodHandler();
  }

  static void setPlayerReplacementHandler({
    required Object owner,
    Future<void> Function(String payload)? onReplace,
  }) {
    _playerReplacementOwner = owner;
    _playerReplacementHandler = onReplace;
    _installMethodHandler();
  }

  static void clearPlayerReplacementHandler({required Object owner}) {
    if (!identical(_playerReplacementOwner, owner)) return;
    _playerReplacementOwner = null;
    _playerReplacementHandler = null;
  }

  static void _installMethodHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'pipAction':
          final arguments = call.arguments;
          final action = arguments is Map ? '${arguments['action'] ?? ''}' : '';
          if (action.isNotEmpty) await _pipActionHandler?.call(action);
          return;
        case 'pipModeChanged':
          final arguments = call.arguments;
          final isInPip = arguments is Map && arguments['isInPip'] == true;
          _pipModeHandler?.call(isInPip);
          return;
        case 'playbackStateChanged':
          await _playbackStateChangedHandler?.call();
          return;
        case 'replacePlayerPayload':
          final arguments = call.arguments;
          final payload = arguments is Map
              ? '${arguments['payload'] ?? ''}'
              : '';
          if (payload.isNotEmpty) {
            await _playerReplacementHandler?.call(payload);
          }
          return;
      }
    });
  }

  static bool clearPictureInPictureHandlers({required Object owner}) {
    if (!identical(_pipHandlerOwner, owner)) return false;
    _pipHandlerOwner = null;
    _pipActionHandler = null;
    _pipModeHandler = null;
    return true;
  }


  static Future<bool> openPlayer(
    String payload, {
    bool bringToFront = true,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('openPlayer', {
            'payload': payload,
            'bringToFront': bringToFront,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> hasActivePlayer() async {
    try {
      return await _channel.invokeMethod<bool>('hasActivePlayer') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<String?> getPlayerPayload() async {
    try {
      return await _channel.invokeMethod<String>('getPlayerPayload');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<bool> isTelevision() async {
    try {
      return await _channel.invokeMethod<bool>('isTelevision') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> openCastSettings() async {
    try {
      await _channel.invokeMethod<void>('openCastSettings');
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> isPictureInPictureSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isPipSupported') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> isPictureInPictureAllowed() async {
    try {
      return await _channel.invokeMethod<bool>('isPipAllowed') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> isInPictureInPictureMode() async {
    try {
      return await _channel.invokeMethod<bool>('isInPipMode') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> configurePictureInPicture({
    required bool enabled,
    required bool autoEnter,
    required bool isPlaying,
    required bool hasNext,
    required String title,
    required String subtitle,
  }) async {
    try {
      await _channel.invokeMethod<void>('configurePip', {
        'enabled': enabled,
        'autoEnter': autoEnter,
        'isPlaying': isPlaying,
        'hasNext': hasNext,
        'title': title,
        'subtitle': subtitle,
      });
    } on PlatformException {
      // PiP is optional and must not interrupt playback.
    } on MissingPluginException {
      // Non-Android platforms do not provide the native channel.
    }
  }

  static Future<bool> enterPictureInPicture() async {
    try {
      return await _channel.invokeMethod<bool>('enterPip') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> openPictureInPictureSettings() async {
    try {
      await _channel.invokeMethod<void>('openPipSettings');
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> closePictureInPictureActivity() async {
    try {
      await _channel.invokeMethod<void>('closePipActivity');
    } on PlatformException {
      // The activity may already have been closed by Android.
    } on MissingPluginException {
      // No native activity exists on this platform.
    }
  }

  static Future<Map<String, dynamic>> recordingCapability() async {
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>(
        'recordingCapability',
      );
      return value == null ? const {} : Map<String, dynamic>.from(value);
    } on PlatformException {
      return const {};
    } on MissingPluginException {
      return const {};
    }
  }

  static Future<bool> requestRecordingNotificationPermission() async {
    try {
      return await _channel.invokeMethod<bool>(
            'requestRecordingNotificationPermission',
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> openRecordingNotificationSettings() async {
    try {
      await _channel.invokeMethod<void>('openRecordingNotificationSettings');
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<Map<String, dynamic>> startLiveRecording({
    required String sourceChannelId,
    required String title,
    required String channelTitle,
    required String posterUrl,
    required List<String> urls,
    required int maxDurationMinutes,
  }) async {
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>(
        'startLiveRecording',
        {
          'sourceChannelId': sourceChannelId,
          'title': title,
          'channelTitle': channelTitle,
          'posterUrl': posterUrl,
          'urls': urls,
          'maxDurationMinutes': maxDurationMinutes,
        },
      );
      return value == null ? const {} : Map<String, dynamic>.from(value);
    } on PlatformException catch (error) {
      return {
        'success': false,
        'message': error.message ?? 'Android no pudo iniciar la grabación.',
      };
    } on MissingPluginException {
      return const {
        'success': false,
        'message': 'La grabación local solo está disponible en Android.',
      };
    }
  }

  static Future<Map<String, dynamic>> stopLiveRecording() async {
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>(
        'stopLiveRecording',
      );
      return value == null ? const {} : Map<String, dynamic>.from(value);
    } on PlatformException catch (error) {
      return {
        'success': false,
        'message': error.message ?? 'No se pudo detener la grabación.',
      };
    } on MissingPluginException {
      return const {
        'success': false,
        'message': 'No existe una grabación activa.',
      };
    }
  }

  static Future<List<Map<String, dynamic>>> listLiveRecordings() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'listLiveRecordings',
      );
      return (raw ?? const [])
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList(growable: false);
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  static Future<Map<String, dynamic>?> activeLiveRecording() async {
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>(
        'activeLiveRecording',
      );
      return value == null ? null : Map<String, dynamic>.from(value);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<bool> deleteLiveRecording(String id) async {
    try {
      return await _channel.invokeMethod<bool>(
            'deleteLiveRecording',
            {'id': id},
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

}
