//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import Foundation

import XCTest
import Amplify
@testable import AWSCognitoAuthPlugin
import AWSCognitoIdentityProvider

// swiftlint:disable type_body_length
// swiftlint:disable file_length
class ConfirmSignInWithMFASelectionTaskTests: BasePluginTest {

    override var initialState: AuthState {
        AuthState.configured(
            AuthenticationState.signingIn(
                .resolvingChallenge(
                    .waitingForAnswer(
                        .testData(challenge: .selectMfaType),
                        .apiBased(.userSRP),
                        .confirmSignInWithTOTPCode
                    ),
                    .selectMFAType,
                    .apiBased(.userSRP))),
            AuthorizationState.sessionEstablished(.testData),
            .notStarted)
    }

    /// Test a successful confirmSignIn call with .confirmSignInWithSMSMFACode as next step
    ///
    /// - Given: an auth plugin with mocked service. Mocked service calls should mock a successful response
    /// - When:
    ///    - I invoke confirmSignIn with SMS as selection
    /// - Then:
    ///    - I should get a successful result with .confirmSignInWithSMSMFACode as the next step
    ///
    func testSuccessfulConfirmSignInWithSMSAsMFASelection() async {

        self.mockIdentityProvider = MockIdentityProvider(
            mockRespondToAuthChallengeResponse: { request in

                XCTAssertEqual(request.challengeName, .selectMfaType)
                XCTAssertEqual(request.challengeResponses?["ANSWER"], "SMS_MFA")

                return .testData(challenge: .smsMfa)
            })

        do {
            let confirmSignInResult = try await plugin.confirmSignIn(
                challengeResponse: MFAType.sms.challengeResponse)
            guard case .confirmSignInWithSMSMFACode = confirmSignInResult.nextStep else {
                XCTFail("Result should be .confirmSignInWithSMSMFACode for next step")
                return
            }
            XCTAssertFalse(confirmSignInResult.isSignedIn, "Signin result should NOT be complete")
        } catch {
            XCTFail("Received failure with error \(error)")
        }
    }

    /// Test a successful confirmSignIn call with .confirmSignInWithTOTPCode as next step
    ///
    /// - Given: an auth plugin with mocked service. Mocked service calls should mock a successful response
    /// - When:
    ///    - I invoke confirmSignIn with TOTP as selection
    /// - Then:
    ///    - I should get a successful result with .confirmSignInWithTOTPCode as the next step
    ///
    func testSuccessfulConfirmSignInWithTOTPAsMFASelection() async {

        self.mockIdentityProvider = MockIdentityProvider(
            mockRespondToAuthChallengeResponse: { request in

                XCTAssertEqual(request.challengeName, .selectMfaType)
                XCTAssertEqual(request.challengeResponses?["ANSWER"], "SOFTWARE_TOKEN_MFA")

                return .testData(challenge: .softwareTokenMfa)
            })

        do {
            let confirmSignInResult = try await plugin.confirmSignIn(
                challengeResponse: MFAType.totp.challengeResponse)
            guard case .confirmSignInWithTOTPCode = confirmSignInResult.nextStep else {
                XCTFail("Result should be .confirmSignInWithTOTPCode for next step")
                return
            }
            XCTAssertFalse(confirmSignInResult.isSignedIn, "Signin result should NOT be complete")
        } catch {
            XCTFail("Received failure with error \(error)")
        }
    }

    /// Test a confirmSignIn call with an invalid MFA selection
    ///
    /// - Given: an auth plugin with mocked service.
    /// - When:
    ///    - I invoke confirmSignIn with a invalid (dummy) MFA selection
    /// - Then:
    ///    - I should get an .validation error
    ///
    func testConfirmSignInWithInvalidMFASelection() async {

        self.mockIdentityProvider = MockIdentityProvider(
            mockRespondToAuthChallengeResponse: { _ in
                XCTFail("Cognito service should not be called")
                return .testData()
            })

        do {
            _ = try await plugin.confirmSignIn(challengeResponse: "dummy")
            XCTFail("Should not succeed")
        } catch {
            guard case AuthError.validation = error else {
                XCTFail("Should produce validation error instead of \(error)")
                return
            }
        }
    }
    

    /// Test a confirmSignIn call with an empty confirmation code
    ///
    /// - Given: an auth plugin with mocked service.
    /// - When:
    ///    - I invoke confirmSignIn with an empty MFA selection
    /// - Then:
    ///    - I should get an .validation error
    ///
    func testConfirmSignInWithEmptyResponse() async {

        self.mockIdentityProvider = MockIdentityProvider(
            mockRespondToAuthChallengeResponse: { _ in
                XCTFail("Cognito service should not be called")
                return .testData()
            })

        do {
            _ = try await plugin.confirmSignIn(challengeResponse: "")
            XCTFail("Should not succeed")
        } catch {
            guard case AuthError.validation = error else {
                XCTFail("Should produce validation error instead of \(error)")
                return
            }
        }
    }

    /// Test a confirmSignIn call with an empty MFA selection followed by a second valid confirmSignIn call
    ///
    /// - Given: an auth plugin with mocked service. Mocked service should mock a successful response
    /// - When:
    ///    - I invoke second confirmSignIn after confirmSignIn with an invalid MFA selection
    /// - Then:
    ///    - I should get a successful result with .confirmSignInWithTOTPCode as the next step
    ///
    func testSuccessfullyConfirmSignInAfterAFailedConfirmSignIn() async {

        self.mockIdentityProvider = MockIdentityProvider(
            mockRespondToAuthChallengeResponse: { _ in
                return .testData(challenge: .softwareTokenMfa)
            })

        do {
            _ = try await plugin.confirmSignIn(challengeResponse: "dummy")
            XCTFail("Should not succeed")
        } catch {
            guard case AuthError.validation = error else {
                XCTFail("Should produce validation error instead of \(error)")
                return
            }

            do {
                let confirmSignInResult = try await plugin.confirmSignIn(challengeResponse: MFAType.totp.challengeResponse)
                guard case .confirmSignInWithTOTPCode = confirmSignInResult.nextStep else {
                    XCTFail("Result should be .confirmSignInWithTOTPCode for next step")
                    return
                }
                XCTAssertFalse(confirmSignInResult.isSignedIn, "Signin result should NOT be complete")
            } catch {
                XCTFail("Received failure with error \(error)")
            }
        }
    }

    // MARK: Service error handling test

    /// Test a confirmSignIn call with aliasExistsException response from service
    ///
    /// - Given: an auth plugin with mocked service. Mocked service should mock a
    ///   aliasExistsException response
    /// - When:
    ///    - I invoke confirmSignIn with a valid MFA selection
    /// - Then:
    ///    - I should get a .service error with .aliasExists as underlyingError
    ///
    func testConfirmSignInWithAliasExistsException() async {

        self.mockIdentityProvider = MockIdentityProvider(
            mockRespondToAuthChallengeResponse: { _ in
                throw AWSCognitoIdentityProvider.AliasExistsException(
                    message: "Exception"
                )
            })

        do {
            _ = try await plugin.confirmSignIn(challengeResponse: MFAType.totp.challengeResponse)
            XCTFail("Should return an error if the result from service is invalid")
        } catch {
            guard case AuthError.service(_, _, let underlyingError) = error else {
                XCTFail("Should produce service error instead of \(error)")
                return
            }
            guard case .aliasExists = (underlyingError as? AWSCognitoAuthError) else {
                XCTFail("Underlying error should be aliasExists \(error)")
                return
            }
        }
    }

    /// Test a confirmSignIn call with CodeMismatchException response from service
    ///
    /// - Given: an auth plugin with mocked service. Mocked service should mock a
    ///   CodeMismatchException response
    /// - When:
    ///    - I invoke confirmSignIn with a valid MFA selection
    /// - Then:
    ///    - I should get a .service error with .codeMismatch as underlyingError
    ///
    func testConfirmSignInWithCodeMismatchException() async {
        self.mockIdentityProvider = MockIdentityProvider(
            mockRespondToAuthChallengeResponse: { _ in
                throw AWSCognitoIdentityProvider.CodeMismatchException(
                    message: "Exception"
                )
            })

        do {
            _ = try await plugin.confirmSignIn(challengeResponse: MFAType.totp.challengeResponse)
            XCTFail("Should return an error if the result from service is invalid")
        } catch {
            guard case AuthError.service(_, _, let underlyingError) = error else {
                XCTFail("Should produce service error instead of \(error)")
                return
            }
            guard case .codeMismatch = (underlyingError as? AWSCognitoAuthError) else {
                XCTFail("Underlying error should be codeMismatch \(error)")
                return
            }
        }
    }

    /// Test a successful confirmSignIn call after a CodeMismatchException response from service
    ///
    /// - Given: an auth plugin with mocked service. Mocked service should mock a
    ///   CodeMismatchException response
    /// - When:
    ///    - I invoke confirmSignIn with a valid MFA selection
    /// - Then:
    ///    - I should get a .service error with .codeMismatch as underlyingError
    /// - Then:
    ///    - I invoke confirmSignIn with a valid MFA selection, I should get a successful result
    ///
    func testConfirmSignInRetryWithCodeMismatchException() async {
        self.mockIdentityProvider = MockIdentityProvider(
            mockRespondToAuthChallengeResponse: { _ in
                throw AWSCognitoIdentityProvider.CodeMismatchException(
                    message: "Exception"
                )
            })

        do {
            _ = try await plugin.confirmSignIn(challengeResponse: MFAType.totp.challengeResponse)
            XCTFail("Should return an error if the result from service is invalid")
        } catch {
            guard case AuthError.service(_, _, let underlyingError) = error else {
                XCTFail("Should produce service error instead of \(error)")
                return
            }
            guard case .codeMismatch = (underlyingError as? AWSCognitoAuthError) else {
                XCTFail("Underlying error should be codeMismatch \(error)")
                return
            }

            self.mockIdentityProvider = MockIdentityProvider(
                mockRespondToAuthChallengeResponse: { _ in
                    return .testData(challenge: .softwareTokenMfa)
                })
            do {
                let confirmSignInResult = try await plugin.confirmSignIn(challengeResponse: MFAType.totp.challengeResponse)
                guard case .confirmSignInWithTOTPCode = confirmSignInResult.nextStep else {
                    XCTFail("Result should be .confirmSignInWithTOTPCode for next step")
                    return
                }
                XCTAssertFalse(confirmSignInResult.isSignedIn, "Signin result should NOT be complete")
            } catch {
                XCTFail("Received failure with error \(error)")
            }

        }
    }

    /// Test a confirmSignIn call with CodeExpiredException response from service
    ///
    /// - Given: an auth plugin with mocked service. Mocked service should mock a
    ///   CodeExpiredException response
    /// - When:
    ///    - I invoke confirmSignIn with a valid MFA selection
    /// - Then:
    ///    - I should get a .service error with .codeExpired as underlyingError
    ///
    func testConfirmSignInWithExpiredCodeException() async {

        self.mockIdentityProvider = MockIdentityProvider(
            mockRespondToAuthChallengeResponse: { _ in
                throw AWSCognitoIdentityProvider.ExpiredCodeException(
                    message: "Exception"
                )
            })

        do {
            _ = try await plugin.confirmSignIn(challengeResponse: MFAType.totp.challengeResponse)
            XCTFail("Should return an error if the result from service is invalid")
        } catch {
            guard case AuthError.service(_, _, let underlyingError) = error else {
                XCTFail("Should produce service error instead of \(error)")
                return
            }
            guard case .codeExpired = (underlyingError as? AWSCognitoAuthError) else {
                XCTFail("Underlying error should be codeExpired \(error)")
                return
            }
        }
    }

    /// Test a confirmSignIn call with InternalErrorException response from service
    ///
    /// - Given: an auth plugin with mocked service. Mocked service should mock a InternalErrorException response
    /// - When:
    ///    - I invoke confirmSignIn with a valid MFA selection
    /// - Then:
    ///    - I should get an .unknown error
    ///
    func testConfirmSignInWithInternalErrorException() async {

        self.mockIdentityProvider = MockIdentityProvider(
            mockRespondToAuthChallengeResponse: { _ in
                throw AWSCognitoIdentityProvider.InternalErrorException(
                    message: "Exception"
                )
            })

        do {
            _ = try await plugin.confirmSignIn(challengeResponse: MFAType.totp.challengeResponse)
            XCTFail("Should return an error if the result from service is invalid")
        } catch {
            guard case AuthError.unknown = error else {
                XCTFail("Should produce an unknown error instead of \(error)")
                return
            }
        }
    }

    /// Test a confirmSignIn call with InvalidLambdaResponseException response from service
    ///
    /// - Given: an auth plugin with mocked service. Mocked service should mock a
    ///   InvalidLambdaResponseException response
    /// - When:
    ///    - I invoke confirmSignIn with a valid MFA selection
    /// - Then:
    ///    - I should get a .service error with .lambda as underlyingError
    ///
    func testConfirmSignInWithInvalidLambdaResponseException() async {
        self.mockIdentityProvider = MockIdentityProvider(
            mockRespondToAuthChallengeResponse: { _ in
                throw AWSCognitoIdentityProvider.InvalidLambdaResponseException(
                    message: "Exception"
                )
            })

        do {
            _ = try await plugin.confirmSignIn(challengeResponse: MFAType.totp.challengeResponse)
            XCTFail("Should return an error if the result from service is invalid")
        } catch {
            guard case AuthError.service(_, _, let underlyingError) = error else {
                XCTFail("Should produce service error instead of \(error)")
                return
            }
            guard case .lambda = (underlyingError as? AWSCognitoAuthError) else {
                XCTFail("Underlying error should be lambda \(error)")
                return
            }
        }
    }

    /// Test a confirmSignIn call with InvalidParameterException response from service
    ///
    /// - Given: an auth plugin with mocked service. Mocked service should mock a
    ///   InvalidParameterException response
    ///
    /// - When:
    ///    - I invoke confirmSignIn with a valid MFA selection
    /// - Then:
    ///    - I should get a .service error with  .invalidParameter as underlyingError
    ///
    func testConfirmSignInWithInvalidParameterException() async {

        self.mockIdentityProvider = MockIdentityProvider(
            mockRespondToAuthChallengeResponse: { _ in
                throw AWSCognitoIdentityProvider.InvalidParameterException(
                    message: "Exception"
                )
            })

        do {
            _ = try await plugin.confirmSignIn(challengeResponse: MFAType.totp.challengeResponse)
            XCTFail("Should return an error if the result from service is invalid")
        } catch {
            guard case AuthError.service(_, _, let underlyingError) = error else {
                XCTFail("Should produce service error instead of \(error)")
                return
            }
            guard case .invalidParameter = (underlyingError as? AWSCognitoAuthError) else {
                XCTFail("Underlying error should be invalidParameter \(error)")
                return
            }
        }
    }

    /// Test a confirmSignIn call with InvalidPasswordException response from service
    ///
    /// - Given: an auth plugin with mocked service. Mocked service should mock a
    ///   InvalidPasswordException response
    ///
    /// - When:
    ///    - I invoke confirmSignIn with a valid MFA selection
    /// - Then:
    ///    - I should get a .service error with  .invalidPassword as underlyingError
    ///
    func testConfirmSignInWithInvalidPasswordException() async {

        self.mockIdentityProvider = MockIdentityProvider(
            mockRespondToAuthChallengeResponse: { _ in
                throw AWSCognitoIdentityProvider.InvalidPasswordException(
                    message: "Exception"
                )
            })

        do {
            _ = try await plugin.confirmSignIn(challengeResponse: MFAType.totp.challengeResponse)
            XCTFail("Should return an error if the result from service is invalid")
        } catch {
            guard case AuthError.service(_, _, let underlyingError) = error else {
                XCTFail("Should produce service error instead of \(error)")
                return
            }
            guard case .invalidPassword = (underlyingError as? AWSCognitoAuthError) else {
                XCTFail("Underlying error should be invalidPassword \(error)")
                return
            }
        }
    }

    /// Test a confirmSignIn call with InvalidSmsRoleAccessPolicy response from service
    ///
    /// - Given: an auth plugin with mocked service. Mocked service should mock a
    ///   InvalidSmsRoleAccessPolicyException response
    /// - When:
    ///    - I invoke confirmSignIn with a valid MFA selection
    /// - Then:
    ///    - I should get a .service error with  .smsRole as underlyingError
    ///
    func testConfirmSignInWithinvalidSmsRoleAccessPolicyException() async {
        self.mockIdentityProvider = MockIdentityProvider(
            mockRespondToAuthChallengeResponse: { _ in
                throw AWSCognitoIdentityProvider.InvalidSmsRoleAccessPolicyException(
                    message: "Exception"
                )
            })

        do {
            _ = try await plugin.confirmSignIn(challengeResponse: MFAType.totp.challengeResponse)
            XCTFail("Should return an error if the result from service is invalid")
        } catch {
            guard case AuthError.service(_, _, let underlyingError) = error else {
                XCTFail("Should produce service error instead of \(error)")
                return
            }
            guard case .smsRole = (underlyingError as? AWSCognitoAuthError) else {
                XCTFail("Underlying error should be invalidPassword \(error)")
                return
            }
        }
    }

    /// Test a confirmSignIn call with InvalidSmsRoleTrustRelationship response from service
    ///
    /// - Given: Given an auth plugin with mocked service. Mocked service should mock a
    ///   CodeDeliveryFailureException response
    /// - When:
    ///    - I invoke confirmSignIn with a valid MFA selection
    /// - Then:
    ///    - I should get a .service error with  .smsRole as underlyingError
    ///
    func testConfirmSignInWithInvalidSmsRoleTrustRelationshipException() async {
        self.mockIdentityProvider = MockIdentityProvider(
            mockRespondToAuthChallengeResponse: { _ in
                throw AWSCognitoIdentityProvider.InvalidSmsRoleTrustRelationshipException(
                    message: "Exception"
                )
            })

        do {
            _ = try await plugin.confirmSignIn(challengeResponse: MFAType.totp.challengeResponse)
            XCTFail("Should return an error if the result from service is invalid")
        } catch {
            guard case AuthError.service(_, _, let underlyingError) = error else {
                XCTFail("Should produce service error instead of \(error)")
                return
            }
            guard case .smsRole = (underlyingError as? AWSCognitoAuthError) else {
                XCTFail("Underlying error should be invalidPassword \(error)")
                return
            }
        }
    }

    /// Test a confirmSignIn with User pool configuration from service
    ///
    /// - Given: an auth plugin with mocked service with no User Pool configuration
    ///
    /// - When:
    ///    - I invoke confirmSignIn with a valid MFA selection
    /// - Then:
    ///    - I should get a .configuration error
    ///
    func testConfirmSignInWithInvalidUserPoolConfigurationException() async {
        let identityPoolConfigData = Defaults.makeIdentityConfigData()
        let authorizationEnvironment = BasicAuthorizationEnvironment(
            identityPoolConfiguration: identityPoolConfigData,
            cognitoIdentityFactory: Defaults.makeIdentity)
        let environment = AuthEnvironment(
            configuration: .identityPools(identityPoolConfigData),
            userPoolConfigData: nil,
            identityPoolConfigData: identityPoolConfigData,
            authenticationEnvironment: nil,
            authorizationEnvironment: authorizationEnvironment,
            credentialsClient: Defaults.makeCredentialStoreOperationBehavior(),
            logger: Amplify.Logging.logger(forCategory: "awsCognitoAuthPluginTest")
        )
        let stateMachine = Defaults.authStateMachineWith(environment: environment,
                                                         initialState: .notConfigured)
        let plugin = AWSCognitoAuthPlugin()
        plugin.configure(
            authConfiguration: .identityPools(identityPoolConfigData),
            authEnvironment: environment,
            authStateMachine: stateMachine,
            credentialStoreStateMachine: Defaults.makeDefaultCredentialStateMachine(),
            hubEventHandler: MockAuthHubEventBehavior(),
            analyticsHandler: MockAnalyticsHandler())

        do {
            _ = try await plugin.confirmSignIn(challengeResponse: MFAType.totp.challengeResponse)
            XCTFail("Should return an error if the result from service is invalid")
        } catch {
            guard case AuthError.configuration(_, _, _) = error else {
                XCTFail("Should produce configuration instead produced \(error)")
                return
            }
        }

    }

    /// Test a confirmSignIn with MFAMethodNotFoundException from service
    ///
    /// - Given: an auth plugin with mocked service. Mocked service should mock a
    ///   MFAMethodNotFoundException response
    ///
    /// - When:
    ///    - I invoke confirmSignIn with a valid MFA selection
    /// - Then:
    ///    - I should get a .service error with  .mfaMethodNotFound as underlyingError
    ///
    func testCofirmSignInWithMFAMethodNotFoundException() async {

        self.mockIdentityProvider = MockIdentityProvider(
            mockRespondToAuthChallengeResponse: { _ in
                throw AWSCognitoIdentityProvider.MFAMethodNotFoundException(
                    message: "Exception"
                )
            })

        do {
            _ = try await plugin.confirmSignIn(challengeResponse: MFAType.totp.challengeResponse)
            XCTFail("Should not succeed")
        } catch {
            guard case AuthError.service(_, _, let underlyingError) = error else {
                XCTFail("Should produce service error instead of \(error)")
                return
            }
            guard case .mfaMethodNotFound = (underlyingError as? AWSCognitoAuthError) else {
                XCTFail("Underlying error should be mfaMethodNotFound \(error)")
                return
            }
        }
    }

    /// Test a confirmSignIn call with NotAuthorizedException response from service
    ///
    /// - Given: an auth plugin with mocked service. Mocked service should mock a
    ///   NotAuthorizedException response
    ///
    /// - When:
    ///    - I invoke confirmSignIn with a valid MFA selection
    /// - Then:
    ///    - I should get a .notAuthorized error
    ///
    func testConfirmSignInWithNotAuthorizedException() async {

        self.mockIdentityProvider = MockIdentityProvider(
            mockRespondToAuthChallengeResponse: { _ in
                throw AWSCognitoIdentityProvider.NotAuthorizedException(
                    message: "Exception"
                )
            })

        do {
            _ = try await plugin.confirmSignIn(challengeResponse: MFAType.totp.challengeResponse)
            XCTFail("Should return an error if the result from service is invalid")
        } catch {
            guard case AuthError.notAuthorized = error else {
                XCTFail("Should produce notAuthorized error instead of \(error)")
                return
            }
        }
    }

    /// Test a confirmSignIn with PasswordResetRequiredException from service
    ///
    /// - Given: an auth plugin with mocked service. Mocked service should mock a
    ///   PasswordResetRequiredException response
    ///
    /// - When:
    ///    - I invoke confirmSignIn with a valid MFA selection
    /// - Then:
    ///    - I should get a .resetPassword as next step
    ///
    func testConfirmSignInWithPasswordResetRequiredException() async {

        self.mockIdentityProvider = MockIdentityProvider(
            mockRespondToAuthChallengeResponse: { _ in
                throw AWSCognitoIdentityProvider.PasswordResetRequiredException(
                    message: "Exception"
                )
            })

        do {
            let confirmSignInResult = try await plugin.confirmSignIn(challengeResponse: MFAType.totp.challengeResponse)
            guard case .resetPassword = confirmSignInResult.nextStep else {
                XCTFail("Result should be .resetPassword for next step")
                return
            }
        } catch {
            XCTFail("Should not return error \(error)")
        }
    }


    /// Test a confirmSignIn call with SoftwareTokenMFANotFoundException response from service
    ///
    /// - Given: an auth plugin with mocked service. Mocked service should mock a
    ///   SoftwareTokenMFANotFoundException response
    ///
    /// - When:
    ///    - I invoke confirmSignIn with a valid MFA selection
    /// - Then:
    ///    - I should get a .service error with .softwareTokenMFANotEnabled as underlyingError
    ///
    func testConfirmSignInWithSoftwareTokenMFANotFoundException() async {

        self.mockIdentityProvider = MockIdentityProvider(
            mockRespondToAuthChallengeResponse: { _ in
                throw AWSCognitoIdentityProvider.SoftwareTokenMFANotFoundException(
                    message: "Exception"
                )
            })

        do {
            _ = try await plugin.confirmSignIn(challengeResponse: MFAType.totp.challengeResponse)
            XCTFail("Should return an error if the result from service is invalid")
        } catch {
            guard case AuthError.service(_, _, let underlyingError) = error else {
                XCTFail("Should produce service error instead of \(error)")
                return
            }
            guard case .softwareTokenMFANotEnabled = (underlyingError as? AWSCognitoAuthError) else {
                XCTFail("Underlying error should be softwareTokenMFANotEnabled \(error)")
                return
            }
        }
    }

    /// Test a confirmSignIn call with TooManyRequestsException response from service
    ///
    /// - Given: an auth plugin with mocked service. Mocked service should mock a
    ///   TooManyRequestsException response
    ///
    /// - When:
    ///    - I invoke confirmSignIn with a valid MFA selection
    /// - Then:
    ///    - I should get a .service error with .requestLimitExceeded as underlyingError
    ///
    func testConfirmSignInWithTooManyRequestsException() async {

        self.mockIdentityProvider = MockIdentityProvider(
            mockRespondToAuthChallengeResponse: { _ in
                throw AWSCognitoIdentityProvider.TooManyRequestsException(
                    message: "Exception"
                )
            })

        do {
            _ = try await plugin.confirmSignIn(challengeResponse: MFAType.totp.challengeResponse)
            XCTFail("Should return an error if the result from service is invalid")
        } catch {
            guard case AuthError.service(_, _, let underlyingError) = error else {
                XCTFail("Should produce service error instead of \(error)")
                return
            }
            guard case .requestLimitExceeded = (underlyingError as? AWSCognitoAuthError) else {
                XCTFail("Underlying error should be requestLimitExceeded \(error)")
                return
            }
        }
    }

    /// Test a confirmSignIn call with UnexpectedLambdaException response from service
    ///
    /// - Given: an auth plugin with mocked service. Mocked service should mock a
    ///   UnexpectedLambdaException response
    ///
    /// - When:
    ///    - I invoke confirmSignIn with a valid MFA selection
    /// - Then:
    ///    - I should get a .service error with .lambda as underlyingError
    ///
    func testConfirmSignInWithUnexpectedLambdaException() async {

        self.mockIdentityProvider = MockIdentityProvider(
            mockRespondToAuthChallengeResponse: { _ in
                throw AWSCognitoIdentityProvider.UnexpectedLambdaException(
                    message: "Exception"
                )
            })

        do {
            _ = try await plugin.confirmSignIn(challengeResponse: MFAType.totp.challengeResponse)
            XCTFail("Should return an error if the result from service is invalid")
        } catch {
            guard case AuthError.service(_, _, let underlyingError) = error else {
                XCTFail("Should produce service error instead of \(error)")
                return
            }
            guard case .lambda = (underlyingError as? AWSCognitoAuthError) else {
                XCTFail("Underlying error should be lambda \(error)")
                return
            }
        }
    }

    /// Test a confirmSignIn call with UserLambdaValidationException response from service
    ///
    /// - Given: an auth plugin with mocked service. Mocked service should mock a
    ///   UserLambdaValidationException response
    ///
    /// - When:
    ///    - I invoke confirmSignIn with a valid MFA selection
    /// - Then:
    ///    - I should get a .service error with .lambda as underlyingError
    ///
    func testConfirmSignInWithUserLambdaValidationException() async {

        self.mockIdentityProvider = MockIdentityProvider(
            mockRespondToAuthChallengeResponse: { _ in
                throw AWSCognitoIdentityProvider.UserLambdaValidationException(
                    message: "Exception"
                )
            })

        do {
            _ = try await plugin.confirmSignIn(challengeResponse: MFAType.totp.challengeResponse)
            XCTFail("Should return an error if the result from service is invalid")
        } catch {
            guard case AuthError.service(_, _, let underlyingError) = error else {
                XCTFail("Should produce service error instead of \(error)")
                return
            }
            guard case .lambda = (underlyingError as? AWSCognitoAuthError) else {
                XCTFail("Underlying error should be lambda \(error)")
                return
            }
        }
    }

    /// Test a confirmSignIn call with UserNotConfirmedException response from service
    ///
    /// - Given: Given an auth plugin with mocked service. Mocked service should mock a
    ///   UserNotConfirmedException response
    ///
    /// - When:
    ///    - I invoke confirmSignIn with a valid MFA selection
    /// - Then:
    ///    - I should get .confirmSignUp as next step
    ///
    func testConfirmSignInWithUserNotConfirmedException() async {

        self.mockIdentityProvider = MockIdentityProvider(
            mockRespondToAuthChallengeResponse: { _ in
                throw AWSCognitoIdentityProvider.UserNotConfirmedException(
                    message: "Exception"
                )
            })

        do {
            let confirmSignInResult = try await plugin.confirmSignIn(challengeResponse: MFAType.totp.challengeResponse)
            guard case .confirmSignUp = confirmSignInResult.nextStep else {
                XCTFail("Result should be .confirmSignUp for next step")
                return
            }
        } catch {
            XCTFail("Should not return error \(error)")
        }
    }

    /// Test a confirmSignIn call with UserNotFound response from service
    ///
    /// - Given: an auth plugin with mocked service. Mocked service should mock a
    ///   UserNotFoundException response
    ///
    /// - When:
    ///    - I invoke confirmSignIn with a valid MFA selection
    /// - Then:
    ///    - I should get a .userNotFound error
    ///
    func testConfirmSignInWithUserNotFoundException() async {

        self.mockIdentityProvider = MockIdentityProvider(
            mockRespondToAuthChallengeResponse: { _ in
                throw AWSCognitoIdentityProvider.UserNotFoundException(
                    message: "Exception"
                )
            })

        do {
            _ = try await plugin.confirmSignIn(challengeResponse: MFAType.totp.challengeResponse)
            XCTFail("Should return an error if the result from service is invalid")
        } catch {
            guard case AuthError.service(_, _, let underlyingError) = error else {
                XCTFail("Should produce service error instead of \(error)")
                return
            }
            guard case .userNotFound = (underlyingError as? AWSCognitoAuthError) else {
                XCTFail("Underlying error should be userNotFound \(error)")
                return
            }
        }
    }
}
