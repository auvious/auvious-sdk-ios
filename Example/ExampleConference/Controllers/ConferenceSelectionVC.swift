//
//  ConferenceSelectionVC.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 24/12/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import UIKit
import SVProgressHUD
import AuviousSDK

class ConferenceSelectionVC: UIViewController, UITextFieldDelegate, UITableViewDataSource, UITableViewDelegate, ConferenceVCDelegate {
    
    @IBOutlet weak var conferenceTextfield: UITextField!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var createConfBtn: UIButton!
    @IBOutlet weak var joinConfBtn: UIButton!
    @IBOutlet weak var tableView: UITableView!
    
    private var createdConferences: [String] = [String]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Conference Selection"
        let logoutButton = UIBarButtonItem(title: "Logout", style: .done, target: self, action: #selector(self.logout))
        logoutButton.tintColor = .gray
        self.navigationItem.leftBarButtonItem = logoutButton
        
        createConfBtn.layer.cornerRadius = 5.0
        joinConfBtn.layer.cornerRadius = 5.0
        
        tableView.register(UINib(nibName: "ConferenceSelectionTableViewCell", bundle: nil), forCellReuseIdentifier: "ConferenceSelectionTableViewCell")
        tableView.register(UINib(nibName: "ConferenceSelectionTableViewHeader", bundle: nil), forHeaderFooterViewReuseIdentifier: "ConferenceSelectionTableViewHeader")
        tableView.tableFooterView = UIView(frame: .zero)
                
        let tapGesture: UITapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(ConferenceSelectionVC.endEditing(_:)))
        self.view.addGestureRecognizer(tapGesture)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        conferenceTextfield.text = ""
        statusLabel.text = "Idle"
        
        tableView.reloadData()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if !AuviousConferenceSDK.sharedInstance.isLoggedIn {
            let vc = LoginVC()
            let nc = UINavigationController(rootViewController: vc)
            self.navigationController?.present(nc, animated: true, completion: nil)
        }
    }
    
    //MARK: TableView delegate
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "ConferenceSelectionTableViewHeader") as! ConferenceSelectionTableViewHeader
        
        if(createdConferences.count > 0){
            headerView.headerTitleLb.text = "Available Conferences"
        }
        else{
            headerView.headerTitleLb.text = ""
        }
        
        return headerView
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return createdConferences.count
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 54
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ConferenceSelectionTableViewCell", for: indexPath) as! ConferenceSelectionTableViewCell
        
        cell.selectionStyle = .none
        cell.confIdLb.text = createdConferences[indexPath.row]
        cell.joinBtn.tag = indexPath.row
        cell.joinBtn.addTarget(self, action: #selector(listJoinButtonClicked), for: .touchUpInside)
        
        return cell
    }
    
    //MARK: Textfield delegate
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        
        if(textField == conferenceTextfield){
            textField.resignFirstResponder()
        }
        return true
    }
    
    //MARK: Actions
    @objc func logout(){
        AuviousConferenceSDK.sharedInstance.logout(onSuccess: {
            
            if !AuviousConferenceSDK.sharedInstance.isLoggedIn {
                let vc = LoginVC()
                let nc = UINavigationController(rootViewController: vc)
                self.navigationController?.present(nc, animated: true, completion: nil)
            }
            
        }, onFailure: {(error) in
            self.showAlert(title: "Error", msg: error.localizedDescription)
        })
    }
    
    @objc func listJoinButtonClicked(sender: UIButton){
        let tag = sender.tag
        joinConference(id: createdConferences[tag])
    }
    
    @IBAction func createConferenceButtonPressed(_ sender: Any) {
        if let input = conferenceTextfield.text, !input.isEmpty {
            createConference(id: input.trim())
        } else {
            showAlert(title: "Error", msg: "Please enter a conference name.")
        }
    }
    
    @IBAction func joinConferenceButtonPressed(_ sender: Any) {
        if let input = conferenceTextfield.text, !input.isEmpty {
            joinConference(id: input.trim())
        } else {
            showAlert(title: "Error", msg: "Please enter a conference name.")
        }
    }
    
    @objc func endEditing(_ gesture: UITapGestureRecognizer){
        dismisKeyboard()
    }
    
    func dismisKeyboard(){
        self.view.endEditing(true)
    }
    
    //Create conference
    func createConference(id:String){
        
        dismisKeyboard()
        SVProgressHUD.show(withStatus: NSLocalizedString("Please wait...", comment: "General"))
        
        AuviousConferenceSDK.sharedInstance.createConference(id:id, mode: .router, onSuccess: {(conferenceSummary) in
            
            SVProgressHUD.dismiss()
            
            if let conference = conferenceSummary {
                os_log("Created conference with id %@", log: Log.conferenceApp, type: .info, String(describing: conference.id))
                self.statusLabel.text = "Created conference"
                self.conferenceTextfield.text = conference.id
                self.addCreatedConferenceToList(confId: conference.id)
                self.tableView.reloadData()
            }
        }, onFailure: {(error) in
            SVProgressHUD.dismiss()
            self.showAlert(title: "Error", msg: error.localizedDescription)
        })
    }
    
    //Join conference
    func joinConference(id:String){
        
        dismisKeyboard()
        SVProgressHUD.show(withStatus: NSLocalizedString("Please wait...", comment: "General"))
        
        AuviousConferenceSDK.sharedInstance.joinConference(conferenceId: id, onSuccess: {(joinedConference) in
            
            SVProgressHUD.dismiss()
            
            if let jConference = joinedConference {
                os_log("Joined conference with id %@", log: Log.conferenceApp, type: .info, String(describing: jConference.id))
                self.statusLabel.text = "Joined conference"
                
                let vc = ConferenceVC(conference: jConference)
                vc.delegate = self
                self.navigationController?.pushViewController(vc, animated: true)
                
            }
        }, onFailure: {(error) in
            SVProgressHUD.dismiss()
            self.showAlert(title: "Error", msg: error.localizedDescription)
        })
    }
    
    private func addCreatedConferenceToList(confId: String) {
        createdConferences.append(confId)
    }
    
    func removeCreatedConferenceFromList(confId: String) {
        if let index = createdConferences.firstIndex(of: confId) {
            createdConferences.remove(at: index)
        }
    }
}
