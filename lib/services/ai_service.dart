import 'package:google_generative_ai/google_generative_ai.dart';

class AIService {
  // Provided Gemini API Key
  static const String apiKey = 'AIzaSyAiO8GfyfWfO0BaSaiDsdQhw2LvRLqr_gU'; 
  
  static final GenerativeModel _model = GenerativeModel(
    model: 'gemini-1.5-flash',
    apiKey: apiKey,
    generationConfig: GenerationConfig(
      temperature: 0.2, // Low temperature for more factual emergency advice
    )
  );

  static Future<String> getEmergencyAdvice(String prompt) async {
    if (apiKey == 'YOUR_GEMINI_API_KEY') {
      return "Error: Gemini API Key is missing. Please add it to lib/services/ai_service.dart.";
    }

    try {
      final String contextPrompt = """
You are 'Sentinel AI', an emergency medical and safety assistant integrated into a mobile app.
Your purpose is to give clear, concise, and immediate advice for the user's emergency situation while they wait for authorities or medical professionals to arrive.
Keep responses short, actionable, and easy to read in a panic situation. Use bullet points.
User's situation: $prompt
""";
      final content = [Content.text(contextPrompt)];
      final response = await _model.generateContent(content);
      return response.text ?? "I could not generate a response. Please contact authorities immediately.";
    } catch (e) {
      return "Error connecting to AI Assistant: $e\n\nPlease call emergency services directly.";
    }
  }
}
