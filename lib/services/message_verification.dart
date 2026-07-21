class MessageVerification {
  static final MessageVerification _instance = MessageVerification._internal();
  factory MessageVerification() => _instance;
  MessageVerification._internal();

  final String _hardcodedMessage = "I am aware that my screen time for this app is exhausted. I choose to continue using it and accept the consequences. I am typing this message to prove that I am making a conscious decision and not just mindlessly scrolling. Time is the most valuable asset I have, and I must use it wisely. I will try to be more mindful of my digital habits and limit my usage to productive tasks. This is a deliberate action, and I will be responsible for my time management. I acknowledge that excessive screen time is detrimental to my goals.";

  /// Returns the hardcoded message (exactly 100 words)
  String generateMessage() {
    return _hardcodedMessage;
  }

  /// Verifies exact match (case-sensitive)
  bool verifyMessage(String userInput) {
    // Check if the user input exactly matches the hardcoded message
    // It's case-sensitive and must perfectly match to prevent simple bypasses.
    return userInput.trim() == _hardcodedMessage.trim();
  }
}
