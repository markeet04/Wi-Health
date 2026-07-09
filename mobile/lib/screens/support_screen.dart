import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Complaints & support — App Users raise complaints here; they sync to
/// Firebase for the Admin panel's Complaints page to review and resolve.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key, required this.app});

  final AppState app;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  static const _categories = [
    'Device issue',
    'App issue',
    'Alert accuracy',
    'Other',
  ];

  String _category = _categories.first;
  final _subject = TextEditingController();
  final _description = TextEditingController();

  @override
  void dispose() {
    _subject.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    if (_subject.text.trim().isEmpty || _description.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please add a subject and a description.')));
      return;
    }
    widget.app.submitComplaint(
      category: _category,
      subject: _subject.text.trim(),
      description: _description.text.trim(),
    );
    _subject.clear();
    _description.clear();
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Complaint submitted — our team will follow up.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Complaints & Support'),
      ),
      body: ListenableBuilder(
        listenable: widget.app,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SoftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SUBMIT A COMPLAINT', style: WiText.label),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 7),
                      child: Text('CATEGORY', style: WiText.label),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in _categories)
                          GestureDetector(
                            onTap: () => setState(() => _category = c),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: _category == c
                                    ? WiColors.primary
                                    : WiColors.field,
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: Text(
                                c,
                                style: TextStyle(
                                  color: _category == c
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
                    const SizedBox(height: 16),
                    SoftTextField(
                      label: 'Subject',
                      hint: 'Brief summary of the issue',
                      controller: _subject,
                    ),
                    const SizedBox(height: 16),
                    SoftTextField(
                      label: 'Description',
                      hint: 'What happened, when, and on which device?',
                      controller: _description,
                      maxLines: 4,
                    ),
                    const SizedBox(height: 20),
                    PrimaryButton(
                      text: 'Submit Complaint',
                      trailingArrow: false,
                      onPressed: _submit,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              SectionHeader(title: 'Previous Complaints'),
              for (final c in widget.app.complaints) ...[
                _complaintCard(c),
                const SizedBox(height: 12),
              ],
              if (widget.app.complaints.isEmpty)
                Text('No complaints yet.', style: WiText.body),
            ],
          ),
        ),
      ),
    );
  }

  Widget _complaintCard(Complaint c) {
    final (text, color, bg) = switch (c.status) {
      ComplaintStatus.open => ('Open', WiColors.amber, WiColors.amberSoft),
      ComplaintStatus.inProgress => (
          'In Progress',
          WiColors.blue,
          WiColors.blueSoft
        ),
      ComplaintStatus.resolved => (
          'Resolved',
          WiColors.green,
          WiColors.greenSoft
        ),
    };
    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(c.subject,
                    style: WiText.title.copyWith(fontSize: 14)),
              ),
              StatusPill(text: text, color: color, background: bg),
            ],
          ),
          const SizedBox(height: 6),
          Text('${c.category} · ${c.date}', style: WiText.caption),
          const SizedBox(height: 8),
          Text(c.description, style: WiText.body.copyWith(fontSize: 12.8)),
        ],
      ),
    );
  }
}
