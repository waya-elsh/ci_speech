import 'dart:typed_data';
import 'package:fftea/fftea.dart';

void main() {
  // Known signal: cos(2*pi*10*n/2048), i.e. 10 cycles in 2048 samples.
  const n = 2048;
  final x = Float64List(n);
  for (var i = 0; i < n; i++) {
    x[i] = 1.0;  // DC = 1.0 → bin 0 should = 2048, others = 0
  }
  final fft = FFT(n);
  final y = fft.realFft(x);
  // ignore: avoid_print
  print('output length: ${y.length}  (expected $n or ${n ~/ 2 + 1})');
  // ignore: avoid_print
  print('bin 0: re=${y[0].x} im=${y[0].y}  → expected re=$n im=0');
  // ignore: avoid_print
  print('bin 1: re=${y[1].x} im=${y[1].y}  → expected ~0');
  // ignore: avoid_print
  print('bin ${n ~/ 2}: re=${y[n ~/ 2].x} im=${y[n ~/ 2].y}  (Nyquist)');
}
