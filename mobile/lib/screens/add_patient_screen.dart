import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Pair a device and link it to a new patient — the flow behind the
/// Home "+ Add Patient" action and Profile → Pair New Device.
class AddPatientScreen extends StatefulWidget {
  const AddPatientScreen({super.key, required this.app});

  final AppState app;

  @override
  State<AddPatientScreen> createState() => _AddPatientScreenState();
}

class _AddPatientScreenState extends State<AddPatientScreen> {
  // Fake "discovered nearby" devices until real pairing exists.
  static const _devices = ['WH-S3-D4E1', 'WH-S3-E2B9'];
  static const _bands = [
    (label: 'Adult · 12–20', low: 12, high: 20),
    (label: 'Elderly · 12–22', low: 12, high: 22),
    (label: 'Infant · 25–40', low: 25, high: 40),
  ];

  int _device = 0;
  int _band = 0;
  final _name = TextEditingController();
  final _relation = TextEditingController();
  final _room = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _relation.dispose();
    _room.dispose();
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().isEmpty || _room.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please add the patient’s name and room.')));
      return;
    }
    final band = _bands[_band];
    widget.app.addPatient(
      name: _name.text.trim(),
      relation:
          _relation.text.trim().isEmpty ? 'Family' : _relation.text.trim(),
      room: _room.text.trim(),
      deviceId: _devices[_device],
      normalLow: band.low,
      normalHigh: band.high,
    );
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Patient added — 60 s baseline calibration started.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Add Patient'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('1 · CHOOSE A SENSOR', style: WiText.label),
                  const SizedBox(height: 6),
                  Text('Devices discovered nearby', style: WiText.caption),
                  const SizedBox(height: 12),
                  for (var i = 0; i < _devices.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => setState(() => _device = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: _device == i
                              ? WiColors.primarySoft
                              : WiColors.field,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _device == i
                                ? WiColors.primary
                                : Colors.transparent,
                            width: 1.4,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.sensors_rounded,
                                size: 19,
                                color: _device == i
                                    ? WiColors.primary
                                    : WiColors.inkFaint),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Wi-Health Sense · ${_devices[i]}',
                                style: WiText.title.copyWith(fontSize: 13.5),
                              ),
                            ),
                            if (_device == i)
                              const Icon(Icons.check_circle_rounded,
                                  color: WiColors.primary, size: 19),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('2 · WHO ARE WE WATCHING OVER?', style: WiText.label),
                  const SizedBox(height: 16),
                  SoftTextField(
                    label: 'Patient name',
                    hint: 'e.g. Ayesha Khan',
                    controller: _name,
                  ),
                  const SizedBox(height: 14),
                  SoftTextField(
                    label: 'Relation (optional)',
                    hint: 'e.g. Mother, Grandfather',
                    controller: _relation,
                  ),
                  const SizedBox(height: 14),
                  SoftTextField(
                    label: 'Room',
                    hint: 'e.g. Bedroom, Nursery',
                    controller: _room,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('3 · NORMAL BREATHING BAND', style: WiText.label),
                  const SizedBox(height: 6),
                  Text('Alerts fire outside this range (breaths/min)',
                      style: WiText.caption),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < _bands.length; i++)
                        GestureDetector(
                          onTap: () => setState(() => _band = i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 9),
                            decoration: BoxDecoration(
                              color: _band == i
                                  ? WiColors.primary
                                  : WiColors.field,
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Text(
                              _bands[i].label,
                              style: TextStyle(
                                color: _band == i
                                    ? Colors.white
                                    : WiColors.inkSoft,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SoftCard(
              color: WiColors.primarySoft,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.self_improvement_rounded,
                      color: WiColors.primary, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'After adding, the patient sits still between the sensors for 60 seconds while we calibrate the room’s baseline.',
                      style: WiText.caption.copyWith(color: WiColors.inkSoft),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            PrimaryButton(
              text: 'Add & Calibrate',
              trailingArrow: false,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
