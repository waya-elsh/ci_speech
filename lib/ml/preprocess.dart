import 'dart:math' as math;
import 'dart:typed_data';

import 'mfcc.dart';

Float64List peakNormalize(Float64List samples) {
  double maxVal = 0.0;
  for (var i = 0; i < samples.length; i++) {
    final a = samples[i].abs();
    if (a > maxVal) maxVal = a;
  }
  if (maxVal == 0.0) return samples;
  final out = Float64List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    out[i] = samples[i] / maxVal;
  }
  return out;
}

Float64List trimSilence(Float64List y, {double topDb = 20.0}) {
  if (y.length < kNFft) return y;
  const frameLength = kNFft;
  const hopLength = kHopLength;
  final pad = frameLength ~/ 2;
  final padded = Float64List(y.length + 2 * pad);
  for (var i = 0; i < y.length; i++) {
    padded[i + pad] = y[i];
  }
  final nFrames = 1 + (padded.length - frameLength) ~/ hopLength;
  if (nFrames <= 0) return y;
  final mse = Float64List(nFrames);
  for (var f = 0; f < nFrames; f++) {
    final start = f * hopLength;
    double sum = 0.0;
    for (var i = 0; i < frameLength; i++) {
      final v = padded[start + i];
      sum += v * v;
    }
    mse[f] = sum / frameLength;
  }
  double maxMse = 0.0;
  for (var f = 0; f < nFrames; f++) {
    if (mse[f] > maxMse) maxMse = mse[f];
  }
  if (maxMse <= 0) return y;
  final refDb = 10.0 * (math.log(maxMse) / math.ln10);
  int firstNonSilent = -1;
  int lastNonSilent = -1;
  for (var f = 0; f < nFrames; f++) {
    final amin = mse[f] < 1e-10 ? 1e-10 : mse[f];
    final db = 10.0 * (math.log(amin) / math.ln10) - refDb;
    if (db > -topDb) {
      if (firstNonSilent < 0) firstNonSilent = f;
      lastNonSilent = f;
    }
  }
  if (firstNonSilent < 0) return y;
  final start = firstNonSilent * hopLength;
  final end = ((lastNonSilent + 1) * hopLength).clamp(0, y.length);
  if (start >= end) return y;
  return Float64List.sublistView(y, start, end);
}
