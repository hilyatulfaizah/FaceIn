import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart'; // For PDF generation
import 'package:pdf/widgets.dart' as pw; // For PDF widgets
import 'package:excel/excel.dart'; // For Excel generation
import 'package:path_provider/path_provider.dart'; // For temporary directory
import 'package:share_plus/share_plus.dart'; // Corrected import for sharing files
import 'dart:io'; // For File operations
import 'dart:typed_data'; // Needed for Uint8List

// New imports for direct saving and permissions
import 'package:permission_handler/permission_handler.dart';
import 'package:file_saver/file_saver.dart';
import 'package:device_info_plus/device_info_plus.dart'; // Added for Android version check


// Enum to define the report filtering type
enum ReportFilterType { daily, month, year }

class HistoryPageEmployee extends StatefulWidget {
  const HistoryPageEmployee({super.key});

  @override
  State<HistoryPageEmployee> createState() => _HistoryPageEmployeeState();
}

class _HistoryPageEmployeeState extends State<HistoryPageEmployee> with SingleTickerProviderStateMixin {
  DateTime? _selectedDate;
  ReportFilterType _selectedFilterType = ReportFilterType.daily; // Default to daily
  String? _employeeUid; // Current employee's UID
  String _employeeName = 'Employee'; // Current employee's name
  bool _isLoadingData = true; // Combined loading flag for initial data and reports
  late TabController _tabController;

  // State variables to hold fetched data for each report type
  List<Map<String, dynamic>> _attendanceSummaryData = [];
  List<Map<String, dynamic>> _dailyAttendanceLogsData = [];
  List<Map<String, dynamic>> _workingHoursData = []; // Correctly defined

  // Tab names for display
  final List<String> _tabNames = const [
    'Summary',
    'Daily Logs',
    'Working Hours',
  ];

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _tabController = TabController(length: _tabNames.length, vsync: this);
    _initializeEmployeeData(); // Initialize UID and name first
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Formats a DateTime object into a day string (e.g., "Monday, 20 July 2024").
  String _formatDay(DateTime dt) {
    return DateFormat('EEEE, dd MMMM yyyy').format(dt);
  }

  /// Formats a DateTime object into a month string (e.g., "July 2024").
  String _formatMonth(DateTime dt) {
    return DateFormat('MMMM yyyy').format(dt);
  }

  /// Formats a DateTime object into a year string (e.g., "2024").
  String _formatYear(DateTime dt) {
    return DateFormat('yyyy').format(dt);
  }


  Future<void> _initializeEmployeeData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // Handle not logged in, maybe navigate to login
      if (mounted) {
        setState(() {
          _isLoadingData = false;
        });
      }
      return;
    }
    _employeeUid = user.uid;

    try {
      final employeeDoc = await FirebaseFirestore.instance.collection('Employee').doc(_employeeUid).get();
      if (employeeDoc.exists) {
        setState(() {
          _employeeName = employeeDoc.data()?['fullName'] ?? 'Employee';
        });
      }
    } catch (e) {
      debugPrint('[DEBUG] Error fetching employee name: $e');
    }

    _fetchReportData(); // Fetch reports after employee data is set
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      _fetchReportData();
    }
  }

  Future<void> _fetchReportData() async {
    if (_employeeUid == null) {
      if (mounted) {
        setState(() {
          _isLoadingData = false;
        });
      }
      return; // Cannot fetch without UID
    }

    setState(() {
      _isLoadingData = true;
      // Clear previous data
      _attendanceSummaryData = [];
      _dailyAttendanceLogsData = [];
      _workingHoursData = []; // Clear this as well
    });

    // Determine the date range based on the selected filter type
    DateTime startDate;
    DateTime endDate;

    _selectedDate ??= DateTime.now();

    if (_selectedFilterType == ReportFilterType.daily) {
      startDate = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
      endDate = startDate.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
    } else if (_selectedFilterType == ReportFilterType.month) {
      startDate = DateTime(_selectedDate!.year, _selectedDate!.month, 1);
      endDate = DateTime(_selectedDate!.year, _selectedDate!.month + 1, 0).add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
    } else { // ReportFilterType.year
      startDate = DateTime(_selectedDate!.year, 1, 1);
      endDate = DateTime(_selectedDate!.year + 1, 1, 1).subtract(const Duration(milliseconds: 1));
    }

    try {
      await Future.wait([
        _fetchAttendanceSummary(startDate, endDate),
        _fetchDailyAttendanceLogs(startDate, endDate),
        _fetchWorkingHoursReport(startDate, endDate),
      ]);
    } catch (e) {
      debugPrint("[DEBUG] Error fetching report data: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load reports: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingData = false;
        });
      }
    }
  }

  /// Fetches data for the Attendance Summary Report for the current employee.
  Future<void> _fetchAttendanceSummary(DateTime startDate, DateTime endDate) async {
    final Map<String, dynamic> summary = {
      'totalHours': 0, // Store in minutes for accurate sum
      'totalDaysPresent': 0,
      'totalLateDays': 0,
      'totalLeaveDays': 0,
      'status': 'Absent', // Overall status for the period
    };

    try {
      // Fetch attendance records for the period
      final attendanceRecordsSnapshot = await FirebaseFirestore.instance
          .collection('Attendance')
          .doc(_employeeUid)
          .collection('Records')
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: DateFormat('yyyy-MM-dd').format(startDate))
          .where(FieldPath.documentId, isLessThanOrEqualTo: DateFormat('yyyy-MM-dd').format(endDate))
          .get();

      for (var doc in attendanceRecordsSnapshot.docs) {
        final data = doc.data();
        final Timestamp? clockInTs = data['Clock InOut.in'] as Timestamp?;
        final Timestamp? clockOutTs = data['Clock InOut.out'] as Timestamp?;

        if (clockInTs != null) {
          summary['totalDaysPresent']++;
          if (clockOutTs != null) {
            Duration workedDuration = clockOutTs.toDate().difference(clockInTs.toDate());
            // Subtract break times if available
            final Timestamp? breakInTs = data['Break.in'] as Timestamp?;
            final Timestamp? breakOutTs = data['Break.out'] as Timestamp?;
            if (breakInTs != null && breakOutTs != null) {
              Duration breakDuration = breakOutTs.toDate().difference(breakInTs.toDate());
              workedDuration = workedDuration - breakDuration;
            }
            summary['totalHours'] += workedDuration.inMinutes;
          }
        }
      }

      // Fetch punch logs for lateness (assuming PunchLogs are stored per company, but filtered by employeeId)
      // This part might need adjustment if PunchLogs are directly under employee UID
      final punchLogsSnapshot = await FirebaseFirestore.instance
          .collection('PunchLogs') // Assuming PunchLogs is a top-level collection
          .where('employeeId', isEqualTo: _employeeUid) // Filter by current employee
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .get();

      for (var log in punchLogsSnapshot.docs) {
        final logData = log.data();
        // Check for 'excessively late' first, then 'latenessMessage'
        final String latenessMessage = logData['excessively late'] ?? logData['latenessMessage'] ?? '';
        if (latenessMessage.isNotEmpty) {
          summary['totalLateDays']++;
        }
      }

      // Fetch leave data for the period
      final leaveSnapshot = await FirebaseFirestore.instance
          .collection('Leaves')
          .where('uid', isEqualTo: _employeeUid)
          .where('status', isEqualTo: 'approved')
          .get();

      for (var leaveDoc in leaveSnapshot.docs) {
        final leaveData = leaveDoc.data();
        final DateTime leaveStartDate = (leaveData['startDate'] as Timestamp).toDate();
        final DateTime leaveEndDate = (leaveData['endDate'] as Timestamp).toDate();

        // Count days where leave overlaps with the report period
        DateTime currentDay = startDate;
        while (currentDay.isBefore(endDate.add(const Duration(days: 1)))) {
          if (currentDay.isAfter(leaveStartDate.subtract(const Duration(days: 1))) &&
              currentDay.isBefore(leaveEndDate.add(const Duration(days: 1)))) {
            summary['totalLeaveDays']++;
          }
          currentDay = currentDay.add(const Duration(days: 1));
        }
      }

      // Determine overall status based on aggregated data
      if (summary['totalDaysPresent'] > 0) {
        summary['status'] = 'Present';
      }
      if (summary['totalLeaveDays'] > 0 && summary['totalDaysPresent'] == 0) {
        summary['status'] = 'On Leave';
      }
      if (summary['totalLateDays'] > 0 && summary['totalDaysPresent'] > 0) {
        summary['status'] = 'Mixed (Late)';
      }
    } catch (e) {
      debugPrint("[DEBUG] Error fetching attendance summary for employee: $e");
    }

    // Convert aggregated data to list for UI
    final int totalMinutes = summary['totalHours'] as int;
    final String formattedHours = '${totalMinutes ~/ 60}h ${totalMinutes.remainder(60)}m';
    _attendanceSummaryData = [
      {
        'title': 'Total Hours Worked', 'value': formattedHours,
      },
      {
        'title': 'Days Present', 'value': summary['totalDaysPresent'],
      },
      {
        'title': 'Late Days', 'value': summary['totalLateDays'],
      },
      {
        'title': 'Leave Days', 'value': summary['totalLeaveDays'],
      },
      {
        'title': 'Overall Status', 'value': summary['status'],
      },
    ];

    if (mounted) {
      setState(() {}); // Update UI
    }
  }

  /// Fetches data for the Daily Attendance Logs Report for the current employee.
  Future<void> _fetchDailyAttendanceLogs(DateTime startDate, DateTime endDate) async {
    final List<Map<String, dynamic>> logs = [];

    try {
      DateTime currentDay = startDate;
      while (currentDay.isBefore(endDate.add(const Duration(days: 1)))) {
        final String dateStr = DateFormat('yyyy-MM-dd').format(currentDay);
        final attendanceDoc = await FirebaseFirestore.instance
            .collection('Attendance')
            .doc(_employeeUid)
            .collection('Records')
            .doc(dateStr)
            .get();

        if (attendanceDoc.exists) {
          final data = attendanceDoc.data();
          List<Map<String, dynamic>> dailyPunches = [];

          if (data?['Clock InOut.in'] != null) {
            dailyPunches.add({
              'type': 'Clock In',
              'time': (data!['Clock InOut.in'] as Timestamp).toDate(),
              // 'location': data['Clock InOut.in_location'] ?? 'N/A', // Removed location
            });
          }
          if (data?['Clock InOut.out'] != null) {
            dailyPunches.add({
              'type': 'Clock Out',
              'time': (data!['Clock InOut.out'] as Timestamp).toDate(),
              // 'location': data['Clock InOut.out_location'] ?? 'N/A', // Removed location
            });
          }
          if (data?['Break.in'] != null) {
            dailyPunches.add({
              'type': 'Break Start',
              'time': (data!['Break.in'] as Timestamp).toDate(),
              // 'location': data['Break.in_location'] ?? 'N/A', // Removed location
            });
          }
          if (data?['Break.out'] != null) {
            dailyPunches.add({
              'type': 'Break End',
              'time': (data!['Break.out'] as Timestamp).toDate(),
              // 'location': data['Break.out_location'] ?? 'N/A', // Removed location
            });
          }

          dailyPunches.sort((a, b) => (a['time'] as DateTime).compareTo(b['time'] as DateTime));

          if (dailyPunches.isNotEmpty) {
            if (_selectedFilterType == ReportFilterType.daily) {
              for (var punch in dailyPunches) {
                logs.add({
                  'date': DateFormat('MMM dd, yyyy').format(currentDay),
                  'type': punch['type'],
                  'time': DateFormat('hh:mm a').format(punch['time']),
                  // 'location': punch['location'], // Removed location
                });
              }
            } else {
              // For month/year, show a summary per day
              final firstPunch = dailyPunches.first;
              final lastPunch = dailyPunches.last;
              logs.add({
                'date': DateFormat('MMM dd, yyyy').format(currentDay),
                'summary': '${firstPunch['type']} at ${DateFormat('hh:mm a').format(firstPunch['time'])} - ${lastPunch['type']} at ${DateFormat('hh:mm a').format(lastPunch['time'])}',
                'details': dailyPunches.map((p) => '${p['type']} at ${DateFormat('hh:mm a').format(p['time'])}').join('; '), // Removed location from details
              });
            }
          }
        }
        currentDay = currentDay.add(const Duration(days: 1));
      }
    } catch (e) {
      debugPrint("[DEBUG] Error fetching daily attendance logs for employee: $e");
    }
    if (mounted) {
      setState(() {
        _dailyAttendanceLogsData = logs;
      });
    }
  }

  /// Fetches data for the Working Hours Report for the current employee.
  Future<void> _fetchWorkingHoursReport(DateTime startDate, DateTime endDate) async {
    final Map<String, dynamic> workingHours = {
      'totalWorkedMinutes': 0,
      'totalOvertimeMinutes': 0,
    };

    try {
      DateTime currentDay = startDate;
      while (currentDay.isBefore(endDate.add(const Duration(days: 1)))) {
        final String dateStr = DateFormat('yyyy-MM-dd').format(currentDay);
        final attendanceDoc = await FirebaseFirestore.instance
            .collection('Attendance')
            .doc(_employeeUid)
            .collection('Records')
            .doc(dateStr)
            .get();

        if (attendanceDoc.exists) {
          final data = attendanceDoc.data();
          final Timestamp? clockInTs = data?['Clock InOut.in'] as Timestamp?;
          final Timestamp? clockOutTs = data?['Clock InOut.out'] as Timestamp?;

          if (clockInTs != null && clockOutTs != null) {
            Duration totalDuration = clockOutTs.toDate().difference(clockInTs.toDate());

            final Timestamp? breakInTs = data?['Break.in'] as Timestamp?;
            final Timestamp? breakOutTs = data?['Break.out'] as Timestamp?;

            if (breakInTs != null && breakOutTs != null) {
              Duration breakDuration = breakOutTs.toDate().difference(breakInTs.toDate());
              totalDuration = totalDuration - breakDuration;
            }

            workingHours['totalWorkedMinutes'] += totalDuration.inMinutes;

            const int standardWorkingHoursMinutes = 8 * 60;
            if (totalDuration.inMinutes > standardWorkingHoursMinutes) {
              final Duration overtimeDuration = totalDuration - Duration(minutes: standardWorkingHoursMinutes);
              workingHours['totalOvertimeMinutes'] += overtimeDuration.inMinutes;
            }
          }
        }
        currentDay = currentDay.add(const Duration(days: 1));
      }
    } catch (e) {
      debugPrint("[DEBUG] Error fetching working hours report for employee: $e");
    }
    _workingHoursData = [
      {
        'workedHours': '${workingHours['totalWorkedMinutes'] ~/ 60}h ${workingHours['totalWorkedMinutes'].remainder(60)}m',
        'overtime': '${workingHours['totalOvertimeMinutes'] ~/ 60}h ${workingHours['totalOvertimeMinutes'].remainder(60)}m',
      },
    ];
    if (mounted) {
      setState(() {}); // Update UI
    }
  }

  String get displayedDateRange {
    if (_selectedDate == null) {
      return 'N/A';
    }
    final DateFormat formatter;
    if (_selectedFilterType == ReportFilterType.daily) {
      formatter = DateFormat('d MMM y');
    } else if (_selectedFilterType == ReportFilterType.month) {
      formatter = DateFormat('MMM y');
    } else { // ReportFilterType.year
      formatter = DateFormat('y');
    }
    return formatter.format(_selectedDate!);
  }

  Future<void> _showDatePickerBasedOnFilter(BuildContext context) async {
    DateTime? pickedDate;
    if (_selectedFilterType == ReportFilterType.daily) {
      pickedDate = await showDatePicker(
        context: context,
        initialDate: _selectedDate ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
      );
    } else if (_selectedFilterType == ReportFilterType.month) {
      pickedDate = await showDialog<DateTime>(
        context: context,
        builder: (BuildContext context) {
          int selectedYear = (_selectedDate ?? DateTime.now()).year;
          int selectedMonth = (_selectedDate ?? DateTime.now()).month;

          return AlertDialog(
            title: const Text('Select Month'),
            content: SizedBox(
              width: 300,
              height: 300,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios),
                        onPressed: () {
                          setState(() { selectedYear--; });
                          (context as Element).markNeedsBuild();
                        },
                      ),
                      Text(
                        selectedYear.toString(),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_forward_ios),
                        onPressed: () {
                          setState(() { selectedYear++; });
                          (context as Element).markNeedsBuild();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 1.5,
                      ),
                      itemCount: 12,
                      itemBuilder: (context, index) {
                        final month = index + 1;
                        final monthName = DateFormat('MMM').format(DateTime(selectedYear, month));
                        return TextButton(
                          onPressed: () {
                            Navigator.pop(context, DateTime(selectedYear, month, 1));
                          },
                          style: TextButton.styleFrom(
                            backgroundColor: selectedMonth == month && (_selectedDate?.year ?? -1) == selectedYear
                                ? Colors.black
                                : Colors.transparent,
                            foregroundColor: selectedMonth == month && (_selectedDate?.year ?? -1) == selectedYear
                                ? Colors.white
                                : Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text(monthName),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ],
          );
        },
      );
    } else { // ReportFilterType.year
      pickedDate = await showDialog<DateTime>(
        context: context,
        builder: (BuildContext context) {
          int currentDisplayYear = (_selectedDate ?? DateTime.now()).year;
          final int startYear = currentDisplayYear - 5;
          final int endYear = currentDisplayYear + 5;

          return AlertDialog(
            title: const Text('Select Year'),
            content: SizedBox(
              width: 300,
              height: 300,
              child: ListView.builder(
                itemCount: endYear - startYear + 1,
                itemBuilder: (context, index) {
                  final year = startYear + index;
                  return ListTile(
                    title: Text(
                      year.toString(),
                      style: TextStyle(
                        fontWeight: (_selectedDate?.year ?? -1) == year ? FontWeight.bold : FontWeight.normal,
                        color: (_selectedDate?.year ?? -1) == year ? Colors.black : Colors.grey[700],
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context, DateTime(year, 1, 1));
                    },
                  );
                },
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ],
          );
        },
      );
    }

    if (pickedDate != null && pickedDate != _selectedDate) {
      setState(() {
        _selectedDate = pickedDate!;
      });
      _fetchReportData();
    }
  }

  // Max rows per page for PDF tables to prevent 'more than 20 pages' error
  static const int _maxRowsPerPage = 25; // Adjusted to a common reasonable size

  /// Handles permissions and then offers to save or share the generated file.
  Future<void> _showSaveOrShareOptions({
    required Uint8List fileBytes,
    required String fileName,
    required MimeType mimeType,
  }) async {
    // Request storage permission
    bool granted = await _requestStoragePermission();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Storage permission denied. Cannot save file directly.')),
        );
      }
      // If permission is denied, still offer to share
      try {
        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(fileBytes);
        await Share.shareXFiles([XFile(filePath)], text: 'Here is your attendance report.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('File shared successfully (temporary).')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to share file: $e')),
          );
        }
        debugPrint('[DEBUG] Error sharing file (without direct save): $e');
      }
      return;
    }

    // If permission is granted, proceed with direct save or share options
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Save or Share "$fileName"',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.save, color: Colors.blue),
                title: const Text('Save to Device'),
                onTap: () async {
                  Navigator.pop(context); // Close bottom sheet
                  try {
                    await FileSaver.instance.saveFile(
                      name: fileName,
                      bytes: fileBytes,
                      ext: fileName.split('.').last, // e.g., 'pdf' or 'xlsx'
                      mimeType: mimeType,
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('"$fileName" saved successfully!')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to save file: $e')),
                      );
                    }
                    debugPrint('[DEBUG] Error saving file directly: $e');
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.orange),
                title: const Text('Share File'),
                onTap: () async {
                  Navigator.pop(context); // Close bottom sheet
                  try {
                    final tempDir = await getTemporaryDirectory();
                    final filePath = '${tempDir.path}/$fileName';
                    final file = File(filePath);
                    await file.writeAsBytes(fileBytes);
                    await Share.shareXFiles([XFile(filePath)], text: 'Here is your attendance report.');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('File shared successfully.')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to share file: $e')),
                      );
                    }
                    debugPrint('[DEBUG] Error sharing file: $e');
                  }
                },
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Requests necessary storage permissions for saving files.
  Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      final AndroidDeviceInfo androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) { // Android 13 (API level 33) and above
        final statusMediaImages = await Permission.photos.request();
        final statusMediaVideos = await Permission.videos.request();
        final statusMediaAudio = await Permission.audio.request();
        return statusMediaImages.isGranted || statusMediaVideos.isGranted || statusMediaAudio.isGranted || await Permission.manageExternalStorage.isGranted;
      } else { // Android 12 (API level 31) and below
        final status = await Permission.storage.request();
        return status.isGranted;
      }
    } else if (Platform.isIOS) {
      final status = await Permission.photosAddOnly.request(); // For saving to photos
      return status.isGranted;
    }
    return true; // For other platforms (Web, Desktop) or if no specific permission needed
  }

  /// Generates a PDF report and shares it using the system share sheet.
  Future<void> _generatePdfReport({
    required String reportTitle,
    required List<String> headers,
    required List<List<String>> data,
    required String fileNamePrefix,
  }) async {
    if (data.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No data available to generate PDF for "$reportTitle".')),
      );
      return;
    }

    final pdf = pw.Document();
    String reportPeriod;
    if (_selectedFilterType == ReportFilterType.daily) {
      reportPeriod = _formatDay(_selectedDate!);
    } else if (_selectedFilterType == ReportFilterType.month) {
      reportPeriod = _formatMonth(_selectedDate!);
    } else {
      reportPeriod = _formatYear(_selectedDate!);
    }
    final String fileName = '${fileNamePrefix}_${reportPeriod.replaceAll(' ', '_')}.pdf';

    // Split data into pages if it exceeds _maxRowsPerPage
    List<List<List<String>>> pagesData = [];
    for (int i = 0; i < data.length; i += _maxRowsPerPage) {
      pagesData.add(data.sublist(i, i + _maxRowsPerPage > data.length ? data.length : i + _maxRowsPerPage));
    }

    for (int i = 0; i < pagesData.length; i++) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return [
              pw.Text('$reportTitle - $reportPeriod (Page ${i + 1} of ${pagesData.length})', style: pw.TextStyle(font: pw.Font.helveticaBold(), fontSize: 16)),
              pw.SizedBox(height: 10),
              pw.Table.fromTextArray(
                headers: headers,
                data: pagesData[i],
                border: pw.TableBorder.all(color: PdfColors.grey),
                headerStyle: pw.TextStyle(font: pw.Font.helveticaBold(), fontWeight: pw.FontWeight.bold),
                cellAlignment: pw.Alignment.centerLeft,
                cellPadding: const pw.EdgeInsets.all(6),
                cellStyle: pw.TextStyle(font: pw.Font.helvetica(), fontSize: 10),
              ),
            ];
          },
        ),
      );
    }

    try {
      final Uint8List bytes = await pdf.save();
      _showSaveOrShareOptions(
        fileBytes: bytes,
        fileName: fileName,
        mimeType: MimeType.pdf,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate or share PDF: $e')),
      );
      debugPrint('[DEBUG] Error generating or saving PDF: $e');
    }
  }

  /// Generates an Excel (XLSX) report and shares it using the system share sheet.
  Future<void> _generateExcelReport({
    required String sheetName,
    required List<String> headers,
    required List<List<String>> data,
    required String fileNamePrefix,
  }) async {
    if (data.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No data available to generate Excel for "$sheetName".')),
      );
      return;
    }

    final excel = Excel.createExcel();
    String reportPeriod;
    if (_selectedFilterType == ReportFilterType.daily) {
      reportPeriod = _formatDay(_selectedDate!);
    } else if (_selectedFilterType == ReportFilterType.month) {
      reportPeriod = _formatMonth(_selectedDate!);
    } else {
      reportPeriod = _formatYear(_selectedDate!);
    }
    final String fileName = '${fileNamePrefix}_${reportPeriod.replaceAll(' ', '_')}.xlsx';
    Sheet sheetObject = excel[sheetName];

    // Add headers
    sheetObject.appendRow(headers.map((h) => TextCellValue(h)).toList());

    // Add data rows
    for (var row in data) {
      sheetObject.appendRow(row.map((cell) => TextCellValue(cell)).toList());
    }

    try {
      final Uint8List bytes = Uint8List.fromList(excel.encode()!);
      _showSaveOrShareOptions(
        fileBytes: bytes,
        fileName: fileName,
        mimeType: MimeType.microsoftExcel,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate or share Excel: $e')),
      );
      debugPrint('[DEBUG] Error generating or saving Excel: $e');
    }
  }

  /// Helper to get current report data and headers based on the active tab index.
  Map<String, dynamic> _getCurrentReportDataForExport() {
    String reportTitle = '';
    List<String> headers = [];
    List<List<String>> data = [];
    String fileNamePrefix = '';

    switch (_tabController.index) {
      case 0: // Summary
        reportTitle = 'Attendance Summary Report';
        headers = ['Category', 'Value'];
        data = _attendanceSummaryData.map((d) => [d['title'] as String, d['value'].toString()]).toList();
        fileNamePrefix = 'attendance_summary';
        break;
      case 1: // Daily Logs
        reportTitle = 'Daily Attendance Logs Report';
        // Headers and data adjusted to exclude 'Location'
        if (_selectedFilterType == ReportFilterType.daily) {
          headers = ['Date', 'Type', 'Time'];
          data = _dailyAttendanceLogsData.map((d) => [
            d['date'] as String,
            d['type'] as String,
            d['time'] as String,
          ]).toList();
        } else {
          headers = ['Date', 'Summary', 'Details'];
          data = _dailyAttendanceLogsData.map((d) => [
            d['date'] as String,
            d['summary'] as String,
            d['details'] as String,
          ]).toList();
        }
        fileNamePrefix = 'daily_attendance_logs';
        break;
      case 2: // Working Hours
        reportTitle = 'Working Hours Report';
        headers = ['Category', 'Value'];
        data = _workingHoursData.map((d) => [
          'Worked Hours', d['workedHours'] as String,
        ]).toList();
        if (_workingHoursData.isNotEmpty) {
          data.add(['Overtime', _workingHoursData[0]['overtime'] as String]);
        }
        fileNamePrefix = 'working_hours_report';
        break;
    }
    return {
      'reportTitle': reportTitle,
      'headers': headers,
      'data': data,
      'fileNamePrefix': fileNamePrefix,
    };
  }

  /// Displays a modal bottom sheet with export options (PDF/Excel).
  void _showExportOptions() {
    if (_isLoadingData) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reports are still loading. Please wait.')),
      );
      return;
    }

    final currentReport = _getCurrentReportDataForExport();
    final List<String> headers = currentReport['headers'];
    final List<List<String>> data = currentReport['data'];
    final String reportTitle = currentReport['reportTitle'];
    final String fileNamePrefix = currentReport['fileName']['fileNamePrefix'];

    if (data.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No data available for "$reportTitle". Cannot export.')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Export "$reportTitle"',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                title: const Text('Export as PDF'),
                onTap: () {
                  Navigator.pop(context); // Close bottom sheet
                  _generatePdfReport(
                    reportTitle: reportTitle,
                    headers: headers,
                    data: data,
                    fileNamePrefix: fileNamePrefix,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.table_chart, color: Colors.green),
                title: const Text('Export as Excel (XLSX)'),
                onTap: () {
                  Navigator.pop(context); // Close bottom sheet
                  _generateExcelReport(
                    sheetName: reportTitle.replaceAll(' Report', ''), // Use title as sheet name, remove " Report"
                    headers: headers,
                    data: data,
                    fileNamePrefix: fileNamePrefix,
                  );
                },
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- Report Widgets ---

  Widget _buildAttendanceSummaryReport() {
    if (_isLoadingData) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Expanded(
          child: _attendanceSummaryData.isEmpty
              ? const Center(child: Text('No attendance summary data for this period.'))
              : ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            itemCount: _attendanceSummaryData.length,
            itemBuilder: (context, index) {
              final data = _attendanceSummaryData[index];
              return Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${data['title']}:',
                        style: const TextStyle(fontSize: 15, color: Colors.black87),
                      ),
                      Text(
                        data['value'].toString(),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: data['title'] == 'Overall Status'
                              ? (data['value'] == 'Present' ? Colors.green
                              : (data['value'] == 'On Leave' ? Colors.orange : Colors.red))
                              : Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDailyAttendanceLogsReport() {
    if (_isLoadingData) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Expanded(
          child: _dailyAttendanceLogsData.isEmpty
              ? const Center(child: Text('No daily attendance logs for this period.'))
              : ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            itemCount: _dailyAttendanceLogsData.length,
            itemBuilder: (context, index) {
              final data = _dailyAttendanceLogsData[index];
              return Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Date: ${data['date']}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      if (_selectedFilterType == ReportFilterType.daily) ...[
                        Text(
                          'Type: ${data['type']}',
                          style: TextStyle(color: Colors.blueGrey[700], fontSize: 14),
                        ),
                        Text(
                          'Time: ${data['time']}',
                          style: const TextStyle(color: Colors.black87, fontSize: 14),
                        ),
                        // Removed location display
                        // Text(
                        //   'Location: ${data['location']}',
                        //   style: const TextStyle(color: Colors.grey, fontSize: 13),
                        // ),
                      ] else ...[
                        Text(
                          'Summary: ${data['summary']}',
                          style: const TextStyle(color: Colors.black87, fontSize: 14),
                        ),
                        Text(
                          'Details: ${data['details']}',
                          style: const TextStyle(color: Colors.grey, fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ]
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWorkingHoursReport() {
    if (_isLoadingData) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Expanded(
          child: _workingHoursData.isEmpty
              ? const Center(child: Text('No working hours data for this period.'))
              : ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            itemCount: _workingHoursData.length,
            itemBuilder: (context, index) {
              final data = _workingHoursData[index];
              return Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Worked Hours: ${data['workedHours']}',
                        style: const TextStyle(color: Colors.black87, fontSize: 14),
                      ),
                      Text(
                        'Overtime: ${data['overtime']}',
                        style: const TextStyle(color: Colors.black87, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabNames.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text('History & Reports for $_employeeName'),
          backgroundColor: const Color.fromARGB(255, 143, 83, 167),
          foregroundColor: Colors.white,
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.grey[400],
            indicatorColor: Colors.white,
            tabs: _tabNames.map((name) => Tab(text: name)).toList(),
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Filter Type Selection (Daily, Month, Year)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SegmentedButton<ReportFilterType>(
                      segments: const <ButtonSegment<ReportFilterType>>[
                        ButtonSegment<ReportFilterType>(
                          value: ReportFilterType.daily,
                          label: Text('Daily'),
                          icon: Icon(Icons.calendar_view_day),
                        ),
                        ButtonSegment<ReportFilterType>(
                          value: ReportFilterType.month,
                          label: Text('Month'),
                          icon: Icon(Icons.calendar_view_month),
                        ),
                        ButtonSegment<ReportFilterType>(
                          value: ReportFilterType.year,
                          label: Text('Year'),
                          icon: Icon(Icons.calendar_today),
                        ),
                      ],
                      selected: <ReportFilterType>{_selectedFilterType},
                      onSelectionChanged: (Set<ReportFilterType> newSelection) {
                        setState(() {
                          _selectedFilterType = newSelection.first;
                          // When filter type changes, reset _selectedDate to current day/month/year
                          if (_selectedFilterType == ReportFilterType.daily) {
                            _selectedDate = DateTime.now();
                          } else if (_selectedFilterType == ReportFilterType.month) {
                            _selectedDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
                          } else { // ReportFilterType.year
                            _selectedDate = DateTime(DateTime.now().year, 1, 1);
                          }
                        });
                        _fetchReportData(); // Re-fetch data with new filter type and date
                      },
                      style: SegmentedButton.styleFrom(
                        backgroundColor: Colors.white,
                        selectedBackgroundColor: Colors.purple,
                        selectedForegroundColor: Colors.white,
                        foregroundColor: Colors.purple,
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Date Display and Picker
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Period: $displayedDateRange',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.calendar_today),
                        onPressed: () => _showDatePickerBasedOnFilter(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildAttendanceSummaryReport(),
                  _buildDailyAttendanceLogsReport(),
                  _buildWorkingHoursReport(),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showExportOptions,
          label: const Text('Export Report'),
          icon: const Icon(Icons.download),
          backgroundColor: Colors.purple,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}