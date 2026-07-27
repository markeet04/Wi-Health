import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';

/// Full-screen conversation for a single complaint — the foodpanda-style
/// support chat. The user talks with the admin here. When the complaint is
/// resolved the composer is replaced with a closed banner, but the full
/// history stays readable.
class ComplaintChatScreen extends StatefulWidget {
  const ComplaintChatScreen({
    super.key,
    required this.app,
    required this.complaintId,
  });

  final AppState app;
  final String complaintId;

  @override
  State<ComplaintChatScreen> createState() => _ComplaintChatScreenState();
}

class _ComplaintChatScreenState extends State<ComplaintChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  Complaint? get _complaint {
    for (final c in widget.app.complaints) {
      if (c.id == widget.complaintId) return c;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _jumpToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _input.clear();
    await widget.app.sendComplaintMessage(widget.complaintId, text);
    if (!mounted) return;
    setState(() => _sending = false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }

  (String, Color, Color) _statusStyle(ComplaintStatus status) => switch (status) {
        ComplaintStatus.open => ('Open', WiColors.amber, WiColors.amberSoft),
        ComplaintStatus.inProgress => ('In progress', WiColors.blue, WiColors.blueSoft),
        ComplaintStatus.resolved => ('Resolved', WiColors.green, WiColors.greenSoft),
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.app,
      builder: (context, _) {
        final complaint = _complaint;
        if (complaint == null) {
          return const Scaffold(body: Center(child: Text('Complaint not found')));
        }
        final resolved = complaint.status == ComplaintStatus.resolved;
        final (statusText, statusColor, statusBg) = _statusStyle(complaint.status);

        return Scaffold(
          backgroundColor: WiColors.bg,
          appBar: AppBar(
            titleSpacing: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  complaint.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WiText.title.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 1),
                Text('Support · ${complaint.category}',
                    style: WiText.caption.copyWith(fontSize: 11.5)),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(statusText,
                        style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                  children: [
                    _originCard(complaint),
                    const SizedBox(height: 8),
                    _dayDivider('Conversation'),
                    if (complaint.messages.isEmpty)
                      _systemNote(
                        'We received your complaint. Our team will reply here soon.',
                      ),
                    for (final m in complaint.messages) _bubble(m),
                  ],
                ),
              ),
              if (resolved) _closedBanner() else _composer(),
            ],
          ),
        );
      },
    );
  }

  /// The complaint itself, shown as the first "message" in the thread.
  Widget _originCard(Complaint complaint) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: WiColors.primary,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(complaint.subject,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            Text(complaint.description,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 12.8,
                    height: 1.4)),
            const SizedBox(height: 6),
            Text('You · ${complaint.date}',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75), fontSize: 10.5)),
          ],
        ),
      ),
    );
  }

  Widget _bubble(ComplaintMessage m) {
    final mine = m.senderRole != 'admin';
    final bg = mine ? WiColors.primary : WiColors.card;
    final fg = mine ? Colors.white : WiColors.ink;
    final timeColor =
        mine ? Colors.white.withValues(alpha: 0.75) : WiColors.inkFaint;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 290),
          padding: const EdgeInsets.fromLTRB(13, 9, 13, 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
            border: mine ? null : Border.all(color: WiColors.line),
          ),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(m.text,
                  style: TextStyle(color: fg, fontSize: 13.2, height: 1.4)),
              const SizedBox(height: 3),
              Text('${mine ? 'You' : 'Support'} · ${_time(m.sentAt)}',
                  style: TextStyle(color: timeColor, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dayDivider(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const Expanded(child: Divider(color: WiColors.line)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(label,
                style: WiText.caption.copyWith(
                    fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          const Expanded(child: Divider(color: WiColors.line)),
        ],
      ),
    );
  }

  Widget _systemNote(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: WiColors.field,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(text,
              textAlign: TextAlign.center,
              style: WiText.caption.copyWith(fontSize: 11.5, height: 1.4)),
        ),
      ),
    );
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: const BoxDecoration(
          color: WiColors.card,
          border: Border(top: BorderSide(color: WiColors.line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: WiColors.field,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  style: const TextStyle(fontSize: 13.5, color: WiColors.ink),
                  decoration: const InputDecoration(
                    hintText: 'Write a message…',
                    hintStyle: TextStyle(color: WiColors.inkFaint, fontSize: 13.5),
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _send,
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: WiColors.primary,
                  shape: BoxShape.circle,
                ),
                child: _sending
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.arrow_upward_rounded,
                        color: Colors.white, size: 21),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _closedBanner() {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: const BoxDecoration(
          color: WiColors.greenSoft,
          border: Border(top: BorderSide(color: WiColors.line)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: WiColors.green, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'This complaint is resolved. The chat is closed, but your conversation stays here.',
                style: WiText.caption.copyWith(fontSize: 11.8, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _time(int epochMs) {
    if (epochMs <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(epochMs).toLocal();
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final s = d.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $s';
  }
}
