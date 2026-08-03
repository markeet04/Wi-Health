import 'package:flutter/foundation.dart';

/// Live breathing state of a monitored patient, driven (later) by the
/// device's DSP confidence output. Hardcoded for the frontend build.
enum BreathStatus { normal, lowSignal, noBreathing }

enum AlertSeverity { urgent, warning, info }

enum ComplaintStatus { open, inProgress, resolved }

enum DeviceRequestStatus { pending, fulfilled, declined }

/// A caretaker's request for the admin to provision + assign a device. The
/// admin fulfils it by assigning a device (which then appears via the normal
/// assignment listener) and marking the request fulfilled.
class DeviceRequest {
  DeviceRequest({
    required this.id,
    required this.patientName,
    required this.patientRelation,
    required this.room,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String patientName;
  final String patientRelation;
  final String room;
  final DeviceRequestStatus status;
  final DateTime createdAt;
}

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

  factory Patient.empty() => Patient(
        id: 'none',
        name: 'No Devices Linked',
        relation: '',
        room: '',
        deviceName: '',
        deviceId: '',
        online: false,
        signalQuality: 0,
        confidence: 0,
        bpm: 0,
        status: BreathStatus.lowSignal,
        normalLow: 0,
        normalHigh: 0,
        trend: List.filled(12, 0),
        nightlyAvg: List.filled(7, 0),
        distribution: List.filled(7, 0),
        firmware: '',
        lastSync: 'never',
      );
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

class ComplaintMessage {
  ComplaintMessage({
    required this.id,
    required this.senderUid,
    required this.senderRole,
    required this.text,
    required this.sentAt,
  });

  final String id;
  final String senderUid;
  final String senderRole;
  final String text;
  final int sentAt;
}

class Complaint {
  Complaint({
    required this.id,
    required this.category,
    required this.subject,
    required this.description,
    required this.status,
    required this.date,
    this.messages = const [],
  });

  final String id;
  final String category;
  final String subject;
  final String description;
  final ComplaintStatus status;
  final String date;
  final List<ComplaintMessage> messages;

  Complaint copyWith({
    String? id,
    String? category,
    String? subject,
    String? description,
    ComplaintStatus? status,
    String? date,
    List<ComplaintMessage>? messages,
  }) {
    return Complaint(
      id: id ?? this.id,
      category: category ?? this.category,
      subject: subject ?? this.subject,
      description: description ?? this.description,
      status: status ?? this.status,
      date: date ?? this.date,
      messages: messages ?? this.messages,
    );
  }
}

/// App-wide state (hardcoded data for now — Firebase later).
class AppStateRegistry {
  static AppState? _shared;

  static AppState get shared => _shared ??= AppState.empty();

  static void bind(AppState state) {
    _shared = state;
  }
}

class AppState extends ChangeNotifier {
  AppState({
    required this.patients,
    required this.alerts,
    required this.sessions,
    required this.activity,
    required this.complaints,
  });

  AppState.empty()
      : patients = [],
        alerts = [],
        sessions = [],
        activity = [],
        complaints = [];

  final List<Patient> patients;
  final List<AnomalyAlert> alerts;
  final List<SessionLog> sessions;
  final List<ActivityEvent> activity;
  final List<Complaint> complaints;

  Future<void> Function({
    required String category,
    required String subject,
    required String description,
  })? submitComplaintHandler;

  Future<void> Function(String complaintId, {required String text})? sendComplaintMessageHandler;
  Future<void> Function(String complaintId)? resolveComplaintHandler;

  /// Optional handler provided by a backend repository to persist
  /// notification settings changes (push/urgentOnly/sound) to the server.
  Future<void> Function(String key, Object value)? settingsUpdateHandler;

  /// Optional handler for alert acknowledgements.
  Future<void> Function(String alertId, {required String uid})?
      acknowledgeAlertHandler;

  /// Optional handler for dismissing alerts from the feed.
  Future<void> Function(String alertId, {required String uid})?
      dismissAlertHandler;

  /// Optional handler to claim/link an admin-provisioned device to this
  /// account. Returns null on success, or a human-readable error string.
  /// Provided by the Firebase repository; null in mock mode.
  Future<String?> Function({
    required String deviceId,
    required String patientName,
    required String patientRelation,
    required String room,
  })? claimDeviceHandler;

  /// Optional handler to submit a device request to the admin (request-queue
  /// model: the admin then assigns a provisioned device to this account).
  /// Returns null on success or an error string. Null in mock mode.
  Future<String?> Function({
    required String patientName,
    required String patientRelation,
    required String room,
  })? requestDeviceHandler;

  /// Pending/fulfilled device requests this user has made, newest first.
  List<DeviceRequest> deviceRequests = [];

  void setDeviceRequests(List<DeviceRequest> values) {
    deviceRequests = values;
    notifyListeners();
  }

  Future<String?> requestDevice({
    required String patientName,
    required String patientRelation,
    required String room,
  }) async {
    final handler = requestDeviceHandler;
    if (handler == null) {
      return 'Device requests are only available on the live data connection.';
    }
    return handler(
      patientName: patientName,
      patientRelation: patientRelation,
      room: room,
    );
  }

  void setPatients(List<Patient> values) {
    patients
      ..clear()
      ..addAll(values);
    if (_selectedPatient >= patients.length) {
      _selectedPatient = patients.isEmpty ? 0 : patients.length - 1;
    }
    notifyListeners();
  }

  void setAlerts(List<AnomalyAlert> values) {
    alerts
      ..clear()
      ..addAll(values);
    notifyListeners();
  }

  void setSessions(List<SessionLog> values) {
    sessions
      ..clear()
      ..addAll(values);
    notifyListeners();
  }

  void setActivity(List<ActivityEvent> values) {
    activity
      ..clear()
      ..addAll(values);
    notifyListeners();
  }

  void setComplaints(List<Complaint> values) {
    complaints
      ..clear()
      ..addAll(values);
    notifyListeners();
  }

  void updateComplaint(Complaint updatedComplaint) {
    final index = complaints.indexWhere((complaint) => complaint.id == updatedComplaint.id);
    if (index >= 0) {
      complaints[index] = updatedComplaint;
      notifyListeners();
    }
  }

  void addComplaintMessage(String complaintId, ComplaintMessage message) {
    final index = complaints.indexWhere((complaint) => complaint.id == complaintId);
    if (index < 0) return;

    final existing = complaints[index];
    complaints[index] = existing.copyWith(messages: [...existing.messages, message]);
    notifyListeners();
  }

  Future<void> sendComplaintMessage(String complaintId, String text) async {
    if (sendComplaintMessageHandler != null) {
      await sendComplaintMessageHandler!(complaintId, text: text);
      return;
    }

    final message = ComplaintMessage(
      id: 'local-${DateTime.now().millisecondsSinceEpoch}',
      senderUid: userEmail,
      senderRole: 'app_user',
      text: text,
      sentAt: DateTime.now().toUtc().millisecondsSinceEpoch,
    );
    addComplaintMessage(complaintId, message);
  }

  Future<void> resolveComplaint(String complaintId) async {
    if (resolveComplaintHandler != null) {
      await resolveComplaintHandler!(complaintId);
      return;
    }

    final index = complaints.indexWhere((complaint) => complaint.id == complaintId);
    if (index < 0) return;

    final existing = complaints[index];
    complaints[index] = existing.copyWith(status: ComplaintStatus.resolved);
    notifyListeners();
  }

  String userName = 'Qasim Majid';
  String userEmail = 'qasimmaajid04@gmail.com';
  String userId = '';

  int _selectedPatient = 0;
  int get selectedPatient => _selectedPatient;
  Patient get current => patients.isNotEmpty
      ? patients[_selectedPatient.clamp(0, patients.length - 1)]
      : Patient.empty();

  void selectPatient(int index) {
    if (index == _selectedPatient) return;
    _selectedPatient = index;
    notifyListeners();
  }

  Patient patientById(String id) {
    for (final patient in patients) {
      if (patient.id == id) {
        return patient;
      }
    }
    return Patient.empty();
  }

  int get unacknowledgedUrgent => alerts
      .where((a) => !a.acknowledged && a.severity == AlertSeverity.urgent)
      .length;

  void notifyStateChanged() {
    notifyListeners();
  }

  Future<void> acknowledgeAlert(String id, {required String uid}) async {
    final index = alerts.indexWhere((a) => a.id == id);
    if (index >= 0) {
      alerts[index].acknowledged = true;
      notifyListeners();
    }

    if (acknowledgeAlertHandler != null) {
      await acknowledgeAlertHandler!(id, uid: uid);
    }
  }

  Future<void> dismissAlert(String id, {required String uid}) async {
    final before = alerts.length;
    alerts.removeWhere((a) => a.id == id);
    if (alerts.length != before) {
      notifyListeners();
    }

    if (dismissAlertHandler != null) {
      await dismissAlertHandler!(id, uid: uid);
    }
  }

  /// Dismisses every alert currently in the feed, one at a time through the
  /// same [dismissAlertHandler] used for single dismissals so each alert is
  /// still marked dismissed/dismissedBy on the backend.
  Future<void> dismissAllAlerts({required String uid}) async {
    final ids = alerts.map((a) => a.id).toList();
    if (ids.isEmpty) return;

    alerts.clear();
    notifyListeners();

    if (dismissAlertHandler != null) {
      for (final id in ids) {
        await dismissAlertHandler!(id, uid: uid);
      }
    }
  }

  /// Claims an admin-provisioned device and links it to this account. The real
  /// work is a Firebase transaction in the repository (see [claimDeviceHandler]),
  /// which only succeeds if the device exists and is currently unassigned. Once
  /// linked, the device's live data flows in through the normal listeners — the
  /// patient is NOT fabricated locally. Returns null on success or an error
  /// message to show the user.
  Future<String?> claimDevice({
    required String deviceId,
    required String patientName,
    required String patientRelation,
    required String room,
  }) async {
    final handler = claimDeviceHandler;
    if (handler == null) {
      return 'Device linking is only available on the live data connection.';
    }
    return handler(
      deviceId: deviceId,
      patientName: patientName,
      patientRelation: patientRelation,
      room: room,
    );
  }

  void submitComplaint({
    required String category,
    required String subject,
    required String description,
  }) {
    if (submitComplaintHandler != null) {
      submitComplaintHandler!(
        category: category,
        subject: subject,
        description: description,
      ).catchError((_) {});
      return;
    }

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

  void addComplaint(Complaint complaint) {
    complaints.insert(0, complaint);
    notifyListeners();
  }

  // Notification preferences (Settings screen).
  bool pushEnabled = true;
  bool urgentOnly = false;
  bool soundEnabled = true;

  void setPush(bool v) {
    if (pushEnabled == v) return;
    pushEnabled = v;
    if (settingsUpdateHandler != null) {
      settingsUpdateHandler!('pushEnabled', v).catchError((_) {});
    }
    notifyListeners();
  }

  void setUrgentOnly(bool v) {
    if (urgentOnly == v) return;
    urgentOnly = v;
    if (settingsUpdateHandler != null) {
      settingsUpdateHandler!('urgentOnly', v).catchError((_) {});
    }
    notifyListeners();
  }

  void setSound(bool v) {
    if (soundEnabled == v) return;
    soundEnabled = v;
    if (settingsUpdateHandler != null) {
      settingsUpdateHandler!('soundEnabled', v).catchError((_) {});
    }
    notifyListeners();
  }
}
