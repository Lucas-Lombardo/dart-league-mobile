class ErrorMessages {
  static String getUserFriendlyMessage(String error) {
    final lowerError = error.toLowerCase();
    
    // Network/Connection errors
    if (lowerError.contains('failed to fetch') || 
        lowerError.contains('clientfailed')) {
      return 'Unable to connect to server. Please check your internet connection.';
    }
    
    if (lowerError.contains('socketexception') || 
        lowerError.contains('connection timeout') ||
        lowerError.contains('unable to connect')) {
      return 'Connection failed. Please check your internet connection and try again.';
    }
    
    if (lowerError.contains('handshakeexception') || 
        lowerError.contains('certificate')) {
      return 'Secure connection failed. Please try again.';
    }
    
    // Authentication errors
    if (lowerError.contains('unauthorized') || 
        lowerError.contains('401')) {
      return 'Invalid email or password. Please try again.';
    }
    
    if (lowerError.contains('user not found')) {
      return 'Account not found. Please check your email or register.';
    }
    
    if (lowerError.contains('invalid credentials')) {
      return 'Incorrect email or password. Please try again.';
    }
    
    if (lowerError.contains('user already exists') || 
        lowerError.contains('email already in use')) {
      return 'An account with this email already exists.';
    }
    
    if (lowerError.contains('banned')) {
      return 'Your account has been suspended. Please contact support.';
    }
    
    // Server errors
    if (lowerError.contains('500') || 
        lowerError.contains('internal server error')) {
      return 'Server error. Please try again later.';
    }
    
    if (lowerError.contains('503') || 
        lowerError.contains('service unavailable')) {
      return 'Service temporarily unavailable. Please try again later.';
    }
    
    // Validation errors
    if (lowerError.contains('validation') || 
        lowerError.contains('invalid')) {
      return 'Please check your input and try again.';
    }
    
    // Default fallback
    if (error.isEmpty) {
      return 'An error occurred. Please try again.';
    }
    
    // If error is already clean (no technical jargon), return it
    if (!lowerError.contains('exception') && 
        !lowerError.contains('error') && 
        !lowerError.contains('failed') &&
        error.length < 100) {
      return error;
    }
    
    // Generic fallback for unrecognized errors
    return 'Something went wrong. Please try again.';
  }
}
