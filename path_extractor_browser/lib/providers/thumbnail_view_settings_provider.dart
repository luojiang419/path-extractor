import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/thumbnail_view_settings.dart';
import '../services/thumbnail_view_settings_service.dart';

class ThumbnailViewSettingsNotifier
    extends StateNotifier<ThumbnailViewSettings> {
  ThumbnailViewSettingsNotifier(this._store)
    : super(ThumbnailViewSettings.initial()) {
    unawaited(_load());
  }

  final ThumbnailViewSettingsStore _store;
  bool _hasUserOverride = false;

  Future<void> _load() async {
    final loadedSettings = await _store.load();
    if (_hasUserOverride) return;
    state = loadedSettings;
  }

  void setGridSize(double gridSize) {
    _update(state.copyWith(gridSize: gridSize));
  }

  void zoomIn() {
    setGridSize(state.gridSize + ThumbnailViewSettings.wheelStep);
  }

  void zoomOut() {
    setGridSize(state.gridSize - ThumbnailViewSettings.wheelStep);
  }

  void reset() {
    _update(ThumbnailViewSettings.initial());
  }

  void _update(ThumbnailViewSettings nextState) {
    _hasUserOverride = true;
    if (nextState.gridSize == state.gridSize) return;
    state = nextState;
    unawaited(_store.save(nextState));
  }
}

final thumbnailViewSettingsStoreProvider = Provider<ThumbnailViewSettingsStore>(
  (ref) => FileThumbnailViewSettingsStore(),
);

final thumbnailViewSettingsProvider =
    StateNotifierProvider<ThumbnailViewSettingsNotifier, ThumbnailViewSettings>(
      (ref) => ThumbnailViewSettingsNotifier(
        ref.watch(thumbnailViewSettingsStoreProvider),
      ),
    );
