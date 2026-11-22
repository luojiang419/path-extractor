import 'package:flutter_test/flutter_test.dart';
import 'package:path_extractor_browser/models/file_entry.dart';

void main() {
  test('RAW 和 PSD 文件被识别为图片', () {
    expect(
      FileEntry.fromPath(r'C:\photos\shot.cr2', isDirectory: false).type,
      FileEntryType.image,
    );
    expect(
      FileEntry.fromPath(r'C:\photos\shot.cr3', isDirectory: false).type,
      FileEntryType.image,
    );
    expect(
      FileEntry.fromPath(r'C:\photos\layout.psd', isDirectory: false).type,
      FileEntryType.image,
    );
  });

  test('MXF 被识别为视频，常规格式保持原行为', () {
    expect(
      FileEntry.fromPath(r'C:\video\clip.mxf', isDirectory: false).type,
      FileEntryType.video,
    );
    expect(
      FileEntry.fromPath(r'C:\images\photo.jpg', isDirectory: false).type,
      FileEntryType.image,
    );
    expect(
      FileEntry.fromPath(r'C:\video\clip.mp4', isDirectory: false).type,
      FileEntryType.video,
    );
  });
}
