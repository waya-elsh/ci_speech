import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'audio_loader.dart';
import 'mfcc.dart';
import 'preprocess.dart';

class _Thresholds {
  final double excellentMinSimilarity;
  final double goodTryMinSimilarity;
  final double pExcellent;
  final double pGoodTry;
  final double pRetry;
  _Thresholds(this.excellentMinSimilarity, this.goodTryMinSimilarity,
      this.pExcellent, this.pGoodTry, this.pRetry);
}

class _Gates {
  final double minDurationSeconds;
  final double minRms;
  _Gates(this.minDurationSeconds, this.minRms);
}

class _WordRef {
  final String name;
  final Float64List reference; // unit vector (norm ≈ 1)
  _WordRef(this.name, this.reference);
}

class AyaClassifier {
  late final Float64List _scalerCenter;
  late final Float64List _scalerScale;
  late final _Thresholds _thresh;
  late final _Gates _gates;
  final Map<String, _WordRef> _byWord = {};
  final MfccExtractor _mfcc = MfccExtractor();
  bool _loaded = false;

  bool get isLoaded => _loaded;
  Iterable<String> get knownWordIds => _byWord.keys;

  Future<void> load({String assetPath = 'assets/model/aya_logreg.json'}) async {
    if (_loaded) return;
    final raw = await rootBundle.loadString(assetPath);
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final version = (data['version'] as num?)?.toInt() ?? 1;
    if (version != 4) {
      throw StateError(
          'Unsupported model JSON version $version — expected v4 (cosine to '
          'spherical centroid). Re-run Untitled/export_model_v4.py.');
    }

    final scaler = data['scaler'] as Map<String, dynamic>;
    if (scaler['type'] != 'robust') {
      throw StateError("Expected scaler type 'robust', got ${scaler['type']}");
    }
    _scalerCenter = _toFloat64(scaler['center'] as List);
    _scalerScale = _toFloat64(scaler['scale'] as List);

    final t = data['thresholds'] as Map<String, dynamic>;
    _thresh = _Thresholds(
      (t['excellent_min_similarity'] as num).toDouble(),
      (t['good_try_min_similarity'] as num).toDouble(),
      (t['excellent_p'] as num).toDouble(),
      (t['good_try_p'] as num).toDouble(),
      (t['retry_p'] as num).toDouble(),
    );

    final g = data['gates'] as Map<String, dynamic>;
    _gates = _Gates(
      (g['min_duration_seconds'] as num).toDouble(),
      (g['min_rms'] as num).toDouble(),
    );

    final words = data['words'] as Map<String, dynamic>;
    for (final entry in words.entries) {
      final w = entry.value as Map<String, dynamic>;
      final ref = _toFloat64(w['reference'] as List);
      if (ref.length != _scalerCenter.length) {
        throw StateError(
            'word ${entry.key} reference length ${ref.length} != '
            'scaler length ${_scalerCenter.length}');
      }
      _byWord[entry.key] = _WordRef(w['name'] as String, ref);
    }
    if (_scalerCenter.length != kNMfcc * kMaxFrames) {
      throw StateError(
          'scaler dim ${_scalerCenter.length} != ${kNMfcc * kMaxFrames}');
    }
    _loaded = true;
  }

  Future<double> predictFromWavFile(String path,
      {required String wordId}) async {
    if (!_loaded) await load();
    final samples = await loadWavAsMono16k(path);
    return predictFromSamples(samples, wordId: wordId);
  }

  /// Returns p_correct in {0.0, retry_p, good_try_p, excellent_p}.
  /// Returns 0.0 when the input fails the speech gate or the word is unknown.
  double predictFromSamples(Float64List samples, {required String wordId}) {
    final ref = _byWord[wordId];
    if (ref == null) return 0.0;

    if (_rms(samples) < _gates.minRms) return 0.0;
    final normalized = peakNormalize(samples);
    final trimmed = trimSilence(normalized, topDb: 20.0);
    final durSec = trimmed.length / kSampleRate;
    if (durSec < _gates.minDurationSeconds) return 0.0;

    final features = _mfcc.extract(trimmed);
    final sim = _cosineToReference(features, ref.reference);
    if (sim >= _thresh.excellentMinSimilarity) return _thresh.pExcellent;
    if (sim >= _thresh.goodTryMinSimilarity) return _thresh.pGoodTry;
    return _thresh.pRetry;
  }

  /// Internal helper for tests / diagnostics: cosine similarity between the
  /// scaled+normalized features and the target word's unit-vector reference.
  /// Returns a value in [-1, 1]; higher = more similar.
  double similarityToWord(Float64List samples, String wordId) {
    final ref = _byWord[wordId];
    if (ref == null) return double.negativeInfinity;
    final normalized = peakNormalize(samples);
    final trimmed = trimSilence(normalized, topDb: 20.0);
    final features = _mfcc.extract(trimmed);
    return _cosineToReference(features, ref.reference);
  }

  /// Cosine similarity between scaled features and a unit-length reference.
  /// Computes scaled = (features - center) / scale, then
  /// cos = dot(scaled, ref) / |scaled|  (ref is already unit length).
  double _cosineToReference(Float64List features, Float64List unitRef) {
    double dot = 0.0;
    double sumSq = 0.0;
    final n = features.length;
    for (var i = 0; i < n; i++) {
      final s = _scalerScale[i] == 0.0
          ? 0.0
          : (features[i] - _scalerCenter[i]) / _scalerScale[i];
      final safe = s.isFinite ? s : 0.0;
      dot += safe * unitRef[i];
      sumSq += safe * safe;
    }
    final norm = math.sqrt(sumSq);
    if (norm == 0.0) return 0.0;
    return dot / norm;
  }

  double _rms(Float64List samples) {
    if (samples.isEmpty) return 0.0;
    double sum = 0.0;
    for (var i = 0; i < samples.length; i++) {
      sum += samples[i] * samples[i];
    }
    return math.sqrt(sum / samples.length);
  }

  static Float64List _toFloat64(List raw) =>
      Float64List.fromList(raw.cast<num>().map((e) => e.toDouble()).toList());
}
