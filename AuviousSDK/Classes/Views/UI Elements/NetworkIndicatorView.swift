//
//  NetworkIndicatorView.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 10/2/21.
//

import Foundation

class NetworkIndicatorView: UIView {
    
    //UI components
    private var bar1 = UIView(frame: .zero)
    private var bar2 = UIView(frame: .zero)
    private var bar3 = UIView(frame: .zero)
    
    //UI configuration
    private let barWidth: CGFloat = 5
    private let borderWidth: CGFloat = 0.3
    
    //Data
    private var event: NetworkStatistics?
    
    var index = 0
    
    init() {
        super.init(frame: .zero)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.roundCorners([.bottomRight], radius: 10)
    }
    
    private func setupUI() {
        layer.zPosition = 2000
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = UIColor.black.withAlphaComponent(0.5)
                
        bar3.translatesAutoresizingMaskIntoConstraints = false
        bar3.backgroundColor = NetworkGrade.optimal.color
        bar3.layer.borderWidth = borderWidth
        addSubview(bar3)
        bar3.centerXAnchor.constraint(equalTo: centerXAnchor, constant: barWidth * 1.5).isActive = true
        bar3.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 0).isActive = true
        bar3.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.5).isActive = true
        bar3.widthAnchor.constraint(equalToConstant: barWidth).isActive = true
        
        bar2.translatesAutoresizingMaskIntoConstraints = false
        bar2.backgroundColor = NetworkGrade.optimal.color
        bar2.layer.borderWidth = borderWidth
        addSubview(bar2)
        bar2.centerXAnchor.constraint(equalTo: centerXAnchor, constant: 0).isActive = true
        bar2.heightAnchor.constraint(equalTo: bar3.heightAnchor, multiplier: 0.83).isActive = true
        bar2.bottomAnchor.constraint(equalTo: bar3.bottomAnchor, constant: 0).isActive = true
        bar2.widthAnchor.constraint(equalToConstant: barWidth).isActive = true
        
        bar1.translatesAutoresizingMaskIntoConstraints = false
        bar1.backgroundColor = NetworkGrade.optimal.color
        bar1.layer.borderWidth = borderWidth
        addSubview(bar1)
        bar1.centerXAnchor.constraint(equalTo: centerXAnchor, constant: barWidth * -1.5).isActive = true
        bar1.bottomAnchor.constraint(equalTo: bar2.bottomAnchor, constant: 0).isActive = true
        bar1.heightAnchor.constraint(equalTo: bar2.heightAnchor, multiplier: 0.83).isActive = true
        bar1.widthAnchor.constraint(equalToConstant: barWidth).isActive = true
    }
        
    func updateUI(with object: ConferenceNetworkIndicatorEvent, participantId: String?) {
        guard let endpointId = participantId, let data = object.data[endpointId] else {
            return
        }
        
        self.event = data
        
        UIView.animate(withDuration: 0.25, animations: {
            switch data.grade {
            case .optimal:
                self.bar3.backgroundColor = data.grade.color
                self.bar2.backgroundColor = data.grade.color
                self.bar1.backgroundColor = data.grade.color
                self.bar3.layer.borderColor = data.grade.color.cgColor
                self.bar2.layer.borderColor = data.grade.color.cgColor
                self.bar1.layer.borderColor = data.grade.color.cgColor
            case .suboptimal:
                self.bar3.backgroundColor = .clear
                self.bar3.layer.borderColor = UIColor.white.cgColor
                self.bar2.backgroundColor = data.grade.color
                self.bar2.layer.borderColor = data.grade.color.cgColor
                self.bar1.backgroundColor = data.grade.color
                self.bar1.layer.borderColor = data.grade.color.cgColor
            case .bad:
                self.bar3.backgroundColor = .clear
                self.bar3.layer.borderColor = UIColor.white.cgColor
                self.bar2.backgroundColor = .clear
                self.bar2.layer.borderColor = UIColor.white.cgColor
                self.bar1.backgroundColor = data.grade.color
                self.bar1.layer.borderColor = data.grade.color.cgColor
            }
        })
    }
}
