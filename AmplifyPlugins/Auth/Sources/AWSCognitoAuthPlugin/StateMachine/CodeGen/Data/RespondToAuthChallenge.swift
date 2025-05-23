//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import Amplify
import AWSCognitoIdentityProvider

struct RespondToAuthChallenge: Equatable {

    let challenge: CognitoIdentityProviderClientTypes.ChallengeNameType

    let availableChallenges: [CognitoIdentityProviderClientTypes.ChallengeNameType]

    let username: String

    let session: String?

    let parameters: [String: String]?

}

extension RespondToAuthChallenge {

    var codeDeliveryDetails: AuthCodeDeliveryDetails {
        guard let parameters = parameters,
              let medium = parameters["CODE_DELIVERY_DELIVERY_MEDIUM"] else {
            return AuthCodeDeliveryDetails(destination: .unknown(nil),
                                           attributeKey: nil)
        }

        var deliveryDestination = DeliveryDestination.unknown(nil)
        let destination = parameters["CODE_DELIVERY_DESTINATION"]
        if medium == "SMS" {
            deliveryDestination = .sms(destination)
        } else if medium == "EMAIL" {
            deliveryDestination = .email(destination)
        }
        return AuthCodeDeliveryDetails(destination: deliveryDestination,
                                       attributeKey: nil)
    }

    var getAllowedMFATypesForSelection: Set<MFAType> {
        return getMFATypes(forKey: "MFAS_CAN_CHOOSE")
    }

    var getAllowedMFATypesForSetup: Set<MFAType> {
        return getMFATypes(forKey: "MFAS_CAN_SETUP")
    }

    var getAllowedAuthFactorsForSelection: Set<AuthFactorType> {
        return Set(availableChallenges.compactMap({ $0.authFactor }))
    }

    /// Helper method to extract MFA types from parameters
    private func getMFATypes(forKey key: String) -> Set<MFAType> {
        guard let mfaTypeParameters = parameters?[key],
              let mfaTypesArray = try? JSONDecoder().decode(
                [String].self,
                from: Data(mfaTypeParameters.utf8)
              )
        else { return .init() }

        let mfaTypes = mfaTypesArray.compactMap(MFAType.init(rawValue:))
        return Set(mfaTypes)
    }

    var debugDictionary: [String: Any] {
        return ["challenge": challenge,
                "username": username.masked()]
    }

    func getChallengeKey() throws -> String {
        switch challenge {
        case .customChallenge, .selectMfaType, .selectChallenge: return "ANSWER"
        case .smsMfa: return "SMS_MFA_CODE"
        case .softwareTokenMfa: return "SOFTWARE_TOKEN_MFA_CODE"
        case .newPasswordRequired: return "NEW_PASSWORD"
        case .emailOtp: return "EMAIL_OTP_CODE"
        // At the moment of writing this code, `mfaSetup` only supports EMAIL.
        // TOTP is not part of it because, it follows a completely different setup path
        case .mfaSetup: return "EMAIL"
        case .smsOtp: return "SMS_OTP_CODE"
        default:
            let message = "Unsupported challenge type for response key generation \(challenge)"
            let error = SignInError.unknown(message: message)
            throw error
        }
    }

}

extension RespondToAuthChallenge: Codable { }
