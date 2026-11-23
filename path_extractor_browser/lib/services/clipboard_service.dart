import 'package:flutter/services.dart';

abstract class ClipboardService {
  Future<void> copyToClipboard(String text);
}

class ClipboardServiceImpl implements ClipboardService {
  @override
  Future<void> copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }
}
