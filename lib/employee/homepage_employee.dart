import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // Required for date/time formatting

// Ensure these files exist and their classes are updated/defined
import 'scan_gps_employee.dart';
import 'calendar_employee.dart';
import 'profile_employee.dart';
import 'break_apply_page.dart';
import '../login.dart';
import 'notification_employee.dart'; // IMPORT the separate NotificationPage

class HomepageEmployee extends StatefulWidget {
  final String name;

  const HomepageEmployee({super.key, required this.name});

  @override
  State<HomepageEmployee> createState() => _HomepageUserState();
}

class _HomepageUserState extends State<HomepageEmployee> {
  int _selectedIndex = 0;
  // REMOVED: bool _showNotificationsView = false; // No longer needed for Navigator.push approach

  // State variables to hold attendance and break times/locations
  DateTime? _clockInTime;
  String? _clockInLocation;
  DateTime? _clockOutTime;
  String? _clockOutLocation;
  DateTime? _breakInTime;
  String? _breakInLocation;
  DateTime? _breakOutTime;
  String? _breakOutLocation;

  String?
      _currentEmployeeName; // New variable to store dynamically fetched name
  String? _jobTitle;
  String? _profilePictureUrl; // New variable for profile picture URL

  // New state variables for statistical data
  double _attendancePercentage = 0.0;
  int _leaveTakenCount = 0;
  int _ongoingDaysCount = 0;

  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance; // Firestore instance

  @override
  void initState() {
    super.initState();
    _fetchEmployeeData(); // Fetch initial data when the page loads
  }

  /// Fetches the employee's job title, today's attendance/break records,
  /// statistical data, and profile picture from Firestore.
  Future<void> _fetchEmployeeData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginPage()),
        );
      }
      return;
    }

    final uid = user.uid;

    try {
      // Fetch employee's job title, full name, and profile picture
      final employeeDoc =
          await _firestore.collection('Employee').doc(uid).get();
      if (employeeDoc.exists) {
        setState(() {
          _currentEmployeeName = employeeDoc.data()?['fullName'] ?? widget.name;
          _jobTitle = employeeDoc.data()?['jobTitle'] ?? '';
          _profilePictureUrl = employeeDoc.data()?['profilePicUrl'];
        });
      } else {
        debugPrint('Employee document not found for UID: $uid');
        setState(() {
          _currentEmployeeName = widget.name;
          _jobTitle = 'Unknown';
          _profilePictureUrl = null;
        });
      }

      // Fetch today's attendance records
      final today = DateTime.now();
      final dateStr =
          "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
      final doc = await _firestore
          .collection('Attendance')
          .doc(uid)
          .collection('Records')
          .doc(dateStr)
          .get();

      if (doc.exists) {
        final data = doc.data();
        setState(() {
          _clockInTime = (data?['Clock InOut.in'] as Timestamp?)?.toDate();
          _clockInLocation = data?['Clock InOut.in_location'] ?? '';
          _clockOutTime = (data?['Clock InOut.out'] as Timestamp?)?.toDate();
          _clockOutLocation = data?['Clock InOut.out_location'] ?? '';
          _breakInTime = (data?['Break.in'] as Timestamp?)?.toDate();
          _breakInLocation = data?['Break.in_location'] ?? '';
          _breakOutTime = (data?['Break.out'] as Timestamp?)?.toDate();
          _breakOutLocation = data?['Break.out_location'] ?? '';
        });
      } else {
        setState(() {
          _clockInTime = null;
          _clockOutTime = null;
          _breakInTime = null;
          _breakOutTime = null;
          _clockInLocation = '';
          _clockOutLocation = '';
          _breakInLocation = '';
          _breakOutLocation = '';
        });
      }

      // Fetch statistical data
      await _fetchStatisticalData(uid, _firestore);
    } catch (e) {
      debugPrint('Error fetching employee data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to load employee data: ${e.toString()}')),
        );
      }
    }
  }

  /// Fetches and updates the statistical data for Attendance, Leave Taken, and Ongoing Days.
  Future<void> _fetchStatisticalData(
      String uid, FirebaseFirestore firestore) async {
    final DateTime today = DateTime.now();
    final DateTime todayMidnight = DateTime(today.year, today.month, today.day);

    final attendanceRecords = await firestore
        .collection('Attendance')
        .doc(uid)
        .collection('Records')
        .get();

    int clockedInDays = 0;
    Set<String> uniqueAttendanceDates = {};

    for (var doc in attendanceRecords.docs) {
      final data = doc.data();
      if (data.containsKey('Clock InOut.in') &&
          data['Clock InOut.in'] != null) {
        clockedInDays++;
      }
      uniqueAttendanceDates.add(doc.id);
    }

    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    int totalPossibleWorkingDays = 0;
    for (int i = 1; i <= daysInMonth; i++) {
      final date = DateTime(now.year, now.month, i);
      if (date.weekday != DateTime.saturday &&
          date.weekday != DateTime.sunday) {
        totalPossibleWorkingDays++;
      }
    }

    double calculatedAttendancePercentage = totalPossibleWorkingDays > 0
        ? (clockedInDays / totalPossibleWorkingDays) * 100
        : 0.0;

    calculatedAttendancePercentage =
        calculatedAttendancePercentage.clamp(0.0, 100.0);

    final leaveRecords = await firestore
        .collection('Leaves')
        .where('uid', isEqualTo: uid)
        .where('status', isEqualTo: 'approved')
        .get();

    int leaveCount = 0;

    for (var doc in leaveRecords.docs) {
      final data = doc.data();
      if (data.containsKey('startDate') &&
          data['startDate'] is Timestamp &&
          data.containsKey('endDate') &&
          data['endDate'] is Timestamp) {
        final startDate = (data['startDate'] as Timestamp).toDate();
        final endDate = (data['endDate'] as Timestamp).toDate();

        if (endDate.isAfter(todayMidnight) ||
            endDate.isAtSameMomentAs(todayMidnight)) {
          final Duration diff = endDate.difference(startDate);
          leaveCount += diff.inDays + 1;
        }
      }
    }

    setState(() {
      _attendancePercentage = calculatedAttendancePercentage;
      _leaveTakenCount = leaveCount;
      _ongoingDaysCount = uniqueAttendanceDates.length;
    });
  }

  /// Handles taps on the bottom navigation bar items.
  void _onItemTapped(int index) async {
    setState(() => _selectedIndex = index);
    if (index == 1) {
      await _showPunchActionDialog();
    } else if (index == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const CalendarUserPage()),
      );
    } else if (index == 3) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ProfileUser()),
      );
      _fetchEmployeeData();
    }
  }

  /// Shortens a location string to just the first part before a comma.
  String _shortLocation(String? location) {
    if (location == null || location.isEmpty) return 'Location';
    return location.split(',').first.trim();
  }

  /// Displays a modal bottom sheet to allow the user to select between
  /// 'Attendance' (Clock In/Out) or 'Break' (Start/End) actions.
  Future<void> _showPunchActionDialog() async {
    bool attendanceClockedIn = _clockInTime != null;
    bool attendanceClockedOut = _clockOutTime != null;
    String attendancePunchType =
        attendanceClockedIn ? (attendanceClockedOut ? 'none' : 'out') : 'in';

    bool breakClockedIn = _breakInTime != null;
    bool breakClockedOut = _breakOutTime != null;
    String breakPunchType =
        breakClockedIn ? (breakClockedOut ? 'none' : 'out') : 'in';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25.0)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Select Punch Type',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800]),
              ),
              const SizedBox(height: 20),
              if (attendancePunchType != 'none')
                ListTile(
                  leading: Icon(
                    attendancePunchType == 'in' ? Icons.login : Icons.logout,
                    color: Colors.blueAccent,
                  ),
                  title: Text(
                      'Clock ${attendancePunchType == 'in' ? 'In' : 'Out'} for Attendance'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.pop(context);
                    _navigateToScan(
                        scanType: 'attendance', punchType: attendancePunchType);
                  },
                ),
              if (attendancePunchType != 'none' && _clockInTime != null)
                const Divider(),
              if (_clockInTime != null && breakPunchType != 'none')
                ListTile(
                  leading: Icon(
                    breakPunchType == 'in'
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    color: Colors.orange,
                  ),
                  title:
                      Text('${breakPunchType == 'in' ? 'Start' : 'End'} Break'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.pop(context);
                    _navigateToScan(
                        scanType: 'break', punchType: breakPunchType);
                  },
                ),
              if (_clockInTime == null && attendancePunchType != 'none')
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'You must clock in for attendance before starting or ending a break.',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child:
                    const Text('Cancel', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Navigates to the `ScanGpsEmployee` page and refreshes attendance data upon return.
  void _navigateToScan(
      {required String scanType, required String punchType}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScanGpsEmployee(
          scanType: scanType,
          punchType: punchType,
        ),
      ),
    );
    _fetchEmployeeData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 234, 228, 240),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent, // Changed to transparent
        elevation: 0, // Removed elevation
        title: const Text(
          'F a c e I n',
          style: TextStyle(
            color: const Color.fromARGB(255, 143, 83, 167), // Set app bar title color to orangeAccent
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        centerTitle: true, // Centered the title
        actions: const [], // Removed the IconButton here
      ),
      body: RefreshIndicator(
        onRefresh: _fetchEmployeeData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWelcomeBox(),
                const SizedBox(height: 16),
                _buildCheckInCard(),
                const SizedBox(height: 24),

                Row(
                  children: [
                    _statCard(
                        'Attendance',
                        '${_attendancePercentage.toStringAsFixed(0)}%',
                        Colors.deepPurple,
                        _attendancePercentage / 100),
                    const SizedBox(width: 5),
                    // Removed: _statCard('Leave Taken', _leaveTakenCount.toString().padLeft(2, '0'), Colors.blue, _leaveTakenCount > 0 ? 0.3 : 0.0),
                    // const SizedBox(width: 5),
                    _statCard(
                        'Ongoing Days',
                        _ongoingDaysCount.toString().padLeft(2, '0'),
                        Colors.purple,
                        _ongoingDaysCount > 0 ? 0.7 : 0.0),
                  ],
                ),
                const SizedBox(height: 30),

                // Today Attendance section
                const Text('Today Attendance',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _attendanceCard(
                        'IN',
                        _formatTime(_clockInTime),
                        _shortLocation(_clockInLocation),
                        _clockInTime != null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _attendanceCard(
                        'OUT',
                        _formatTime(_clockOutTime),
                        _shortLocation(_clockOutLocation),
                        _clockOutTime != null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Break Time section
                const Text('Break Time',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _attendanceCard(
                        'IN',
                        _formatTime(_breakInTime),
                        _shortLocation(_breakInLocation),
                        _breakInTime != null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _attendanceCard(
                        'OUT',
                        _formatTime(_breakOutTime),
                        _shortLocation(_breakOutLocation),
                        _breakOutTime != null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.white,
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color.fromARGB(
            255, 143, 83, 167), // Changed to Colors.amber.shade400
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.qr_code_scanner), label: 'Scan'),
          BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today), label: 'Calendar'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }

  /// Builds the welcome box displayed at the top of the homepage.
  Widget _buildWelcomeBox() {
    final DateTime now = DateTime.now();
    String greeting;
    // Fixed orange gradient colors to match admin homepage
    List<Color> gradientColors = [
      Colors.yellow.withOpacity(0.8),
      const Color.fromARGB(255, 143, 83, 167),
    ];
    Color textColor =
        Colors.white; // Text color remains white for good contrast

    // Determine greeting based on time of day (still useful for text)
    if (now.hour >= 5 && now.hour < 12) {
      greeting = 'Good Morning,';
    } else if (now.hour >= 12 && now.hour < 18) {
      greeting = 'Good Afternoon,';
    } else {
      greeting = 'Good Evening,';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white.withOpacity(0.8),
            backgroundImage:
                _profilePictureUrl != null && _profilePictureUrl!.isNotEmpty
                    ? NetworkImage(_profilePictureUrl!) as ImageProvider
                    : null,
            child: _profilePictureUrl == null || _profilePictureUrl!.isEmpty
                ? Icon(Icons.person, size: 40, color: gradientColors.last)
                : null,
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: TextStyle(
                    color: textColor.withOpacity(0.8),
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _currentEmployeeName ?? widget.name,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (_jobTitle != null && _jobTitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      _jobTitle!,
                      style: TextStyle(
                        color: textColor.withOpacity(0.7),
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the main 'Check in' card with current time, status, and location.
  Widget _buildCheckInCard() {
    final DateTime now = DateTime.now();
    final DateTime targetCheckInTime =
        DateTime(now.year, now.month, now.day, 9, 22);
    final Duration difference = now.difference(targetCheckInTime);

    String topTimeStatus;
    Color topTimeStatusColor;
    String detailedTimeStatus = '';

    if (_clockInTime != null) {
      topTimeStatus = "Checked In";
      topTimeStatusColor = Colors.green.shade600;
    } else {
      if (difference.isNegative) {
        detailedTimeStatus = "${difference.inMinutes.abs()} Min Early";
        if (difference.inMinutes.abs() <= 15) {
          topTimeStatus = "On time";
          topTimeStatusColor = Colors.orange.shade700;
        } else {
          topTimeStatus = "Early";
          topTimeStatusColor = Colors.green.shade600;
        }
      } else if (difference.inMinutes <= 15) {
        topTimeStatus = "On time";
        topTimeStatusColor = Colors.orange.shade700;
      } else {
        topTimeStatus = "Late";
        topTimeStatusColor = Colors.red.shade700;
        detailedTimeStatus = "${difference.inMinutes} Min Late";
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        image: const DecorationImage(
          image: AssetImage('assets/map_background.jpg'),
          fit: BoxFit.cover,
          opacity: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.check,
                        color: Colors.blue.shade700, size: 16),
                  ),
                  const SizedBox(width: 8),
                  Text('Check in',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800])),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: topTimeStatusColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  topTimeStatus,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('EEE, MMM dd, HH:mm:ss').format(now),
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                flex: 2,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      _clockInTime != null
                          ? _formatTime(_clockInTime, includeAmPm: false)
                          : DateFormat('hh:mm').format(now),
                      style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[900]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _clockInTime != null
                          ? DateFormat('a').format(_clockInTime!)
                          : DateFormat('a').format(now),
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.normal,
                          color: Colors.grey[700]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (_clockInTime == null && detailedTimeStatus.isNotEmpty)
                Expanded(
                  child: Text(
                    detailedTimeStatus,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[600]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.location_on, size: 16, color: Colors.blueGrey),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  (_clockInLocation?.isNotEmpty ?? false)
                      ? _shortLocation(_clockInLocation)
                      : 'Main Office - Entrance Gate',
                  style: TextStyle(color: Colors.grey[600]),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Helper widget for displaying attendance/break IN/OUT status boxes.
  static Widget _attendanceCard(
      String title, String time, String location, bool isChecked) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isChecked
              ? [const Color.fromARGB(255, 143, 83, 167), const Color.fromARGB(255, 135, 63, 163)]
              : [
                  const Color.fromARGB(255, 246, 245, 242),
                  const Color.fromARGB(255, 246, 245, 242),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isChecked ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            time,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isChecked ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            location,
            style: TextStyle(
              fontSize: 12,
              color: isChecked ? Colors.white70 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  /// Formats a DateTime object into a time string (e.g., "09:10 AM").
  static String _formatTime(DateTime? time, {bool includeAmPm = true}) {
    if (time == null) return '--:--';
    if (includeAmPm) {
      return DateFormat('hh:mm a').format(time);
    } else {
      return DateFormat('hh:mm').format(time);
    }
  }

  /// Builds a statistical card for metrics like Attendance, Leave Taken, etc.
  Widget _statCard(
      String label, String value, Color color, double progressValue) {
    return Expanded(
      child: Card(
        color: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 70,
                height: 70,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 70,
                      height: 70,
                      child: CircularProgressIndicator(
                        value: progressValue,
                        color: color,
                        backgroundColor: color.withOpacity(0.2),
                        strokeWidth: 5,
                      ),
                    ),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the "Apply for Leave" or "Check Upcoming Holidays" box.
  Widget _buildLeaveHolidayBox() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_month,
                    color: Colors.blue.shade800, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Manage Leaves & Holidays',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Apply for leave or check upcoming holidays to manage your time off efficiently.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const BreakApplyPage()),
                  );
                },
                icon: const Icon(Icons.arrow_forward_ios, size: 18),
                label: const Text('Apply Now', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}