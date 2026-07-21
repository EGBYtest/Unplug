import 'package:flutter/services.dart';

/// Blocks paste operations in TextFields.
/// Only single-character changes (actual typing) or deletions are allowed.
/// This ensures users must type the verification message manually.
class NoPasteFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final addedChars = newValue.text.length - oldValue.text.length;
    // Allow deletions (addedChars <= 0) and single-key presses (addedChars == 1)
    // Anything adding more than 1 character at once is a paste — reject it.
    if (addedChars > 1) {
      return oldValue;
    }
    return newValue;
  }
}
