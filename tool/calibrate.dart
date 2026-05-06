import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:ci_speech/ml/audio_loader.dart';
import 'package:ci_speech/ml/mfcc.dart';
import 'package:ci_speech/ml/preprocess.dart';

void main(List<String> args) async {
  final refPath = args.isNotEmpty ? args[0] : 'Aya_Dataset/calibration_python.json';
  final modelPath = args.length > 1 ? args[1] : 'assets/model/aya_logreg.json';

  final ref = jsonDecode(await File(refPath).readAsString()) as List<dynamic>;
  final model = jsonDecode(await File(modelPath).readAsString()) as Map<String, dynamic>;
  final coef = (model['coef'] as List).cast<num>().map((e) => e.toDouble()).toList();
  final intercept = (model['intercept'] as num).toDouble();
  final mean = (model['mean'] as List).cast<num>().map((e) => e.toDouble()).toList();
  final scale = (model['scale'] as List).cast<num>().map((e) => e.toDouble()).toList();

  final mfcc = MfccExtractor();

  print('file                                          py     dart   |Δp|   featΔmax  featΔmean');
  print('-' * 100);

  int matchClass = 0;
  double sumAbsDp = 0.0;
  double worstDp = 0.0;

  for (final entry in ref.cast<Map<String, dynamic>>()) {
    final path = entry['path'] as String;
    final pyP = (entry['p_correct'] as num).toDouble();
    final pyFeats = (entry['features_raw'] as List).cast<num>().map((e) => e.toDouble()).toList();

    final samples = await loadWavAsMono16k(path);
    final normalized = peakNormalize(samples);
    final trimmed = trimSilence(normalized, topDb: 20.0);
    final dartFeats = mfcc.extract(trimmed);

    double z = intercept;
    for (var i = 0; i < dartFeats.length; i++) {
      final s = scale[i] == 0.0 ? 0.0 : (dartFeats[i] - mean[i]) / scale[i];
      z += coef[i] * (s.isFinite ? s : 0.0);
    }
    final dartP = 1.0 / (1.0 + math.exp(-z));

    double maxAbs = 0.0;
    double sumAbs = 0.0;
    for (var i = 0; i < dartFeats.length; i++) {
      final d = (dartFeats[i] - pyFeats[i]).abs();
      if (d > maxAbs) maxAbs = d;
      sumAbs += d;
    }

    final dp = (dartP - pyP).abs();
    if (dp > worstDp) worstDp = dp;
    sumAbsDp += dp;
    if ((pyP >= 0.5) == (dartP >= 0.5)) matchClass++;

    final fname = path.split('/').sublist(path.split('/').length - 2).join('/');
    print('${fname.padRight(46)}  '
        '${pyP.toStringAsFixed(4)}  '
        '${dartP.toStringAsFixed(4)}  '
        '${dp.toStringAsFixed(4)}  '
        '${maxAbs.toStringAsFixed(3).padLeft(8)}  '
        '${(sumAbs / dartFeats.length).toStringAsFixed(4)}');
  }

  final n = ref.length;
  print('');
  print('class agreement: $matchClass / $n');
  print('mean |Δp|:       ${(sumAbsDp / n).toStringAsFixed(4)}');
  print('worst |Δp|:      ${worstDp.toStringAsFixed(4)}');
}
