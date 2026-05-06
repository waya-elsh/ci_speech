import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'audio_loader.dart';
import 'mfcc.dart';
import 'preprocess.dart';

const double _kMinRms = 0.005;
const int _kMinTrimmedSamples = 6400;

class _WordModel {
  final String name;
  final Float64List coef;
  final double intercept;
  _WordModel(this.name, this.coef, this.intercept);
}

class AyaClassifier {
  late final Float64List _mean;
  late final Float64List _scale;
  late final _WordModel _fallback;
  final Map<int, _WordModel> _byWord = {};
  final MfccExtractor _mfcc = MfccExtractor();
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> load({String assetPath = 'assets/model/aya_logreg.json'}) async {
    if (_loaded) return;
    final raw = await rootBundle.loadString(assetPath);
    final data = jsonDecode(raw) as Map<String, dynamic>;

    final version = (data['version'] as num?)?.toInt() ?? 1;
    if (version >= 2) {
      _loadV2(data);
    } else {
      _loadV1Compat(data);
    }
    _loaded = true;
  }

  void _loadV2(Map<String, dynamic> data) {
    final shared = data['shared'] as Map<String, dynamic>;
    _mean = _toFloat64(shared['mean'] as List);
    _scale = _toFloat64(shared['scale'] as List);

    final fb = data['fallback'] as Map<String, dynamic>;
    _fallback = _WordModel(
      'fallback',
      _toFloat64(fb['coef'] as List),
      (fb['intercept'] as num).toDouble(),
    );

    final words = data['words'] as Map<String, dynamic>;
    for (final entry in words.entries) {
      final wid = int.parse(entry.key);
      final w = entry.value as Map<String, dynamic>;
      _byWord[wid] = _WordModel(
        w['name'] as String,
        _toFloat64(w['coef'] as List),
        (w['intercept'] as num).toDouble(),
      );
    }
    _validate(_fallback);
    for (final m in _byWord.values) {
      _validate(m);
    }
  }

  void _loadV1Compat(Map<String, dynamic> data) {
    _mean = _toFloat64(data['mean'] as List);
    _scale = _toFloat64(data['scale'] as List);
    _fallback = _WordModel(
      'fallback',
      _toFloat64(data['coef'] as List),
      (data['intercept'] as num).toDouble(),
    );
    _validate(_fallback);
  }

  void _validate(_WordModel m) {
    if (m.coef.length != kNMfcc * kMaxFrames ||
        _mean.length != m.coef.length ||
        _scale.length != m.coef.length) {
      throw StateError(
          'aya_logreg.json shape mismatch: coef=${m.coef.length} '
          'mean=${_mean.length} scale=${_scale.length}');
    }
  }

  Future<double> predictFromWavFile(String path, {int? wordId}) async {
    if (!_loaded) await load();
    final samples = await loadWavAsMono16k(path);
    return predictFromSamples(samples, wordId: wordId);
  }

  double predictFromSamples(Float64List samples, {int? wordId}) {
    if (_rms(samples) < _kMinRms) return 0.0;
    final normalized = peakNormalize(samples);
    final trimmed = trimSilence(normalized, topDb: 20.0);
    if (trimmed.length < _kMinTrimmedSamples) return 0.0;
    final features = _mfcc.extract(trimmed);
    final model = wordId == null ? _fallback : (_byWord[wordId] ?? _fallback);
    return _scoreFeatures(features, model);
  }

  double _rms(Float64List samples) {
    if (samples.isEmpty) return 0.0;
    double sum = 0.0;
    for (var i = 0; i < samples.length; i++) {
      sum += samples[i] * samples[i];
    }
    return math.sqrt(sum / samples.length);
  }

  double _scoreFeatures(Float64List features520, _WordModel model) {
    double z = model.intercept;
    final n = features520.length;
    final coef = model.coef;
    for (var i = 0; i < n; i++) {
      final s = _scale[i] == 0.0 ? 0.0 : (features520[i] - _mean[i]) / _scale[i];
      final safe = s.isFinite ? s : 0.0;
      z += coef[i] * safe;
    }
    return 1.0 / (1.0 + math.exp(-z));
  }

  static Float64List _toFloat64(List raw) =>
      Float64List.fromList(raw.cast<num>().map((e) => e.toDouble()).toList());
}
