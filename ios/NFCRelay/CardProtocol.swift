import Foundation
import Combine
import CieSDK

class CardProtocol: ObservableObject {
    @Published var paceResult: String = ""
    @Published var isRunning: Bool = false
    
    private let sdk = CieSDK()
    private var cancellables = Set<AnyCancellable>()
    private var logCallback: ((String) -> Void)?
    
    init() {
        setupObservers()
    }
    
    func verifyPACE(can: String, logHandler: @escaping (String) -> Void) {
        guard can.count == 6 || can.count == 8 else {
            logHandler("Error: CAN must be 6 digits (or PIN 8 digits).")
            self.paceResult = "Invalid credentials length"
            return
        }
        
        self.logCallback = logHandler
        self.isRunning = true
        self.paceResult = "Scanning..."
        logHandler("Initializing PagoPA CIE SDK...")
        
        // Configure the SDK with the user-provided CAN/PIN
        sdk.pin = can
        
        // Start the reading flow (the SDK displays the native Apple NFC sheet)
        logHandler("Starting performMtrd()...")
        sdk.performMtrd()
    }
    
    private func setupObservers() {
        let events = [
            ("ON_TAG_DISCOVERED", "NFC Tag Discovered."),
            ("CONNECTED", "Connected to CIE Card."),
            ("ON_TAG_DISCOVERED_NOT_CIE", "Error: Discovered tag is not a CIE card."),
            ("ON_TAG_WRONG_PIN", "Error: Incorrect CAN/PIN entered."),
            ("ON_TAG_BLOCKED_PIN", "Error: CIE Card is blocked (3 wrong PIN attempts)."),
            ("ON_TAG_COMMUNICATION_ERROR", "Error: NFC communication error."),
            ("ON_TAG_AUTHENTICATION_ERROR", "Error: PACE authentication failed."),
            ("ON_CARD_READ_SUCCESS", "Successfully read CIE data groups!")
        ]
        
        for (event, message) in events {
            NotificationCenter.default.publisher(for: Notification.Name(event))
                .sink { [weak self] notification in
                    guard let self = self else { return }
                    self.logCallback?(message)
                    
                    DispatchQueue.main.async {
                        if event == "ON_CARD_READ_SUCCESS" {
                            self.isRunning = false
                            if let dataString = notification.object as? String {
                                self.paceResult = "Success: Read \(dataString)"
                            } else {
                                self.paceResult = "Success"
                            }
                        } else if event.contains("ERROR") || event.contains("WRONG") || event.contains("BLOCKED") {
                            self.isRunning = false
                            self.paceResult = "Failed: \(message)"
                        }
                    }
                }
                .store(in: &cancellables)
        }
    }
}
