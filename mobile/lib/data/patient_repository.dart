import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../auth/auth_models.dart';
import '../models.dart';

class PatientRepository {
  PatientRepository({
    required this._user,
    required this._appState,
    FirebaseDatabase? database,
  }) : _db = database ?? FirebaseDatabase.instance {
    debugPrint('PatientRepository: init for uid=${_user.uid} linked=${_user.linkedDeviceIds}');
    _appState.submitComplaintHandler = _submitComplaint;
    _appState.sendComplaintMessageHandler = _sendComplaintMessage;
    _appState.resolveComplaintHandler = _resolveComplaint;
    // Persist settings changes to RTDB when toggles change in the UI.
    _appState.settingsUpdateHandler = (key, value) async {
      try {
        await _db.ref('users/${_user.uid}/settings/$key').set(value);
      } catch (_) {}
    };

    _appState.acknowledgeAlertHandler = _acknowledgeAlert;
    _appState.dismissAlertHandler = _dismissAlert;

    _listenUserSettings();
    _listenComplaints();
    _listenDevices();
    _registerFcmToken();
  }

  void _listenUserSettings() {
    final ref = _db.ref('users/${_user.uid}/settings');
    _subscriptions.add(ref.onValue.listen((event) {
      if (_disposed) return;
      final raw = event.snapshot.value;
      if (raw == null) return;
      try {
        final map = _castMap(raw as Map?);
        _appState.setPush(map['pushEnabled'] == true);
        _appState.setUrgentOnly(map['urgentOnly'] == true);
        _appState.setSound(map['soundEnabled'] == true);
      } catch (_) {}
    }));
  }

  final AuthUser _user;
  final AppState _appState;
  final FirebaseDatabase _db;
  final Map<String, _DeviceState> _deviceStates = {};
  final List<StreamSubscription<DatabaseEvent>> _subscriptions = [];
  bool _disposed = false;

  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _appState.submitComplaintHandler = null;
    _appState.sendComplaintMessageHandler = null;
    _appState.resolveComplaintHandler = null;
    _appState.acknowledgeAlertHandler = null;
    _appState.dismissAlertHandler = null;
    _disposed = true;
  }

  void _listenDevices() {
    if (_user.linkedDeviceIds.isEmpty) {
      _refreshAppState();
      return;
    }

    for (final deviceId in _user.linkedDeviceIds) {
      _bindDevice(deviceId);
    }
  }

  Future<void> _bindDevice(String deviceId) async {
    if (_disposed) return;

    _deviceStates[deviceId] = _DeviceState();

    try {
      final metaSnapshot = await _db.ref('devices/$deviceId/meta').get();
      debugPrint('Device $deviceId meta exists=${metaSnapshot.exists}');
      if (metaSnapshot.exists && metaSnapshot.value is Map) {
        _deviceStates[deviceId]!.meta
          ..clear()
          ..addAll(_castMap(metaSnapshot.value as Map));
      }
    } catch (_) {
      // Ignore one-time meta failures; we still want live updates if available.
    }

    _subscriptions.add(_db.ref('devices/$deviceId/live').onValue.listen((event) {
      if (_disposed) return;
      debugPrint('Device $deviceId live snapshot: ${event.snapshot.exists}');
      _deviceStates[deviceId]!.live
        ..clear()
        ..addAll(_castMap(event.snapshot.value as Map?));
      _refreshAppState();
    }));

    _subscriptions.add(_db.ref('devices/$deviceId/health').onValue.listen((event) {
      if (_disposed) return;
      _deviceStates[deviceId]!.health
        ..clear()
        ..addAll(_castMap(event.snapshot.value as Map?));
      _refreshAppState();
    }));

    _subscriptions.add(_db.ref('alerts/$deviceId').onValue.listen((event) {
      if (_disposed) return;
      _deviceStates[deviceId]!.alerts
        ..clear()
        ..addAll(_castMap(event.snapshot.value as Map?));
      _refreshAppState();
    }));

    _subscriptions.add(_db.ref('devices/$deviceId/sessions').onValue.listen((event) {
      if (_disposed) return;
      _deviceStates[deviceId]!.sessions
        ..clear()
        ..addAll(_castMap(event.snapshot.value as Map?));
      _refreshAppState();
    }));

    _refreshAppState();
  }

  void _listenComplaints() {
    final complaintsQuery = _db
        .ref('complaints')
        .orderByChild('uid')
        .equalTo(_user.uid);
    _subscriptions.add(complaintsQuery.onValue.listen((event) {
      if (_disposed) return;
      final raw = _castMap(event.snapshot.value as Map?);
      _appState.setComplaints(_buildComplaints(raw));
    }));
  }

  Future<void> _registerFcmToken() async {
    if (_disposed) return;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: true,
      );
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;
      await _db.ref('users/${_user.uid}/fcmTokens/$token').set(true);

      messaging.onTokenRefresh.listen((newToken) async {
        if (_disposed) return;
        try {
          await _db.ref('users/${_user.uid}/fcmTokens/$newToken').set(true);
        } catch (_) {}
      });
    } catch (_) {}
  }

  Future<void> _acknowledgeAlert(String alertId, {required String uid}) async {
    if (_disposed) return;
    final alertRef = await _findAlertReference(alertId);
    if (alertRef == null) return;

    await alertRef.update({
      'acknowledged': true,
      'acknowledgedBy': uid,
    });

    final index = _appState.alerts.indexWhere((alert) => alert.id == alertId);
    if (index >= 0) {
      _appState.alerts[index].acknowledged = true;
      _appState.notifyStateChanged();
    }
  }

  Future<void> _dismissAlert(String alertId, {required String uid}) async {
    if (_disposed) return;
    final alertRef = await _findAlertReference(alertId);
    if (alertRef == null) return;

    await alertRef.update({
      'dismissed': true,
      'dismissedBy': uid,
    });

    _appState.alerts.removeWhere((alert) => alert.id == alertId);
    _appState.notifyStateChanged();
  }

  Future<DatabaseReference?> _findAlertReference(String alertId) async {
    for (final entry in _deviceStates.entries) {
      final deviceId = entry.key;
      final alertNode = _db.ref('alerts/$deviceId/$alertId');
      final snapshot = await alertNode.get();
      if (snapshot.exists) {
        return alertNode;
      }
    }
    return null;
  }

  Future<void> _submitComplaint({
    required String category,
    required String subject,
    required String description,
  }) async {
    final complaintsRef = _db.ref('complaints').push();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final complaintData = {
      'uid': _user.uid,
      'category': category,
      'subject': subject,
      'description': description,
      'status': 'open',
      'messages': {},
      'adminResponse': null,
      'createdAt': ServerValue.timestamp,
      'updatedAt': ServerValue.timestamp,
    };

    await complaintsRef.set(complaintData);

    _appState.addComplaint(Complaint(
      id: complaintsRef.key ?? now.toString(),
      category: category,
      subject: subject,
      description: description,
      status: ComplaintStatus.open,
      date: 'Just now',
    ));
  }

  Future<void> _sendComplaintMessage(String complaintId, {required String text}) async {
    if (_disposed) return;

    final complaintRef = _db.ref('complaints/$complaintId');
    final messageRef = complaintRef.child('messages').push();
    await messageRef.set({
      'senderUid': _user.uid,
      'senderRole': 'app_user',
      'text': text,
      'sentAt': ServerValue.timestamp,
    });

    // No optimistic local add: the live `_listenComplaints` onValue listener
    // already re-delivers this message (keyed by messageRef.key) the moment
    // the write lands, so adding it here too showed the message twice until
    // the next full server rebuild deduped it. The listener is the single
    // source of truth for the thread.
  }

  Future<void> _resolveComplaint(String complaintId) async {
    if (_disposed) return;

    await _db.ref('complaints/$complaintId').update({
      'status': 'resolved',
      'updatedAt': ServerValue.timestamp,
    });

    final index = _appState.complaints.indexWhere((complaint) => complaint.id == complaintId);
    if (index >= 0) {
      final existing = _appState.complaints[index];
      _appState.complaints[index] = existing.copyWith(status: ComplaintStatus.resolved);
      _appState.setComplaints(_appState.complaints.toList());
    }
  }

  void _refreshAppState() {
    final patients = _buildPatients();
    final alerts = _buildAlerts();
    final sessions = _buildSessions();
    final activity = _buildActivity(alerts, sessions);

    _appState.setPatients(patients);
    _appState.setAlerts(alerts);
    _appState.setSessions(sessions);
    _appState.setActivity(activity);
  }

  List<Patient> _buildPatients() {
    final devices = _deviceStates.entries.map((entry) {
      return _buildPatient(entry.key, entry.value);
    }).where((p) => p != null).cast<Patient>().toList();
    return devices;
  }

  Patient? _buildPatient(String deviceId, _DeviceState state) {
    final meta = state.meta;
    final live = state.live;
    final health = state.health;

    final name = meta['patientName']?.toString() ?? deviceId;
    final relation = meta['patientRelation']?.toString() ?? '';
    final room = meta['room']?.toString() ?? '';
    final normalLow = _toInt(meta['normalLow']);
    final normalHigh = _toInt(meta['normalHigh']);
    final firmware = meta['firmware']?.toString() ?? '';

    final status = _mapBreathStatus(live['status']?.toString());
    final bpm = _toInt(live['bpm']);
    final confidence = _toDouble(live['confidence']);
    final signalQuality = _toDouble(live['signalQuality']);
    final online = health['online'] == true;
    final lastSync = _formatRelativeTimestamp(
      _toInt(health['lastSeen']) != 0
          ? _toInt(health['lastSeen'])
          : _toInt(live['updatedAt']),
    );

    return Patient(
      id: deviceId,
      name: name,
      relation: relation,
      room: room,
      deviceName: _buildDeviceName(deviceId),
      deviceId: deviceId,
      online: online,
      signalQuality: signalQuality,
      confidence: confidence,
      bpm: status == BreathStatus.normal ? bpm : 0,
      status: status,
      normalLow: normalLow,
      normalHigh: normalHigh,
      trend: _buildTrend(status, bpm),
      nightlyAvg: _buildNightlyAvg(status, bpm),
      distribution: _defaultDistribution(),
      firmware: firmware,
      lastSync: lastSync,
    );
  }

  List<AnomalyAlert> _buildAlerts() {
    final alerts = <AnomalyAlert>[];
    for (final entry in _deviceStates.entries) {
      final deviceId = entry.key;
      final rawAlerts = entry.value.alerts;
      for (final alertEntry in rawAlerts.entries) {
        final id = alertEntry.key;
        final raw = _castMap(alertEntry.value as Map?);
        final severity = _mapSeverity(raw['severity']?.toString());
        final type = raw['type']?.toString() ?? '';
        final summary = raw['summary']?.toString() ?? '';
        final detail = _castStringMap(raw['detail'] as Map?);
        final raisedAt = _toInt(raw['raisedAt']);
        final time = _formatTime(raisedAt);
        final day = _formatDayLabel(raisedAt);

        alerts.add(AnomalyAlert(
          id: id,
          patientId: deviceId,
          title: summary.isNotEmpty
              ? summary.split('.').first
              : _humanizeAlertType(type),
          severity: severity,
          time: time,
          day: day,
          summary: summary,
          detail: detail,
          acknowledged: raw['acknowledged'] == true,
        ));
      }
    }

    alerts.sort((a, b) => _parseEventTime(b.day, b.time)
        .compareTo(_parseEventTime(a.day, a.time)));
    return alerts;
  }

  List<SessionLog> _buildSessions() {
    final sessions = <SessionLog>[];
    for (final entry in _deviceStates.entries) {
      final deviceId = entry.key;
      final rawSessions = entry.value.sessions;
      final patientName = entry.value.meta['patientName']?.toString() ?? deviceId;

      for (final sessionEntry in rawSessions.entries) {
        final raw = _castMap(sessionEntry.value as Map?);
        final startedAt = _toInt(raw['startedAt']);
        final endedAt = _toInt(raw['endedAt']);
        if (endedAt == 0 || startedAt == 0) {
          continue;
        }
        final avgBpm = _toDouble(raw['avgBpm']);
        final minBpm = _toInt(raw['minBpm']);
        final maxBpm = _toInt(raw['maxBpm']);
        final quality = _toInt(raw['validPct']);
        final day = _formatDayLabel(endedAt);
        final time = _formatTime(endedAt);
        final duration = _formatDuration(endedAt - startedAt);

        sessions.add(SessionLog(
          patientId: deviceId,
          title: 'Night session — $patientName',
          day: day,
          time: time,
          duration: duration,
          avgBpm: avgBpm,
          minBpm: minBpm,
          maxBpm: maxBpm,
          quality: quality,
        ));
      }
    }

    sessions.sort((a, b) => _parseEventTime(b.day, b.time)
        .compareTo(_parseEventTime(a.day, a.time)));
    return sessions;
  }

  List<ActivityEvent> _buildActivity(
      List<AnomalyAlert> alerts, List<SessionLog> sessions) {
    final events = <_TimedActivity>[];

    for (final alert in alerts) {
      final patientName = _deviceStates[alert.patientId]?.meta['patientName']?.toString() ?? alert.patientId;
      final room = _deviceStates[alert.patientId]?.meta['room']?.toString() ?? '';
      final title = _capitalized(alert.title);
      final subtitle = '$patientName · ${room.isNotEmpty ? room : alert.patientId}';
      events.add(_TimedActivity(
        ActivityEvent(
          title: title,
          subtitle: subtitle,
          time: alert.time,
          kind: 'alert',
        ),
        _parseEventTime(alert.day, alert.time),
      ));
    }

    for (final session in sessions) {
      final patientName = _deviceStates[session.patientId]?.meta['patientName']?.toString() ?? session.patientId;
      events.add(_TimedActivity(
        ActivityEvent(
          title: 'Night session ended',
          subtitle: '$patientName · ${session.duration} · avg ${session.avgBpm.toStringAsFixed(1)} bpm',
          time: session.time,
          kind: 'session',
        ),
        _parseEventTime(session.day, session.time),
      ));
    }

    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return events.map((e) => e.event).toList();
  }

  List<Complaint> _buildComplaints(Map<String, dynamic> raw) {
    final complaints = <Complaint>[];
    for (final entry in raw.entries) {
      final id = entry.key;
      final value = _castMap(entry.value as Map?);
      final createdAt = _toInt(value['createdAt']);
      final messages = <ComplaintMessage>[];
      final rawMessages = value['messages'];
      if (rawMessages is Map) {
        for (final messageEntry in rawMessages.entries) {
          final messageValue = _castMap(messageEntry.value as Map?);
          messages.add(ComplaintMessage(
            id: messageEntry.key.toString(),
            senderUid: messageValue['senderUid']?.toString() ?? '',
            senderRole: messageValue['senderRole']?.toString() ?? 'app_user',
            text: messageValue['text']?.toString() ?? '',
            sentAt: _toInt(messageValue['sentAt']),
          ));
        }
      }
      messages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
      complaints.add(Complaint(
        id: id,
        category: value['category']?.toString() ?? 'Other',
        subject: value['subject']?.toString() ?? '',
        description: value['description']?.toString() ?? '',
        status: _mapComplaintStatus(value['status']?.toString()),
        date: _formatRelativeTimestamp(createdAt),
        messages: messages,
      ));
    }

    complaints.sort((a, b) => _parseEventTime(_formatDayLabelFromDate(b.date), b.date)
        .compareTo(_parseEventTime(_formatDayLabelFromDate(a.date), a.date)));
    return complaints;
  }

  Map<String, dynamic> _castMap(Map? raw) {
    if (raw == null) return {};
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }

  Map<String, String> _castStringMap(Map? raw) {
    if (raw == null) return {};
    return raw.map((key, value) => MapEntry(key.toString(), value?.toString() ?? ''));
  }

  int _toInt(Object? value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  double _toDouble(Object? value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  BreathStatus _mapBreathStatus(String? status) {
    return switch (status) {
      'ok' => BreathStatus.normal,
      'no_breathing' => BreathStatus.noBreathing,
      'low_signal' || 'calibrating' => BreathStatus.lowSignal,
      _ => BreathStatus.lowSignal,
    };
  }

  AlertSeverity _mapSeverity(String? severity) {
    return switch (severity) {
      'urgent' => AlertSeverity.urgent,
      'warning' => AlertSeverity.warning,
      'info' => AlertSeverity.info,
      _ => AlertSeverity.info,
    };
  }

  ComplaintStatus _mapComplaintStatus(String? status) {
    return switch (status) {
      'open' => ComplaintStatus.open,
      'in_progress' => ComplaintStatus.inProgress,
      'resolved' => ComplaintStatus.resolved,
      _ => ComplaintStatus.open,
    };
  }

  String _buildDeviceName(String deviceId) {
    final suffix = deviceId.split('-').last.toUpperCase();
    return 'Wi-Health Sense $suffix';
  }

  List<double> _buildTrend(BreathStatus status, int bpm) {
    if (status != BreathStatus.normal || bpm == 0) {
      return List<double>.filled(12, 0.0);
    }
    return List<double>.generate(12, (index) {
      final offset = ((index % 3) - 1) * 0.6;
      return (bpm + offset).clamp(0, 60);
    });
  }

  List<double> _buildNightlyAvg(BreathStatus status, int bpm) {
    if (status != BreathStatus.normal || bpm == 0) {
      return List<double>.filled(7, 0.0);
    }
    return List<double>.generate(7, (index) {
      return (bpm + (index % 2 == 0 ? 0.4 : -0.3)).clamp(0, 60);
    });
  }

  List<double> _defaultDistribution() {
    return const [0.03, 0.10, 0.22, 0.30, 0.22, 0.10, 0.03];
  }

  String _formatRelativeTimestamp(int epochMs) {
    if (epochMs <= 0) return 'never';
    final date = DateTime.fromMillisecondsSinceEpoch(epochMs).toLocal();
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} m ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${date.month}/${date.day}/${date.year % 100}';
  }

  String _formatTime(int epochMs) {
    if (epochMs <= 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(epochMs).toLocal();
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final suffix = date.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $suffix';
  }

  String _formatDuration(int milliseconds) {
    if (milliseconds <= 0) return '0 m';
    final duration = Duration(milliseconds: milliseconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return '$hours h $minutes m';
    }
    return '$minutes m';
  }

  String _formatDayLabel(int epochMs) {
    if (epochMs <= 0) return 'Today';
    final date = DateTime.fromMillisecondsSinceEpoch(epochMs).toLocal();
    final now = DateTime.now();
    final diff = now.difference(DateTime(date.year, date.month, date.day));
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    return '${date.month}/${date.day}/${date.year % 100}';
  }

  String _humanizeAlertType(String type) {
    return type
        .split('_')
        .map((part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String _capitalized(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  DateTime _parseEventTime(String dayLabel, String timeLabel) {
    final now = DateTime.now();
    final time = _parseTimeOfDay(timeLabel);
    if (dayLabel == 'Today') {
      return DateTime(now.year, now.month, now.day, time.hour, time.minute);
    }
    if (dayLabel == 'Yesterday') {
      final yesterday = now.subtract(const Duration(days: 1));
      return DateTime(yesterday.year, yesterday.month, yesterday.day, time.hour, time.minute);
    }
    final parts = dayLabel.split('/');
    if (parts.length == 3) {
      final month = int.tryParse(parts[0]) ?? now.month;
      final day = int.tryParse(parts[1]) ?? now.day;
      final year = 2000 + (int.tryParse(parts[2]) ?? now.year % 100);
      return DateTime(year, month, day, time.hour, time.minute);
    }
    return now;
  }

  TimeOfDay _parseTimeOfDay(String timeLabel) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)').firstMatch(timeLabel.trim());
    if (match != null) {
      final hour = int.parse(match.group(1)!);
      final minute = int.parse(match.group(2)!);
      final isPm = match.group(3) == 'PM';
      final normalizedHour = hour == 12 ? (isPm ? 12 : 0) : (isPm ? hour + 12 : hour);
      return TimeOfDay(hour: normalizedHour, minute: minute);
    }
    return const TimeOfDay(hour: 0, minute: 0);
  }

  String _formatDayLabelFromDate(String label) {
    if (label == 'Today' || label == 'Yesterday') return label;
    final parts = label.split('/');
    if (parts.length == 3) {
      final month = int.tryParse(parts[0]);
      final day = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (month != null && day != null && year != null) {
        final date = DateTime(2000 + year, month, day);
        final now = DateTime.now();
        final diff = now.difference(DateTime(date.year, date.month, date.day));
        if (diff.inDays == 0) return 'Today';
        if (diff.inDays == 1) return 'Yesterday';
      }
    }
    return label;
  }
}

class _DeviceState {
  final Map<String, dynamic> meta = {};
  final Map<String, dynamic> live = {};
  final Map<String, dynamic> health = {};
  final Map<String, dynamic> alerts = {};
  final Map<String, dynamic> sessions = {};
}

class _TimedActivity {
  _TimedActivity(this.event, this.timestamp);

  final ActivityEvent event;
  final DateTime timestamp;
}
