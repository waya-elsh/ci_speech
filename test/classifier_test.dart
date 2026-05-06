import 'dart:io';
import 'dart:typed_data';

import 'package:ci_speech/ml/audio_loader.dart';
import 'package:ci_speech/ml/classifier.dart';
import 'package:ci_speech/ml/mfcc.dart';
import 'package:ci_speech/ml/preprocess.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AyaClassifier offline pipeline', () {
    late AyaClassifier classifier;

    setUpAll(() async {
      classifier = AyaClassifier();
      await classifier.load();
    });

    test('loads model artifact from rootBundle', () {
      expect(classifier.isLoaded, isTrue);
    });

    test('fallback model: correct sample lands in excellent bucket', () async {
      // sample_correct_16k.wav = speaker_25_b_100/64.wav (correctly pronounced)
      final samples = await _loadFixture('test/fixtures/sample_correct_16k.wav');
      final p = classifier.predictFromSamples(samples);
      expect(p, greaterThan(0.90),
          reason: 'fallback model should still score clean speech high; got $p');
    });

    test('fallback model: incorrect sample lands in retry bucket', () async {
      // sample_incorrect_16k.wav = speaker_29_b_100/74_N.wav (mispronunciation)
      final samples = await _loadFixture('test/fixtures/sample_incorrect_16k.wav');
      final p = classifier.predictFromSamples(samples);
      expect(p, lessThan(0.35),
          reason: 'fallback model should reject mispronunciation; got $p');
    });

    test('per-word: correct sample scored against its true target word is high',
        () async {
      // sample_correct_16k.wav is a correct utterance of word 64 (التحدث)
      final samples = await _loadFixture('test/fixtures/sample_correct_16k.wav');
      final pTrueTarget = classifier.predictFromSamples(samples, wordId: 64);
      expect(pTrueTarget, greaterThan(0.5),
          reason: 'should score above 0.5 against the actual target word');
    });

    test('per-word: same audio scored against a WRONG target word is lower',
        () async {
      // Saying word A correctly while target is B should not be ممتاز.
      final samples = await _loadFixture('test/fixtures/sample_correct_16k.wav');
      final pRightTarget = classifier.predictFromSamples(samples, wordId: 64); // التحدث
      final pWrongTarget = classifier.predictFromSamples(samples, wordId: 9); // شكرا
      expect(pWrongTarget, lessThan(pRightTarget),
          reason: 'wrong-word score ($pWrongTarget) must be below '
              'right-word score ($pRightTarget) — the whole point of v2');
    });

    test('empty / silent audio does not crash and returns finite probability', () {
      final silent = Float64List(8000);
      final p = classifier.predictFromSamples(silent);
      expect(p.isFinite, isTrue);
      expect(p, inInclusiveRange(0.0, 1.0));
    });

    test('input gates: pure silence is rejected (p=0)', () {
      final silent = Float64List(16000 * 2);
      expect(classifier.predictFromSamples(silent), 0.0);
    });

    test('input gates: very quiet noise is rejected (RMS below threshold)', () {
      final samples = Float64List(16000 * 2);
      // Pseudo-random low-amplitude noise (RMS ≈ 3e-4)
      var seed = 1;
      for (var i = 0; i < samples.length; i++) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        samples[i] = ((seed / 0x7fffffff) - 0.5) * 0.001;
      }
      expect(classifier.predictFromSamples(samples), 0.0,
          reason: 'quiet ambient noise must not score as ممتاز');
    });

    test('input gates: too-short recording is rejected', () {
      // 0.3 s of loud noise — would score >0.9 without the gate
      final samples = Float64List(4800);
      var seed = 7;
      for (var i = 0; i < samples.length; i++) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        samples[i] = ((seed / 0x7fffffff) - 0.5) * 0.6;
      }
      expect(classifier.predictFromSamples(samples), 0.0,
          reason: 'sub-0.4s recordings cannot be a real Arabic word');
    });

    test('thresholds map to the same buckets the UI uses', () async {
      final correct = await _loadFixture('test/fixtures/sample_correct_16k.wav');
      final incorrect = await _loadFixture('test/fixtures/sample_incorrect_16k.wav');
      final pCorrect = classifier.predictFromSamples(correct);
      final pIncorrect = classifier.predictFromSamples(incorrect);
      // Buckets used in training_screen.dart
      String bucket(double p) => p >= 0.90
          ? 'excellent'
          : p >= 0.35
              ? 'good'
              : 'retry';
      expect(bucket(pCorrect), 'excellent');
      expect(bucket(pIncorrect), 'retry');
    });
  });

  group('MFCC pipeline shape', () {
    test('extract returns exactly nMfcc * maxFrames floats, all finite', () async {
      final samples = await _loadFixture('test/fixtures/sample_correct_16k.wav');
      final normalized = peakNormalize(samples);
      final trimmed = trimSilence(normalized, topDb: 20.0);
      final feats = MfccExtractor().extract(trimmed);
      expect(feats.length, kNMfcc * kMaxFrames);
      expect(feats.length, 520);
      for (final v in feats) {
        expect(v.isFinite, isTrue);
      }
    });
  });
}

Future<Float64List> _loadFixture(String assetPath) async {
  // Asset paths in tests are resolved via rootBundle exactly like in the app.
  final bytes = await rootBundle.load(assetPath);
  // Write to a temp file so we can reuse loadWavAsMono16k unchanged.
  final tmp = await File(
    '${Directory.systemTemp.createTempSync('ci_speech_test_').path}/$assetPath'
        .replaceAll('test/fixtures/', ''),
  ).create(recursive: true);
  await tmp.writeAsBytes(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
  return loadWavAsMono16k(tmp.path);
}

