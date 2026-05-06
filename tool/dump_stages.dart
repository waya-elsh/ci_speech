import 'dart:convert';
import 'dart:io';

import 'package:ci_speech/ml/audio_loader.dart';
import 'package:ci_speech/ml/mfcc.dart';
import 'package:ci_speech/ml/preprocess.dart';

void main(List<String> args) async {
  final path = args.isNotEmpty ? args[0] : 'Aya_Dataset/ASMDD/speaker_25_b_100/64.wav';

  final samples = await loadWavAsMono16k(path);
  final norm = peakNormalize(samples);
  final trimmed = trimSilence(norm, topDb: 20.0);

  final mfcc = MfccExtractor();
  final featsNoTrim = mfcc.extract(norm);
  final featsTrim = mfcc.extract(trimmed);

  print(jsonEncode({
    'path': path,
    'n_samples': samples.length,
    'n_samples_trim': trimmed.length,
    'y_norm_first10': norm.take(10).toList(),
    'y_norm_last10': norm.skip(norm.length - 10).toList(),
    'y_norm_max': _max(norm),
    'mfcc_no_trim_first_frame': List.generate(13, (k) => featsNoTrim[k * kMaxFrames + 0]),
    'mfcc_no_trim_frame20': List.generate(13, (k) => featsNoTrim[k * kMaxFrames + 20]),
    'mfcc_trim_first_frame': List.generate(13, (k) => featsTrim[k * kMaxFrames + 0]),
  }));
}

double _max(Iterable<double> xs) {
  double m = 0.0;
  for (final x in xs) {
    if (x.abs() > m) m = x.abs();
  }
  return m;
}
