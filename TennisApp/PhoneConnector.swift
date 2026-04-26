import Foundation
import UIKit
import WatchConnectivity

/// Receives match logs from Apple Watch via WatchConnectivity
@MainActor
class PhoneConnector: NSObject, ObservableObject {

    @Published var matches: [MatchLog] = []

    private var session: WCSession?

    override init() {
        super.init()
        matches = MatchHistory.load()
        print("📲 PhoneConnector: Loaded \(matches.count) matches from storage")

        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
            print("📲 PhoneConnector: WCSession setup")
        } else {
            print("📲 PhoneConnector: WCSession NOT supported")
        }
    }

    func reload() {
        matches = MatchHistory.load()
        print("📲 PhoneConnector: Reloaded \(matches.count) matches")
    }

    func deleteMatch(_ id: UUID) {
        MatchHistory.delete(id)
        matches = MatchHistory.load()
    }
}

// MARK: - Process Incoming Data

extension PhoneConnector {

    nonisolated private func processPayload(_ payload: [String: Any], source: String) {
        print("📲 PhoneConnector: Received payload from \(source), keys: \(payload.keys)")

        // Single match log
        if let logData = payload["matchLog"] as? Data {
            if let log = try? JSONDecoder().decode(MatchLog.self, from: logData) {
                print("📲 PhoneConnector: Decoded single match: \(log.playerA) vs \(log.playerB)")
                MatchHistory.save(log)
                // Auto-upload to CloudKit for community feed
                Task { @MainActor in
                    self.matches = MatchHistory.load()
                    CloudKitService.shared.uploadMatch(log)
                }
                return
            } else {
                print("📲 PhoneConnector: Failed to decode single match log")
            }
        }

        // All matches bulk sync
        if let data = payload["allMatches"] as? Data {
            if let logs = try? JSONDecoder().decode([MatchLog].self, from: data) {
                print("📲 PhoneConnector: Decoded \(logs.count) matches from bulk sync")
                if let encoded = try? JSONEncoder().encode(logs) {
                    UserDefaults.standard.set(encoded, forKey: "tennis_match_history")
                }
                Task { @MainActor in
                    self.matches = MatchHistory.load()
                }
                return
            } else {
                print("📲 PhoneConnector: Failed to decode bulk matches")
            }
        }

        print("📲 PhoneConnector: Unrecognized payload from \(source)")
    }
}

// MARK: - WCSessionDelegate

extension PhoneConnector: WCSessionDelegate {

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("📲 WCSession activated: state=\(activationState.rawValue), error=\(error?.localizedDescription ?? "none")")
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        print("📲 WCSession became inactive")
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        print("📲 WCSession deactivated, reactivating...")
        session.activate()
    }

    /// Receive from watch via sendMessage (interactive, foreground)
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        processPayload(message, source: "sendMessage")
    }

    /// Receive from watch via sendMessage with reply
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        processPayload(message, source: "sendMessage+reply")
        replyHandler(["status": "ok"])
    }

    /// Receive from watch via transferUserInfo (background)
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        processPayload(userInfo, source: "transferUserInfo")
    }

    /// Receive from watch via updateApplicationContext
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        processPayload(applicationContext, source: "applicationContext")
    }
}
