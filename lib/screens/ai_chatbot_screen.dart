import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class SafetyChatbotScreen extends StatefulWidget {
  const SafetyChatbotScreen({super.key});

  @override
  State<SafetyChatbotScreen> createState() => _SafetyChatbotScreenState();
}

class _SafetyChatbotScreenState extends State<SafetyChatbotScreen> {
  // TODO: Replace with read from remote config, env vars, or secure storage
  static const String _apiKey = 'AIzaSyBa1j6cL3vgVoXzXzVfp3LpAA5KABeOypk';

  late final GenerativeModel _model;
  late final ChatSession _chat;
  
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Message> _messages = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initChatbot();
  }

  void _initChatbot() {
    _model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: _apiKey,
      systemInstruction: Content.system(
        "You are an expert safety assistant answering within the offline Guardian app."
        "Provide direct, concise advice on self-defense, first aid, emergency protocols, or legal rights."
        "Always recommend contacting local emergency authorities if the situation represents an immediate threat."
      ),
    );
    _chat = _model.startChat();
    
    setState(() {
      _messages.add(
        Message(
          text: "Hi there. I'm your AI Safety Assistant. How can I help you today? You can ask me about self-defense, first-aid, or safety protocols.",
          isUser: false,
        )
      );
    });
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(Message(text: text, isUser: true));
      _isLoading = true;
    });
    _textController.clear();
    _scrollToBottom();

    try {
      if (_apiKey == 'YOUR_GEMINI_API_KEY') {
        await Future.delayed(const Duration(seconds: 1));
        setState(() {
          _messages.add(Message(
            text: "⚠️ Placeholder API key detected. Please add your actual Gemini API Key in the source code to get real responses.",
            isUser: false,
          ));
        });
      } else {
        final response = await _chat.sendMessage(Content.text(text));
        setState(() {
          _messages.add(Message(text: response.text ?? 'No response', isUser: false));
        });
      }
    } catch (e) {
      setState(() {
        _messages.add(Message(text: "Error: Could not process request. Please check your network context.", isUser: false));
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Safety AI Assistant'),
        backgroundColor: const Color(0xFF1D3557),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16.0),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return _buildMessageBubble(message);
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message message) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: message.isUser ? const Color(0xFF457B9D) : const Color(0xFF2A9D8F),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: message.isUser ? const Radius.circular(16) : const Radius.circular(0),
            bottomRight: message.isUser ? const Radius.circular(0) : const Radius.circular(16),
          ),
        ),
        child: SelectableText(
          message.text,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(8.0),
      color: const Color(0xFF1D3557),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Ask for safety advice...',
                hintStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: const Color(0xFF457B9D).withOpacity(0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24.0),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: const Color(0xFFE63946),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}

class Message {
  final String text;
  final bool isUser;

  Message({required this.text, required this.isUser});
}
