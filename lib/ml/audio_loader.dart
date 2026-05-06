import 'dart:io';
import 'dart:typed_data';

import 'package:wav/wav.dart';

import 'mfcc.dart';

Future<Float64List> loadWavAsMono16k(String path) async {
  final wav = await Wav.readFile(path);
  final channels = wav.channels;
  final n = channels.isEmpty ? 0 : channels[0].length;
  final mono = Float64List(n);
  if (channels.length == 1) {
    for (var i = 0; i < n; i++) {
      mono[i] = channels[0][i];
    }
  } else {
    final c = channels.length;
    for (var i = 0; i < n; i++) {
      double s = 0.0;
      for (var ch = 0; ch < c; ch++) {
        s += channels[ch][i];
      }
      mono[i] = s / c;
    }
  }
  if (wav.samplesPerSecond == kSampleRate) return mono;
  return _resampleLinear(mono, wav.samplesPerSecond, kSampleRate);
}

Float64List _resampleLinear(Float64List input, int srIn, int srOut) {
  if (srIn == srOut || input.isEmpty) return input;
  final ratio = srOut / srIn;
  final outLen = (input.length * ratio).floor();
  final out = Float64List(outLen);
  for (var i = 0; i < outLen; i++) {
    final src = i / ratio;
    final j = src.floor();
    final frac = src - j;
    final a = input[j];
    final b = (j + 1 < input.length) ? input[j + 1] : a;
    out[i] = a + (b - a) * frac;
  }
  return out;
}

bool fileExists(String path) => File(path).existsSync();
