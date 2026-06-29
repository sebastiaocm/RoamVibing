import Foundation
import Security

public enum CodeSigningRequirement {
    public static func release(bundleIdentifier: String, teamIdentifier: String) throws -> String {
        guard !bundleIdentifier.isEmpty, !teamIdentifier.isEmpty else {
            throw CodeSigningRequirementError.missingReleaseIdentity
        }

        guard isValidBundleIdentifier(bundleIdentifier) else {
            throw CodeSigningRequirementError.invalidBundleIdentifier
        }

        guard isValidTeamIdentifier(teamIdentifier) else {
            throw CodeSigningRequirementError.invalidTeamIdentifier
        }

        let requirement = #"anchor apple generic and identifier "\#(bundleIdentifier)" and certificate leaf[subject.OU] = "\#(teamIdentifier)""#
        try validate(requirement)
        return requirement
    }

    public static func adHocDebug(bundleIdentifier: String, cdHash: String) throws -> String {
        guard !bundleIdentifier.isEmpty, !cdHash.isEmpty else {
            throw CodeSigningRequirementError.missingDebugIdentity
        }

        guard isValidBundleIdentifier(bundleIdentifier) else {
            throw CodeSigningRequirementError.invalidBundleIdentifier
        }

        guard isValidCdHash(cdHash) else {
            throw CodeSigningRequirementError.invalidCdHash
        }

        let requirement = #"identifier "\#(bundleIdentifier)" and cdhash H"\#(cdHash)""#
        try validate(requirement)
        return requirement
    }

    public static func validate(_ requirement: String) throws {
        if let releaseRequirement = parseReleaseRequirement(requirement) {
            guard isValidBundleIdentifier(releaseRequirement.bundleIdentifier) else {
                throw CodeSigningRequirementError.invalidBundleIdentifier
            }

            guard isValidTeamIdentifier(releaseRequirement.teamIdentifier) else {
                throw CodeSigningRequirementError.invalidTeamIdentifier
            }

            try compile(requirement)
            return
        }

        if let debugRequirement = parseDebugRequirement(requirement) {
            guard isValidBundleIdentifier(debugRequirement.bundleIdentifier) else {
                throw CodeSigningRequirementError.invalidBundleIdentifier
            }

            guard isValidCdHash(debugRequirement.cdHash) else {
                throw CodeSigningRequirementError.invalidCdHash
            }

            try compile(requirement)
            return
        }

        let hasIdentifier = requirement.contains("identifier ")
        let hasAppleAnchor = requirement.contains("anchor apple generic")
        let hasTeamAnchor = requirement.contains("certificate leaf[subject.OU] =")
        let hasCdHash = requirement.contains(" cdhash H\"")

        try compile(requirement)

        if requirement.hasPrefix("identifier ") && !hasCdHash {
            throw CodeSigningRequirementError.identifierOnlyRequirement
        }

        guard hasIdentifier else {
            throw CodeSigningRequirementError.missingIdentifier
        }

        if hasAppleAnchor && !hasTeamAnchor {
            throw CodeSigningRequirementError.missingTeamAnchor
        }

        guard (hasAppleAnchor && hasTeamAnchor) || hasCdHash else {
            throw CodeSigningRequirementError.missingAnchorOrCdHash
        }

        throw CodeSigningRequirementError.unsupportedRequirementShape
    }

    private static func parseReleaseRequirement(_ requirement: String) -> (bundleIdentifier: String, teamIdentifier: String)? {
        let prefix = "anchor apple generic and identifier \""
        let separator = "\" and certificate leaf[subject.OU] = \""

        guard requirement.hasPrefix(prefix), requirement.hasSuffix("\"") else {
            return nil
        }

        let body = requirement.dropFirst(prefix.count).dropLast()
        guard let separatorRange = body.range(of: separator) else {
            return nil
        }

        let bundleIdentifier = String(body[..<separatorRange.lowerBound])
        let teamIdentifier = String(body[separatorRange.upperBound...])
        return (bundleIdentifier, teamIdentifier)
    }

    private static func parseDebugRequirement(_ requirement: String) -> (bundleIdentifier: String, cdHash: String)? {
        let prefix = "identifier \""
        let separator = "\" and cdhash H\""

        guard requirement.hasPrefix(prefix), requirement.hasSuffix("\"") else {
            return nil
        }

        let body = requirement.dropFirst(prefix.count).dropLast()
        guard let separatorRange = body.range(of: separator) else {
            return nil
        }

        let bundleIdentifier = String(body[..<separatorRange.lowerBound])
        let cdHash = String(body[separatorRange.upperBound...])
        return (bundleIdentifier, cdHash)
    }

    private static func compile(_ requirement: String) throws {
        var compiledRequirement: SecRequirement?
        let status = SecRequirementCreateWithString(requirement as CFString, SecCSFlags(), &compiledRequirement)
        guard status == errSecSuccess, compiledRequirement != nil else {
            throw CodeSigningRequirementError.invalidRequirement(status: status)
        }
    }

    private static func isValidBundleIdentifier(_ bundleIdentifier: String) -> Bool {
        let segments = bundleIdentifier.split(separator: ".", omittingEmptySubsequences: false)
        guard !segments.isEmpty else {
            return false
        }

        return segments.allSatisfy { segment in
            guard let first = segment.utf8.first, let last = segment.utf8.last else {
                return false
            }

            return isASCIIAlphanumeric(first)
                && isASCIIAlphanumeric(last)
                && segment.utf8.allSatisfy { isASCIIAlphanumeric($0) || $0 == UInt8(ascii: "-") }
        }
    }

    private static func isValidTeamIdentifier(_ teamIdentifier: String) -> Bool {
        teamIdentifier.utf8.count == 10
            && teamIdentifier.utf8.allSatisfy { byte in
                isASCIIUppercaseLetter(byte) || isASCIIDigit(byte)
            }
    }

    private static func isValidCdHash(_ cdHash: String) -> Bool {
        cdHash.utf8.count == 40
            && cdHash.utf8.allSatisfy(isASCIIHexDigit)
    }

    private static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        isASCIIUppercaseLetter(byte) || isASCIILowercaseLetter(byte) || isASCIIDigit(byte)
    }

    private static func isASCIIHexDigit(_ byte: UInt8) -> Bool {
        isASCIIDigit(byte)
            || (UInt8(ascii: "A")...UInt8(ascii: "F")).contains(byte)
            || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
    }

    private static func isASCIIUppercaseLetter(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
    }

    private static func isASCIILowercaseLetter(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
    }

    private static func isASCIIDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }
}

public enum CurrentProcessCodeSigningIdentity {
    public static func teamIdentifier() throws -> String {
        var code: SecCode?
        let selfStatus = SecCodeCopySelf([], &code)
        guard selfStatus == errSecSuccess, let code else {
            throw CodeSigningRequirementError.missingReleaseIdentity
        }

        var staticCode: SecStaticCode?
        let staticStatus = SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode)
        guard staticStatus == errSecSuccess, let staticCode else {
            throw CodeSigningRequirementError.missingReleaseIdentity
        }

        var information: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
        guard infoStatus == errSecSuccess,
              let dictionary = information as? [String: Any],
              let teamIdentifier = dictionary[kSecCodeInfoTeamIdentifier as String] as? String,
              !teamIdentifier.isEmpty
        else {
            throw CodeSigningRequirementError.missingReleaseIdentity
        }

        return teamIdentifier
    }
}

public enum CodeSigningRequirementError: LocalizedError, Equatable {
    case missingReleaseIdentity
    case missingDebugIdentity
    case identifierOnlyRequirement
    case missingIdentifier
    case missingTeamAnchor
    case missingAnchorOrCdHash
    case invalidBundleIdentifier
    case invalidTeamIdentifier
    case invalidCdHash
    case unsupportedRequirementShape
    case invalidRequirement(status: OSStatus)

    public var errorDescription: String? {
        switch self {
        case .missingReleaseIdentity:
            return "Release helper builds require a bundle identifier and Team ID."
        case .missingDebugIdentity:
            return "Ad-hoc debug helper builds require a bundle identifier and cdhash."
        case .identifierOnlyRequirement:
            return "Refusing identifier-only XPC code-signing requirement for privileged helper."
        case .missingIdentifier:
            return "XPC code-signing requirement must include the expected bundle identifier."
        case .missingTeamAnchor:
            return "Release XPC code-signing requirements must include a Team ID anchor."
        case .missingAnchorOrCdHash:
            return "XPC code-signing requirement must be Team ID anchored for release or cdhash-scoped for explicit local debug builds."
        case .invalidBundleIdentifier:
            return "Bundle identifier must use dot-separated ASCII alphanumeric or hyphenated segments."
        case .invalidTeamIdentifier:
            return "Team ID must be exactly 10 uppercase ASCII alphanumeric characters."
        case .invalidCdHash:
            return "cdhash must be exactly 40 ASCII hexadecimal characters."
        case .unsupportedRequirementShape:
            return "XPC code-signing requirement must exactly match the release Team ID form or the debug cdhash form."
        case let .invalidRequirement(status):
            return "Could not compile XPC code-signing requirement. Security.framework returned \(status)."
        }
    }
}
