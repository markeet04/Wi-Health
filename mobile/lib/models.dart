import 'package:flutter/foundation.dart';

/// Live breathing state of a monitored patient, driven (later) by the
/// device's DSP confidence output. Hardcoded for the frontend build.
enum BreathStatus { normal, lowSignal, noBreathing }

enum AlertSeverity { urgent, warning, info }

enum ComplaintStatus { open, inProgress, resolved }

class Patient {
  Patient({
    required this.id,
    required this.name,
    required this.relation,
    required this.room,
    required this.deviceName,
    required this.deviceId,
    required this.online,
    required this.signalQuality,
    required this.confidence,
    required this.bpm,
    required this.status,
    required this.normalLow,
    required this.normalHigh,
    required this.trend,
    required this.nightlyAvg,
    required this.distribution,
    required this.firmware,
    required this.lastSync,
  });

  final String id;
  final String name;
  final String relation;
  final String room;
  final String deviceName;
  final String deviceId;
  final bool online;

  /// 0..1 — link quality of the CSI stream.
  final double signalQuality;

  /// 0..1 — DSP estimator confidence (Module 3).
  final double confidence;

  /// Current breaths per minute (0 when no valid breathing).
  final int bpm;
  final BreathStatus status;

  /// Personal normal band (adults ≈ 12–20, infants higher).
  final int normalLow;
  final int normalHigh;

  /// Recent BPM samples for sparklines / live trend.
  final List<double> trend;

  /// Avg BPM for the last 7 nights (history chart).
  final List<double> nightlyAvg;

  /// Rate distribution buckets (share of time per BPM bucket).
  final List<double> distribution;

  final String firmware;
  final String lastSync;

  String get initials =>
      name.split(' ').take(2).map((w) => w[0]).join().toUpperCase();

  bool get hasValidBreathing => status == BreathStatus.normal && online;
}

class AnomalyAlert {
  AnomalyAlert({
    required this.id,
    required this.patientId,
    required this.title,
    required this.severity,
    required this.time,
    required this.day,
    required this.summary,
    required this.detail,
    this.acknowledged = false,
  });

  final String id;
  final String patientId;
  final String title;
  final AlertSeverity severity;
  final String time;
  final String day; // "Today" | "Yesterday"
  final String summary;

  /// Label → value rows shown on the detail screen.
  final Map<String, String> detail;
  bool acknowledged;
}

class SessionLog {
  const SessionLog({
    required this.patientId,
    required this.title,
    required this.day,
    required this.time,
    required this.duration,
    required this.avgBpm,
    required this.minBpm,
    required this.maxBpm,
    required this.quality,
  });

  final String patientId;
  final String title;
  final String day;
  final String time;
  final String duration;
  final double avgBpm;
  final int minBpm;
  final int maxBpm;
  final int quality; // percent of windows with valid breathing
}

class ActivityEvent {
  const ActivityEvent({
    required this.title,
    required this.subtitle,
    required this.time,
    required this.kind,
  });

  final String title;
  final String subtitle;
  final String time;
  final String kind; // alert | signal | session | system
}

class Complaint {
  Complaint({
    required this.id,
    required this.category,
    required this.subject,
    required this.description,
    required this.status,
    required this.date,
  });

  final String id;
  final String category;
  final String subject;
  final String description;
  final ComplaintStatus status;
  final String date;
}

/// App-wide state (hardcoded data for now — Firebase later).
class AppState extends ChangeNotifier {
  AppState({
    required this.patients,
    required this.alerts,
    required this.sessions,
    required this.activity,
    required this.complaints,
  });

  final List<Patient> patients;
  final List<AnomalyAlert> alerts;
  final List<SessionLog> sessions;
  final List<ActivityEvent> activity;
  final List<Complaint> complaints;

  String userName = 'Qasim Majid';
  String userEmail = 'qasimmaajid04@gmail.com';

  int _selectedPatient = 0;
  int get selectedPatient => _selectedPatient;
  Patient get current => patients[_selectedPatient];

  void selectPatient(int index) {
    if (index == _selectedPatient) return;
    _selectedPatient = index;
    notifyListeners();
  }

  Patient patientById(String id) => patients.firstWhere((p) => p.id == id);

  int get unacknowledgedUrgent => alerts
      .where((a) => !a.acknowledged && a.severity == AlertSeverity.urgent)
      .length;

  void acknowledgeAlert(String id) {
    alerts.firstWhere((a) => a.id == id).acknowledged = true;
    notifyListeners();
  }

  /// Links a new patient/device pair (hardcoded locally for now; later this
  /// becomes device pairing + Firebase assignment).
  void addPatient({
    required String name,
    required String relation,
    required String room,
    required String deviceId,
    required int normalLow,
    required int normalHigh,
  }) {
    final mid = ((normalLow + normalHigh) / 2).round();
    patients.add(Patient(
      id: 'p${patients.length + 1}',
      name: name,
      relation: relation,
      room: room,
      deviceName: 'Wi-Health Sense 0${patients.length + 1}',
      deviceId: deviceId,
      online: true,
      signalQuality: 0.82,
      confidence: 0.86,
      bpm: mid,
      status: BreathStatus.normal,
      normalLow: normalLow,
      normalHigh: normalHigh,
      trend: [
        for (var i = 0; i < 12; i++) mid + (i % 3 - 1) * 0.6,
      ],
      nightlyAvg: List.filled(7, mid.toDouble()),
      distribution: const [0.03, 0.10, 0.22, 0.30, 0.22, 0.10, 0.03],
      firmware: 'v0.4.2',
      lastSync: 'just now',
    ));
    notifyListeners();
  }

  void submitComplaint({
    required String category,
    required String subject,
    required String description,
  }) {
    complaints.insert(
      0,
      Complaint(
        id: 'c${complaints.length + 1}',
        category: category,
        subject: subject,
        description: description,
        status: ComplaintStatus.open,
        date: 'Just now',
      ),
    );
    notifyListeners();
  }

  // Notification preferences (Settings screen).
  bool pushEnabled = true;
  bool urgentOnly = false;
  bool soundEnabled = true;

  void setPush(bool v) {
    pushEnabled = v;
    notifyListeners();
  }

  void setUrgentOnly(bool v) {
    urgentOnly = v;
    notifyListeners();
  }

  void setSound(bool v) {
    soundEnabled = v;
    notifyListeners();
  }
}
