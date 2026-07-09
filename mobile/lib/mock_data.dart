import 'models.dart';

/// Hardcoded demo data — replaced by Firebase Realtime Database later.
AppState buildMockAppState() {
  final patients = [
    Patient(
      id: 'p1',
      name: 'Ayesha Khan',
      relation: 'Mother',
      room: 'Bedroom',
      deviceName: 'Wi-Health Sense 01',
      deviceId: 'WH-S3-A1F4',
      online: true,
      signalQuality: 0.92,
      confidence: 0.94,
      bpm: 16,
      status: BreathStatus.normal,
      normalLow: 12,
      normalHigh: 20,
      trend: [15, 15.5, 16, 16.5, 16, 15.5, 15, 15.5, 16, 17, 16.5, 16],
      nightlyAvg: [15.2, 15.8, 14.9, 16.1, 15.4, 15.9, 15.6],
      distribution: [0.02, 0.08, 0.22, 0.34, 0.22, 0.09, 0.03],
      firmware: 'v0.4.2',
      lastSync: '3 s ago',
    ),
    Patient(
      id: 'p2',
      name: 'Abdul Rahman',
      relation: 'Grandfather',
      room: 'Living Room',
      deviceName: 'Wi-Health Sense 02',
      deviceId: 'WH-S3-B7C2',
      online: true,
      signalQuality: 0.88,
      confidence: 0.90,
      bpm: 21,
      status: BreathStatus.normal,
      normalLow: 12,
      normalHigh: 22,
      trend: [19, 19.5, 20, 21, 21.5, 22, 21.5, 21, 20.5, 21, 21.5, 21],
      nightlyAvg: [18.8, 19.4, 20.1, 19.7, 20.6, 21.0, 20.4],
      distribution: [0.01, 0.05, 0.14, 0.26, 0.30, 0.17, 0.07],
      firmware: 'v0.4.2',
      lastSync: '5 s ago',
    ),
    Patient(
      id: 'p3',
      name: 'Zara',
      relation: 'Daughter',
      room: 'Nursery',
      deviceName: 'Wi-Health Sense 03',
      deviceId: 'WH-S3-C9D8',
      online: true,
      signalQuality: 0.41,
      confidence: 0.38,
      bpm: 0,
      status: BreathStatus.lowSignal,
      normalLow: 25,
      normalHigh: 40,
      trend: [31, 32, 31.5, 33, 32, 30, 24, 12, 0, 0, 0, 0],
      nightlyAvg: [31.5, 32.2, 30.8, 31.9, 32.4, 31.1, 31.8],
      distribution: [0.03, 0.10, 0.24, 0.31, 0.20, 0.09, 0.03],
      firmware: 'v0.4.1',
      lastSync: '38 s ago',
    ),
  ];

  final alerts = [
    AnomalyAlert(
      id: 'a1',
      patientId: 'p3',
      title: 'Low Signal',
      severity: AlertSeverity.info,
      time: '09:41 AM',
      day: 'Today',
      summary:
          'CSI signal quality below threshold in Nursery — breathing rate paused, not a health alert.',
      detail: {
        'Type': 'Signal quality gate',
        'Device': 'Wi-Health Sense 03 · Nursery',
        'Signal quality': '41% (threshold 60%)',
        'Estimator state': 'No valid breathing reported',
        'Suggested fix': 'Check device placement — TX/RX 1–2 m apart',
      },
    ),
    AnomalyAlert(
      id: 'a2',
      patientId: 'p2',
      title: 'Tachypnea — Elevated Rate',
      severity: AlertSeverity.warning,
      time: '07:18 AM',
      day: 'Today',
      summary:
          'Breathing rate 24 bpm exceeded the 22 bpm upper bound for 3 consecutive windows.',
      detail: {
        'Type': 'Rule tier — tachypnea',
        'Peak rate': '24 bpm (bound 22 bpm)',
        'Temporal voting': '3 / 3 windows',
        'Confidence': '91%',
        'Duration': '1 m 30 s',
        'Device': 'Wi-Health Sense 02 · Living Room',
      },
    ),
    AnomalyAlert(
      id: 'a3',
      patientId: 'p1',
      title: 'Suspected Apnea',
      severity: AlertSeverity.urgent,
      time: '02:56 AM',
      day: 'Yesterday',
      summary:
          'No valid breathing for 28 s with high signal quality — cleared after normal breathing resumed.',
      detail: {
        'Type': 'Rule tier — apnea',
        'Pause duration': '28 s (threshold 20 s)',
        'Signal quality': '89% — room occupied',
        'Temporal voting': '2 / 2 windows',
        'Resolution': 'Breathing resumed at 15 bpm',
        'Device': 'Wi-Health Sense 01 · Bedroom',
      },
      acknowledged: true,
    ),
    AnomalyAlert(
      id: 'a4',
      patientId: 'p2',
      title: 'Bradypnea — Low Rate',
      severity: AlertSeverity.warning,
      time: '11:32 PM',
      day: 'Yesterday',
      summary:
          'Breathing rate dipped to 9 bpm, below the 12 bpm lower bound, during deep sleep.',
      detail: {
        'Type': 'Rule tier — bradypnea',
        'Lowest rate': '9 bpm (bound 12 bpm)',
        'Temporal voting': '3 / 3 windows',
        'Confidence': '87%',
        'Duration': '2 m 15 s',
        'Device': 'Wi-Health Sense 02 · Living Room',
      },
      acknowledged: true,
    ),
  ];

  final sessions = [
    const SessionLog(
      patientId: 'p1',
      title: 'Night session — Ayesha',
      day: 'Today',
      time: '06:52 AM',
      duration: '7 h 42 m',
      avgBpm: 15.4,
      minBpm: 12,
      maxBpm: 19,
      quality: 96,
    ),
    const SessionLog(
      patientId: 'p2',
      title: 'Night session — Abdul Rahman',
      day: 'Today',
      time: '06:10 AM',
      duration: '6 h 58 m',
      avgBpm: 20.2,
      minBpm: 9,
      maxBpm: 24,
      quality: 91,
    ),
    const SessionLog(
      patientId: 'p3',
      title: 'Nap session — Zara',
      day: 'Yesterday',
      time: '03:20 PM',
      duration: '1 h 45 m',
      avgBpm: 31.6,
      minBpm: 27,
      maxBpm: 38,
      quality: 88,
    ),
  ];

  final activity = [
    const ActivityEvent(
      title: 'Low signal — Nursery',
      subtitle: 'Zara · breathing readout paused',
      time: '09:41 AM',
      kind: 'signal',
    ),
    const ActivityEvent(
      title: 'Tachypnea alert — cleared',
      subtitle: 'Abdul Rahman · peak 24 bpm, back in range',
      time: '07:24 AM',
      kind: 'alert',
    ),
    const ActivityEvent(
      title: 'Night session ended',
      subtitle: 'Ayesha · 7 h 42 m · avg 15.4 bpm',
      time: '06:52 AM',
      kind: 'session',
    ),
    const ActivityEvent(
      title: 'All devices calibrated',
      subtitle: 'Baseline SNR reference updated',
      time: '06:00 AM',
      kind: 'system',
    ),
  ];

  final complaints = [
    Complaint(
      id: 'c1',
      category: 'Device issue',
      subject: 'Nursery sensor drops offline at night',
      description:
          'The Wi-Health Sense 03 in the nursery goes offline for a few minutes around 2 AM most nights.',
      status: ComplaintStatus.inProgress,
      date: '2 days ago',
    ),
    Complaint(
      id: 'c2',
      category: 'Alert accuracy',
      subject: 'False apnea alert while away',
      description:
          'Received an apnea alert when the room was empty. Expected the empty-room check to catch this.',
      status: ComplaintStatus.resolved,
      date: 'Last week',
    ),
  ];

  return AppState(
    patients: patients,
    alerts: alerts,
    sessions: sessions,
    activity: activity,
    complaints: complaints,
  );
}
