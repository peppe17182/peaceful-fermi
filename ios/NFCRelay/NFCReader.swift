import Foundation
import CoreNFC
import Combine

@MainActor
class NFCReader: NSObject, ObservableObject {
    @Published var statusMessage: String = "Ready to scan"
    @Published var isSessionActive: Bool = false
    @Published var connectedTagATR: String = ""
    @Published var logs: [String] = []
    
    private var session: NFCTagReaderSession?
    private var activeTag: NFCISO7816Tag?
    
    // Callback when a tag is detected and connected
    var onTagConnected: (() -> Void)?
    var onTagDisconnected: (() -> Void)?
    
    func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append("[\(timestamp)] \(message)")
        if logs.count > 100 {
            logs.removeFirst()
        }
    }
    
    func startSession() {
        log("Starting NFC Tag Reader Session...")
        session = NFCTagReaderSession(pollingOption: [.iso14443], delegate: self, queue: nil)
        session?.alertMessage = "Hold your CIE / TS-CNS card close to the top of your iPhone."
        session?.begin()
    }
    
    func stopSession(alertMessage: String? = nil) {
        if let msg = alertMessage {
            session?.alertMessage = msg
        }
        session?.invalidate()
        session = nil
        activeTag = nil
        isSessionActive = false
    }
    
    // MARK: - NFCTagReaderSessionDelegate (called on NFC internal queue, hop to MainActor)
    
    nonisolated func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        Task { @MainActor in
            self.log("NFC Session Active.")
            self.isSessionActive = true
            self.statusMessage = "Hold card near iPhone"
        }
    }
    
    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        Task { @MainActor in
            let nfcError = error as NSError
            if nfcError.code == 200 { // User cancelled
                self.log("NFC Session cancelled by user.")
                self.statusMessage = "Scan cancelled"
            } else {
                self.log("NFC Session invalidated with error: \(error.localizedDescription)")
                self.statusMessage = "Error: \(error.localizedDescription)"
            }
            self.isSessionActive = false
            self.connectedTagATR = ""
            self.activeTag = nil
            self.onTagDisconnected?()
        }
    }
    
    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let firstTag = tags.first else {
            session.invalidate(errorMessage: "No tags found.")
            return
        }
        
        session.connect(to: firstTag) { [weak self] (error: Error?) in
            guard let self else { return }
            
            if let error = error {
                Task { @MainActor in
                    self.log("Connection failed: \(error.localizedDescription)")
                }
                session.invalidate(errorMessage: "Connection failed: \(error.localizedDescription)")
                return
            }
            
            switch firstTag {
            case .iso7816(let tag):
                let historicalBytes = tag.historicalBytes ?? Data()
                let atr = self.deriveATR(from: historicalBytes)
                let atrHex = atr.map { String(format: "%02X", $0) }.joined()
                let hbHex = historicalBytes.map { String(format: "%02X", $0) }.joined()
                
                nonisolated(unsafe) let safeTag = tag
                nonisolated(unsafe) let safeSession = session
                
                Task { @MainActor in
                    self.activeTag = safeTag
                    self.connectedTagATR = atrHex
                    self.statusMessage = "Card connected!"
                    self.log("Successfully connected to ISO7816 Tag.")
                    self.log("ATS Historical Bytes: \(hbHex)")
                    self.log("Simulated ATR: \(atrHex)")
                    safeSession.alertMessage = "Card connected. Keep card near iPhone."
                    self.onTagConnected?()
                }
                
            default:
                session.invalidate(errorMessage: "Unsupported tag type. Needs ISO7816.")
                Task { @MainActor in
                    self.log("Unsupported tag type.")
                }
            }
        }
    }
    
    // Derives an ATR from historical bytes (or returns a default CIE ATR if empty)
    nonisolated private func deriveATR(from historicalBytes: Data) -> Data {
        let defaultCIEATR = Data([
            0x3B, 0x8F, 0x80, 0x01, 0x80, 0x4F, 0x0C, 0xA0, 0x00, 0x00, 0x03, 0x06, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x6A
        ])
        if historicalBytes.isEmpty {
            return defaultCIEATR
        }
        
        var atr = Data([0x3B, 0x8F, 0x80, 0x01])
        atr.append(historicalBytes)
        
        var checksum: UInt8 = 0
        for byte in atr {
            checksum ^= byte
        }
        atr.append(checksum)
        return atr
    }
    
    // Sends raw APDU to the tag and returns the raw response including SW1 and SW2
    func sendAPDU(_ apduData: Data) async throws -> Data {
        guard let tag = activeTag else {
            log("Error: Send APDU called, but no tag is active.")
            throw NSError(domain: "NFCReader", code: 404, userInfo: [NSLocalizedDescriptionKey: "No active NFC tag connected"])
        }
        
        guard let apdu = NFCISO7816APDU(data: apduData) else {
            log("Error: Invalid APDU format (Length: \(apduData.count) bytes)")
            throw NSError(domain: "NFCReader", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid APDU format"])
        }
        
        log("--> \(apduData.map { String(format: "%02X", $0) }.joined(separator: " "))")
        
        return try await withCheckedThrowingContinuation { continuation in
            tag.sendCommand(apdu: apdu) { [weak self] (responseData: Data, sw1: UInt8, sw2: UInt8, error: Error?) in
                if let error = error {
                    Task { @MainActor in
                        self?.log("Command error: \(error.localizedDescription)")
                    }
                    continuation.resume(throwing: error)
                    return
                }
                
                var fullResponse = responseData
                fullResponse.append(sw1)
                fullResponse.append(sw2)
                
                Task { @MainActor in
                    self?.log("<-- \(fullResponse.map { String(format: "%02X", $0) }.joined(separator: " "))")
                }
                continuation.resume(returning: fullResponse)
            }
        }
    }
}

// MARK: - NFCTagReaderSessionDelegate conformance (nonisolated methods declared above)
extension NFCReader: NFCTagReaderSessionDelegate {}
