import 'dart:typed_data';

import 'package:flutter/services.dart';

enum SpecialImageFormatHint { raw, psd }

class SpecialImageThumbnailService {
  static const MethodChannel _channel = MethodChannel(
    'path_extractor_browser/special_thumbnail',
  );

  static Future<Uint8List?> generateThumbnail({
    required String path,
    required SpecialImageFormatHint formatHint,
    required int maxEdge,
  }) async {
    try {
      return await _channel.invokeMethod<Uint8List>('generateSpecialThumbnail', {
        'path': path,
        'formatHint': switch (formatHint) {
          SpecialImageFormatHint.raw => 'raw',
          SpecialImageFormatHint.psd => 'psd',
        },
        'maxEdge': maxEdge,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
