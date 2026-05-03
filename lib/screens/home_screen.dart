import 'package:ci_speech/screens/results_screen.dart';
import 'package:ci_speech/screens/training_screen.dart';
import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:  const Color(0xFFACE9FF),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 20),

            // Coco
            Image.asset(
              'assets/images/coco2.png',
              width: 350,
            ),

            const SizedBox(height: 30),

            const Text(
              "مرحبًا",
              
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 40),

          
            _buildButton("تدريب"),
            _buildButton("النتائج"),
            _buildButton("الدعم"),
          ],
        ),
      ),
    );
  }

  Widget _buildButton(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
      child: _HoverButton(title: title),
    );
  }
}


class _HoverButton extends StatefulWidget {
  final String title;

  const _HoverButton({required this.title});

  @override
  State<_HoverButton> createState() => _HoverButtonState();
}

class _HoverButtonState extends State<_HoverButton> {
  bool isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        setState(() {
          isHovering = true;
        });
      },
      onExit: (_) {
        setState(() {
          isHovering = false;
        });
      },
      child: GestureDetector(
        onTap: () {
  if (widget.title == "تدريب") {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TrainingScreen()),
    );
  }

  if (widget.title == "النتائج") {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ResultsScreen()),
    );
  }
},
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 65,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: isHovering
                  ? [
                      const Color.fromARGB(255, 233, 195, 219),
                      Colors.lightBlueAccent,
                    ]
                  : [
                      Color(0xFF6EC6FF),
                      Color(0xFF2196F3),
                    ],
            ),
            boxShadow: [
              if (isHovering)
                BoxShadow(
                  color: const Color.fromARGB(255, 219, 196, 216).withOpacity(0.4),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
            ],
          ),
          child: Center(
            child: Text(
              widget.title,
              style: const TextStyle(
                fontSize: 20,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}