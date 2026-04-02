import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  print('Background notification tapped via top-level function: ${notificationResponse.payload}');
}

class PushNotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    print('User granted notification permissions: ${settings.authorizationStatus}');

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );
    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        print('Notification tapped: ${response.payload}');
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('🔔 [Foreground Message] Title: ${message.notification?.title}, Body: ${message.notification?.body}');
      if (message.notification != null) {
        // Get current user's role
        FirebaseAuth.instance.currentUser?.getIdTokenResult().then((idTokenResult) async {
          final bool isAdmin = idTokenResult.claims?['role'] == 'admin';
          final bool isEmployeeActivityNotification =
              (message.notification!.title?.contains('Activity Alert') == true ||
               message.notification!.body?.contains('clocked in') == true ||
               message.notification!.body?.contains('clocked out') == true ||
               message.data['type'] == 'employee_activity');

          if (isAdmin) {
            // Admins receive all notifications and save them
            _showLocalNotification(message);
            _saveNotificationToFirestore(message, forAdmin: true); // Indicate it's for admin
          } else { // Current user is an Employee
            // Employees only receive and save "Forgot to Clock In/Out" reminders.
            // Employee activity notifications (their own punches) should NOT be shown or saved to their list.
            if (message.notification!.title?.contains('Forgot to Clock') == true ||
                message.data['type'] == 'forgot_punch') {
              _showLocalNotification(message);
              _saveNotificationToFirestore(message, forEmployee: true); // Indicate it's for employee
            } else if (isEmployeeActivityNotification) {
              // This is an employee's own activity notification, but it should only go to admin.
              // So, do NOT show local notification or save to employee's Firestore.
              print('Employee activity notification received by employee, but only forwarding to admin. Not showing locally or saving to employee list.');
              // We still need to ensure it gets to the admin, which is handled in the _saveNotificationToFirestore logic.
              // We will call _saveNotificationToFirestore with a specific flag to only send to admin.
              _saveNotificationToFirestore(message, onlyForwardToAdmin: true);
            } else {
              print('Skipping other non-relevant notification for employee: ${message.notification?.title}');
            }
          }
        });
      }
    });

    String? token = await _fcm.getToken();
    if (token != null) {
      print("FCM Token: $token");
      await _saveTokenToFirestore(token);
    }

    _fcm.onTokenRefresh.listen((String newToken) {
      print("FCM Token refreshed: $newToken");
      _saveTokenToFirestore(newToken);
    });

    _fcm.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        print("App opened from terminated state by tapping notification.");
        // Apply the same filtering logic for initial messages
        FirebaseAuth.instance.currentUser?.getIdTokenResult().then((idTokenResult) async {
          final bool isAdmin = idTokenResult.claims?['role'] == 'admin';
          final bool isEmployeeActivityNotification =
              (message.notification!.title?.contains('Activity Alert') == true ||
               message.notification!.body?.contains('clocked in') == true ||
               message.notification!.body?.contains('clocked out') == true ||
               message.data['type'] == 'employee_activity');

          if (isAdmin) {
            _saveNotificationToFirestore(message, forAdmin: true);
          } else if (message.notification!.title?.contains('Forgot to Clock') == true || message.data['type'] == 'forgot_punch') {
            _saveNotificationToFirestore(message, forEmployee: true);
          } else if (isEmployeeActivityNotification) {
            _saveNotificationToFirestore(message, onlyForwardToAdmin: true);
          }
        });
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print("App opened from background state by tapping notification.");
      // Apply the same filtering logic for messages opened from background
      FirebaseAuth.instance.currentUser?.getIdTokenResult().then((idTokenResult) async {
        final bool isAdmin = idTokenResult.claims?['role'] == 'admin';
        final bool isEmployeeActivityNotification =
              (message.notification!.title?.contains('Activity Alert') == true ||
               message.notification!.body?.contains('clocked in') == true ||
               message.notification!.body?.contains('clocked out') == true ||
               message.data['type'] == 'employee_activity');

        if (isAdmin) {
          _saveNotificationToFirestore(message, forAdmin: true);
        } else if (message.notification!.title?.contains('Forgot to Clock') == true || message.data['type'] == 'forgot_punch') {
          _saveNotificationToFirestore(message, forEmployee: true);
        } else if (isEmployeeActivityNotification) {
          _saveNotificationToFirestore(message, onlyForwardToAdmin: true);
        }
      });
    });
  }

  Future<void> _saveTokenToFirestore(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userId = user.uid;
      final adminDoc = await _firestore.collection('users').doc(userId).get();
      if (adminDoc.exists && adminDoc.data()?['role'] == 'admin') {
        await _firestore.collection('users').doc(userId).set({
          'fcmToken': token,
        }, SetOptions(merge: true));
        print("FCM token saved for admin: $userId");
      } else {
        final employeeDoc = await _firestore.collection('Employee').doc(userId).get();
        if (employeeDoc.exists) {
          await _firestore.collection('Employee').doc(userId).set({
            'fcmToken': token,
          }, SetOptions(merge: true));
          print("FCM token saved for employee: $userId");
        } else {
          print("User not found in 'users' or 'Employee' collection. Cannot save FCM token.");
        }
      }
    } else {
      print("No authenticated user to save FCM token for.");
    }
  }

  void _showLocalNotification(RemoteMessage message) {
    if (message.notification == null) return;

    final notification = message.notification!;
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'attendance_channel_id',
      'Attendance Notifications',
      channelDescription: 'Notifications related to employee attendance and punches.',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false,
      icon: '@mipmap/ic_launcher',
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics, iOS: DarwinNotificationDetails());

    _flutterLocalNotificationsPlugin.show(
      0,
      notification.title,
      notification.body,
      platformChannelSpecifics,
      payload: jsonEncode(message.data),
    );
  }

  Future<void> _saveNotificationToFirestore(
    RemoteMessage message, {
    bool forAdmin = false,
    bool forEmployee = false,
    bool onlyForwardToAdmin = false, // New flag
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || message.notification == null) return;

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final bool isCurrentUserAdmin = userDoc.exists && userDoc.data()?['role'] == 'admin';

      // Determine if this is an employee activity notification
      final bool isEmployeeActivityNotification =
          (message.notification!.title?.contains('Activity Alert') == true ||
           message.notification!.body?.contains('clocked in') == true ||
           message.notification!.body?.contains('clocked out') == true ||
           message.data['type'] == 'employee_activity');

      // Logic to save to the current user's collection (employee or admin)
      // Only save to employee's collection if it's explicitly for them (e.g., forgot punch)
      // and NOT an employee activity notification meant only for admin.
      if (!onlyForwardToAdmin) { // If this flag is true, we skip saving to current user's collection
        String targetCollectionPath;
        if (isCurrentUserAdmin) {
          targetCollectionPath = 'users'; // Admin's own notifications
        } else {
          targetCollectionPath = 'Employee'; // Employee's own notifications
        }

        // Only save to employee's collection if it's not an activity alert
        // (because activity alerts are only for admin now)
        if (isCurrentUserAdmin || (forEmployee && !isEmployeeActivityNotification)) {
            await _firestore.collection(targetCollectionPath).doc(user.uid).collection('notifications').add({
              'title': message.notification!.title,
              'body': message.notification!.body,
              'timestamp': FieldValue.serverTimestamp(),
              'isRead': false,
              'data': message.data,
            });
            print('Notification saved to Firestore for user ${user.uid} in $targetCollectionPath/notifications');
        } else {
          print('Skipping saving notification to employee ${user.uid} as it is an activity alert meant for admin.');
        }
      }

      // Logic to forward employee activity notifications to admins
      // This part runs if the current user is an employee AND the notification is an activity type.
      // This also covers the `onlyForwardToAdmin` scenario where the employee doesn't get it locally.
      if (!isCurrentUserAdmin && isEmployeeActivityNotification) {
        final adminUsers = await _firestore.collection('users').where('role', isEqualTo: 'admin').get();
        for (var adminDoc in adminUsers.docs) {
          final employeeName = message.data['employeeName'] ?? user.email ?? user.uid;
          await _firestore.collection('users').doc(adminDoc.id).collection('notifications').add({
            'title': "Employee Activity: ${message.notification!.title}",
            'body': "${message.notification!.body} (Employee: $employeeName)",
            'timestamp': FieldValue.serverTimestamp(),
            'isRead': false,
            'data': {
              ...message.data,
              'sourceEmployeeId': user.uid,
              'sourceEmployeeName': employeeName,
              'type': 'admin_employee_activity_alert'
            },
          });
          print('Employee activity notification forwarded to admin ${adminDoc.id}');
        }
      }
    } catch (e) {
      print('Error saving notification to Firestore: $e');
    }
  }

  static Future<void> sendNotification({
    required String deviceToken,
    required String title,
    required String message,
    Map<String, dynamic>? data,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('❌ Error: Cannot call Cloud Function. User is not authenticated.');
        throw FirebaseFunctionsException(
          code: 'unauthenticated',
          message: 'The function must be called while authenticated.',
        );
      }

      final functions = FirebaseFunctions.instance;
      final HttpsCallable callable = functions.httpsCallable('sendFCMNotification');

      final Map<String, dynamic> requestData = {
        'deviceToken': deviceToken,
        'title': title,
        'body': message,
        'data': data ?? {},
      };

      final HttpsCallableResult result = await callable.call(requestData);

      print('Cloud Function response: ${result.data}');
      if (result.data['success'] == true) {
        print('✅ Notification request sent to Cloud Function successfully!');
      } else {
        print('❌ Notification request failed via Cloud Function: ${result.data['error']}');
      }
    } catch (e) {
      print('❌ Error calling Cloud Function to send notification: $e');
      if (e is FirebaseFunctionsException) {
        print('Cloud Function Error Code: ${e.code}');
        print('Cloud Function Error Details: ${e.details}');
        print('Cloud Function Error Message: ${e.message}');
      }
    }
  }

  // EMPLOYEE NOTIFICATIONS:

  // 1. Forgot to Clock In/Out Reminder – handled via Cloud Scheduler backend logic.

  // ADMIN NOTIFICATIONS:

  // 1. When Employee Late – implemented in scan_gps_employee.dart and uses sendNotification().

  // 2. Employee Registration:
  /*
    static Future<void> sendNewEmployeeNotification({
      required String adminDeviceToken,
      required String newEmployeeName,
    }) async {
      final title = "New Employee Registered";
      final body = "$newEmployeeName has registered an account and might require setup.";
      await PushNotificationService.sendNotification(
        deviceToken: adminDeviceToken,
        title: title,
        message: body,
        data: {'type': 'new_employee_registration', 'employeeId': '...'},
      );
    }
  */
}
