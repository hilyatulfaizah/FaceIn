import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:table_calendar/table_calendar.dart';
// Import the new employee history page
import 'history_page_employee.dart'; // Import the new employee history page


class CalendarUserPage extends StatefulWidget {
  const CalendarUserPage({super.key});

  @override
  State<CalendarUserPage> createState() => _CalendarUserPageState();
}

class _CalendarUserPageState extends State<CalendarUserPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _events = [];

  @override
  void initState() {
    super.initState();
    _fetchAttendanceForDate(_selectedDate); // Auto-load today's records
  }

  Future<void> _fetchAttendanceForDate(DateTime date) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final dateStr =
        "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
    final doc = await FirebaseFirestore.instance
        .collection('Attendance')
        .doc(uid)
        .collection('Records')
        .doc(dateStr)
        .get();

    List<Map<String, dynamic>> events = [];
    if (doc.exists) {
      final data = doc.data()!;
      if (data['Clock InOut.in'] != null) {
        events.add({
          'time': _formatTime((data['Clock InOut.in'] as Timestamp).toDate()),
          'punchType': 'Punch In',
          'location': data['Clock InOut.in_location'] ?? '',
          'color': const Color.fromARGB(255, 143, 83, 167),
          'textColor': Colors.white,
        });
      }
      if (data['Clock InOut.out'] != null) {
        events.add({
          'time': _formatTime((data['Clock InOut.out'] as Timestamp).toDate()),
          'punchType': 'Punch Out',
          'location': data['Clock InOut.out_location'] ?? '',
          'color': const Color.fromARGB(255, 143, 83, 167),
          'textColor': Colors.white,
        });
      }
      if (data['Break.in'] != null) {
        events.add({
          'time': _formatTime((data['Break.in'] as Timestamp).toDate()),
          'punchType': 'Break In',
          'location': data['Break.in_location'] ?? '',
          'color': const Color.fromARGB(255, 143, 83, 167),
          'textColor': Colors.white,
        });
      }
      if (data['Break.out'] != null) {
        events.add({
          'time': _formatTime((data['Break.out'] as Timestamp).toDate()),
          'punchType': 'Break Out',
          'location': data['Break.out_location'] ?? '',
          'color': const Color.fromARGB(255, 143, 83, 167),
          'textColor': Colors.white,
        });
      }
      events.sort((a, b) => a['time'].compareTo(b['time']));
    }

    setState(() {
      _events = events;
    });
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Attendance Calendar', style: TextStyle(color: Colors.black)),
        backgroundColor: const Color.fromARGB(255, 143, 83, 167),
        centerTitle: true,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          // The history button was removed from here.
        ],
      ),
      body: Column(
        children: [
          // 🗓️ Calendar Box
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.all(18),
              child: TableCalendar(
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focusedDay,
                selectedDayPredicate: (day) => isSameDay(_selectedDate, day),
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDate = selectedDay;
                    _focusedDay = focusedDay;
                  });
                  _fetchAttendanceForDate(selectedDay); // only fetch when tapped
                },
                onPageChanged: (focusedDay) {
                  setState(() {
                    _focusedDay = focusedDay;
                    _events = []; // clear data when switching months
                  });
                },
                calendarFormat: CalendarFormat.month,
                headerStyle: const HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  titleTextStyle: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  leftChevronIcon: Icon(Icons.chevron_left, color: Colors.white),
                  rightChevronIcon: Icon(Icons.chevron_right, color: Colors.white),
                ),
                calendarStyle: const CalendarStyle(
                  todayDecoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  todayTextStyle: TextStyle(
                    color: Colors.black, // 🔸 black number on white circle
                    fontWeight: FontWeight.bold,
                  ),
                  selectedDecoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                  selectedTextStyle: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  defaultTextStyle: TextStyle(color: Colors.white),
                  weekendTextStyle: TextStyle(color: Colors.white),
                  outsideTextStyle: TextStyle(color: Colors.grey),
                ),
                daysOfWeekStyle: const DaysOfWeekStyle(
                  weekdayStyle: TextStyle(color: Colors.grey),
                  weekendStyle: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          ),

          // ⏰ Attendance Timeline
          Expanded(
            child: _events.isEmpty
                ? const Center(
                    child: Text(
                      'No attendance records for this day.',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _events.length,
                    itemBuilder: (context, i) {
                      final e = _events[i];
                      return _buildTimelineEvent(
                        time: e['time'],
                        punchType: e['punchType'],
                        location: e['location'],
                        color: e['color'],
                        textColor: e['textColor'],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineEvent({
    required String time,
    required String punchType,
    required String location,
    required Color color,
    required Color textColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Text(
            time,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ),
        Column(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            Container(
              width: 2,
              height: 60,
              color: Colors.grey[300],
            ),
          ],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  punchType,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 5),
                Text(location, style: TextStyle(fontSize: 14, color: textColor)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}