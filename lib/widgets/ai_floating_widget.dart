import 'package:flutter/material.dart';
import '../services/ai_service.dart';

// Copying some neon colors for consistency
class Neon {
  static const Color bg        = Color(0xFF050508);
  static const Color surface   = Color(0xFF0D0D12);
  static const Color cyan      = Color(0xFF00F0FF);
  static const Color magenta   = Color(0xFFFF2D78);
  static const Color textMain  = Color(0xFFE8E8EC);
  static const Color textDim   = Color(0xFF6B6B80);
}

class AIFloatingWidget extends StatefulWidget {
  final Widget child;
  const AIFloatingWidget({super.key, required this.child});

  @override
  State<AIFloatingWidget> createState() => _AIFloatingWidgetState();
}

class _AIFloatingWidgetState extends State<AIFloatingWidget> {
  bool _isOpen = false;
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [
    {"role": "ai", "content": "I am Sentinel AI. How can I help you stay safe today?"}
  ];
  bool _isLoading = false;

  void _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    
    setState(() {
      _messages.add({"role": "user", "content": text});
      _isLoading = true;
    });
    
    _controller.clear();
    
    String response = await AIService.getEmergencyAdvice(text);
    
    setState(() {
      _messages.add({"role": "ai", "content": response});
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          widget.child,
          
          if (_isOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _isOpen = false),
                child: Container(color: Colors.black54),
              ),
            ),

          if (_isOpen)
            Positioned(
              bottom: 100,
              right: 20,
              left: 20,
              top: 100,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: Neon.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Neon.cyan.withOpacity(0.5), width: 2),
                    boxShadow: [
                      BoxShadow(color: Neon.cyan.withOpacity(0.2), blurRadius: 20, spreadRadius: 5)
                    ]
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Neon.cyan.withOpacity(0.1),
                          borderRadius: const BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.smart_toy, color: Neon.cyan),
                                SizedBox(width: 8),
                                Text("SENTINEL AI", style: const TextStyle(color: Neon.cyan, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Neon.textDim),
                              onPressed: () => setState(() => _isOpen = false),
                            )
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            final isUser = msg["role"] == "user";
                            return Align(
                              alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: isUser ? Neon.magenta.withOpacity(0.1) : Neon.cyan.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isUser ? Neon.magenta.withOpacity(0.3) : Neon.cyan.withOpacity(0.3)
                                  )
                                ),
                                child: Text(
                                  msg["content"]!,
                                  style: const TextStyle(color: Neon.textMain, fontSize: 14),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: CircularProgressIndicator(color: Neon.cyan),
                        ),
                      
                      // Predefined Prompts
                      if (!_isLoading)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              _PromptChip(label: "Medical Help", onTap: () => _sendMessage("I have a medical emergency, guide me.")),
                              _PromptChip(label: "Safety Threat", onTap: () => _sendMessage("I feel unsafe, someone is following me.")),
                              _PromptChip(label: "First Aid", onTap: () => _sendMessage("Give me quick CPR instructions.")),
                            ],
                          ),
                        ),
                        
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                style: const TextStyle(color: Neon.textMain),
                                decoration: InputDecoration(
                                  hintText: "Type your emergency...",
                                  hintStyle: const TextStyle(color: Neon.textDim),
                                  filled: true,
                                  fillColor: Neon.bg,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(30),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                ),
                                onSubmitted: _sendMessage,
                              ),
                            ),
                            const SizedBox(width: 8),
                            CircleAvatar(
                              backgroundColor: Neon.cyan.withOpacity(0.2),
                              child: IconButton(
                                icon: const Icon(Icons.send, color: Neon.cyan),
                                onPressed: () => _sendMessage(_controller.text),
                              ),
                            )
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ),
            
          if (!_isOpen)
            Positioned(
              bottom: 40,
              right: 20,
              child: GestureDetector(
                onTap: () => setState(() => _isOpen = true),
                child: Container(
                  height: 60,
                  width: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Neon.cyan.withOpacity(0.15),
                    border: Border.all(color: Neon.cyan, width: 2),
                    boxShadow: [
                      BoxShadow(color: Neon.cyan.withOpacity(0.4), blurRadius: 15, spreadRadius: 2)
                    ]
                  ),
                  child: const Icon(Icons.smart_toy, color: Neon.cyan, size: 30),
                ),
              ),
            )
        ],
      ),
    );
  }
}

class _PromptChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PromptChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Neon.bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Neon.textDim.withOpacity(0.5)),
        ),
        child: Text(label, style: const TextStyle(color: Neon.textDim, fontSize: 12)),
      ),
    );
  }
}
