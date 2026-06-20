import Foundation
import Network
import Combine

class RelayServer: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var connectionState: String = "Disconnected"
    @Published var serverPort: UInt16 = 35963
    
    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private let nfcReader: NFCReader
    
    init(nfcReader: NFCReader) {
        self.nfcReader = nfcReader
    }
    
    func start() {
        guard !isRunning else { return }
        
        do {
            let parameters = NWParameters.tcp
            // Allow fast reuse of port
            parameters.requiredInterfaceType = .wifi
            
            let port = NWEndpoint.Port(rawValue: serverPort)!
            let newListener = try NWListener(using: parameters, on: port)
            
            newListener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.nfcReader.log("TCP Relay Server listening on port \(self.serverPort)...")
                    DispatchQueue.main.async {
                        self.isRunning = true
                        self.connectionState = "Listening"
                    }
                case .failed(let error):
                    self.nfcReader.log("TCP Relay Server listener failed: \(error.localizedDescription)")
                    self.stop()
                default:
                    break
                }
            }
            
            newListener.newConnectionHandler = { [weak self] connection in
                guard let self = self else { return }
                if self.activeConnection != nil {
                    self.nfcReader.log("Rejecting incoming connection, already have an active session.")
                    connection.cancel()
                    return
                }
                self.setupConnection(connection)
            }
            
            newListener.start(queue: .global(qos: .userInitiated))
            self.listener = newListener
            
        } catch {
            nfcReader.log("Failed to start TCP Server: \(error.localizedDescription)")
        }
    }
    
    func stop() {
        activeConnection?.cancel()
        activeConnection = nil
        
        listener?.cancel()
        listener = nil
        
        DispatchQueue.main.async {
            self.isRunning = false
            self.connectionState = "Disconnected"
        }
        nfcReader.log("TCP Relay Server stopped.")
    }
    
    private func setupConnection(_ connection: NWConnection) {
        activeConnection = connection
        nfcReader.log("Accepted connection from \(connection.endpoint)...")
        
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.nfcReader.log("TCP Connection established.")
                DispatchQueue.main.async {
                    self.connectionState = "Connected to PC"
                }
                self.readNextMessageHeader()
            case .failed(let error):
                self.nfcReader.log("TCP Connection failed: \(error.localizedDescription)")
                self.closeActiveConnection()
            case .cancelled:
                self.nfcReader.log("TCP Connection cancelled.")
                self.closeActiveConnection()
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
    }
    
    private func closeActiveConnection() {
        activeConnection = nil
        DispatchQueue.main.async {
            if self.isRunning {
                self.connectionState = "Listening"
            } else {
                self.connectionState = "Disconnected"
            }
        }
    }
    
    // MARK: - vpicc Protocol Parsing
    
    private func readNextMessageHeader() {
        guard let connection = activeConnection else { return }
        
        // Read 2 bytes length prefix (big-endian)
        connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { [weak self] (data, _, isComplete, error) in
            guard let self = self else { return }
            
            if let error = error {
                self.nfcReader.log("Error receiving message length: \(error.localizedDescription)")
                self.closeActiveConnection()
                return
            }
            
            if isComplete && data == nil {
                self.nfcReader.log("PC disconnected (EOF).")
                self.closeActiveConnection()
                return
            }
            
            guard let lengthData = data, lengthData.count == 2 else {
                if !isComplete {
                    self.readNextMessageHeader()
                }
                return
            }
            
            // Convert big-endian bytes to UInt16
            let messageLength = UInt16(lengthData[0]) << 8 | UInt16(lengthData[1])
            if messageLength == 0 {
                // Keep reading
                self.readNextMessageHeader()
                return
            }
            
            self.readMessagePayload(length: Int(messageLength))
        }
    }
    
    private func readMessagePayload(length: Int) {
        guard let connection = activeConnection else { return }
        
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] (data, _, isComplete, error) in
            guard let self = self else { return }
            
            if let error = error {
                self.nfcReader.log("Error receiving payload: \(error.localizedDescription)")
                self.closeActiveConnection()
                return
            }
            
            guard let payload = data, payload.count == length else {
                self.nfcReader.log("Incomplete payload received.")
                self.closeActiveConnection()
                return
            }
            
            Task {
                await self.handleIncomingPayload(payload)
                self.readNextMessageHeader()
            }
        }
    }
    
    private func handleIncomingPayload(_ payload: Data) async {
        guard !payload.isEmpty else { return }
        
        if payload.count == 1 {
            // Handle control commands
            let controlByte = payload[0]
            switch controlByte {
            case 0x00: // Power Off
                nfcReader.log("PC sent Control: Power Off")
                // Return empty response with length 0
                sendTCPResponse(Data())
                
            case 0x01: // Power On
                nfcReader.log("PC sent Control: Power On")
                let atr = await getATR()
                sendTCPResponse(atr)
                
            case 0x02: // Reset
                nfcReader.log("PC sent Control: Reset")
                let atr = await getATR()
                sendTCPResponse(atr)
                
            case 0x04: // Get ATR
                nfcReader.log("PC sent Control: Get ATR")
                let atr = await getATR()
                sendTCPResponse(atr)
                
            default:
                nfcReader.log("PC sent unknown control byte: \(String(format: "%02X", controlByte))")
                sendTCPResponse(Data())
            }
        } else {
            // Raw APDU command
            do {
                if !nfcReader.isSessionActive {
                    // Automatically prompt to scan tag if session isn't active
                    nfcReader.log("PC sent APDU, but NFC session not active. Starting session...")
                    nfcReader.startSession()
                    
                    // Wait for card to connect (wait up to 10 seconds)
                    var retries = 0
                    while !nfcReader.isSessionActive && retries < 100 {
                        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                        retries += 1
                    }
                }
                
                let response = try await nfcReader.sendAPDU(payload)
                sendTCPResponse(response)
            } catch {
                nfcReader.log("APDU relay failed: \(error.localizedDescription)")
                // Send general error code: SW1=6F, SW2=00
                sendTCPResponse(Data([0x6F, 0x00]))
            }
        }
    }
    
    private func getATR() async -> Data {
        let hexString = nfcReader.connectedTagATR
        if !hexString.isEmpty {
            // Parse hex string back to Data
            var data = Data()
            var index = hexString.startIndex
            while index < hexString.endIndex {
                let nextIndex = hexString.index(index, offsetBy: 2)
                if let byte = UInt8(hexString[index..<nextIndex], radix: 16) {
                    data.append(byte)
                }
                index = nextIndex
            }
            return data
        } else {
            // Default CIE ATR
            return Data([
                0x3B, 0x8F, 0x80, 0x01, 0x80, 0x4F, 0x0C, 0xA0, 0x00, 0x00, 0x03, 0x06, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x6A
            ])
        }
    }
    
    private func sendTCPResponse(_ responseData: Data) {
        guard let connection = activeConnection else { return }
        
        var frame = Data()
        let length = UInt16(responseData.count)
        frame.append(UInt8((length >> 8) & 0xFF))
        frame.append(UInt8(length & 0xFF))
        frame.append(responseData)
        
        connection.send(content: frame, completion: .contentProcessed({ [weak self] error in
            if let error = error {
                self?.nfcReader.log("Error sending TCP response: \(error.localizedDescription)")
                self?.closeActiveConnection()
            }
        }))
    }
}
