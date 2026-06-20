import SwiftUI
import Foundation
import Darwin

struct ContentView: View {
    @StateObject private var nfcReader = NFCReader()
    @StateObject private var server: RelayServer
    @StateObject private var cardProtocol = CardProtocol()
    
    @State private var canInput: String = ""
    @State private var customPort: String = "35963"
    
    init() {
        let reader = NFCReader()
        _nfcReader = StateObject(wrappedValue: reader)
        _server = StateObject(wrappedValue: RelayServer(nfcReader: reader))
    }
    
    var body: some View {
        ZStack {
            // Sleek dark-mode background gradient
            LinearGradient(
                gradient: Gradient(colors: [Color(red: 0.08, green: 0.08, blue: 0.12), Color(red: 0.04, green: 0.04, blue: 0.06)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Header Title
                HStack {
                    Image(systemName: "nfc")
                        .font(.system(size: 32))
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CIE / TS-CNS Relay")
                            .font(.title).bold()
                            .foregroundColor(.white)
                        Text("LiveContainer Sideload Edition")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 10)
                
                // Server Connection Status Card
                VStack(spacing: 12) {
                    HStack {
                        Text("TCP Relay Server")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        statusBadge(for: server.connectionState)
                    }
                    
                    if server.isRunning {
                        HStack {
                            Text("Listening on:")
                                .foregroundColor(.gray)
                            Text("\(getIPAddress() ?? "Wi-Fi IP"):\(customPort)")
                                .foregroundColor(.white).bold()
                            Spacer()
                        }
                        .font(.subheadline)
                    }
                    
                    if !nfcReader.connectedTagATR.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Card ATR:")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text(nfcReader.connectedTagATR)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.green)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(6)
                    }
                    
                    HStack(spacing: 12) {
                        if server.isRunning {
                            Button(action: {
                                server.stop()
                            }) {
                                HStack {
                                    Image(systemName: "stop.fill")
                                    Text("Stop Server")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red.opacity(0.8))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                        } else {
                            Button(action: {
                                if let portVal = UInt16(customPort) {
                                    server.serverPort = portVal
                                }
                                server.start()
                            }) {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text("Start Server")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                        }
                    }
                }
                .padding()
                .background(Color.white.opacity(0.06))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal)
                
                // PACE Configuration & Diagnostics Card
                VStack(alignment: .leading, spacing: 12) {
                    Text("Local PACE Diagnostics")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundColor(.gray)
                        SecureField("Enter 6-digit CAN or 8-digit PIN", text: $canInput)
                            .keyboardType(.numberPad)
                            .foregroundColor(.white)
                            .textFieldStyle(PlainTextFieldStyle())
                        
                        if !canInput.isEmpty {
                            Button(action: { canInput = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(10)
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            cardProtocol.verifyPACE(can: canInput) { logMsg in
                                nfcReader.log(logMsg)
                            }
                        }) {
                            HStack {
                                Image(systemName: "checkmark.shield.fill")
                                if cardProtocol.isRunning {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text("Verify PACE")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(canInput.count == 6 || canInput.count == 8 ? Color.green : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(canInput.count != 6 && canInput.count != 8)
                        
                        Button(action: {
                            nfcReader.startSession()
                        }) {
                            HStack {
                                Image(systemName: "sensor.tag.radiowaves.forward")
                                Text("NFC Ping")
                            }
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }
                    
                    if !cardProtocol.paceResult.isEmpty {
                        Text(cardProtocol.paceResult)
                            .font(.footnote)
                            .foregroundColor(cardProtocol.paceResult.contains("Success") ? .green : .red)
                    }
                }
                .padding()
                .background(Color.white.opacity(0.06))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal)
                
                // Terminal Console (Logs)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Terminal Console")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Button(action: {
                            nfcReader.logs.removeAll()
                        }) {
                            Text("Clear")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    ScrollView {
                        ScrollViewReader { proxy in
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(nfcReader.logs, id: \.self) { log in
                                    Text(log)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.green.opacity(0.9))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .onChange(of: nfcReader.logs) { _ in
                                if let lastLog = nfcReader.logs.last {
                                    proxy.scrollTo(lastLog, anchor: .bottom)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .padding(8)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(8)
                }
                .padding()
                .background(Color.white.opacity(0.06))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
        }
    }
    
    // Status Badge generator
    @ViewBuilder
    private func statusBadge(for state: String) -> some View {
        let (color, text) = badgeConfig(for: state)
        Text(text)
            .font(.caption).bold()
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(20)
    }
    
    private func badgeConfig(for state: String) -> (Color, String) {
        switch state {
        case "Listening":
            return (.orange, "LISTENING")
        case "Connected to PC":
            return (.green, "CONNECTED")
        default:
            return (.red, "OFFLINE")
        }
    }
    
    // Retrieve Wi-Fi IP address on local network
    private func getIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }
        
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            guard let addr = interface.ifa_addr else { continue }
            let addrFamily = addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                if let cName = interface.ifa_name {
                    let name = String(cString: cName)
                    if name == "en0" { // Wi-Fi Interface
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                                    &hostname, socklen_t(hostname.count),
                                    nil, socklen_t(0), NI_NUMERICHOST)
                        address = String(cString: hostname)
                    }
                }
            }
        }
        freeifaddrs(ifaddr)
        return address
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
