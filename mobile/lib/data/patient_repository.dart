import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../auth/auth_models.dart';
import '../models.dart';

class PatientRepository {
  /// A device is considered offline / its reading stale if the newest
  /// live.updatedAt is older than this. The device writes every ~5 s (stride),
  /// so ~20 s tolerates a couple of missed writes without false-flapping, while
  /// still flipping to offline quickly when the device actually stops.
  static const int _deviceStaleMs = 20000;

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
    _appState.claimDeviceHandler = _claimDevice;
    _appState.requestDeviceHandler = _requestDevice;

    _listenUserSettings();
    _listenComplaints();
    _listenDeviceRequests();
    _listenDevices();
    _registerFcmToken();

    // Re-evaluate liveness periodically even when NO new Firebase data arrives:
    // if the device dies, updates simply stop, so without this tick the stale
    // reading would never be recomputed. Every few seconds we rebuild patients,
    // which re-runs the updatedAt-freshness check and flips a dead device to
    // offline / no-valid-breathing.
    _staleTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_disposed) return;
      _refreshAppState();
    });
  }

  Timer? _staleTimer;

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
    _staleTimer?.cancel();
    _staleTimer = null;
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _appState.submitComplaintHandler = null;
    _appState.sendComplaintMessageHandler = null;
    _appState.resolveComplaintHandler = null;
    _appState.acknowledgeAlertHandler = null;
    _appState.dismissAlertHandler = null;
    _appState.claimDeviceHandler = null;
    _appState.requestDeviceHandler = null;
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
      _maybeLogHistorySample(deviceId);
      _refreshAppState();
    }));

    // Keep the last 7 days of bpm samples in memory for the History charts.
    // Ordered by key (epochMs) and capped server-side to the recent window so
    // this never pulls the whole history.
    final sevenDaysAgo =
        DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    _subscriptions.add(_db
        .ref('devices/$deviceId/history')
        .orderByKey()
        .startAt(sevenDaysAgo.toString())
        .onValue
        .listen((event) {
      if (_disposed) return;
      _deviceStates[deviceId]!.history
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

    /* Sessions are derived from the logged history samples (see _buildSessions),
     * so there is no /sessions listener — the firmware never writes that node. */

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

  void _listenDeviceRequests() {
    final query = _db
        .ref('deviceRequests')
        .orderByChild('uid')
        .equalTo(_user.uid);
    _subscriptions.add(query.onValue.listen((event) {
      if (_disposed) return;
      final raw = _castMap(event.snapshot.value as Map?);
      _appState.setDeviceRequests(_buildDeviceRequests(raw));
    }));
  }

  List<DeviceRequest> _buildDeviceRequests(Map<String, dynamic> raw) {
    final requests = <DeviceRequest>[];
    raw.forEach((id, value) {
      final r = _castMap(value as Map?);
      requests.add(DeviceRequest(
        id: id,
        patientName: r['patientName']?.toString() ?? 'Patient',
        patientRelation: r['patientRelation']?.toString() ?? '',
        room: r['room']?.toString() ?? '',
        status: switch (r['status']?.toString()) {
          'fulfilled' => DeviceRequestStatus.fulfilled,
          'declined' => DeviceRequestStatus.declined,
          _ => DeviceRequestStatus.pending,
        },
        createdAt: DateTime.fromMillisecondsSinceEpoch(_toInt(r['createdAt'])),
      ));
    });
    requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return requests;
  }

  /// Submit a device request to the admin queue. The admin fulfils it by
  /// assigning a provisioned device. Returns null on success, else an error.
  Future<String?> _requestDevice({
    required String patientName,
    required String patientRelation,
    required String room,
  }) async {
    if (patientName.trim().isEmpty || room.trim().isEmpty) {
      return 'Please add the patient’s name and room.';
    }
    // One open request at a time keeps the admin queue clean.
    final hasPending = _appState.deviceRequests
        .any((r) => r.status == DeviceRequestStatus.pending);
    if (hasPending) {
      return 'You already have a pending request. Your admin will action it soon.';
    }
    try {
      await _db.ref('deviceRequests').push().set({
        'uid': _user.uid,
        'patientName': patientName.trim(),
        'patientRelation': patientRelation.trim(),
        'room': room.trim(),
        'status': 'pending',
        'createdAt': ServerValue.timestamp,
      });
    } catch (_) {
      return 'Could not send the request. Please try again.';
    }
    return null;
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

  /// Claim an admin-provisioned device for this account. Uses a transaction on
  /// devices/$id/meta so the claim is atomic and race-safe: it only succeeds if
  /// the device exists and is currently unassigned (ownerUid empty). This — plus
  /// the security rule that only lets a user set ownerUid to their own uid when
  /// it was empty — is what stops one user from claiming another's device.
  /// Returns null on success, or a user-facing error message.
  Future<String?> _claimDevice({
    required String deviceId,
    required String patientName,
    required String patientRelation,
    required String room,
  }) async {
    final id = deviceId.trim();
    if (id.isEmpty) return 'Enter the device ID from your administrator.';

    final metaRef = _db.ref('devices/$id/meta');

    // Fail fast with a clear message if the device was never provisioned.
    final existing = await metaRef.get();
    if (!existing.exists) {
      return 'No device found with that ID. Check the ID your admin gave you.';
    }
    final existingMeta = _castMap(existing.value as Map?);
    final currentOwner = existingMeta['ownerUid']?.toString() ?? '';
    if (currentOwner.isNotEmpty && currentOwner != _user.uid) {
      return 'That device is already linked to another account.';
    }
    if (currentOwner == _user.uid) {
      return 'That device is already linked to your account.';
    }

    TransactionResult result;
    try {
      result = await metaRef.runTransaction((current) {
        final meta = current == null
            ? <String, Object?>{}
            : Map<String, Object?>.from(current as Map);
        final owner = meta['ownerUid']?.toString() ?? '';
        // Someone else won the race between our read and the transaction.
        if (owner.isNotEmpty) return Transaction.abort();
        meta['ownerUid'] = _user.uid;
        meta['patientName'] = patientName;
        meta['patientRelation'] = patientRelation;
        meta['room'] = room;
        return Transaction.success(meta);
      });
    } catch (_) {
      return 'Could not link the device. Please try again.';
    }

    if (!result.committed) {
      return 'That device was just linked to another account.';
    }

    // Add the device to this user's switcher. If this write fails the meta
    // owner is still set to us, so a retry of the claim is harmless.
    try {
      await _db.ref('users/${_user.uid}/devices/$id').set(true);
    } catch (_) {
      return 'Device linked, but adding it to your list failed. Pull to refresh.';
    }

    return null;
  }

  /// Append the current live bpm to devices/$id/history for the History charts.
  /// Only logs valid, fresh 'ok' readings, throttled to one sample per minute
  /// per device so a 5 s live stream doesn't flood the DB. Owner-writable by the
  /// security rules (the app, not the device, records history).
  static const int _historyThrottleMs = 60000;

  void _maybeLogHistorySample(String deviceId) {
    final state = _deviceStates[deviceId];
    if (state == null) return;
    final live = state.live;
    if (live['status']?.toString() != 'ok') return;

    final bpm = _toDouble(live['bpm']);
    if (bpm <= 0) return;

    final updatedAt = _toInt(live['updatedAt']);
    final now = DateTime.now().millisecondsSinceEpoch;
    // Ignore stale readings (same freshness rule as the live view).
    if (updatedAt == 0 || now - updatedAt >= _deviceStaleMs) return;

    if (now - state.lastHistoryWriteMs < _historyThrottleMs) return;
    state.lastHistoryWriteMs = now;

    // Key by wall-clock time so day-bucketing is straightforward.
    _db.ref('devices/$deviceId/history/$now').set(bpm).catchError((_) {});
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

    var status = _mapBreathStatus(live['status']?.toString());
    var bpm = _toInt(live['bpm']);
    final confidence = _toDouble(live['confidence']);
    final signalQuality = _toDouble(live['signalQuality']);

    // Liveness is judged by DATA FRESHNESS, not just the health.online flag: a
    // device that loses power/WiFi cannot flip online=false, so that flag can
    // sit stale-true forever. The device writes live.updatedAt every ~5 s, so
    // if the newest value is older than _deviceStaleMs the device is effectively
    // offline — and a stale breathing rate must NOT be shown as current.
    final lastUpdate = _toInt(live['updatedAt']) != 0
        ? _toInt(live['updatedAt'])
        : _toInt(health['lastSeen']);
    final ageMs = DateTime.now().millisecondsSinceEpoch - lastUpdate;
    final fresh = lastUpdate != 0 && ageMs >= 0 && ageMs < _deviceStaleMs;
    final online = fresh && (health['online'] == true);
    if (!fresh) {
      // stale data: don't present an old rate as if it were live
      status = BreathStatus.noBreathing;
      bpm = 0;
    }
    final lastSync = _formatRelativeTimestamp(lastUpdate);

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
      trend: _buildTrend(state.history),
      nightlyAvg: _buildNightlyAvg(state.history),
      distribution: _buildDistribution(state.history, normalLow, normalHigh),
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
        // Dismissed alerts are hidden from the feed. Without this the onValue
        // listener re-adds a just-dismissed alert on the next sync, so it would
        // reappear moments after the user taps Dismiss.
        if (raw['dismissed'] == true) continue;
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

  /// A run of logged samples with no gap larger than this is one "session".
  /// (The app logs a valid bpm ~once/min, so a >10 min gap means monitoring
  /// stopped — a new session starts after it.)
  static const int _sessionGapMs = 10 * 60 * 1000;
  static const int _historyLogMs = 60 * 1000; // matches _historyThrottleMs
  static const int _minSessionSamples = 3;    // ignore trivially short runs

  /// Derive sessions from the real logged bpm history (devices/$id/history).
  /// The firmware only streams live/alerts; history is what the app records, so
  /// sessions are computed from those samples rather than a device-written node
  /// — honest, and needs no firmware change.
  List<SessionLog> _buildSessions() {
    final sessions = <SessionLog>[];
    for (final entry in _deviceStates.entries) {
      final deviceId = entry.key;
      final patientName = entry.value.meta['patientName']?.toString() ?? deviceId;
      final samples = _historySamples(entry.value.history); // sorted (ts, bpm)
      if (samples.length < _minSessionSamples) continue;

      var runStart = 0;
      for (var i = 1; i <= samples.length; i++) {
        final boundary = i == samples.length ||
            (samples[i].key - samples[i - 1].key) > _sessionGapMs;
        if (!boundary) continue;

        final run = samples.sublist(runStart, i);
        runStart = i;
        if (run.length < _minSessionSamples) continue;

        final startedAt = run.first.key;
        final endedAt = run.last.key;
        final bpms = run.map((e) => e.value).toList();
        final avgBpm = bpms.reduce((a, b) => a + b) / bpms.length;
        final minBpm = bpms.reduce((a, b) => a < b ? a : b).round();
        final maxBpm = bpms.reduce((a, b) => a > b ? a : b).round();

        // Continuity %: how much of the span actually produced valid samples
        // (100% = a sample every ~minute with no dropouts).
        final spanMs = endedAt - startedAt;
        final expected = spanMs <= 0 ? run.length : (spanMs ~/ _historyLogMs) + 1;
        final quality = ((run.length / (expected == 0 ? 1 : expected)) * 100)
            .clamp(0, 100)
            .round();

        sessions.add(SessionLog(
          patientId: deviceId,
          title: 'Monitoring — $patientName',
          day: _formatDayLabel(endedAt),
          time: _formatTime(endedAt),
          duration: _formatDuration(spanMs),
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

  /// Parse the raw history map into (epochMs, bpm) samples sorted by time,
  /// keeping only positive bpm (valid readings we logged).
  List<MapEntry<int, double>> _historySamples(Map<String, dynamic> history) {
    final samples = <MapEntry<int, double>>[];
    for (final entry in history.entries) {
      final ts = int.tryParse(entry.key) ?? 0;
      final bpm = _toDouble(entry.value);
      if (ts > 0 && bpm > 0) samples.add(MapEntry(ts, bpm));
    }
    samples.sort((a, b) => a.key.compareTo(b.key));
    return samples;
  }

  /// Recent-trend sparkline: the last 12 real logged bpm samples. Empty (zeros)
  /// until enough samples exist.
  List<double> _buildTrend(Map<String, dynamic> history) {
    final samples = _historySamples(history);
    if (samples.isEmpty) return List<double>.filled(12, 0.0);
    final recent = samples.length <= 12
        ? samples
        : samples.sublist(samples.length - 12);
    final values = recent.map((e) => e.value).toList();
    // Left-pad with zeros so the sparkline keeps a stable width early on.
    if (values.length < 12) {
      return [...List<double>.filled(12 - values.length, 0.0), ...values];
    }
    return values;
  }

  /// Real nightly average for the last 7 calendar days: mean of the day's
  /// logged samples, 0.0 for days with no data. Index 0 = 6 days ago .. 6 = today.
  List<double> _buildNightlyAvg(Map<String, dynamic> history) {
    final samples = _historySamples(history);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sums = List<double>.filled(7, 0.0);
    final counts = List<int>.filled(7, 0);
    for (final s in samples) {
      final d = DateTime.fromMillisecondsSinceEpoch(s.key);
      final day = DateTime(d.year, d.month, d.day);
      final idx = 6 - today.difference(day).inDays;
      if (idx >= 0 && idx < 7) {
        sums[idx] += s.value;
        counts[idx]++;
      }
    }
    return List<double>.generate(
        7, (i) => counts[i] == 0 ? 0.0 : sums[i] / counts[i]);
  }

  /// Real rate distribution (share of time per bpm bucket) computed from the
  /// logged samples, using 7 buckets spanning the patient's normal band ±. All
  /// zeros until samples exist.
  List<double> _buildDistribution(
      Map<String, dynamic> history, int normalLow, int normalHigh) {
    final samples = _historySamples(history);
    if (samples.isEmpty) return List<double>.filled(7, 0.0);

    final low = (normalLow - 6).toDouble();
    final high = (normalHigh + 8).toDouble();
    final span = (high - low).clamp(1, double.infinity);
    final step = span / 7;
    final buckets = List<double>.filled(7, 0.0);
    for (final s in samples) {
      var idx = ((s.value - low) / step).floor();
      if (idx < 0) idx = 0;
      if (idx > 6) idx = 6;
      buckets[idx]++;
    }
    final total = samples.length.toDouble();
    return buckets.map((c) => c / total).toList();
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
  // Real bpm samples logged over time: { epochMs(String) : bpm(num) }.
  // Populated from devices/$id/history and used to compute the History charts.
  final Map<String, dynamic> history = {};
  // Throttle: last epochMs we wrote a history sample for this device.
  int lastHistoryWriteMs = 0;
}

class _TimedActivity {
  _TimedActivity(this.event, this.timestamp);

  final ActivityEvent event;
  final DateTime timestamp;
}
