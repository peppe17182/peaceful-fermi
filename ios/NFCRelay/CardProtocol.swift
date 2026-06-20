import Foundation
import Combine
import CieSDK

/// Wraps PagoPA's CieDigitalId SDK for local CIE card PACE authentication.
/// Used by ContentView to test the NFC connection and read eMRTD data locally,
/// independently of the TCP relay mode.
@MainActor
class CardProtocol: ObservableObject {
    @Published var paceResult: String = ""
    @Published var isRunning: Bool = false

    private let cie = CieDigitalId()

    /// Starts PACE authentication using the 6-digit CAN printed on the CIE card.
    /// On success, reads DG1, DG11 and SOD from the chip.
    func verifyPACE(can: String, logHandler: @escaping @MainActor (String) -> Void) {
        guard !isRunning else { return }
        isRunning = true

        Task {
            do {
                _ = try await cie.performMtrd(can: can) { event, progress in
                    Task { @MainActor in
                        logHandler("[\(Int(progress * 100))%] \(event)")
                    }
                }
                paceResult = "Success"
                isRunning = false
                logHandler("PACE completed successfully")
            } catch {
                paceResult = "Error: \(error.localizedDescription)"
                isRunning = false
                logHandler("PACE failed: \(error.localizedDescription)")
            }
        }
    }
}
