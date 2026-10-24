import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/pill_badge.dart';

class ChatMessage {
  final String sender; // 'rider' or 'driver'
  final String text;
  final String time;

  const ChatMessage({
    required this.sender,
    required this.text,
    required this.time,
  });
}

class InRideChatSheet extends StatefulWidget {
  final String rideId;
  final String myRole; // 'rider' or 'driver'
  final String otherPartyName;
  final String otherPartySubtitle;

  const InRideChatSheet({
    super.key,
    required this.rideId,
    required this.myRole,
    required this.otherPartyName,
    required this.otherPartySubtitle,
  });

  @override
  State<InRideChatSheet> createState() => _InRideChatSheetState();
}

class _InRideChatSheetState extends State<InRideChatSheet> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  RealtimeChannel? _chatChannel;

  final List<ChatMessage> _messages = [];

  // Quick preset chips
  List<String> get _quickChips => widget.myRole == 'rider'
      ? [
          'Waiting at main entrance',
          'Wearing a navy abaya',
          'Outside the gate',
          'Please take your time',
        ]
      : [
          'Arrived outside your pickup point',
          'Hazard lights are flashing',
          'Toyota Yaris - Gold',
          'Traffic is slightly slow, 2 mins',
        ];

  @override
  void initState() {
    super.initState();
    _initChatChannel();
    _seedInitialMessages();
  }

  void _seedInitialMessages() {
    _messages.add(ChatMessage(
      sender: widget.myRole == 'rider' ? 'driver' : 'rider',
      text: widget.myRole == 'rider'
          ? 'Peace be upon you! I have accepted your request and heading to pickup.'
          : 'Thank you Captain! I will be ready at the entrance.',
      time: 'Just now',
    ));
  }

  void _initChatChannel() {
    try {
      final supabase = Supabase.instance.client;
      _chatChannel = supabase.channel('refqa-chat-${widget.rideId}');

      _chatChannel!.onBroadcast(
        event: 'chat_message',
        callback: (payload) {
          final senderRole = payload['sender_role']?.toString();
          final text = payload['text']?.toString();
          if (text != null && senderRole != widget.myRole) {
            HapticFeedback.lightImpact();
            setState(() {
              _messages.add(ChatMessage(
                sender: senderRole ?? 'other',
                text: text,
                time: 'Just now',
              ));
            });
            _scrollToBottom();
          }
        },
      );

      _chatChannel!.subscribe();
    } catch (e) {
      debugPrint('[Rafik Chat] Channel init notice: $e');
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _chatChannel?.unsubscribe();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage(String text) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;

    _textController.clear();
    HapticFeedback.lightImpact();

    setState(() {
      _messages.add(ChatMessage(
        sender: widget.myRole,
        text: cleanText,
        time: 'Just now',
      ));
    });
    _scrollToBottom();

    try {
      await _chatChannel?.sendBroadcastMessage(
        event: 'chat_message',
        payload: {
          'ride_id': widget.rideId,
          'sender_role': widget.myRole,
          'text': cleanText,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      debugPrint('Realtime chat broadcast error: $e');
    }
  }

  Future<void> _makeMaskedCall() async {
    HapticFeedback.mediumImpact();
    // Launches masked phone dialer
    final Uri phoneUri = Uri.parse('tel:0221227429');
    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRider = widget.myRole == 'rider';

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppTheme.roseGold.withOpacity(0.2),
                  child: Icon(
                    isRider ? Icons.directions_car_rounded : Icons.person_rounded,
                    color: AppTheme.roseGold,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.otherPartyName,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        widget.otherPartySubtitle,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const PillBadge(
                  text: 'ENCRYPTED CHAT',
                  textColor: AppTheme.sageSafe,
                  bgColor: Color(0x1F6B8E23),
                  borderColor: Color(0x3D6B8E23),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _makeMaskedCall,
                  icon: const Icon(Icons.phone_in_talk_rounded, color: AppTheme.roseGold),
                  tooltip: 'Masked Secure Call',
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white10, height: 24),

          // Messages List
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isMe = msg.sender == widget.myRole;

                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    decoration: BoxDecoration(
                      color: isMe
                          ? AppTheme.roseGold.withOpacity(0.2)
                          : const Color(0xFF221118),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isMe ? 16 : 4),
                        bottomRight: Radius.circular(isMe ? 4 : 16),
                      ),
                      border: Border.all(
                        color: isMe
                            ? AppTheme.roseGold.withOpacity(0.4)
                            : Colors.white10,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment:
                          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg.text,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 14,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          msg.time,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Quick Preset Chips
          Container(
            height: 40,
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _quickChips.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final chip = _quickChips[index];
                return ActionChip(
                  backgroundColor: const Color(0xFF23141B),
                  side: const BorderSide(color: Colors.white12),
                  label: Text(
                    chip,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  onPressed: () => _sendMessage(chip),
                );
              },
            ),
          ),

          // Message Input Field
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      style: const TextStyle(color: Colors.white),
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Type secure message...',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13),
                        filled: true,
                        fillColor: const Color(0xFF1A0D13),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: Colors.white12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: AppTheme.roseGold),
                        ),
                      ),
                      onSubmitted: _sendMessage,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.roseGold,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.black, size: 20),
                      onPressed: () => _sendMessage(_textController.text),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
