import UIKit
import MatrixSDK

class LoginViewController: UIViewController {

    @IBOutlet weak var usernameTextField: UITextField!
    @IBOutlet weak var passwordTextField: UITextField!
    
    let manager = MatrixManager.shared
    
    @IBAction func createAccountTapped(_ sender: Any) {
        let promise = manager.registerUserAndLogin(username: usernameTextField.text!, password: passwordTextField.text!)
        promise.then { (_) -> Void in
            self.performSegue(withIdentifier: "toGroups", sender: nil)
        }
        
        promise.catch { (error) in
            print("error")
        }
    }
    
    @IBAction func loginTapped(_ sender: Any) {
        let promise = manager.login(username: usernameTextField.text!, password: passwordTextField.text!)
        promise.then { (_) -> Void in
            self.performSegue(withIdentifier: "toGroups", sender: nil)
        }
        
        promise.catch { (error) in
            print("error")
        }
    }
}

