class MessageVerification {
  static final MessageVerification _instance = MessageVerification._internal();
  factory MessageVerification() => _instance;
  MessageVerification._internal();

  final String _hardcodedMessage = "I am aware that my screen time limit has been reached. I am choosing to continue using this app consciously and intentionally. I type this message to prove I am making a deliberate decision rather than mindlessly scrolling. Time is truly valuable and I must use it wisely every day.";

  /// Returns the hardcoded message (exactly 50 words)
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
