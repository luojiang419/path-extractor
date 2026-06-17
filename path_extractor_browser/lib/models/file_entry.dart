enum FileEntryType {
  directory,
  image,
  video,
  audio,
  code,
  document,
  archive,
  other,
}

class FileEntry {
  final String path;
  final String name;
  final bool isDirectory;
  final FileEntryType type;

  const FileEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.type,
  });

  factory FileEntry.fromPath(String path, {bool isDirectory = false}) {
    final name =
        path.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).lastOrNull ??
        path;

    FileEntryType type;
    if (isDirectory) {
      type = FileEntryType.directory;
    } else {
      final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
      type = _inferType(ext);
    }

    return FileEntry(
      path: path,
      name: name,
      isDirectory: isDirectory,
      type: type,
    );
  }

  static FileEntryType _inferType(String ext) {
    const imageExts = {
      'jpg',
      'jpeg',
      'png',
      'gif',
      'bmp',
      'webp',
      'svg',
      'ico',
    };
    const videoExts = {'mp4', 'avi', 'mov', 'mkv', 'wmv', 'flv'};
    const audioExts = {'mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a'};
    const codeExts = {
      'dart',
      'js',
      'ts',
      'py',
      'java',
      'kt',
      'swift',
      'go',
      'rs',
      'cpp',
      'c',
      'h',
      'cs',
      'php',
      'rb',
      'sh',
    };
    const documentExts = {
      'pdf',
      'doc',
      'docx',
      'xls',
      'xlsx',
      'ppt',
      'pptx',
      'txt',
      'md',
    };
    const archiveExts = {'zip', 'rar', '7z', 'tar', 'gz', 'bz2'};

    if (imageExts.contains(ext)) return FileEntryType.image;
    if (videoExts.contains(ext)) return FileEntryType.video;
    if (audioExts.contains(ext)) return FileEntryType.audio;
    if (codeExts.contains(ext)) return FileEntryType.code;
    if (documentExts.contains(ext)) return FileEntryType.document;
    if (archiveExts.contains(ext)) return FileEntryType.archive;
    return FileEntryType.other;
  }

  @override
  bool operator ==(Object other) => other is FileEntry && other.path == path;

  @override
  int get hashCode => path.hashCode;
}
