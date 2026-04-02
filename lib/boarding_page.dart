// onboarding_page.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:face_in/login.dart'; // Import your login page
import 'package:google_fonts/google_fonts.dart'; // Import Google Fonts

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  List<Map<String, String>> onboardingData = [
    {
      "image": "assets/logo.png", // Make sure you have a logo in your assets folder
      "title": "Welcome to FaceIn",
      "description": "Your ultimate solution for seamless attendance management and enhanced security.",
    },
    {
      "image": "assets/lottie/face_scan_animation.json", // Example image - ensure this path is correct
      "title": "Effortless Attendance",
      "description": "Clock in and out with just your face! Quick, accurate, and secure.",
    },
    {
      "image": "assets/notifications.png", // Example image - ensure this path is correct
      "title": "Stay Informed",
      "description": "Receive real-time notifications about logins, attendance, and important updates.",
    },
  ];

  _onPageViewChange(int page) {
    setState(() {
      _currentPage = page;
    });
  }

  // Function to mark onboarding as seen and navigate to login
  _getStarted() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenOnboarding', true);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Consistent dark background color
      backgroundColor: const Color(0xFF2C3E50), // Dark Blue-Gray
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: onboardingData.length,
              onPageChanged: _onPageViewChange,
              itemBuilder: (context, index) {
                return OnboardingScreen(
                  image: onboardingData[index]["image"]!,
                  title: onboardingData[index]["title"]!,
                  description: onboardingData[index]["description"]!,
                );
              },
            ),
          ),
          // Dot indicators
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              onboardingData.length,
              (index) => _buildDot(index),
            ),
          ),
          const SizedBox(height: 30),
          // Get Started Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: SizedBox(
              width: double.infinity,
              height: 55, // Increased height for better tap target
              child: ElevatedButton(
                onPressed: _getStarted,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF27AE60), // Vibrant Green accent
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12), // Slightly more rounded
                  ),
                  elevation: 5, // Add a subtle shadow
                ),
                child: Text(
                  _currentPage == onboardingData.length - 1 ? "Get Started" : "Next",
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white, // White text on green button
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 40), // More spacing at the bottom
        ],
      ),
    );
  }

  // Helper method to build the dot indicators
  Widget _buildDot(int index) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: 10,
      width: _currentPage == index ? 25 : 10, // Wider for active dot
      margin: const EdgeInsets.only(right: 8), // Increased margin
      decoration: BoxDecoration(
        color: _currentPage == index ? const Color(0xFF27AE60) : Colors.grey.shade600, // Accent green for active, darker grey for inactive
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }
}

class OnboardingScreen extends StatelessWidget {
  final String image;
  final String title;
  final String description;

  const OnboardingScreen({
    super.key,
    required this.image,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Using Image.asset for local images
          Image.asset(
            image,
            height: 250,
            width: 250,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 50),
          Text(
            title,
            style: GoogleFonts.poppins( // Using Poppins font
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: Colors.white, // White text on dark background
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Text(
            description,
            style: GoogleFonts.poppins( // Using Poppins font
              fontSize: 16,
              color: Colors.white70, // Slightly lighter white for description
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
