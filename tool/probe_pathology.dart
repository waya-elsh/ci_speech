import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ci_speech/ml/audio_loader.dart';
import 'package:ci_speech/ml/mfcc.dart';
import 'package:ci_speech/ml/preprocess.dart';

void main(List<String> args) async {
  final model = jsonDecode(await File('assets/model/aya_logreg.json').readAsString())
      as Map<String, dynamic>;
  final coef = (model['coef'] as List).cast<num>().map((e) => e.toDouble()).toList();
  final intercept = (model['intercept'] as num).toDouble();
  final mean = (model['mean'] as List).cast<num>().map((e) => e.toDouble()).toList();
  final scale = (model['scale'] as List).cast<num>().map((e) => e.toDouble()).toList();

  final mfcc = MfccExtractor();

  double scoreSamples(Float64List samples) {
    // mirror the gates from classifier.dart
    double rmsSum = 0.0;
    for (var i = 0; i < samples.length; i++) {
      rmsSum += samples[i] * samples[i];
    }
    final rms = samples.isEmpty ? 0.0 : math.sqrt(rmsSum / samples.length);
    if (rms < 0.005) return 0.0;
    final n = peakNormalize(samples);
    final t = trimSilence(n, topDb: 20.0);
    if (t.length < 6400) return 0.0;
    final f = mfcc.extract(t);
    double z = intercept;
    for (var i = 0; i < f.length; i++) {
      final s = scale[i] == 0.0 ? 0.0 : (f[i] - mean[i]) / scale[i];
      z += coef[i] * (s.isFinite ? s : 0.0);
    }
    return 1.0 / (1.0 + math.exp(-z));
  }

  // 1. All-zero (pure silence)
  final silent = Float64List(16000 * 2);
  // ignore: avoid_print
  print('silence (2s zeros):           p=${scoreSamples(silent).toStringAsFixed(4)}');

  // 2. Very low amplitude noise (mic with no input)
  final rng = math.Random(42);
  final lowNoise = Float64List(16000 * 2);
  for (var i = 0; i < lowNoise.length; i++) {
    lowNoise[i] = (rng.nextDouble() - 0.5) * 0.001;
  }
  // ignore: avoid_print
  print('quiet noise (RMS≈3e-4):       p=${scoreSamples(lowNoise).toStringAsFixed(4)}');

  // 3. White noise full scale
  final whiteNoise = Float64List(16000 * 2);
  for (var i = 0; i < whiteNoise.length; i++) {
    whiteNoise[i] = (rng.nextDouble() - 0.5) * 2.0;
  }
  // ignore: avoid_print
  print('white noise (full scale):     p=${scoreSamples(whiteNoise).toStringAsFixed(4)}');

  // 4. Pure tone 440 Hz
  final tone = Float64List(16000 * 2);
  for (var i = 0; i < tone.length; i++) {
    tone[i] = 0.5 * math.sin(2 * math.pi * 440 * i / 16000);
  }
  // ignore: avoid_print
  print('440 Hz tone:                  p=${scoreSamples(tone).toStringAsFixed(4)}');

  // 5. Very short recording (0.3s of speech-ish noise — too short to contain a word)
  final tooShort = Float64List(4800);
  for (var i = 0; i < tooShort.length; i++) {
    tooShort[i] = (rng.nextDouble() - 0.5) * 0.3;
  }
  // ignore: avoid_print
  print('too-short recording (0.3s):   p=${scoreSamples(tooShort).toStringAsFixed(4)}');

  // 6. Real correct sample (sanity)
  final correct = await loadWavAsMono16k('test/fixtures/sample_correct_16k.wav');
  // ignore: avoid_print
  print('real correct sample:          p=${scoreSamples(correct).toStringAsFixed(4)}');

  // 7. Real incorrect sample (sanity)
  final incorrect = await loadWavAsMono16k('test/fixtures/sample_incorrect_16k.wav');
  // ignore: avoid_print
  print('real incorrect sample:        p=${scoreSamples(incorrect).toStringAsFixed(4)}');

  // 8. Wrong sample rate path: pretend a 44.1 kHz WAV is loaded — uses linear resampler
  final raw44k = await loadWavAsMono16k('Aya_Dataset/ASMDD/speaker_25_b_100/64.wav');
  // ignore: avoid_print
  print('44.1k via linear resample:    p=${scoreSamples(raw44k).toStringAsFixed(4)}  (expect drift vs proper soxr)');
}
