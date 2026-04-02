import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // Import for DateFormat

class NotificationAdminPage extends StatefulWidget {
  const NotificationAdminPage({super.key});

  @override
  State<NotificationAdminPage> createState() => _NotificationAdminPageState();
}

class _NotificationAdminPageState extends State<NotificationAdminPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _adminUid;

  @override
  void initState() {
    super.initState();
    _adminUid = _auth.currentUser?.uid;
    print('NotificationAdminPage: Admin UID in initState: $_adminUid'); // Debug print
    if (_adminUid == null) {
      // Handle case where admin is not logged in, perhaps navigate to login
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Admin not logged in.')),
        );
        // You might want to navigate to a login page here
      });
    }
  }

  /// Calculates how long ago a timestamp occurred.
  String _timeAgo(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()}y ago';
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()}mo ago';
    } else if (difference.inDays > 7) {
      return '${(difference.inDays / 7).floor()}w ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  /// Marks a specific notification as read.
  Future<void> _markNotificationAsRead(String notificationId) async {
    if (_adminUid == null) {
      print('Error: _adminUid is null when trying to mark notification as read.'); // Debug print
      return;
    }
    try {
      await _firestore
          .collection('users')
          .doc(_adminUid)
          .collection('notifications')
          .doc(notificationId)
          .update({'isRead': true});
      debugPrint('Notification $notificationId marked as read.');
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  /// Marks all notifications as read for the current admin.
  Future<void> _markAllAsRead() async {
    if (_adminUid == null) {
      print('Error: _adminUid is null when trying to mark all as read.'); // Debug print
      return;
    }
    try {
      final unreadNotifications = await _firestore
          .collection('users')
          .doc(_adminUid)
          .collection('notifications')
          .where('isRead', isEqualTo: false)
          .get();

      final batch = _firestore.batch();
      for (var doc in unreadNotifications.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
      debugPrint('All notifications marked as read for admin $_adminUid.');
    } catch (e) {
      debugPrint('Error marking all notifications as read: $e');
    }
  }

  /// Deletes a specific notification from Firestore.
  Future<void> _deleteNotification(String notificationId) async {
    if (_adminUid == null) {
      print('Error: _adminUid is null when trying to delete notification.'); // Debug print
      return;
    }
    try {
      await _firestore
          .collection('users')
          .doc(_adminUid)
          .collection('notifications')
          .doc(notificationId)
          .delete();
      debugPrint('Notification $notificationId deleted successfully.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification deleted.')),
      );
    } catch (e) {
      debugPrint('Error deleting notification: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete notification: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_adminUid == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(), // Or a message indicating login required
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[100], // Light grey background
      body: Column(
        children: [
          // Custom AppBar-like header
          Padding(
            padding: const EdgeInsets.only(top: 40.0, left: 16.0, right: 16.0, bottom: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black),
                  onPressed: () {
                    Navigator.pop(context);
                  },
                ),
                const Text(
                  'Admin Notifications', // Specific title for admin
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                // This Spacer ensures the title remains centered
                const SizedBox(width: 48), // Placeholder for alignment
              ],
            ),
          ),
          // Section for "Recent" notifications and "Mark all as read" button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
                TextButton(
                  onPressed: _markAllAsRead,
                  child: const Text(
                    'Mark all as read',
                    style: TextStyle(
                      color: Colors.blue, // Changed to blue for action
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('users')
                  .doc(_adminUid)
                  .collection('notifications')
                  .orderBy('timestamp', descending: true) // Order by latest
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  print('StreamBuilder: ConnectionState.waiting'); // Debug print
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  print('StreamBuilder: Error: ${snapshot.error}'); // Debug print
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  print('StreamBuilder: No data or empty docs. Has data: ${snapshot.hasData}, Docs empty: ${snapshot.data?.docs.isEmpty}'); // Debug print
                  return const Center(
                    child: Text('No notifications for now.'),
                  );
                }

                final notifications = snapshot.data!.docs;
                print('StreamBuilder: Found ${notifications.length} notifications.'); // Debug print

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  itemCount: notifications.length,
                  itemBuilder: (context, index) {
                    final doc = notifications[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final String title = data['title'] ?? 'No Title';
                    final String body = data['body'] ?? 'No Body';
                    final Timestamp timestamp = data['timestamp'] as Timestamp? ?? Timestamp.now();
                    final bool isRead = data['isRead'] ?? false;
                    final Map<String, dynamic>? notificationData = data['data'] as Map<String, dynamic>?; // Extract the nested 'data' field

                    print('Notification ${doc.id}: Title: $title, Body: $body, IsRead: $isRead, Data: $notificationData'); // Debug print for each notification

                    // Determine icon and color based on notification content or type
                    IconData icon = Icons.info_outline;
                    Color avatarBgColor = Colors.blue.shade100;
                    Color itemIconColor = Colors.blue.shade700;

                    String displayTitle = title;
                    String displaySubtitle = body;

                    // Check for employee activity notifications specifically
                    if (notificationData != null && notificationData['type'] == 'admin_employee_activity_alert') {
                      final String? employeeName = notificationData['employeeName'] ?? notificationData['sourceEmployeeName'];
                      final String? activityType = notificationData['activity']; // e.g., 'punch_in', 'punch_out'
                      final String? latenessMessage = notificationData['latenessMessage'];
                      final bool? isLate = notificationData['isLate']; // Assuming these flags are passed
                      final bool? isEarly = notificationData['isEarly'];

                      icon = Icons.access_time;
                      avatarBgColor = Colors.orange.shade100;
                      itemIconColor = Colors.orange.shade700; // Default for activity

                      String employeePart = employeeName != null ? '$employeeName ' : 'An employee ';
                      String statusPart = '';

                      if (activityType == 'punch_in') {
                        statusPart = 'clocked in';
                        if (isLate == true) {
                          statusPart += ' late';
                          itemIconColor = Colors.red.shade700; // Highlight late punches
                        }
                      } else if (activityType == 'punch_out') {
                        statusPart = 'clocked out';
                        if (isEarly == true) {
                          statusPart += ' early';
                          itemIconColor = Colors.red.shade700; // Highlight early punches
                        }
                      } else {
                        statusPart = 'had activity';
                      }

                      displayTitle = '${employeePart}${statusPart}';
                      displaySubtitle = 'At ${DateFormat('hh:mm a').format(timestamp.toDate())}';

                      if (latenessMessage != null && latenessMessage.isNotEmpty) {
                        displaySubtitle += '\nReason: $latenessMessage';
                      } else if (isLate == true) {
                         displaySubtitle += '\n(Late Clock-in)';
                      } else if (isEarly == true) {
                         displaySubtitle += '\n(Early Clock-out)';
                      }
                      // Append original body if it contains additional useful info
                      // Only append if it's not redundant with the statusPart
                      if (body.isNotEmpty && !body.toLowerCase().contains(statusPart.toLowerCase())) {
                         displaySubtitle += '\nOriginal: $body';
                      }

                    } else if (title.contains('Leave Request')) {
                      icon = Icons.calendar_today;
                      avatarBgColor = Colors.purple.shade100;
                      itemIconColor = Colors.purple.shade700;
                    }

                    return Dismissible(
                      key: ValueKey(doc.id), // Unique key for Dismissible
                      direction: DismissDirection.endToStart, // Only swipe left
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        color: Colors.red, // Red background when swiping
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (direction) {
                        _deleteNotification(doc.id); // Call delete function
                      },
                      child: _buildNotificationTileContent(
                        context,
                        doc.id,
                        displayTitle,
                        displaySubtitle,
                        _timeAgo(timestamp.toDate()),
                        avatarBgColor,
                        icon,
                        itemIconColor,
                        isRead,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to build individual notification tiles content (without Dismissible wrapper)
  Widget _buildNotificationTileContent(
    BuildContext context,
    String notificationId,
    String title,
    String subtitle,
    String timeAgo,
    Color avatarBgColor,
    IconData avatarIcon,
    Color iconColor,
    bool isRead,
  ) {
    return GestureDetector(
      onTap: () {
        if (!isRead) {
          _markNotificationAsRead(notificationId); // Mark as read on tap
        }
        // TODO: Implement navigation to specific notification details if needed
        debugPrint('Tapped on notification: $title');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Container(
          decoration: BoxDecoration(
            color: isRead ? Colors.white : Colors.blue.shade50, // Highlight unread
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 5,
                offset: const Offset(0, 3),
              ),
            ],
          ),
            child: ListTile(
              leading: CircleAvatar(
                radius: 24,
                backgroundColor: avatarBgColor,
                child: Icon(avatarIcon, color: iconColor, size: 28), // Use iconColor
              ),
              title: Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isRead ? Colors.black87 : Colors.black, // Darker for unread
                ),
              ),
              subtitle: Text(
                subtitle,
                style: TextStyle(
                  color: isRead ? Colors.grey : Colors.grey[800], // Darker for unread
                ),
                maxLines: 3, // Increased maxLines for subtitle
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    timeAgo,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                  if (!isRead) // Show unread dot
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.blue.shade700,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
        ),
      ),
    );
  }
}
