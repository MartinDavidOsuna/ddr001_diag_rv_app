import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:hive_ce/hive.dart';

import '../../../domain/media/inspection_photo.dart';

/// Exact-ID, bounded projection for photo metadata used by thumbnail lists.
///
/// It caches documents only, never image bytes. Rebuilding a widget therefore
/// cannot read Hive or decode the same JSON repeatedly. Owners must call
/// [clear] from `dispose` so the projection lifetime matches the screen/dialog.
class InspectionPhotoDocumentProjection {
  InspectionPhotoDocumentProjection({String? Function(String)? readRaw})
    : _readRaw =
          readRaw ?? ((id) => Hive.box<String>('inspection_photos_v1').get(id));

  final String? Function(String) _readRaw;
  final Map<String, InspectionPhoto?> _photos = {};
  Set<String> _retainedIds = const {};
  int hiveReads = 0;
  int jsonDecodes = 0;

  int get retainedDocuments => _photos.length;

  InspectionPhoto? photo(String id) => _photos[id];

  bool contains(String id) => _photos.containsKey(id);

  void retain(Iterable<String> photoIds) {
    final retained = photoIds.toSet();
    _retainedIds = retained;
    _photos.removeWhere((id, _) => !retained.contains(id));
    for (final id in retained) {
      _load(id);
    }
  }

  /// Drops one cached result, including a cached missing/unreadable result.
  /// The next [retain] or [refresh] reads only this ID again.
  void invalidate(String photoId) => _photos.remove(photoId);

  /// Re-reads only visible IDs explicitly identified as modified.
  Set<String> refresh(Iterable<String> photoIds) {
    final requested = photoIds.where(_retainedIds.contains).toSet();
    final before = {for (final id in requested) id: _identity(_photos[id])};
    for (final id in requested) {
      _photos.remove(id);
    }
    for (final id in requested) {
      _load(id);
    }
    return {
      for (final id in requested)
        if (before[id] != _identity(_photos[id])) id,
    };
  }

  String _identity(InspectionPhoto? photo) =>
      photo == null ? '<missing>' : jsonEncode(photo.toJson());

  void _load(String id) {
    if (_photos.containsKey(id)) return;
    hiveReads++;
    final raw = _readRaw(id);
    if (raw == null) {
      _photos[id] = null;
      return;
    }
    try {
      jsonDecodes++;
      _photos[id] = InspectionPhoto.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } on Object {
      _photos[id] = null;
    }
  }

  void clear() {
    _retainedIds = const {};
    _photos.clear();
  }
}

/// Owns only key-specific Hive listeners for the IDs currently visible.
/// There is no global box listener, scan or polling task.
class InspectionPhotoProjectionBinding {
  InspectionPhotoProjectionBinding({
    required this.projection,
    required this.onChanged,
    Box<String>? box,
    void Function(InspectionPhoto? before, InspectionPhoto? after)?
    evictThumbnail,
  }) : _box = box ?? Hive.box<String>('inspection_photos_v1'),
       _evictThumbnailOverride = evictThumbnail;

  final InspectionPhotoDocumentProjection projection;
  final void Function() onChanged;
  final Box<String> _box;
  final void Function(InspectionPhoto? before, InspectionPhoto? after)?
  _evictThumbnailOverride;
  final Map<String, StreamSubscription<BoxEvent>> _subscriptions = {};
  Set<String> _visibleIds = const {};
  bool _disposed = false;

  int get activeListeners => _subscriptions.length;
  Set<String> get visibleIds => Set.unmodifiable(_visibleIds);

  void retain(Iterable<String> photoIds) {
    if (_disposed) return;
    final next = photoIds.toSet();
    final removed = _visibleIds.difference(next);
    final added = next.difference(_visibleIds);
    for (final id in removed) {
      final subscription = _subscriptions.remove(id);
      if (subscription != null) unawaited(subscription.cancel());
    }
    _visibleIds = next;
    for (final id in added) {
      _subscriptions[id] = _box.watch(key: id).listen((_) {
        if (_disposed || !_visibleIds.contains(id)) return;
        final before = projection.photo(id);
        final changed = projection.refresh([id]).contains(id);
        if (!changed) return;
        final after = projection.photo(id);
        _evictThumbnail(before, after);
        onChanged();
      });
    }
    projection.retain(next);
  }

  /// Explicit selective refresh for repairs performed outside Hive writes in
  /// tests or platform adapters. Other visible documents remain untouched.
  void refresh(String photoId) {
    if (_disposed || !_visibleIds.contains(photoId)) return;
    final before = projection.photo(photoId);
    projection.refresh([photoId]);
    _evictThumbnail(before, projection.photo(photoId));
    onChanged();
  }

  void _evictThumbnail(InspectionPhoto? before, InspectionPhoto? after) {
    if (_evictThumbnailOverride case final callback?) {
      callback(before, after);
      return;
    }
    final paths = {
      if (before?.thumbnailPath.isNotEmpty == true) before!.thumbnailPath,
      if (after?.thumbnailPath.isNotEmpty == true) after!.thumbnailPath,
    };
    for (final path in paths) {
      unawaited(FileImage(File(path)).evict());
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _visibleIds = const {};
    for (final subscription in _subscriptions.values) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    projection.clear();
  }
}
