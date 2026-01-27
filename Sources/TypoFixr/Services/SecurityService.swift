import Foundation

/// Service for pre-flight security checks on user text before sending to AI
class SecurityService {
    static let shared = SecurityService()
    
    private init() {}
    
    // MARK: - Security Check Result
    
    enum SecurityCheckResult {
        case safe
        case promptInjectionWarning(patterns: [String])
        case sensitiveDataWarning(types: [SensitiveDataType])
        case blocked(reason: String)
    }
    
    enum SensitiveDataType: String, CaseIterable {
        case creditCard = "Credit card number"
        case ssn = "Social Security Number"
        case password = "Password"
        case apiKey = "API key"
        case email = "Email address"
        case phoneNumber = "Phone number"
        
        var icon: String {
            switch self {
            case .creditCard: return "creditcard"
            case .ssn: return "person.text.rectangle"
            case .password: return "key"
            case .apiKey: return "key.horizontal"
            case .email: return "envelope"
            case .phoneNumber: return "phone"
            }
        }
    }
    
    // MARK: - Prompt Injection Patterns
    
    /// Patterns that commonly indicate prompt injection attempts
    private let injectionPatterns: [(pattern: String, description: String)] = [
        // Direct instruction override attempts
        ("ignore\\s+(all\\s+)?previous\\s+instructions?", "instruction override"),
        ("ignore\\s+(the\\s+)?(above|system)", "instruction override"),
        ("disregard\\s+(all\\s+)?previous", "instruction override"),
        ("forget\\s+(all\\s+)?previous", "instruction override"),
        ("new\\s+instructions?:", "new instructions"),
        ("system\\s*:", "system prompt injection"),
        ("assistant\\s*:", "role injection"),
        ("\\[INST\\]", "instruction tag"),
        ("\\[/INST\\]", "instruction tag"),
        
        // Role/persona manipulation
        ("you\\s+are\\s+(now|no\\s+longer)", "role change"),
        ("pretend\\s+(to\\s+be|you\\s+are)", "role manipulation"),
        ("act\\s+as\\s+(if|a)", "role manipulation"),
        ("from\\s+now\\s+on", "behavior change"),
        
        // Output manipulation
        ("instead,?\\s+(output|return|say|print)", "output manipulation"),
        ("do\\s+not\\s+correct", "behavior override"),
        ("don'?t\\s+fix", "behavior override"),
        
        // Jailbreak patterns
        ("DAN\\s+mode", "jailbreak attempt"),
        ("developer\\s+mode", "jailbreak attempt"),
        ("bypass\\s+(content|safety)", "bypass attempt"),
    ]
    
    // MARK: - Sensitive Data Patterns
    
    /// Patterns for detecting sensitive data
    private let sensitiveDataPatterns: [(type: SensitiveDataType, pattern: String)] = [
        // Credit card numbers (Visa, Mastercard, Amex, etc.)
        (.creditCard, "\\b(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|3[47][0-9]{13}|6(?:011|5[0-9]{2})[0-9]{12})\\b"),
        // Credit card with spaces/dashes
        (.creditCard, "\\b(?:\\d{4}[- ]?){3}\\d{4}\\b"),
        
        // Social Security Numbers (various formats)
        (.ssn, "\\b\\d{3}[- ]\\d{2}[- ]\\d{4}\\b"),  // With separators: 123-45-6789 or 123 45 6789
        (.ssn, "\\b\\d{9}\\b"),  // Without separators: 123456789
        (.ssn, "(?:ssn|social\\s*security)\\s*(?:number|#|no\\.?)?\\s*(?:is)?\\s*[:=]?\\s*\\d"),  // SSN: or "my SSN is"
        
        // Password patterns (password: xxx, pwd: xxx, etc.) - includes common typos
        (.password, "(?:password|passwd|pwd|pass)\\s*(?:is)?\\s*[:=]\\s*\\S+"),
        // Handle typos like "pasword", "passowrd", "passwrod", "passord"
        (.password, "\\bp[ao]ss?w?[oar]*r?d\\s*(?:is)?\\s*[:=]\\s*\\S+"),
        (.password, "(?:secret|token)\\s*(?:is)?\\s*[:=]\\s*\\S+"),
        
        // API keys (common formats)
        (.apiKey, "\\b(?:sk-[a-zA-Z0-9]{20,}|api[_-]?key\\s*[:=]\\s*\\S+)\\b"),
        (.apiKey, "\\bAIza[0-9A-Za-z_-]{35}\\b"), // Google API key
        (.apiKey, "\\b[A-Za-z0-9]{32}\\b"), // Generic 32-char key
        
        // Email addresses
        (.email, "\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}\\b"),
        
        // Phone numbers (US format)
        (.phoneNumber, "\\b(?:\\+1[- ]?)?(?:\\([0-9]{3}\\)|[0-9]{3})[- ]?[0-9]{3}[- ]?[0-9]{4}\\b"),
    ]
    
    // MARK: - Public Methods
    
    /// Performs comprehensive security check on input text
    func checkText(_ text: String) -> SecurityCheckResult {
        // Check for prompt injection patterns
        let injectionWarnings = detectPromptInjection(text)
        if !injectionWarnings.isEmpty {
            return .promptInjectionWarning(patterns: injectionWarnings)
        }
        
        // Check for sensitive data
        let sensitiveTypes = detectSensitiveData(text)
        if !sensitiveTypes.isEmpty {
            return .sensitiveDataWarning(types: sensitiveTypes)
        }
        
        return .safe
    }
    
    /// Checks specifically for prompt injection patterns
    func detectPromptInjection(_ text: String) -> [String] {
        var detected: [String] = []
        
        for (pattern, description) in injectionPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) != nil {
                if !detected.contains(description) {
                    detected.append(description)
                }
            }
        }
        
        return detected
    }
    
    /// Checks specifically for sensitive data patterns
    func detectSensitiveData(_ text: String) -> [SensitiveDataType] {
        var detected: Set<SensitiveDataType> = []
        
        for (type, pattern) in sensitiveDataPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) != nil {
                detected.insert(type)
            }
        }
        
        return Array(detected).sorted { $0.rawValue < $1.rawValue }
    }
    
    /// Returns a user-friendly warning message for detected issues
    func getWarningMessage(for result: SecurityCheckResult) -> (title: String, message: String)? {
        switch result {
        case .safe:
            return nil
            
        case .promptInjectionWarning(let patterns):
            let patternList = patterns.prefix(3).joined(separator: ", ")
            return (
                "Unusual Text Detected",
                "Your text contains patterns that may not work correctly with the AI: \(patternList). Send anyway?"
            )
            
        case .sensitiveDataWarning(let types):
            let typeList = types.map { $0.rawValue }.joined(separator: ", ")
            return (
                "Sensitive Data Detected",
                "Your text may contain: \(typeList). This will be sent to OpenAI's servers. Continue?"
            )
            
        case .blocked(let reason):
            return ("Blocked", reason)
        }
    }
}
