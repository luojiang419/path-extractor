import 'dart:io';

abstract class PathService {
  String normalize(String path);
  List<String> splitSegments(String path);
  String joinSegments(List<String> segments);
}

class PathServiceImpl implements PathService {
  @override
  String normalize(String path) {
    if (Platform.isWindows) {
      return path.replaceAll('/', '\\');
    } else {
      return path.replaceAll('\\', '/');
    }
  }

  @override
  List<String> splitSegments(String path) {
    final normalized = normalize(path);
    if (Platform.isWindows) {
      if (normalized.startsWith(r'\\')) {
        final parts = normalized
            .substring(2)
            .split('\\')
            .where((s) => s.isNotEmpty)
            .toList();
        if (parts.isEmpty) return const [];
        if (parts.length == 1) return ['\\\\${parts.first}'];
        return ['\\\\${parts[0]}\\${parts[1]}', ...parts.skip(2)];
      }

      return normalized
          .split('\\')
          .where((s) => s.isNotEmpty || _isDriveLetter(s))
          .where((s) => s.isNotEmpty)
          .toList();
    }

    return normalized.split('/').where((s) => s.isNotEmpty).toList();
  }

  @override
  String joinSegments(List<String> segments) {
    if (segments.isEmpty) {
      return Platform.isWindows ? '' : '/';
    }

    if (Platform.isWindows) {
      final first = segments.first;
      if (first.startsWith(r'\\')) {
        if (segments.length == 1) return first;
        return '$first\\${segments.skip(1).join('\\')}';
      }
      if (_isDriveLetter(first)) {
        if (segments.length == 1) return '$first\\';
        return '$first\\${segments.skip(1).join('\\')}';
      }
      return segments.join('\\');
    } else {
      return '/${segments.join('/')}';
    }
  }

  bool _isDriveLetter(String s) {
    return s.length == 2 && s[1] == ':';
  }
}
