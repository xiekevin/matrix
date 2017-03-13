//
//  MatrixManager.swift
//  MatrixTest
//
//  Created by Kevin Xie on 3/13/17.
//  Copyright © 2017 Brigade. All rights reserved.
//

import Foundation
import MatrixSDK
import PromiseKit

class MatrixManager {
    static let shared = MatrixManager()
    
    var unauthenticatedClient: MXRestClient
    var authenticatedSession: AuthenticatedMatrixSession?
    
    init() {
        unauthenticatedClient = MXRestClient(homeServer: "https://devzero.corp.brigade.zone:8448", andOnUnrecognizedCertificateBlock: { (data: Data?) -> Bool in
            return true
        })
        unauthenticatedClient.identityServer = "https://devzero.corp.brigade.zone:8090"
    }
    
    func registerUserAndLogin(username: String, password: String) -> Promise<EmptyResponse> {
        return Promise { (fulfill, reject) in
            unauthenticatedClient.register(withLoginType: kMXLoginFlowTypeDummy, username: username, password: password, success: { (credentials) in
                guard let credential = credentials else {
                    return
                }
                self.login(credential: credential)
                fulfill(EmptyResponse())
            }) { (maybeError) in
                guard let error = maybeError else {
                    return
                }
                reject(error)
            }
        }
    }
    
    func login(username: String, password: String) -> Promise<EmptyResponse> {
        return Promise { (fulfill, reject) in
            unauthenticatedClient.login(withLoginType: kMXLoginFlowTypePassword, username: username, password: password, success: { (credentials) in
                guard let credential = credentials else {
                    return
                }
                self.login(credential: credential)
                fulfill(EmptyResponse())
            }) { (maybeError) in
                guard let error = maybeError else {
                    return
                }
                reject(error)
            }
        }
    }
    
    func startSession() -> Promise<EmptyResponse>? {
        return authenticatedSession?.start()
    }
    
    private func login(credential: MXCredentials) {
        guard let client = MXRestClient(credentials: credential, andOnUnrecognizedCertificateBlock: { (data) -> Bool in
            return true
        }) else {
            return
        }
        authenticatedSession = AuthenticatedMatrixSession(client: client)
    }
}

class EmptyResponse {
    
}
