import MatrixSDK
import PromiseKit

class AuthenticatedMatrixSession {
    
    var client: MXRestClient
    var session: MXSession
    
    init(client: MXRestClient) {
        self.client = client
        self.session = MXSession(matrixRestClient: client)
    }
    
    func start() -> Promise<EmptyResponse> {
        return Promise { (fulfill, reject) in
            self.session.start({
                fulfill(EmptyResponse())
            }, failure: { (maybeError) in
                reject(maybeError ?? NSError())
            })
        }
    }
}
