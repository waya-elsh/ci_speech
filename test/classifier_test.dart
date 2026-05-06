import 'dart:io';
import 'dart:typed_data';

import 'package:ci_speech/ml/audio_loader.dart';
import 'package:ci_speech/ml/classifier.dart';
import 'package:ci_speech/ml/mfcc.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AyaClassifier v4 (cosine to spherical centroid)', () {
    late AyaClassifier classifier;

    setUpAll(() async {
      classifier = AyaClassifier();
      await classifier.load();
    });

    test('loads v4 model from rootBundle and knows all 15 app words', () {
      expect(classifier.isLoaded, isTrue);
      const expected = {
        '9', '15', '21', '22', '25', '55', '62', '64',
        '72', '74', '82', '83', '86', '92', '95',
      };
      expect(classifier.knownWordIds.toSet(), expected);
    });

    test('correct sample of word 64 targeted as word 64 → not rejected', () async {
      final samples = await _loadFixture('test/fixtures/correct_word64.wav');
      final p = classifier.predictFromSamples(samples, wordId: '64');
      expect(p, greaterThanOrEqualTo(0.20),
          reason: 'should at least pass the speech gate for clean speech');
    });

    test('correct sample of word 55 targeted as word 55 → not rejected', () async {
      final samples = await _loadFixture('test/fixtures/correct_word55.wav');
      final p = classifier.predictFromSamples(samples, wordId: '55');
      expect(p, greaterThanOrEqualTo(0.20));
    });

    test('SAME audio scored against a WRONG word has lower similarity', () async {
      // The whole point of v4: cosine similarity to the right word should be
      // higher than cosine similarity to any unrelated word.
      final samples = await _loadFixture('test/fixtures/correct_word64.wav');
      final simRight = classifier.similarityToWord(samples, '64');
      final simWrong = classifier.similarityToWord(samples, '9');
      expect(simRight, greaterThan(simWrong),
          reason: 'right-word similarity ($simRight) must exceed '
              'wrong-word similarity ($simWrong)');
    });

    test('unknown wordId returns 0.0 instead of crashing', () {
      final samples = Float64List(16000 * 2);
      // fake speech-like noise so the gate passes
      for (var i = 0; i < samples.length; i++) {
        samples[i] = 0.05 * (((i * 1664525 + 1013904223) & 0x7fffffff) /
                0x7fffffff -
            0.5);
      }
      final p = classifier.predictFromSamples(samples, wordId: '99999');
      expect(p, 0.0);
    });

    test('gate: pure silence → 0.0', () {
      final silent = Float64List(16000 * 2);
      expect(classifier.predictFromSamples(silent, wordId: '64'), 0.0);
    });

    test('gate: very quiet noise → 0.0 (RMS below threshold)', () {
      final samples = Float64List(16000 * 2);
      var seed = 1;
      for (var i = 0; i < samples.length; i++) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        samples[i] = ((seed / 0x7fffffff) - 0.5) * 0.001;
      }
      expect(classifier.predictFromSamples(samples, wordId: '64'), 0.0);
    });

    test('gate: too-short recording → 0.0', () {
      // 0.1 s of loud noise
      final samples = Float64List(1600);
      var seed = 7;
      for (var i = 0; i < samples.length; i++) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        samples[i] = ((seed / 0x7fffffff) - 0.5) * 0.6;
      }
      expect(classifier.predictFromSamples(samples, wordId: '64'), 0.0);
    });

    test('output is one of the four canonical v3 probabilities', () async {
      final samples = await _loadFixture('test/fixtures/correct_word64.wav');
      final allowed = {0.0, 0.20, 0.70, 0.95};
      for (final wid in const ['9', '15', '64', '95']) {
        final p = classifier.predictFromSamples(samples, wordId: wid);
        expect(allowed.contains(p), isTrue,
            reason: 'wordId=$wid produced unexpected p=$p');
      }
    });
  });

  group('MFCC pipeline shape', () {
    test('extract returns exactly nMfcc * maxFrames floats, all finite', () async {
      final samples = await _loadFixture('test/fixtures/correct_word64.wav');
      final feats = MfccExtractor().extract(samples);
      expect(feats.length, kNMfcc * kMaxFrames);
      expect(feats.length, 520);
      for (final v in feats) {
        expect(v.isFinite, isTrue);
      }
    });
  });
}

Future<Float64List> _loadFixture(String assetPath) async {
  final bytes = await rootBundle.load(assetPath);
  final tmp = await File(
    '${Directory.systemTemp.createTempSync('ci_speech_test_').path}/'
            '${assetPath.replaceAll('test/fixtures/', '')}',
  ).create(recursive: true);
  await tmp.writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
  return loadWavAsMono16k(tmp.path);
}
