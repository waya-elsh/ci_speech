import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/home_screen.dart';


void main() {
  runApp(const CiSpeechApp());
}

class CiSpeechApp extends StatelessWidget {
  const CiSpeechApp({super.key});

  @override
Widget build(BuildContext context) {
  return MaterialApp(
    title: 'نطقي',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      textTheme: GoogleFonts.cairoTextTheme(),
    ),
    home: const SplashScreen(),
  );
}
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool showRaisedBlink = false;
  Timer? poseTimer;
  Timer? navTimer;

  @override
  void initState() {
    super.initState();


    poseTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) return;

      setState(() {
        showRaisedBlink = true;
      });

     
      await Future.delayed(const Duration(milliseconds: 1400));

      if (!mounted) return;
      setState(() {
        showRaisedBlink = false;
      });
    });

    
    navTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    });
  }

  @override
  void dispose() {
    poseTimer?.cancel();
    navTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFACE9FF),
      body: Center(
  child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 700),
        child: Image.asset(
          showRaisedBlink
              ? 'assets/images/coco.png'
              : 'assets/images/coco2.png',
          key: ValueKey(showRaisedBlink),
          width: 400,
        ),
      ),

      const SizedBox(height: 25),

      Text(
  "Coco لنتعلم النطق مع ",
  textAlign: TextAlign.center,
  style: GoogleFonts.cairo(
    fontSize: 30,
    fontWeight: FontWeight.bold,
    color: const Color.fromARGB(255, 255, 255, 255),
    shadows: [
      Shadow(
        blurRadius: 4,
        color: Colors.black12,
        offset: Offset(2, 2),
      ),
    ],
  ),
),
    ],
  ),
),
    );
  }
}
