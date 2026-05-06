import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

const int kSampleRate = 16000;
const int kNFft = 2048;
const int kHopLength = 512;
const int kNMels = 128;
const int kNMfcc = 13;
const int kMaxFrames = 40;
const double kFMin = 0.0;
const double kFMax = 8000.0;
const double kPowerToDbAmin = 1e-10;
const double kPowerToDbTopDb = 80.0;

class MfccExtractor {
  final FFT _fft = FFT(kNFft);
  late final Float64List _hannWindow = _buildHannWindow(kNFft);
  late final List<Float64List> _melFilterbank =
      _buildMelFilterbank(sr: kSampleRate, nFft: kNFft, nMels: kNMels, fMin: kFMin, fMax: kFMax);
  late final List<Float64List> _dctMatrix = _buildDctMatrix(kNMfcc, kNMels);

  Float64List extract(Float64List samples) {
    final framed = _frameWithCenterPadding(samples, kNFft, kHopLength);
    final nFrames = framed.length;
    if (nFrames == 0) {
      return Float64List(kNMfcc * kMaxFrames);
    }

    final powerSpec = List<Float64List>.generate(nFrames, (i) {
      final frame = Float64List(kNFft);
      for (var j = 0; j < kNFft; j++) {
        frame[j] = framed[i][j] * _hannWindow[j];
      }
      final spectrum = _fft.realFft(frame);
      final nBins = kNFft ~/ 2 + 1;
      final out = Float64List(nBins);
      for (var k = 0; k < nBins; k++) {
        final c = spectrum[k];
        out[k] = c.x * c.x + c.y * c.y;
      }
      return out;
    });

    final melSpec = List<Float64List>.generate(nFrames, (t) {
      final col = Float64List(kNMels);
      final p = powerSpec[t];
      for (var m = 0; m < kNMels; m++) {
        final w = _melFilterbank[m];
        double s = 0.0;
        for (var k = 0; k < w.length; k++) {
          s += w[k] * p[k];
        }
        col[m] = s;
      }
      return col;
    });

    final logMel = List<Float64List>.generate(nFrames, (t) {
      final col = Float64List(kNMels);
      for (var m = 0; m < kNMels; m++) {
        final v = melSpec[t][m];
        col[m] = 10.0 * _log10(v < kPowerToDbAmin ? kPowerToDbAmin : v);
      }
      return col;
    });

    double globalMax = double.negativeInfinity;
    for (var t = 0; t < nFrames; t++) {
      for (var m = 0; m < kNMels; m++) {
        if (logMel[t][m] > globalMax) globalMax = logMel[t][m];
      }
    }
    final floor = globalMax - kPowerToDbTopDb;
    for (var t = 0; t < nFrames; t++) {
      for (var m = 0; m < kNMels; m++) {
        if (logMel[t][m] < floor) logMel[t][m] = floor;
      }
    }

    final mfccFrames = List<Float64List>.generate(nFrames, (t) {
      final col = Float64List(kNMfcc);
      for (var k = 0; k < kNMfcc; k++) {
        final row = _dctMatrix[k];
        double s = 0.0;
        for (var m = 0; m < kNMels; m++) {
          s += row[m] * logMel[t][m];
        }
        col[k] = s;
      }
      return col;
    });

    final out = Float64List(kNMfcc * kMaxFrames);
    final framesToCopy = nFrames < kMaxFrames ? nFrames : kMaxFrames;
    for (var k = 0; k < kNMfcc; k++) {
      for (var t = 0; t < framesToCopy; t++) {
        final v = mfccFrames[t][k];
        out[k * kMaxFrames + t] = v.isFinite ? v : 0.0;
      }
    }
    return out;
  }
}

List<Float64List> _frameWithCenterPadding(Float64List y, int frameLength, int hopLength) {
  final pad = frameLength ~/ 2;
  final padded = Float64List(y.length + 2 * pad);
  for (var i = 0; i < y.length; i++) {
    padded[i + pad] = y[i];
  }
  if (padded.length < frameLength) return const [];
  final nFrames = 1 + (padded.length - frameLength) ~/ hopLength;
  return List<Float64List>.generate(nFrames, (f) {
    final start = f * hopLength;
    final frame = Float64List(frameLength);
    for (var i = 0; i < frameLength; i++) {
      frame[i] = padded[start + i];
    }
    return frame;
  });
}

Float64List _buildHannWindow(int n) {
  final w = Float64List(n);
  for (var i = 0; i < n; i++) {
    w[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / n);
  }
  return w;
}

double _hzToMelSlaney(double f) {
  const fSp = 200.0 / 3.0;
  const minLogHz = 1000.0;
  const minLogMel = minLogHz / fSp;
  final logstep = math.log(6.4) / 27.0;
  if (f < minLogHz) return f / fSp;
  return minLogMel + math.log(f / minLogHz) / logstep;
}

double _melToHzSlaney(double m) {
  const fSp = 200.0 / 3.0;
  const minLogHz = 1000.0;
  const minLogMel = minLogHz / fSp;
  final logstep = math.log(6.4) / 27.0;
  if (m < minLogMel) return fSp * m;
  return minLogHz * math.exp(logstep * (m - minLogMel));
}

List<Float64List> _buildMelFilterbank({
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
  final minMel = _hzToMelSlaney(fMin);
  final maxMel = _hzToMelSlaney(fMax);
  final melPoints = Float64List(nMels + 2);
  for (var i = 0; i < nMels + 2; i++) {
    final m = minMel + (maxMel - minMel) * i / (nMels + 1);
    melPoints[i] = _melToHzSlaney(m);
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

List<Float64List> _buildDctMatrix(int nMfcc, int nMels) {
  final m = List<Float64List>.generate(nMfcc, (_) => Float64List(nMels));
  final norm0 = math.sqrt(1.0 / nMels);
  final normK = math.sqrt(2.0 / nMels);
  for (var k = 0; k < nMfcc; k++) {
    final s = (k == 0) ? norm0 : normK;
    for (var n = 0; n < nMels; n++) {
      m[k][n] = s * math.cos(math.pi * k * (2 * n + 1) / (2.0 * nMels));
    }
  }
  return m;
}

double _log10(double x) => math.log(x) / math.ln10;
