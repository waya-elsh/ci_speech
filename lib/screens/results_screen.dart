import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  int excellent = 0;
  int good = 0;
  int retry = 0;

  @override
  void initState() {
    super.initState();
    loadResults();
  }

  Future<void> loadResults() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      excellent = prefs.getInt('excellent') ?? 0;
      good = prefs.getInt('good') ?? 0;
      retry = prefs.getInt('retry') ?? 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    int total = excellent + good + retry;
    double success = total == 0 ? 0 : ((excellent + good) / total) * 100;

    return Scaffold(
      backgroundColor: const Color(0xFFACE9FF),
      body: SafeArea(
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(25),
            padding: const EdgeInsets.all(25),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "نتائج الطفل",
                  style: GoogleFonts.cairo(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 25),
                _row("ممتاز", excellent),
                _row("محاولة جيدة", good),
                _row("يحتاج تدريب", retry),
                const SizedBox(height: 30),
                Text(
                  "٪ نسبة التقدم ${success.toStringAsFixed(0)}",
                  style: GoogleFonts.cairo(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(String title, int num) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: GoogleFonts.cairo(fontSize: 20)),
          Text("$num", style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}