import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Request a device from the administrator (request-queue model). Devices are
/// physical hardware the admin provisions and assigns; the caretaker submits a
/// request with the patient details, and once the admin assigns a device it
/// appears on the dashboard automatically — no device ID typing.
class LinkDeviceScreen extends StatefulWidget {
  const LinkDeviceScreen({super.key, required this.app});

  final AppState app;

  @override
  State<LinkDeviceScreen> createState() => _LinkDeviceScreenState();
}

class _LinkDeviceScreenState extends State<LinkDeviceScreen> {
  final _name = TextEditingController();
  final _relation = TextEditingController();
  final _room = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _relation.dispose();
    _room.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty || _room.text.trim().isEmpty) {
      setState(() => _error = 'Please add the patient’s name and room.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final error = await widget.app.requestDevice(
      patientName: _name.text.trim(),
      patientRelation:
          _relation.text.trim().isEmpty ? 'Family' : _relation.text.trim(),
      room: _room.text.trim(),
    );

    if (!mounted) return;

    if (error != null) {
      setState(() {
        _submitting = false;
        _error = error;
      });
      return;
    }

    _name.clear();
    _relation.clear();
    _room.clear();
    FocusScope.of(context).unfocus();
    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Request sent — your admin will assign a device to your account.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Request a Device'),
      ),
      body: ListenableBuilder(
        listenable: widget.app,
        builder: (context, _) {
          final requests = widget.app.deviceRequests;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SoftCard(
                  color: WiColors.primarySoft,
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          color: WiColors.primary, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Devices are set up and assigned by your administrator. '
                          'Send a request with the patient details — once a device '
                          'is assigned, it appears on your dashboard automatically.',
                          style:
                              WiText.caption.copyWith(color: WiColors.inkSoft),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('WHO ARE WE WATCHING OVER?', style: WiText.label),
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
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: WiColors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!,
                            style:
                                WiText.caption.copyWith(color: WiColors.red)),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 22),
                PrimaryButton(
                  text: _submitting ? 'Sending…' : 'Send Request',
                  trailingArrow: false,
                  onPressed: () {
                    if (!_submitting) _submit();
                  },
                ),
                if (requests.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  const SectionHeader(title: 'Your Requests'),
                  for (final r in requests) ...[
                    _requestCard(r),
                    const SizedBox(height: 12),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _requestCard(DeviceRequest r) {
    final (text, color, bg) = switch (r.status) {
      DeviceRequestStatus.pending => ('Pending', WiColors.amber, WiColors.amberSoft),
      DeviceRequestStatus.fulfilled => ('Assigned', WiColors.green, WiColors.greenSoft),
      DeviceRequestStatus.declined => ('Declined', WiColors.red, WiColors.redSoft),
    };
    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.patientName,
                    style: WiText.title.copyWith(fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                    [r.room, if (r.patientRelation.isNotEmpty) r.patientRelation]
                        .join(' · '),
                    style: WiText.caption),
              ],
            ),
          ),
          StatusPill(text: text, color: color, background: bg),
        ],
      ),
    );
  }
}
