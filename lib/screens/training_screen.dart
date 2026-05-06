

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:ci_speech/data/word_data.dart';
import 'package:ci_speech/ml/classifier.dart';
import 'package:ci_speech/screens/results_screen.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:confetti/confetti.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen>
    with TickerProviderStateMixin {
  final AudioPlayer _wordPlayer = AudioPlayer();
  final AudioPlayer _fxPlayer = AudioPlayer();
  final AudioRecorder _recorder = AudioRecorder();
  final ConfettiController _confetti =
      ConfettiController(duration: const Duration(seconds: 4));
  final AyaClassifier _classifier = AyaClassifier();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();
  Timer? _maxRecordTimer;
  static const Duration _maxRecordDuration = Duration(seconds: 5);

  int currentIndex = 0;
  bool isRecording = false;
  String feedback = "";
  double probability = 0.0;
  int attemptCount = 0;
  bool trainingFinished = false;

  int excellentCount = 0;
  int goodCount = 0;
  int retryCount = 0;

  int failAttempts = 0;
  List<int> difficultIndexes = [];
  bool reviewMode = false;
  int reviewPointer = 0;

  @override
  void initState() {
    super.initState();
    _classifier.load();
  }

  Future<void> saveResults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('excellent', excellentCount);
    await prefs.setInt('good', goodCount);
    await prefs.setInt('retry', retryCount);
  }


  Future<void> playWordAudio() async {
    await _wordPlayer.stop();
    await _wordPlayer.setAsset(trainingWords[currentIndex].audio);
    _wordPlayer.play();
  }

  Future<void> playFx(String asset) async {
    try {
      await _fxPlayer.stop();
      await _fxPlayer.setAsset(asset);
      _fxPlayer.play();
    } catch (e, st) {
      // Audio playback is a UX nicety — never let a missing or undecodable
      // FX file break the evaluation flow.
      developer.log('playFx($asset) failed: $e',
          name: 'ci_speech.fx', error: e, stackTrace: st);
    }
  }

  Future<void> startRecording() async {
    if (isRecording || trainingFinished) return;
    if (!await _recorder.hasPermission()) return;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/child_record.wav';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );

    setState(() {
      isRecording = true;
      feedback = "";
    });

    _maxRecordTimer?.cancel();
    _maxRecordTimer = Timer(_maxRecordDuration, () {
      if (isRecording) stopRecording();
    });
  }

  Future<void> stopRecording() async {
    if (!isRecording) return;
    _maxRecordTimer?.cancel();
    _maxRecordTimer = null;
    final path = await _recorder.stop();

    setState(() {
      isRecording = false;
    });

    if (path != null) {
      await evaluateLocally(path);
    }
  }

  Future<void> _logRecordingDiagnostics(String path) async {
    try {
      final f = File(path);
      final exists = await f.exists();
      final size = exists ? await f.length() : -1;
      String header = '<no file>';
      if (exists && size > 0) {
        final raf = await f.open();
        try {
          final n = size < 64 ? size : 64;
          final bytes = await raf.read(n);
          final hex = bytes
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(' ');
          final ascii = String.fromCharCodes(
              bytes.map((b) => b >= 0x20 && b < 0x7f ? b : 0x2e));
          header = '\n  hex:   $hex\n  ascii: $ascii';
        } finally {
          await raf.close();
        }
      }
      developer.log(
        'recording: path=$path  exists=$exists  size=$size$header',
        name: 'ci_speech.record',
      );
    } catch (e, st) {
      developer.log('diagnostics failed: $e',
          name: 'ci_speech.record', error: e, stackTrace: st);
    }
  }

  // يحلل النطق محليًا داخل التطبيق دون الحاجة إلى سيرفر خارجي
  Future<void> evaluateLocally(String audioPath) async {
    await _logRecordingDiagnostics(audioPath);
    try {
      final wid = trainingWords[currentIndex].datasetWordId;
      final p = await _classifier.predictFromWavFile(audioPath, wordId: wid);
      developer.log('p_correct=$p target=${wid ?? "fallback"}',
          name: 'ci_speech.classifier');

      setState(() {
        probability = p;
        attemptCount++;
      });

      if (p >= 0.90) {
        excellentCount++;
        await saveResults();

        setState(() => feedback = "ممتاز ");
        await playFx("assets/audio/excellent.mp3");

        Future.delayed(const Duration(seconds: 2), nextWord);
      } else if (p >= 0.35) {
        goodCount++;
        await saveResults();

        setState(() => feedback = "محاولة جيدة ");
        await playFx("assets/audio/goodtry.wav");

        Future.delayed(const Duration(seconds: 2), nextWord);
      } else {
        retryCount++;
        failAttempts++;
        await saveResults();

        if (failAttempts < 2) {
          setState(() => feedback = "حاول مرة أخرى ");
          await playFx("assets/audio/retry.mp3");
        } else {
          if (!difficultIndexes.contains(currentIndex)) {
            difficultIndexes.add(currentIndex);
          }

          setState(() => feedback = "سنعود لها لاحقًا ");
          await playFx("assets/audio/goodtry.wav");

          Future.delayed(const Duration(seconds: 2), nextWord);
        }
      }
    } catch (e, st) {
      developer.log('evaluateLocally failed: $e',
          name: 'ci_speech.classifier', error: e, stackTrace: st);
      final msg = e.toString();
      final short = msg.length > 60 ? '${msg.substring(0, 60)}…' : msg;
      setState(() {
        feedback = "تعذر التحليل: $short";
      });
    }
  }

  Future<void> nextWord() async {
    failAttempts = 0;

    if (!reviewMode) {
      if (currentIndex < trainingWords.length - 1) {
        setState(() {
          currentIndex++;
          feedback = "";
          probability = 0.0;
          attemptCount = 0;
        });

        
      } else {
        if (difficultIndexes.isNotEmpty) {
          reviewMode = true;
          reviewPointer = 0;
//هنا يبدا يرد علي كلمات للمراجعة الصعبة اللي غلط فيها الطفل في التدريب
          setState(() {
            currentIndex = difficultIndexes[reviewPointer];
            feedback = "لنراجع الكلمات الصعبة ";
            probability = 0.0;
          });

          
        } else {
          finishTraining();
        }
      }
    } else {
      if (reviewPointer < difficultIndexes.length - 1) {
        reviewPointer++;

        setState(() {
          currentIndex = difficultIndexes[reviewPointer];
          feedback = "";
          probability = 0.0;
        });

       
      } else {
        finishTraining();
      }
    }
  }

  Future<void> finishTraining() async {
    setState(() {
      trainingFinished = true;
      feedback = "أحسنت! انتهى التدريب ";
    });

    _confetti.play();
    await playFx("assets/audio/finish.wav");

    Future.delayed(const Duration(seconds: 3), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ResultsScreen()),
      );
    });
  }

  @override
  void dispose() {
    _maxRecordTimer?.cancel();
    _pulse.dispose();
    _wordPlayer.dispose();
    _fxPlayer.dispose();
    _recorder.dispose();
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentWord = trainingWords[currentIndex];
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFFACE9FF),
      body: Stack(
        alignment: Alignment.topCenter,
        children: [
          ConfettiWidget(
            confettiController: _confetti,
            blastDirectionality: BlastDirectionality.explosive,
            shouldLoop: false,
            emissionFrequency: 0.08,
            numberOfParticles: 25,
            gravity: 0.2,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Text(
                    "التدريب ${currentIndex + 1} / ${trainingWords.length}",
                    style: GoogleFonts.cairo(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Image.asset(
                    'assets/images/coco2.png',
                    width: size.width * 0.30,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 28),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Text(
                      trainingFinished
                          ? "رائع يا بطل!"
                          : isRecording
                              ? "تحدث الآن... ارفع إصبعك عند الانتهاء"
                              : "اضغط مع الاستمرار وقل الكلمة",
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 22),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(35),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            currentWord.image,
                            width: size.width * 0.42,
                            height: size.width * 0.42,
                          ),
                          const SizedBox(height: 18),
                          Text(
                            currentWord.word,
                            style: GoogleFonts.cairo(
                              fontSize: 34,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 28),
                          if (!trainingFinished)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                GestureDetector(
                                  onTap: playWordAudio,
                                  child: _circleBtn(Icons.volume_up_rounded,
                                      const Color(0xFF7DB9FF), 68),
                                ),
                                const SizedBox(width: 30),
                                _holdToRecordButton(),
                              ],
                            ),
                          const SizedBox(height: 30),
                          SizedBox(
                            height: 55,
                            child: feedback.isNotEmpty
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEAF7FF),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Center(
                                      child: Text(
                                        feedback,
                                        style: GoogleFonts.cairo(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  )
                                : const SizedBox(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _holdToRecordButton() {
    const double base = 88;
    const Color idleColor = Color(0xFF253746);
    const Color activeColor = Color(0xFFE63946);
    final color = isRecording ? activeColor : idleColor;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => startRecording(),
      onTapUp: (_) => stopRecording(),
      onTapCancel: stopRecording,
      child: SizedBox(
        width: base + 36,
        height: base + 36,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isRecording)
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) {
                  final t = _pulse.value;
                  return Container(
                    width: base + 36 * t,
                    height: base + 36 * t,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: activeColor.withOpacity(0.55 * (1 - t)),
                        width: 3,
                      ),
                    ),
                  );
                },
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              width: isRecording ? base + 12 : base,
              height: isRecording ? base + 12 : base,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (isRecording ? activeColor : Colors.black)
                        .withOpacity(isRecording ? 0.45 : 0.16),
                    blurRadius: isRecording ? 18 : 8,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Icon(
                isRecording ? Icons.mic : Icons.mic_none_rounded,
                color: Colors.white,
                size: (isRecording ? base + 12 : base) / 2.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleBtn(IconData icon, Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.16),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Icon(icon, color: Colors.white, size: size / 2.2),
    );
  }
}