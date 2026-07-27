import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'complaint_chat_screen.dart';

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

  (String, Color, Color) _statusStyle(ComplaintStatus status) => switch (status) {
        ComplaintStatus.open => ('Open', WiColors.amber, WiColors.amberSoft),
        ComplaintStatus.inProgress => ('In Progress', WiColors.blue, WiColors.blueSoft),
        ComplaintStatus.resolved => ('Resolved', WiColors.green, WiColors.greenSoft),
      };

  Widget _complaintCard(Complaint c) {
    final (text, color, bg) = _statusStyle(c.status);
    final hasReply = c.messages.any((m) => m.senderRole == 'admin');
    final replyCount = c.messages.where((m) => m.senderRole == 'admin').length;

    return GestureDetector(
      onTap: () => _openComplaintDetail(c),
      child: SoftCard(
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
            Text(c.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: WiText.body.copyWith(fontSize: 12.8)),
            if (hasReply) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.mark_chat_read_rounded,
                      size: 15, color: WiColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    replyCount == 1
                        ? 'Support replied'
                        : 'Support replied · $replyCount messages',
                    style: WiText.caption.copyWith(
                        color: WiColors.primary, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right_rounded,
                      size: 18, color: WiColors.inkFaint),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Tap a complaint -> clean detail sheet. From there, open the full-screen
  /// chat (foodpanda-style) to continue the conversation with support.
  Future<void> _openComplaintDetail(Complaint complaint) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => ListenableBuilder(
        listenable: widget.app,
        builder: (context, _) {
          final current = widget.app.complaints.firstWhere(
            (entry) => entry.id == complaint.id,
            orElse: () => complaint,
          );
          return _ComplaintDetailSheet(
            complaint: current,
            statusStyle: _statusStyle,
            onOpenChat: () {
              Navigator.of(sheetContext).pop();
              _openChat(current.id);
            },
          );
        },
      ),
    );
  }

  void _openChat(String complaintId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComplaintChatScreen(
          app: widget.app,
          complaintId: complaintId,
        ),
      ),
    );
  }
}

/// Minimal, clean detail sheet for a complaint. Shows the essentials and a
/// single clear action to open the conversation.
class _ComplaintDetailSheet extends StatelessWidget {
  const _ComplaintDetailSheet({
    required this.complaint,
    required this.statusStyle,
    required this.onOpenChat,
  });

  final Complaint complaint;
  final (String, Color, Color) Function(ComplaintStatus) statusStyle;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context) {
    final (statusText, statusColor, statusBg) = statusStyle(complaint.status);
    final hasReply = complaint.messages.any((m) => m.senderRole == 'admin');
    final resolved = complaint.status == ComplaintStatus.resolved;

    return Container(
      decoration: const BoxDecoration(
        color: WiColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: WiColors.line,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(complaint.subject,
                    style: WiText.title.copyWith(fontSize: 17)),
              ),
              const SizedBox(width: 12),
              StatusPill(text: statusText, color: statusColor, background: statusBg),
            ],
          ),
          const SizedBox(height: 6),
          Text('${complaint.category} · ${complaint.date}', style: WiText.caption),
          const SizedBox(height: 18),
          Text('DESCRIPTION', style: WiText.label),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: WiColors.field,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(complaint.description,
                style: WiText.body.copyWith(fontSize: 13, height: 1.45)),
          ),
          const SizedBox(height: 18),
          if (hasReply)
            Row(
              children: [
                const Icon(Icons.mark_chat_read_rounded,
                    size: 16, color: WiColors.primary),
                const SizedBox(width: 7),
                Expanded(
                  child: Text('Support has replied to your complaint.',
                      style: WiText.caption.copyWith(
                          color: WiColors.primary, fontWeight: FontWeight.w700)),
                ),
              ],
            )
          else
            Row(
              children: [
                const Icon(Icons.schedule_rounded,
                    size: 16, color: WiColors.inkSoft),
                const SizedBox(width: 7),
                Expanded(
                  child: Text('Awaiting a reply from our support team.',
                      style: WiText.caption),
                ),
              ],
            ),
          const SizedBox(height: 18),
          PrimaryButton(
            text: resolved
                ? 'View conversation'
                : (hasReply ? 'Continue chat' : 'Open chat'),
            trailingArrow: false,
            onPressed: onOpenChat,
          ),
        ],
      ),
    );
  }
}

