const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

const db = admin.firestore();

exports.checkLateEmployeesAndSendFCM = functions.pubsub.schedule('every day 09:10').timeZone('Asia/Kuala_Lumpur').onRun(async (context) => {
  const now = new Date();
  const dateString = now.toISOString().split('T')[0];

  const settingsSnap = await db.collection('CompanySettings').get();

  for (const doc of settingsSnap.docs) {
    const companyId = doc.id;
    const data = doc.data();
    const checkInTime = data.checkInTime; // "08:00"

    if (!checkInTime) continue;

    const [hour, minute] = checkInTime.split(':').map(Number);
    const expectedCheckIn = new Date(now);
    expectedCheckIn.setHours(hour, minute, 0, 0);

    if (now < expectedCheckIn) continue;

    const employeeSnap = await db.collection('Employee').where('companyId', '==', companyId).get();

    for (const empDoc of employeeSnap.docs) {
      const employeeId = empDoc.id;
      const employeeData = empDoc.data();

      const punchLog = await db.collection('PunchLogs')
        .doc(employeeId)
        .collection('Logs')
        .doc(dateString)
        .get();

      let reason = '';

      if (!punchLog.exists) {
        reason = 'No check-in detected';
      } else {
        const checkInTimestamp = punchLog.data().checkInTime;
        if (!checkInTimestamp) continue;
        const checkIn = checkInTimestamp.toDate();
        if (checkIn <= expectedCheckIn) continue;
        reason = `Checked in late at ${checkIn.getHours()}:${checkIn.getMinutes()}`;
      }

      if (reason !== '') {
        const messageBody = `You were late on ${dateString}. ${reason}`;

        // Add notification to Firestore
        await db.collection('Employee').doc(employeeId)
          .collection('Notifications').add({
            title: 'Late Check-In Alert',
            message: messageBody,
            timestamp: admin.firestore.Timestamp.now(),
            read: false,
          });

        // Send FCM push notification
        const fcmToken = employeeData.fcmToken;
        if (fcmToken) {
          await admin.messaging().send({
            token: fcmToken,
            notification: {
              title: 'Late Check-In Alert',
              body: messageBody,
            },
            data: {
              type: 'late_checkin',
              date: dateString,
            }
          });
        }
      }
    }
  }
});
