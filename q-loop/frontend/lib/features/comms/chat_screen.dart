/// Rapido-style in-app chat — message bubbles, polling, read receipts.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/api_constants.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/dio_client.dart';
import '../auth/domain/auth_provider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String recipientId;
  final String recipientName;
  final String recipientRole;
  final String? recipientCustomId;
  final String? recipientOrg;

  const ChatScreen({
    super.key,
    this.recipientId = '',
    this.recipientName = '',
    this.recipientRole = '',
    this.recipientCustomId,
    this.recipientOrg,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();

  List<Map<String, dynamic>> _messages = [];
  bool _sending = false;
  bool _loading = true;
  Timer? _pollTimer;
  bool _calling = false;

  // AI suggestion state
  bool _aiSuggestLoading = false;
  String? _aiSuggestion;

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    // Poll every 5 seconds for new messages
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _fetchMessages(silent: true),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchMessages({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final res =
          await dio.get(ApiConstants.commsConversation(widget.recipientId));
      final serverMsgs =
          List<Map<String, dynamic>>.from(res.data as List? ?? []);
      if (mounted) {
        // Keep only optimistic messages that haven't been confirmed by server yet
        final serverBodies =
            serverMsgs.map((m) => '${m['sender_id']}:${m['body']}').toSet();
        final pendingOptimistic = _messages
            .where((m) =>
                m['_optimistic'] == true &&
                !serverBodies.contains('${m['sender_id']}:${m['body']}'))
            .toList();
        setState(() {
          _messages = [...serverMsgs, ...pendingOptimistic];
          _loading = false;
        });
        _scrollToBottom();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    _msgCtrl.clear();

    // Optimistic: add local bubble immediately
    final auth = ref.read(authNotifierProvider);
    final now = DateTime.now().toIso8601String();
    final optimistic = {
      'id': 'tmp_$now',
      'sender_id': auth.userId ?? '',
      'recipient_id': widget.recipientId,
      'body': text,
      'channel': 'in_app',
      'twilio_sid': null,
      'read_at': null,
      'created_at': now,
      'sender_name': 'You',
      'sender_role': auth.role,
      '_optimistic': true,
    };
    setState(() => _messages = [..._messages, optimistic]);
    _scrollToBottom();

    try {
      final dio = ref.read(dioProvider);
      await dio.post(ApiConstants.commsMessage, data: {
        'recipient_id': widget.recipientId,
        'body': text,
        'also_send_sms': false,
      });
      // Fetch immediately to replace optimistic message with real one
      await _fetchMessages(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to send: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _initiateCall() async {
    if (_calling) return;
    setState(() => _calling = true);
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.post(ApiConstants.commsCall, data: {
        'recipient_user_id': widget.recipientId,
        'use_voip': true,
      });
      final data = res.data as Map<String, dynamic>;
      final status = data['status'] as String? ?? 'unknown';
      final sid = data['call_sid'] as String?;
      if (mounted) _showCallStatus(status, sid);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Call failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _calling = false);
    }
  }

  void _showCallStatus(String status, String? sid) {
    final initiated = status == 'initiated';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (initiated ? AppColors.primary : AppColors.warning)
                    .withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                initiated ? Icons.call : Icons.call_end,
                color: initiated ? AppColors.primary : AppColors.warning,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              initiated ? 'Call Initiated' : 'Call Simulated',
              style: TextStyle(
                  color: AppColors.textMain(context),
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Calling ${widget.recipientName}…',
              style: TextStyle(
                  color: AppColors.textSub(context), fontSize: 13),
            ),
            if (sid != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.scaffold(context),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'SID: $sid',
                  style: TextStyle(
                      color: AppColors.labelText(context),
                      fontSize: 10,
                      fontFamily: 'monospace'),
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'No phone number on file — call was simulated.',
                style:
                    TextStyle(color: AppColors.labelText(context), fontSize: 12),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Future<void> _getAiSuggestion() async {
    if (_aiSuggestLoading) return;
    setState(() {
      _aiSuggestLoading = true;
      _aiSuggestion = null;
    });

    // Build context from last 3 messages
    final last3 = _messages.length <= 3
        ? _messages
        : _messages.sublist(_messages.length - 3);
    final msgContext = last3
        .map((m) => '${m['sender_name'] ?? 'User'}: ${m['body'] ?? ''}')
        .join(' | ');

    try {
      final dio = ref.read(dioProvider);
      final res = await dio.post(ApiConstants.aiInsight, data: {
        'query':
            'Suggest a helpful reply in a logistics chat context. Last messages: $msgContext',
      });
      final data = res.data as Map<String, dynamic>;
      final suggestion =
          (data['insight'] as String?) ?? (data['message'] as String?) ?? '';
      if (mounted) {
        setState(
            () => _aiSuggestion = suggestion.isNotEmpty ? suggestion : null);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('AI suggestion unavailable'),
          backgroundColor: AppColors.error,
          duration: Duration(seconds: 2),
        ));
      }
    } finally {
      if (mounted) setState(() => _aiSuggestLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authNotifierProvider);
    final myId = auth.userId ?? '';

    final roleColors = <String, Color>{
      'driver': AppColors.accent,
      'gatekeeper': AppColors.primary,
      'manager': AppColors.warning,
      'admin': AppColors.error,
      'superadmin': AppColors.error,
    };
    final recipientColor =
        roleColors[widget.recipientRole] ?? AppColors.textSecondary;

    return Scaffold(
      backgroundColor: AppColors.scaffold(context),
      appBar: AppBar(
        backgroundColor: AppColors.sidebarBg,
        elevation: 0,
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: Icon(Icons.arrow_back_ios,
                    color: AppColors.textSub(context), size: 18),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: recipientColor.withValues(alpha: 0.18),
            child: Icon(_roleIcon(widget.recipientRole),
                color: recipientColor, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.recipientName,
                    style: TextStyle(
                        color: AppColors.textMain(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                if (widget.recipientCustomId != null)
                  Text(widget.recipientCustomId!,
                      style: TextStyle(
                          color: AppColors.labelText(context),
                          fontSize: 10,
                          fontFamily: 'monospace')),
              ],
            ),
          ),
        ]),
        actions: [
          // Call button
          _calling
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.phone_rounded,
                      color: AppColors.primary, size: 20),
                  tooltip: 'Call',
                  onPressed: _initiateCall,
                ),
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: recipientColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _roleBadge(widget.recipientRole),
              style: TextStyle(
                  color: recipientColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Message list
          Expanded(
            child: _loading && _messages.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : _messages.isEmpty
                    ? _EmptyChat(
                        name: widget.recipientName, color: recipientColor)
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) {
                          final m = _messages[i];
                          final isMe = (m['sender_id'] as String?) == myId;
                          return _MessageBubble(
                            message: m,
                            isMe: isMe,
                            myColor: AppColors.primary,
                            theirColor: recipientColor,
                          );
                        },
                      ),
          ),

          // AI suggestion card
          if (_aiSuggestion != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome,
                          color: AppColors.accent, size: 14),
                      const SizedBox(width: 6),
                      Text('AI Suggestion',
                          style: TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w600,
                              fontSize: 11)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => setState(() => _aiSuggestion = null),
                        child: Icon(Icons.close,
                            color: AppColors.labelText(context), size: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () {
                      _msgCtrl.text = _aiSuggestion!;
                      _msgCtrl.selection = TextSelection.fromPosition(
                          TextPosition(offset: _aiSuggestion!.length));
                      setState(() => _aiSuggestion = null);
                      _focusNode.requestFocus();
                    },
                    child: Text(_aiSuggestion!,
                        style: TextStyle(
                            color: AppColors.textMain(context),
                            fontSize: 13,
                            height: 1.4)),
                  ),
                  const SizedBox(height: 4),
                  Text('Tap to insert',
                      style:
                          TextStyle(color: AppColors.labelText(context), fontSize: 10)),
                ],
              ),
            ),

          // Input bar
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              color: AppColors.sidebar(context),
              border: Border(top: BorderSide(color: AppColors.divider(context))),
            ),
            child: SafeArea(
              top: false,
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    focusNode: _focusNode,
                    style: TextStyle(
                        color: AppColors.textMain(context), fontSize: 14),
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: 'Message ${widget.recipientName}…',
                      hintStyle: TextStyle(
                          color: AppColors.labelText(context), fontSize: 13),
                      filled: true,
                      fillColor: AppColors.cardBg,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: AppColors.divider(context)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: AppColors.divider(context)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(
                            color: AppColors.primary, width: 1.5),
                      ),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 6),
                // AI Suggest button
                GestureDetector(
                  onTap: _aiSuggestLoading ? null : _getAiSuggestion,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: _aiSuggestLoading
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.accent),
                          )
                        : const Icon(Icons.auto_awesome,
                            color: AppColors.accent, size: 16),
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  child: _sending
                      ? const SizedBox(
                          width: 44,
                          height: 44,
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.primary),
                            ),
                          ),
                        )
                      : GestureDetector(
                          onTap: _send,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                )
                              ],
                            ),
                            child: const Icon(Icons.send_rounded,
                                color: Colors.black, size: 18),
                          ),
                        ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'driver':
        return Icons.local_shipping_outlined;
      case 'gatekeeper':
        return Icons.warehouse_outlined;
      case 'manager':
      case 'admin':
        return Icons.admin_panel_settings_outlined;
      default:
        return Icons.person_outlined;
    }
  }

  String _roleBadge(String role) {
    if (role == 'gatekeeper' &&
        widget.recipientOrg != null &&
        widget.recipientOrg!.isNotEmpty) {
      return widget.recipientOrg!.toUpperCase();
    }
    switch (role) {
      case 'gatekeeper':
        return 'HUB OPS';
      case 'manager':
        return 'MANAGER';
      case 'admin':
        return 'ADMIN';
      case 'driver':
        return 'DRIVER';
      default:
        return role.toUpperCase();
    }
  }
}

// ── Message bubble ─────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.myColor,
    required this.theirColor,
  });

  final Map<String, dynamic> message;
  final bool isMe;
  final Color myColor, theirColor;

  @override
  Widget build(BuildContext context) {
    final body = (message['body'] as String?) ?? '';
    final createdAt = message['created_at'] as String? ?? '';
    final readAt = message['read_at'] as String?;

    // Format timestamp
    String timeStr = '';
    try {
      final dt = DateTime.parse(createdAt).toLocal();
      timeStr =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {}

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) ...[
                CircleAvatar(
                  radius: 14,
                  backgroundColor: theirColor.withValues(alpha: 0.18),
                  child: Icon(Icons.person, color: theirColor, size: 14),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.68,
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe ? myColor.withValues(alpha: 0.2) : AppColors.cardBg,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isMe ? 18 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 18),
                    ),
                    border: Border.all(
                      color:
                          isMe ? myColor.withValues(alpha: 0.35) : AppColors.border,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    body,
                    style: TextStyle(
                      color:
                          isMe ? AppColors.textPrimary : AppColors.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              if (isMe) const SizedBox(width: 8),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: EdgeInsets.only(
              left: isMe ? 0 : 36,
              right: isMe ? 4 : 0,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment:
                  isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                Text(timeStr,
                    style: TextStyle(
                        color: AppColors.labelText(context), fontSize: 10)),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    readAt != null ? Icons.done_all : Icons.done,
                    size: 12,
                    color: readAt != null
                        ? AppColors.primary
                        : AppColors.textMuted,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.name, required this.color});
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: color.withValues(alpha: 0.14),
            child: Icon(Icons.chat_bubble_outline, color: color, size: 32),
          ),
          const SizedBox(height: 16),
          Text('Start a conversation with $name',
              style: TextStyle(
                  color: AppColors.textMain(context),
                  fontWeight: FontWeight.w600,
                  fontSize: 15)),
          const SizedBox(height: 6),
          Text(
            'Messages are stored in the database\nand delivered in-app',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSub(context), fontSize: 12),
          ),
        ],
      ),
    );
  }
}
