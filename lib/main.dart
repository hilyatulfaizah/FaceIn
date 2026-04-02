// main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:face_in/login.dart';
import 'package:face_in/admin/homepage_admin.dart';
import 'package:face_in/employee/homepage_employee.dart';
import 'package:face_in/employee/face_registration.dart';
import 'package:face_in/push_notification_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:face_in/splash_screen.dart';
import 'package:face_in/firebase_options.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// 🔔 Background handler (MUST be a top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print(
      "📩 [Background Message] Title: ${message.notification?.title}, Body: ${message.notification?.body}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Load environment variables
  await dotenv.load(fileName: '.env');

  // ✅ Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await PushNotificationService().initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FaceIn',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
        // Using GoogleFonts.interTextTheme for overall theme, but Poppins is used specifically in onboarding for style.
        textTheme: GoogleFonts.interTextTheme(
          Theme.of(context).textTheme,
        ),
      ),
      home: const SplashScreen(), // Start with the SplashScreen
    );
  }
}

/// A widget that checks the user's authentication state and redirects
/// them to the appropriate page (Admin, Employee, or Login).
class AuthChecker extends StatelessWidget {
  const AuthChecker({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final User? user = authSnapshot.data;

        if (user == null) {
          return const LoginPage();
        }

        // Check if user is an admin.
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get(), // Correct collection based on your structure
          builder: (context, adminSnapshot) {
            if (adminSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (adminSnapshot.hasData && adminSnapshot.data!.exists) {
              final adminData =
                  adminSnapshot.data!.data() as Map<String, dynamic>;
              // FIX: Changed check from 'isAdmin' to 'role'
              if (adminData['role'] == 'admin') {
                final companyId = adminData['companyId'] as String? ?? '';
                final name = adminData['displayName'] ??
                    user.email ??
                    'Admin'; // Prefer displayName if available
                return HomepageAdmin(name: name, companyId: companyId);
              }
            }

            // If not admin, try employee.
            return FutureBuilder<QuerySnapshot>(
              future: FirebaseFirestore.instance
                  .collection('Employee')
                  .where('email', isEqualTo: user.email)
                  .limit(1)
                  .get(),
              builder: (context, empSnapshot) {
                if (empSnapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }

                if (empSnapshot.hasData && empSnapshot.data!.docs.isNotEmpty) {
                  final empDoc = empSnapshot.data!.docs.first;
                  final data = empDoc.data() as Map<String, dynamic>;
                  final name = data['name'] ??
                      data['fullName'] ??
                      'Employee'; // Prefer 'name', then 'fullName'
                  final hasRegisteredFace = data['hasRegisteredFace'] ?? false;
                  final docId = empDoc.id;

                  if (!hasRegisteredFace) {
                    return FaceRegistration(docId: docId, name: name);
                  }
                  return HomepageEmployee(name: name);
                }

                // Fallback: If logged in but no admin or employee record found, log out and show login page.
                FirebaseAuth.instance.signOut();
                return const LoginPage();
              },
            );
          },
        );
      },
    );
  }
}
