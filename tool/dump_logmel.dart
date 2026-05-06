import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ci_speech/ml/audio_loader.dart';
import 'package:ci_speech/ml/preprocess.dart';
import 'package:fftea/fftea.dart';

const n = 2048;
const nMels = 128;
const sr = 16000;

void main(List<String> args) async {
  final path = args.isNotEmpty ? args[0] : 'Aya_Dataset/ASMDD/speaker_25_b_100/64.wav';
  final y = await loadWavAsMono16k(path);
  final yn = peakNormalize(y);

  final pad = n ~/ 2;
  final padded = Float64List(yn.length + 2 * pad);
  for (var i = 0; i < yn.length; i++) {
    padded[i + pad] = yn[i];
  }
  final frame = Float64List(n);
  for (var i = 0; i < n; i++) {
    frame[i] = padded[i] * (0.5 - 0.5 * math.cos(2 * math.pi * i / n));
  }
  final fft = FFT(n);
  final spectrum = fft.realFft(frame);
  final nBins = n ~/ 2 + 1;
  final power = Float64List(nBins);
  for (var k = 0; k < nBins; k++) {
    power[k] = spectrum[k].x * spectrum[k].x + spectrum[k].y * spectrum[k].y;
  }

  final fb = melFilterbank(sr: sr, nFft: n, nMels: nMels, fMin: 0.0, fMax: 8000.0);

  final melS = Float64List(nMels);
  for (var m = 0; m < nMels; m++) {
    double s = 0.0;
    for (var k = 0; k < nBins; k++) {
      s += fb[m][k] * power[k];
    }
    melS[m] = s;
  }

  final logMel = Float64List(nMels);
  for (var m = 0; m < nMels; m++) {
    final v = melS[m] < 1e-10 ? 1e-10 : melS[m];
    logMel[m] = 10.0 * (math.log(v) / math.ln10);
  }

  // ignore: avoid_print
  print('power[0..7] = ${power.sublist(0, 8).toList()}');
  double basisSum = 0.0;
  for (var k = 0; k < fb[0].length; k++) {
    basisSum += fb[0][k];
  }
  // ignore: avoid_print
  print('mel_basis filter0[:5] = ${fb[0].sublist(0, 5).toList()}  sum=$basisSum');
  // ignore: avoid_print
  print('mel_S[:5] = ${melS.sublist(0, 5).toList()}');
  // ignore: avoid_print
  print('log_mel[:5] = ${logMel.sublist(0, 5).toList()}');
  double logMelSum = 0.0;
  for (var m = 0; m < nMels; m++) {
    logMelSum += logMel[m];
  }
  // ignore: avoid_print
  print('log_mel sum frame 0 = $logMelSum');
}

double hzToMelSlaney(double f) {
  const fSp = 200.0 / 3.0;
  const minLogHz = 1000.0;
  const minLogMel = minLogHz / fSp;
  final logstep = math.log(6.4) / 27.0;
  if (f < minLogHz) return f / fSp;
  return minLogMel + math.log(f / minLogHz) / logstep;
}

double melToHzSlaney(double m) {
  const fSp = 200.0 / 3.0;
  const minLogHz = 1000.0;
  const minLogMel = minLogHz / fSp;
  final logstep = math.log(6.4) / 27.0;
  if (m < minLogMel) return fSp * m;
  return minLogHz * math.exp(logstep * (m - minLogMel));
}

List<Float64List> melFilterbank({
  required int sr,
  required int nFft,
  required int nMels,
  required double fMin,
  required double fMax,
}) {
  final nBins = nFft ~/ 2 + 1;
  final fftFreqs = Float64List(nBins);
  for (var i = 0; i < nBins; i++) {
    fftFreqs[i] = i * sr / nFft;
  }
  final minMel = hzToMelSlaney(fMin);
  final maxMel = hzToMelSlaney(fMax);
  final melPoints = Float64List(nMels + 2);
  for (var i = 0; i < nMels + 2; i++) {
    final m = minMel + (maxMel - minMel) * i / (nMels + 1);
    melPoints[i] = melToHzSlaney(m);
  }
  final fb = List<Float64List>.generate(nMels, (_) => Float64List(nBins));
  for (var m = 0; m < nMels; m++) {
    final lower = melPoints[m];
    final center = melPoints[m + 1];
    final upper = melPoints[m + 2];
    final enorm = 2.0 / (upper - lower);
    for (var k = 0; k < nBins; k++) {
      final f = fftFreqs[k];
      double w = 0.0;
      if (f >= lower && f <= center) {
        w = (f - lower) / (center - lower);
      } else if (f > center && f <= upper) {
        w = (upper - f) / (upper - center);
      }
      fb[m][k] = w * enorm;
    }
  }
  return fb;
}
