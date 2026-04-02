import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart'; // For PDF generation
import 'package:pdf/widgets.dart' as pw; // For PDF widgets
import 'package:excel/excel.dart'; // For Excel generation
import 'package:path_provider/path_provider.dart'; // For getTemporaryDirectory
import 'package:path/path.dart' as path; // For path.join
import 'package:share_plus/share_plus.dart'; // For sharing files
import 'dart:io'; // For File operations
import 'dart:typed_data'; // Needed for Uint8List

// New imports for direct saving and permissions (from employee page)
import 'package:permission_handler/permission_handler.dart';
import 'package:file_saver/file_saver.dart';
import 'package:device_info_plus/device_info_plus.dart'; // Added for Android version check


// Enum to define the report filtering type
enum ReportFilterType { daily, month, year }

class HistoryPageAdmin extends StatefulWidget {
  final String companyId;

  const HistoryPageAdmin({super.key, required this.companyId});

  @override
  State<HistoryPageAdmin> createState() => _HistoryPageAdminState();
}

class _HistoryPageAdminState extends State<HistoryPageAdmin> with SingleTickerProviderStateMixin {
  DateTime _selectedDate = DateTime.now();
  ReportFilterType _selectedFilterType = ReportFilterType.daily; // Default to daily
  Map<String, String> _employeeNames = {}; // Map employee UIDs to their names
  bool _isLoadingNames = true;
  late TabController _tabController;

  // State variables to hold fetched data for each report type
  List<Map<String, dynamic>> _attendanceSummaryData = [];
  List<Map<String, dynamic>> _dailyAttendanceLogsData = [];
  List<Map<String, dynamic>> _lateEarlyData = [];
  List<Map<String, dynamic>> _workingHoursData = [];
  List<Map<String, dynamic>> _locationData = [];

  bool _isLoadingReports = false; // New flag for report data loading

  // Employee selection variables
  Set<String> _selectedEmployeeIds = {}; // UIDs of selected employees
  bool _selectAllEmployees = true; // Initially select all employees

  // Tab names for display, excluding 'Leave'
  final List<String> _tabNames = const [
    'Summary',
    'Daily Logs',
    'Late/Early',
    'Working Hours',
    'Location',
  ];

  // Max rows per page for PDF tables to prevent 'more than 20 pages' error
  static const int _maxRowsPerPage = 25; // Adjusted to a common reasonable size

  @override
  void initState() {
    super.initState();
    // Adjust tab controller length based on the updated _tabNames list
    _tabController = TabController(length: _tabNames.length, vsync: this);
    _fetchEmployeeNames().then((_) {
      // Initialize _selectedEmployeeIds with all employee UIDs after names are loaded
      _selectedEmployeeIds = _employeeNames.keys.toSet();
      // Fetch report data only after employee names are loaded
      _fetchReportData();
    });

    // Add listener to refetch data when tab changes (if needed, or just rely on date change)
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        // Only refetch if the tab actually changed (not just animation)
        _fetchReportData();
      }
    });
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

  String get _displayedDateRange {
    final DateFormat formatter;
    if (_selectedFilterType == ReportFilterType.daily) {
      formatter = DateFormat('d MMM y');
    } else if (_selectedFilterType == ReportFilterType.month) {
      formatter = DateFormat('MMM y');
    } else { // ReportFilterType.year
      formatter = DateFormat('y');
    }
    return formatter.format(_selectedDate);
  }

  /// Fetches all employee names for the company and stores them in a map.
  /// This map is crucial for displaying employee names instead of UIDs in reports.
  Future<void> _fetchEmployeeNames() async {
    if (!mounted) return;
    setState(() {
      _isLoadingNames = true;
    });
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('Employee')
          .where('companyId', isEqualTo: widget.companyId)
          .get();
      final Map<String, String> names = {};
      for (var doc in querySnapshot.docs) {
        // Ensure that doc.data() is cast to the correct type to avoid 'Object' errors
        final Map<String, dynamic>? data = doc.data();
        if (data != null) {
          names[doc.id] = data['name'] ?? data['fullName'] ?? 'Unknown Employee';
        }
      }
      if (mounted) {
        setState(() {
          _employeeNames = names;
          if (_selectAllEmployees) {
            _selectedEmployeeIds = names.keys.toSet(); // Select all by default
          }
          _isLoadingNames = false;
        });
        debugPrint('Fetched employee names: $_employeeNames');
        debugPrint('Selected employee IDs: $_selectedEmployeeIds');
      }
    } catch (e) {
      debugPrint("Error fetching employee names for history: $e");
      if (mounted) {
        setState(() {
          _isLoadingNames = false;
        });
      }
    }
  }

  /// Orchestrates fetching all report data for the selected date range and selected employees.
  Future<void> _fetchReportData() async {
    if (!mounted) return; // Add mounted check at the start
    if (_isLoadingNames) return; // Don't fetch reports if names are still loading

    setState(() {
      _isLoadingReports = true;
    });

    // Determine the date range based on the selected filter type
    DateTime startDate;
    DateTime endDate;

    if (_selectedFilterType == ReportFilterType.daily) {
      startDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      endDate = startDate.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
    } else if (_selectedFilterType == ReportFilterType.month) {
      startDate = DateTime(_selectedDate.year, _selectedDate.month, 1);
      endDate = DateTime(_selectedDate.year, _selectedDate.month + 1, 0).add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
    } else { // ReportFilterType.year
      startDate = DateTime(_selectedDate.year, 1, 1);
      endDate = DateTime(_selectedDate.year + 1, 1, 1).subtract(const Duration(milliseconds: 1));
    }

    debugPrint('Fetching reports for period: $startDate to $endDate');

    try {
      await Future.wait([
        _fetchAttendanceSummary(startDate, endDate),
        _fetchDailyAttendanceLogs(startDate, endDate),
        _fetchLateEarlyReport(startDate, endDate),
        _fetchWorkingHoursReport(startDate, endDate),
        _fetchLocationReport(startDate, endDate),
      ]);
    } catch (e) {
      debugPrint("Error fetching report data: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load reports: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingReports = false;
        });
      }
    }
  }

  /// Fetches data for the Attendance Summary Report and combines with other report details for a comprehensive summary.
  Future<void> _fetchAttendanceSummary(DateTime startDate, DateTime endDate) async {
    final Map<String, Map<String, dynamic>> summaryMap = {}; // Use map for aggregation

    try {
      // Filter employees based on selection
      final List<String> employeeUidsToFetch = _selectedEmployeeIds.toList();
      debugPrint('Fetching attendance summary for employees: $employeeUidsToFetch');


      if (employeeUidsToFetch.isEmpty) {
        debugPrint('No employees selected for attendance summary. Clearing data.');
        if (mounted) {
          setState(() {
            _attendanceSummaryData = [];
          });
        }
        return;
      }

      for (var employeeUid in employeeUidsToFetch) {
        final String employeeName = _employeeNames[employeeUid] ?? 'Unknown Employee';

        // Initialize summary for each employee
        summaryMap[employeeUid] = {
          'employeeName': employeeName,
          'totalHoursMinutes': 0, // Store in minutes for accurate sum
          'totalDaysPresent': 0,
          'totalLateDays': 0,
          'totalEarlyOutDays': 0, // New: Track early outs
          'totalLeaveDays': 0,
          'totalOvertimeMinutes': 0,
          'firstPunchInTime': null,
          'lastPunchOutTime': null,
          'uniqueLocations': <String>{}, // Use a set to store unique locations
        };

        DateTime currentDay = startDate;
        while (currentDay.isBefore(endDate.add(const Duration(days: 1)))) {
          final String dateStr = DateFormat('yyyy-MM-dd').format(currentDay);
          final attendanceDoc = await FirebaseFirestore.instance
              .collection('Attendance')
              .doc(employeeUid)
              .collection('Records')
              .doc(dateStr)
              .get();

          if (attendanceDoc.exists) {
            debugPrint('Attendance record found for $employeeName on $dateStr');
            final data = attendanceDoc.data() as Map<String, dynamic>?; // Explicitly cast
            List<Map<String, dynamic>> dailyPunches = [];

            if (data != null) { // Ensure data is not null before accessing
              final Timestamp? clockInTs = data['Clock InOut.in'] as Timestamp?;
              final Timestamp? clockOutTs = data['Clock InOut.out'] as Timestamp?;

              if (clockInTs != null) {
                dailyPunches.add({'type': 'Clock In', 'time': clockInTs.toDate(), 'location': data['Clock InOut.in_location'] ?? 'N/A'});
                if (summaryMap[employeeUid]!['firstPunchInTime'] == null || clockInTs.toDate().isBefore(summaryMap[employeeUid]!['firstPunchInTime'])) {
                  summaryMap[employeeUid]!['firstPunchInTime'] = clockInTs.toDate();
                }
              }
              if (clockOutTs != null) {
                dailyPunches.add({'type': 'Clock Out', 'time': clockOutTs.toDate(), 'location': data['Clock InOut.out_location'] ?? 'N/A'});
                if (summaryMap[employeeUid]!['lastPunchOutTime'] == null || clockOutTs.toDate().isAfter(summaryMap[employeeUid]!['lastPunchOutTime'])) {
                  summaryMap[employeeUid]!['lastPunchOutTime'] = clockOutTs.toDate();
                }
              }
              if (data['Break.in'] != null) {
                dailyPunches.add({'type': 'Break Start', 'time': (data['Break.in'] as Timestamp).toDate(), 'location': data['Break.in_location'] ?? 'N/A'});
              }
              if (data['Break.out'] != null) {
                dailyPunches.add({'type': 'Break End', 'time': (data['Break.out'] as Timestamp).toDate(), 'location': data['Break.out_location'] ?? 'N/A'});
              }

              dailyPunches.sort((a, b) => (a['time'] as DateTime).compareTo(b['time'] as DateTime));

              // Only add unique locations to the summary map
              for (var punch in dailyPunches) {
                if (punch['location'] != 'N/A') {
                  summaryMap[employeeUid]!['uniqueLocations'].add(punch['location']);
                }
              }

              if (clockInTs != null) {
                summaryMap[employeeUid]!['totalDaysPresent']++;
                if (clockOutTs != null) {
                  Duration workedDuration = clockOutTs.toDate().difference(clockInTs.toDate());
                  final Timestamp? breakInTs = data['Break.in'] as Timestamp?;
                  final Timestamp? breakOutTs = data['Break.out'] as Timestamp?;
                  if (breakInTs != null && breakOutTs != null) {
                    Duration breakDuration = breakOutTs.toDate().difference(breakInTs.toDate());
                    workedDuration = workedDuration - breakDuration;
                  }
                  summaryMap[employeeUid]!['totalHoursMinutes'] += workedDuration.inMinutes;

                  const int standardWorkingHoursMinutes = 8 * 60;
                  if (workedDuration.inMinutes > standardWorkingHoursMinutes) {
                    final Duration overtimeDuration = workedDuration - Duration(minutes: standardWorkingHoursMinutes);
                    summaryMap[employeeUid]!['totalOvertimeMinutes'] += overtimeDuration.inMinutes;
                  }
                }
              }
            }
          } else {
            debugPrint('No attendance record for $employeeName on $dateStr');
          }

          // Check for lateness/early out for the current day
          final punchLogsSnapshot = await FirebaseFirestore.instance
              .collection('PunchLogs')
              .doc(widget.companyId)
              .collection('Records')
              .where('employeeId', isEqualTo: employeeUid)
              .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime(currentDay.year, currentDay.month, currentDay.day)))
              .where('timestamp', isLessThan: Timestamp.fromDate(DateTime(currentDay.year, currentDay.month, currentDay.day).add(const Duration(days: 1))))
              .get();

          for (var log in punchLogsSnapshot.docs) {
            final logData = log.data() as Map<String, dynamic>; // Explicitly cast
            final String latenessMessage = logData['excessively late'] ?? logData['latenessMessage'] ?? '';

            if (latenessMessage.isNotEmpty) {
              summaryMap[employeeUid]!['totalLateDays']++;
            }
          }
          currentDay = currentDay.add(const Duration(days: 1));
        }

        // Fetch leave data for the period
        final leaveSnapshot = await FirebaseFirestore.instance
            .collection('Leaves')
            .where('uid', isEqualTo: employeeUid)
            .where('status', isEqualTo: 'approved')
            .get();

        for (var leaveDoc in leaveSnapshot.docs) {
          final leaveData = leaveDoc.data() as Map<String, dynamic>; // Explicitly cast
          final DateTime leaveStartDate = (leaveData['startDate'] as Timestamp).toDate();
          final DateTime leaveEndDate = (leaveData['endDate'] as Timestamp).toDate();

          DateTime dayIterator = startDate;
          while (dayIterator.isBefore(endDate.add(const Duration(days: 1)))) {
            if (dayIterator.isAfter(leaveStartDate.subtract(const Duration(days: 1))) &&
                dayIterator.isBefore(leaveEndDate.add(const Duration(days: 1)))) {
              summaryMap[employeeUid]!['totalLeaveDays']++;
            }
            dayIterator = dayIterator.add(const Duration(days: 1));
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching attendance summary: $e");
    }

    final List<Map<String, dynamic>> finalSummary = [];
    summaryMap.forEach((uid, data) {
      final int totalMinutes = data['totalHoursMinutes'] as int;
      final String formattedHours = '${totalMinutes ~/ 60}h ${totalMinutes.remainder(60)}m';
      final int totalOvertimeMinutes = data['totalOvertimeMinutes'] as int;
      final String formattedOvertime = '${totalOvertimeMinutes ~/ 60}h ${totalOvertimeMinutes.remainder(60)}m';

      String status = 'Absent';
      if (data['totalDaysPresent'] > 0) {
        status = 'Present';
      }
      if (data['totalLeaveDays'] > 0 && data['totalDaysPresent'] == 0) {
        status = 'On Leave';
      }
      if (data['totalLateDays'] > 0 && data['totalDaysPresent'] > 0) {
        status = 'Mixed (Late)';
      }

      finalSummary.add({
        'employeeName': data['employeeName'],
        'totalHours': formattedHours,
        'status': status,
        'totalDaysPresent': data['totalDaysPresent'],
        'totalLateDays': data['totalLateDays'],
        'totalLeaveDays': data['totalLeaveDays'],
        'totalOvertime': formattedOvertime,
        'firstPunchInTime': data['firstPunchInTime'] != null ? DateFormat('MMM dd, yyyy hh:mm a').format(data['firstPunchInTime']) : 'N/A',
        'lastPunchOutTime': data['lastPunchOutTime'] != null ? DateFormat('MMM dd, yyyy hh:mm a').format(data['lastPunchOutTime']) : 'N/A',
        'uniqueLocations': data['uniqueLocations'].isEmpty ? 'N/A' : (data['uniqueLocations'] as Set).join(', '),
      });
    });

    debugPrint('Final attendance summary data: $finalSummary');

    if (mounted) {
      setState(() {
        _attendanceSummaryData = finalSummary;
      });
    }
  }


  /// Fetches data for the Daily Attendance Logs Report.
  /// For monthly/yearly, it provides a daily summary.
  Future<void> _fetchDailyAttendanceLogs(DateTime startDate, DateTime endDate) async {
    final List<Map<String, dynamic>> logs = [];

    try {
      final List<String> employeeUidsToFetch = _selectedEmployeeIds.toList();

      if (employeeUidsToFetch.isEmpty) {
        if (mounted) {
          setState(() {
            _dailyAttendanceLogsData = [];
          });
        }
        return;
      }

      for (var employeeUid in employeeUidsToFetch) {
        final String employeeName = _employeeNames[employeeUid] ?? 'Unknown Employee';

        DateTime currentDay = startDate;
        while (currentDay.isBefore(endDate.add(const Duration(days: 1)))) {
          final String dateStr = DateFormat('yyyy-MM-dd').format(currentDay);
          final attendanceDoc = await FirebaseFirestore.instance
              .collection('Attendance')
              .doc(employeeUid)
              .collection('Records')
              .doc(dateStr)
              .get();

          if (attendanceDoc.exists) {
            final data = attendanceDoc.data() as Map<String, dynamic>?; // Explicitly cast
            List<Map<String, dynamic>> dailyPunches = [];

            if (data != null) { // Ensure data is not null
              if (data['Clock InOut.in'] != null) {
                dailyPunches.add({
                  'type': 'Clock In',
                  'time': (data['Clock InOut.in'] as Timestamp).toDate(),
                  'location': data['Clock InOut.in_location'] ?? 'N/A',
                });
              }
              if (data['Clock InOut.out'] != null) {
                dailyPunches.add({
                  'type': 'Clock Out',
                  'time': (data['Clock InOut.out'] as Timestamp).toDate(),
                  'location': data['Clock InOut.out_location'] ?? 'N/A',
                });
              }
              if (data['Break.in'] != null) {
                dailyPunches.add({
                  'type': 'Break Start',
                  'time': (data['Break.in'] as Timestamp).toDate(),
                  'location': data['Break.in_location'] ?? 'N/A',
                });
              }
              if (data['Break.out'] != null) {
                dailyPunches.add({
                  'type': 'Break End',
                  'time': (data['Break.out'] as Timestamp).toDate(),
                  'location': data['Break.out_location'] ?? 'N/A',
                });
              }

              dailyPunches.sort((a, b) => (a['time'] as DateTime).compareTo(b['time'] as DateTime));

              if (dailyPunches.isNotEmpty) {
                if (_selectedFilterType == ReportFilterType.daily) {
                  for (var punch in dailyPunches) {
                    logs.add({
                      'employeeName': employeeName,
                      'type': punch['type'],
                      'time': DateFormat('hh:mm a').format(punch['time']),
                      'location': punch['location'],
                    });
                  }
                } else {
                  // For month/year, show a summary per day per employee
                  final firstPunch = dailyPunches.first;
                  final lastPunch = dailyPunches.last;
                  logs.add({
                    'employeeName': employeeName,
                    'date': DateFormat('MMM dd, yyyy').format(currentDay),
                    'summary': '${firstPunch['type']} at ${DateFormat('hh:mm a').format(firstPunch['time'])} - ${lastPunch['type']} at ${DateFormat('hh:mm a').format(lastPunch['time'])}',
                    'details': dailyPunches.map((p) => '${p['type']} at ${DateFormat('hh:mm a').format(p['time'])} (${p['location']})').join('; '),
                  });
                }
              }
            }
          }
          currentDay = currentDay.add(const Duration(days: 1));
        }
      }
    } catch (e) {
      debugPrint("Error fetching daily attendance logs: $e");
    }
    if (mounted) {
      setState(() {
        _dailyAttendanceLogsData = logs;
      });
    }
  }

  /// Fetches data for the Late/Early Report.
  /// This function queries the 'PunchLogs' collection for records within the selected date range
  /// and for the selected employees. It specifically looks for entries that have a non-empty
  /// 'latenessMessage', indicating a late or early punch.
  Future<void> _fetchLateEarlyReport(DateTime startDate, DateTime endDate) async {
    final List<Map<String, dynamic>> lateEarly = [];

    try {
      Query query = FirebaseFirestore.instance
          .collection('PunchLogs')
          .doc(widget.companyId) // Filter by company ID
          .collection('Records')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endDate));

      // Filter by selected employees
      if (_selectedEmployeeIds.isNotEmpty) {
        query = query.where('employeeId', whereIn: _selectedEmployeeIds.toList());
      } else {
        // If no employees are selected, clear the data and return
        if (mounted) {
          setState(() {
            _lateEarlyData = [];
          });
        }
        return;
      }

      final punchLogsSnapshot = await query.get();

      for (var logDoc in punchLogsSnapshot.docs) {
        // Explicitly cast the data to Map<String, dynamic>
        final data = logDoc.data() as Map<String, dynamic>;
        final String employeeUid = data['employeeId'] ?? '';
        final String employeeName = _employeeNames[employeeUid] ?? 'Unknown Employee';
        final Timestamp timestamp = data['timestamp'] as Timestamp;
        // Fetch 'excessively late' if that's the new field name, otherwise use 'latenessMessage'
        final String latenessMessage = data['excessively late'] ?? data['latenessMessage'] ?? '';
        final String remark = data['remark'] ?? ''; // Fetch the remark field

        // Only add entries that have a lateness message
        if (latenessMessage.isNotEmpty) {
          lateEarly.add({
            'employeeName': employeeName,
            'type': 'Late', // Assuming 'latenessMessage' implies 'Late' or 'Early Out'
            'time': DateFormat('hh:mm a').format(timestamp.toDate()),
            'date': DateFormat('MMM dd, yyyy').format(timestamp.toDate()), // Add date for month/year view
            'remark': remark, // Use the fetched remark
            'excessively late': latenessMessage, // Use the fetched latenessMessage as the 'excessively late' field
          });
        }
      }
      // Sort by date and then time for chronological display
      lateEarly.sort((a, b) {
        final DateTime dateA = DateFormat('MMM dd, yyyy').parse(a['date']);
        final DateTime dateB = DateFormat('MMM dd, yyyy').parse(b['date']);
        int dateComparison = dateA.compareTo(dateB);
        if (dateComparison != 0) return dateComparison;
        final DateTime timeA = DateFormat('hh:mm a').parse(a['time']);
        final DateTime timeB = DateFormat('hh:mm a').parse(b['time']);
        return timeA.compareTo(timeB);
      });
    } catch (e) {
      debugPrint("Error fetching late/early report: $e");
    }
    if (mounted) {
      setState(() {
        _lateEarlyData = lateEarly;
      });
    }
  }

  /// Fetches data for the Working Hours Report.
  /// For monthly/yearly, it aggregates total worked hours and overtime per employee.
  Future<void> _fetchWorkingHoursReport(DateTime startDate, DateTime endDate) async {
    final Map<String, Map<String, dynamic>> workingHoursMap = {};

    try {
      final List<String> employeeUidsToFetch = _selectedEmployeeIds.toList();

      if (employeeUidsToFetch.isEmpty) {
        if (mounted) {
          setState(() {
            _workingHoursData = [];
          });
        }
        return;
      }

      for (var employeeUid in employeeUidsToFetch) {
        final String employeeName = _employeeNames[employeeUid] ?? 'Unknown Employee';

        workingHoursMap[employeeUid] = {
          'employeeName': employeeName,
          'totalWorkedMinutes': 0,
          'totalOvertimeMinutes': 0,
        };

        DateTime currentDay = startDate;
        while (currentDay.isBefore(endDate.add(const Duration(days: 1)))) {
          final String dateStr = DateFormat('yyyy-MM-dd').format(currentDay);
          final attendanceDoc = await FirebaseFirestore.instance
              .collection('Attendance')
              .doc(employeeUid)
              .collection('Records')
              .doc(dateStr)
              .get();

          if (attendanceDoc.exists) {
            final data = attendanceDoc.data() as Map<String, dynamic>?; // Explicitly cast
            if (data != null) { // Ensure data is not null
              final Timestamp? clockInTs = data['Clock InOut.in'] as Timestamp?;
              final Timestamp? clockOutTs = data['Clock InOut.out'] as Timestamp?;

              if (clockInTs != null && clockOutTs != null) {
                Duration totalDuration = clockOutTs.toDate().difference(clockInTs.toDate());

                final Timestamp? breakInTs = data['Break.in'] as Timestamp?;
                final Timestamp? breakOutTs = data['Break.out'] as Timestamp?;

                if (breakInTs != null && breakOutTs != null) {
                  Duration breakDuration = breakOutTs.toDate().difference(breakInTs.toDate());
                  totalDuration = totalDuration - breakDuration;
                }

                workingHoursMap[employeeUid]!['totalWorkedMinutes'] += totalDuration.inMinutes;

                const int standardWorkingHoursMinutes = 8 * 60;
                if (totalDuration.inMinutes > standardWorkingHoursMinutes) {
                  final Duration overtimeDuration = totalDuration - Duration(minutes: standardWorkingHoursMinutes);
                  workingHoursMap[employeeUid]!['totalOvertimeMinutes'] += overtimeDuration.inMinutes;
                }
              }
            }
          }
          currentDay = currentDay.add(const Duration(days: 1));
        }
      }
    } catch (e) {
      debugPrint("Error fetching working hours report: $e");
    }

    final List<Map<String, dynamic>> finalWorkingHours = [];
    workingHoursMap.forEach((uid, data) {
      final int totalWorkedMinutes = data['totalWorkedMinutes'] as int;
      final int totalOvertimeMinutes = data['totalOvertimeMinutes'] as int;
      finalWorkingHours.add({
        'employeeName': data['employeeName'],
        'date': _selectedFilterType == ReportFilterType.daily ? DateFormat('MMM dd, yyyy').format(_selectedDate) : 'Aggregated',
        'workedHours': '${totalWorkedMinutes ~/ 60}h ${totalWorkedMinutes.remainder(60)}m',
        'overtime': '${totalOvertimeMinutes ~/ 60}h ${totalOvertimeMinutes.remainder(60)}m',
      });
    });
    if (mounted) {
      setState(() {
        _workingHoursData = finalWorkingHours;
      });
    }
  }

  /// Fetches data for the Location Report.
  /// For monthly/yearly, it lists all punch locations within the period.
  Future<void> _fetchLocationReport(DateTime startDate, DateTime endDate) async {
    final List<Map<String, dynamic>> locations = [];

    try {
      Query query = FirebaseFirestore.instance
          .collection('PunchLogs')
          .doc(widget.companyId)
          .collection('Records')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endDate));

      // Filter by selected employees
      if (_selectedEmployeeIds.isNotEmpty) {
        query = query.where('employeeId', whereIn: _selectedEmployeeIds.toList());
      } else {
        if (mounted) {
          setState(() {
            _locationData = [];
          });
        }
        return;
      }

      final punchLogsSnapshot = await query.get();

      for (var logDoc in punchLogsSnapshot.docs) {
        final data = logDoc.data() as Map<String, dynamic>; // Explicitly cast
        final String employeeUid = data['employeeId'] ?? '';
        final String employeeName = _employeeNames[employeeUid] ?? 'Unknown Employee';
        final Timestamp timestamp = data['timestamp'] as Timestamp;
        final String location = data['location'] ?? 'N/A';
        final String type = data['type'] ?? 'N/A'; // e.g., 'clocked in', 'started break'
        locations.add({
          'employeeName': employeeName,
          'time': '${DateFormat('hh:mm a').format(timestamp.toDate())} ($type)', // Include punch type in time for context
          'date': DateFormat('MMM dd, yyyy').format(timestamp.toDate()), // Add date for month/year view
          'location': location,
        });
      }
      // Sort by date and then time
      locations.sort((a, b) {
        final DateTime dateA = DateFormat('MMM dd, yyyy').parse(a['date']);
        final DateTime dateB = DateFormat('MMM dd, yyyy').parse(b['date']);
        int dateComparison = dateA.compareTo(dateB);
        if (dateComparison != 0) return dateComparison;
        // Parse time from the string "HH:MM AM/PM (type)"
        final DateTime timeA = DateFormat('hh:mm a').parse(a['time'].split(' ')[0] + ' ' + a['time'].split(' ')[1]);
        final DateTime timeB = DateFormat('hh:mm a').parse(b['time'].split(' ')[0] + ' ' + b['time'].split(' ')[1]);
        return timeA.compareTo(timeB);
      });
    } catch (e) {
      debugPrint("Error fetching location report: $e");
    }
    if (mounted) {
      setState(() {
        _locationData = locations;
      });
    }
  }

  /// Shows a date picker based on the selected filter type.
  Future<void> _showDatePickerBasedOnFilter(BuildContext context) async {
    if (!mounted) return; // Added mounted check
    if (_selectedFilterType == ReportFilterType.daily) {
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: _selectedDate,
        firstDate: DateTime(2000),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
      if (picked != null && picked != _selectedDate) {
        if (mounted) {
          setState(() {
            _selectedDate = picked;
          });
        }
        _fetchReportData();
      }
    } else if (_selectedFilterType == ReportFilterType.month) {
      // Custom Month Picker Dialog
      final DateTime? picked = await showDialog<DateTime>(
        context: context,
        builder: (BuildContext dialogContext) { // Renamed context to dialogContext for clarity
          int selectedYear = _selectedDate.year;
          int selectedMonth = _selectedDate.month;
          return AlertDialog(
            title: const Text('Select Month'),
            content: SizedBox(
              width: 300,
              height: 300,
              child: StatefulBuilder( // Use StatefulBuilder to manage internal dialog state
                builder: (BuildContext innerContext, StateSetter setStateInDialog) {
                  return Column(
                    children: [
                      // Year navigation
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios),
                            onPressed: () {
                              setStateInDialog(() { // Use setStateInDialog here
                                selectedYear--;
                              });
                            },
                          ),
                          Text(
                            selectedYear.toString(),
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward_ios),
                            onPressed: () {
                              setStateInDialog(() { // Use setStateInDialog here
                                selectedYear++;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Month Grid
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
                                Navigator.pop(dialogContext, DateTime(selectedYear, month, 1)); // Use dialogContext for pop
                              },
                              style: TextButton.styleFrom(
                                backgroundColor: selectedMonth == month && _selectedDate.year == selectedYear ? Colors.black : Colors.transparent,
                                foregroundColor: selectedMonth == month && _selectedDate.year == selectedYear ? Colors.white : Colors.black,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: Text(monthName),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () {
                  Navigator.pop(dialogContext); // Use dialogContext for pop
                },
              ),
            ],
          );
        },
      );
      if (picked != null) {
        if (mounted) { // Added mounted check
          setState(() {
            _selectedDate = picked; // picked will already be the 1st of the selected month
          });
        }
        _fetchReportData();
      }
    } else { // ReportFilterType.year
      // Custom Year Picker Dialog
      final DateTime? picked = await showDialog<DateTime>(
        context: context,
        builder: (BuildContext dialogContext) { // Renamed context to dialogContext for clarity
          int currentDisplayYear = _selectedDate.year;
          // Generate a range of years, e.g., 10 years before and 10 years after
          final int startYear = currentDisplayYear - 5; // Show 11 years at a time
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
                        fontWeight: _selectedDate.year == year ? FontWeight.bold : FontWeight.normal,
                        color: _selectedDate.year == year ? Colors.black : Colors.grey[700],
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(dialogContext, DateTime(year, 1, 1)); // Use dialogContext for pop
                    },
                  );
                },
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () {
                  Navigator.pop(dialogContext); // Use dialogContext for pop
                },
              ),
            ],
          );
        },
      );
      if (picked != null) {
        if (mounted) { // Added mounted check
          setState(() {
            _selectedDate = picked; // picked will already be the 1st of the selected year
          });
        }
        _fetchReportData();
      }
    }
  }

  /// Shows a multi-select dialog for employees.
  Future<void> _showEmployeeMultiSelectDialog() async {
    if (!mounted) return; // Added mounted check
    final List<String> allEmployeeUids = _employeeNames.keys.toList();
    final List<String> tempSelectedEmployeeIds = List.from(_selectedEmployeeIds);

    final List<String>? result = await showDialog<List<String>>(
      context: context,
      builder: (BuildContext dialogContext) { // Renamed context to dialogContext for clarity
        return StatefulBuilder(
          builder: (BuildContext innerContext, StateSetter setStateInDialog) {
            return AlertDialog(
              title: const Text('Select Employees'),
              content: _isLoadingNames
                  ? const Center(child: CircularProgressIndicator())
                  : allEmployeeUids.isEmpty
                  ? const Text('No employees found.')
                  : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CheckboxListTile(
                      title: const Text('Select All'),
                      value: _selectAllEmployees,
                      onChanged: (bool? value) {
                        setStateInDialog(() {
                          _selectAllEmployees = value ?? false;
                          if (_selectAllEmployees) {
                            tempSelectedEmployeeIds
                                .addAll(allEmployeeUids
                                .where((uid) => !tempSelectedEmployeeIds.contains(uid)));
                          } else {
                            tempSelectedEmployeeIds.clear();
                          }
                        });
                      },
                    ),
                    ...allEmployeeUids.map((uid) {
                      return CheckboxListTile(
                        title: Text(_employeeNames[uid] ?? 'Unknown Employee'),
                        value: tempSelectedEmployeeIds.contains(uid),
                        onChanged: (bool? selected) {
                          setStateInDialog(() {
                            if (selected == true) {
                              tempSelectedEmployeeIds.add(uid);
                            } else {
                              tempSelectedEmployeeIds.remove(uid);
                            }
                            // Update selectAllEmployees status based on current selection
                            _selectAllEmployees = tempSelectedEmployeeIds.length == allEmployeeUids.length;
                          });
                        },
                      );
                    }).toList(),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () {
                    Navigator.pop(dialogContext); // Use dialogContext for pop
                  },
                ),
                ElevatedButton(
                  child: const Text('Apply'),
                  onPressed: () {
                    Navigator.pop(dialogContext, tempSelectedEmployeeIds); // Use dialogContext for pop
                  },
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      if (mounted) { // Added mounted check
        setState(() {
          _selectedEmployeeIds = result.toSet();
          _selectAllEmployees = _selectedEmployeeIds.length == allEmployeeUids.length;
        });
      }
      _fetchReportData(); // Re-fetch data with new employee selection
    }
  }

  /// Handles permissions and then offers to save or share the generated file.
  Future<void> _showSaveOrShareOptions({
    required Uint8List fileBytes,
    required String fileName,
    required MimeType mimeType,
  }) async {
    if (!mounted) return; // Added mounted check
    // Request storage permission
    bool granted = await _requestStoragePermission();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar( // Use this.context
          const SnackBar(content: Text('Storage permission denied. Cannot save file directly.')),
        );
      }
      // If permission is denied, still offer to share
      try {
        final tempDir = await getTemporaryDirectory(); // Corrected call
        final filePath = path.join(tempDir.path, fileName); // Use path.join for cross-platform compatibility
        final file = File(filePath);
        await file.writeAsBytes(fileBytes);
        await Share.shareXFiles([XFile(filePath)], text: 'Here is your attendance report.');
        if (mounted) {
          ScaffoldMessenger.of(this.context).showSnackBar( // Use this.context
            SnackBar(content: Text('File shared successfully (temporary).')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(this.context).showSnackBar( // Use this.context
            SnackBar(content: Text('Failed to share file: $e')),
          );
        }
        debugPrint('Error sharing file (without direct save): $e');
      }
      return;
    }

    // If permission isGranted, proceed with direct save or share options
    showModalBottomSheet(
      context: context,
      builder: (BuildContext dialogContext) { // Renamed context to dialogContext for clarity
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
                  Navigator.pop(dialogContext); // Close bottom sheet
                  try {
                    await FileSaver.instance.saveFile(
                      name: fileName,
                      bytes: fileBytes,
                      ext: fileName.split('.').last, // e.g., 'pdf' or 'xlsx'
                      mimeType: mimeType,
                    );
                    if (mounted) { // Check if the main widget is still mounted
                      ScaffoldMessenger.of(this.context).showSnackBar( // Use this.context
                        SnackBar(content: Text('"$fileName" saved successfully!')),
                      );
                    }
                  } catch (e) {
                    if (mounted) { // Check if the main widget is still mounted
                      ScaffoldMessenger.of(this.context).showSnackBar( // Use this.context
                        SnackBar(content: Text('Failed to save file: $e')),
                      );
                    }
                    debugPrint('Error saving file directly: $e');
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.orange),
                title: const Text('Share File'),
                onTap: () async {
                  Navigator.pop(dialogContext); // Close bottom sheet
                  try {
                    final tempDir = await getTemporaryDirectory(); // Corrected call
                    final filePath = path.join(tempDir.path, fileName); // Use path.join
                    final file = File(filePath);
                    await file.writeAsBytes(fileBytes);
                    await Share.shareXFiles([XFile(filePath)], text: 'Here is your attendance report.');
                    if (mounted) { // Check if the main widget is still mounted
                      ScaffoldMessenger.of(this.context).showSnackBar( // Use this.context
                        SnackBar(content: Text('File shared successfully.')),
                      );
                    }
                  } catch (e) {
                    if (mounted) { // Check if the main widget is still mounted
                      ScaffoldMessenger.of(this.context).showSnackBar( // Use this.context
                        SnackBar(content: Text('Failed to share file: $e')),
                      );
                    }
                    debugPrint('Error sharing file: $e');
                  }
                },
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
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
        // On Android 13+, WRITE_EXTERNAL_STORAGE is deprecated.
        // FileSaver.instance.saveFile typically uses MediaStore for downloads directory,
        // which doesn't require explicit permissions like WRITE_EXTERNAL_STORAGE on newer Android.
        // We'll just check for manageExternalStorage as a robust fallback, though it's rarely granted.
        final status = await Permission.manageExternalStorage.request();
        return status.isGranted;
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

  /// Helper function to sanitize data for PDF table, ensuring all values are strings.
  List<List<String>> _sanitizeDataForPdf(List<List<String>> data) {
    return data.map((row) {
      return row.map((cell) => cell ?? 'N/A').toList(); // Replace nulls with 'N/A'
    }).toList();
  }

  /// Generates a PDF report and shares it using the system share sheet.
  Future<void> _generatePdfReport({
    required String reportTitle,
    required List<String> headers,
    required List<List<String>> data,
    required String fileNamePrefix,
  }) async {
    debugPrint('Generating PDF for: $reportTitle with headers: $headers');
    debugPrint('Data being passed to PDF generator (before sanitization): $data');

    // Sanitize data before passing to PDF table
    final List<List<String>> sanitizedData = _sanitizeDataForPdf(data);
    debugPrint('Debug: Sanitized data for PDF Table: $sanitizedData');
    debugPrint('Debug: Final headers for PDF Table: $headers');


    if (sanitizedData.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar( // Use this.context
          SnackBar(content: Text('No data available to generate PDF for "$reportTitle".')),
        );
      }
      return;
    }

    final pdf = pw.Document();
    String reportPeriod;
    if (_selectedFilterType == ReportFilterType.daily) {
      reportPeriod = _formatDay(_selectedDate);
    } else if (_selectedFilterType == ReportFilterType.month) {
      reportPeriod = _formatMonth(_selectedDate);
    } else {
      reportPeriod = _formatYear(_selectedDate);
    }
    final String fileName = '${fileNamePrefix}_${_displayedDateRange.replaceAll(' ', '_')}.pdf';

    // Split data into chunks for pagination
    final List<List<List<String>>> dataChunks = [];
    for (int i = 0; i < sanitizedData.length; i += _maxRowsPerPage) {
      final int end = (i + _maxRowsPerPage < sanitizedData.length) ? i + _maxRowsPerPage : sanitizedData.length;
      dataChunks.add(sanitizedData.sublist(i, end));
    }

    // Debug print to check if data chunks are created
    debugPrint('Number of data chunks for PDF: ${dataChunks.length}');


    for (int i = 0; i < dataChunks.length; i++) {
      debugPrint('Adding page ${i + 1} with data chunk (first 5 rows): ${dataChunks[i].take(5).toList()}'); // Limit for readability
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '$reportTitle - $reportPeriod ${dataChunks.length > 1 ? '(Page ${i + 1} of ${dataChunks.length})' : ''}',
                  style: pw.TextStyle(font: pw.Font.helveticaBold(), fontSize: 20),
                ),
                pw.SizedBox(height: 20),
                pw.Table.fromTextArray(
                  headers: headers,
                  data: dataChunks[i],
                  border: pw.TableBorder.all(color: PdfColors.grey),
                  headerStyle: pw.TextStyle(font: pw.Font.helveticaBold(), fontWeight: pw.FontWeight.bold),
                  cellAlignment: pw.Alignment.centerLeft,
                  cellPadding: const pw.EdgeInsets.all(8),
                  cellStyle: pw.TextStyle(font: pw.Font.helvetica()),
                ),
              ],
            );
          },
        ),
      );
    }

    try {
      final Uint8List bytes = await pdf.save();
      // Show option to save directly or share
      _showSaveOrShareOptions(
        fileBytes: bytes,
        fileName: fileName,
        mimeType: MimeType.pdf,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar( // Use this.context
          SnackBar(content: Text('Failed to generate or share PDF: $e')),
        );
      }
      debugPrint('Error generating or saving PDF: $e');
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
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar( // Use this.context
          SnackBar(content: Text('No data available to generate Excel for "$sheetName".')),
        );
      }
      return;
    }

    final excel = Excel.createExcel();
    String reportPeriod;
    if (_selectedFilterType == ReportFilterType.daily) {
      reportPeriod = _formatDay(_selectedDate);
    } else if (_selectedFilterType == ReportFilterType.month) {
      reportPeriod = _formatMonth(_selectedDate);
    } else {
      reportPeriod = _formatYear(_selectedDate);
    }
    final String fileName = '${fileNamePrefix}_${_displayedDateRange.replaceAll(' ', '_')}.xlsx';
    Sheet sheetObject = excel[sheetName];

    // Add headers. Using TextCellValue for explicit type for Excel package.
    sheetObject.appendRow(headers.map((h) => TextCellValue(h)).toList());

    // Add data rows
    for (var row in data) {
      sheetObject.appendRow(row.map((cell) => TextCellValue(cell)).toList());
    }

    try {
      final Uint8List bytes = Uint8List.fromList(excel.encode()!);
      // Show option to save directly or share
      _showSaveOrShareOptions(
        fileBytes: bytes,
        fileName: fileName,
        mimeType: MimeType.microsoftExcel,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar( // Use this.context
          SnackBar(content: Text('Failed to generate or share Excel: $e')),
        );
      }
      debugPrint('Error generating or saving Excel: $e');
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
        headers = [
          'Employee Name',
          'Total Hours',
          'Status',
          'Days Present',
          'Late Days',
          'Leave Days',
          'Overtime',
          'First Punch In',
          'Last Punch Out',
          'Locations',
        ];
        debugPrint('Debug: _attendanceSummaryData before mapping for PDF: $_attendanceSummaryData');
        data = _attendanceSummaryData.map((d) {
          final String totalHours = d['totalHours'].toString();
          final String totalOvertime = d['totalOvertime'].toString();
          return [
            d['employeeName'].toString(),
            totalHours,
            d['status'].toString(),
            d['totalDaysPresent'].toString(),
            d['totalLateDays'].toString(),
            d['totalLeaveDays'].toString(),
            totalOvertime,
            d['firstPunchInTime'].toString(),
            d['lastPunchOutTime'].toString(),
            (d['uniqueLocations'] is String) ? d['uniqueLocations'].toString() : (d['uniqueLocations'] as Set).join(', '), // Ensure correct handling for Set
          ];
        }).toList();
        debugPrint('Debug: Final mapped data for PDF Summary Report: $data');
        fileNamePrefix = 'attendance_summary';
        break;
      case 1: // Daily Logs
        reportTitle = 'Daily Attendance Logs Report';
        if (_selectedFilterType == ReportFilterType.daily) {
          headers = ['Employee Name', 'Type', 'Time', 'Location'];
          data = _dailyAttendanceLogsData.map((d) => [
            d['employeeName'].toString(),
            d['type'].toString(),
            d['time'].toString(),
            d['location'].toString(),
          ]).toList();
        } else {
          headers = ['Employee Name', 'Date', 'Summary', 'Details'];
          data = _dailyAttendanceLogsData.map((d) => [
            d['employeeName'].toString(),
            d['date'].toString(),
            d['summary'].toString(),
            d['details'].toString(),
          ]).toList();
        }
        fileNamePrefix = 'daily_attendance_logs';
        break;
      case 2: // Late/Early
        reportTitle = 'Late/Early Report';
        headers = ['Employee Name', 'Date', 'Time', 'Lateness Message', 'Remark']; // Updated header
        data = _lateEarlyData.map((d) => [
          d['employeeName'].toString(),
          d['date'].toString(),
          d['time'].toString(),
          d['excessively late'].toString(), // Use the new key for the lateness message
          d['remark'].toString(),
        ]).toList();
        fileNamePrefix = 'late_early_report';
        break;
      case 3: // Working Hours
        reportTitle = 'Working Hours Report';
        headers = ['Employee Name', 'Date/Period', 'Worked Hours', 'Overtime'];
        data = _workingHoursData.map((d) => [
          d['employeeName'].toString(),
          d['date'].toString(),
          d['workedHours'].toString(),
          d['overtime'].toString(),
        ]).toList();
        fileNamePrefix = 'working_hours_report';
        break;
      case 4: // Location
        reportTitle = 'Location Report';
        headers = ['Employee Name', 'Date', 'Time (Type)', 'Location'];
        data = _locationData.map((d) => [
          d['employeeName'].toString(),
          d['date'].toString(),
          d['time'].toString(),
          d['location'].toString(),
        ]).toList();
        fileNamePrefix = 'location_report';
        break;
    }
    debugPrint('Data for export (Tab ${_tabController.index}): $data');
    return {
      'reportTitle': reportTitle,
      'headers': headers,
      'data': data,
      'fileNamePrefix': fileNamePrefix,
    };
  }

  /// Displays a modal bottom sheet with export options (PDF/Excel).
  void _showExportOptions() {
    if (!mounted) return; // Added mounted check
    if (_isLoadingReports) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reports are still loading. Please wait.')),
      );
      return;
    }

    final currentReport = _getCurrentReportDataForExport();
    final List<String> headers = currentReport['headers'];
    final List<List<String>> data = currentReport['data'];
    final String reportTitle = currentReport['reportTitle'];
    final String fileNamePrefix = currentReport['fileNamePrefix'];

    // Specific check for Summary tab if you want a custom message for empty data
    if (_tabController.index == 0 && _attendanceSummaryData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Summary report is not suitable for PDF generation as there is no data for the selected period. Please ensure attendance records exist.'),
        ),
      );
      return; // Stop here if Summary tab is selected and its data is empty.
    }

    if (data.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No data available for "$reportTitle". Cannot export.')),
      );
      return;
    }


    showModalBottomSheet(
      context: context,
      builder: (BuildContext dialogContext) {
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
                  Navigator.pop(dialogContext); // Close bottom sheet
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
                  Navigator.pop(dialogContext); // Close bottom sheet
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
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- Report Widgets ---

  Widget _buildSummaryTab() {
    if (_isLoadingReports) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_attendanceSummaryData.isEmpty) {
      return const Center(child: Text('No attendance summary data available for the selected period/employees.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: _attendanceSummaryData.length,
      itemBuilder: (context, index) {
        final data = _attendanceSummaryData[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4.0),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data['employeeName'].toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text('Status: ${data['status']}'),
                Text('Total Hours: ${data['totalHours']}'),
                Text('Total Days Present: ${data['totalDaysPresent']}'),
                Text('Total Late Days: ${data['totalLateDays']}'),
                Text('Total Leave Days: ${data['totalLeaveDays']}'),
                Text('Total Overtime: ${data['totalOvertime']}'),
                Text('First Punch In: ${data['firstPunchInTime']}'),
                Text('Last Punch Out: ${data['lastPunchOutTime']}'),
                Text('Unique Locations: ${data['uniqueLocations']}'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDailyLogsTab() {
    if (_isLoadingReports) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_dailyAttendanceLogsData.isEmpty) {
      return const Center(child: Text('No daily attendance logs available for the selected period/employees.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: _dailyAttendanceLogsData.length,
      itemBuilder: (context, index) {
        final data = _dailyAttendanceLogsData[index];
        if (_selectedFilterType == ReportFilterType.daily) {
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4.0),
            child: ListTile(
              title: Text('${data['employeeName']} - ${data['type']} at ${data['time']}'),
              subtitle: Text('Location: ${data['location']}'),
            ),
          );
        } else {
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4.0),
            child: ExpansionTile(
              title: Text('${data['employeeName']} - ${data['date']}'),
              subtitle: Text(data['summary']),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Text(data['details']),
                ),
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildLateEarlyTab() {
    if (_isLoadingReports) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_lateEarlyData.isEmpty) {
      return const Center(child: Text('No late/early records available for the selected period/employees.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: _lateEarlyData.length,
      itemBuilder: (context, index) {
        final data = _lateEarlyData[index];
        return Card(
          elevation: 2, // Added elevation for a subtle shadow
          margin: const EdgeInsets.symmetric(vertical: 8.0), // Increased vertical margin
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), // Rounded corners
          child: Padding(
            padding: const EdgeInsets.all(16.0), // Increased padding
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Employee: ${data['employeeName']}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  'Date: ${data['date']}',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                Text(
                  'Time: ${data['time']}',
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                ),
                Text(
                  'Type: ${data['type']}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: data['type'] == 'Late' ? Colors.red : Colors.orange, // Differentiate colors
                  ),
                ),
                if (data['excessively late'] != null && data['excessively late'].isNotEmpty) // Use new key
                  Text(
                    'Lateness Message: ${data['excessively late']}', // Display using new key
                    style: const TextStyle(fontSize: 13, color: Colors.blueGrey),
                  ),
                if (data['remark'] != null && data['remark'].isNotEmpty) // Display the remark field
                  Text(
                    'Remark: ${data['remark']}',
                    style: const TextStyle(fontSize: 13, color: Colors.purple),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWorkingHoursTab() {
    if (_isLoadingReports) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_workingHoursData.isEmpty) {
      return const Center(child: Text('No working hours data available for the selected period/employees.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: _workingHoursData.length,
      itemBuilder: (context, index) {
        final data = _workingHoursData[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4.0),
          child: ListTile(
            title: Text('${data['employeeName']} (${data['date']})'),
            subtitle: Text('Worked: ${data['workedHours']}, Overtime: ${data['overtime']}'),
          ),
        );
      },
    );
  }

  Widget _buildLocationTab() {
    if (_isLoadingReports) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_locationData.isEmpty) {
      return const Center(child: Text('No location data available for the selected period/employees.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: _locationData.length,
      itemBuilder: (context, index) {
        final data = _locationData[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4.0),
          child: ListTile(
            title: Text('${data['employeeName']} - ${data['date']}'),
            subtitle: Text('Time: ${data['time']}, Location: ${data['location']}'),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingNames) {
      return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.black)));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('History Report (Admin)'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showEmployeeMultiSelectDialog,
            tooltip: 'Filter Employees',
          ),
          // Export options button
          // Moved FloatingActionButton.extended to the body for better placement.
          // The actions list in AppBar is usually for smaller icons.
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: _tabNames.map((name) => Tab(text: name)).toList(),
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0), // Increased padding for better spacing
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
                      'Period: $_displayedDateRange',
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
          _isLoadingNames || _isLoadingReports
              ? const Expanded(
            child: Center(
              child: CircularProgressIndicator(),
            ),
          )
              : _selectedEmployeeIds.isEmpty
              ? const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Please select at least one employee to view reports.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ),
            ),
          )
              : Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSummaryTab(),
                _buildDailyLogsTab(),
                _buildLateEarlyTab(),
                _buildWorkingHoursTab(),
                _buildLocationTab(),
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
    );
  }
}