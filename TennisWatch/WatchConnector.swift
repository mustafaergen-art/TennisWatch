import Foundation
import WatchConnectivity

/// Sends match logs from Apple Watch to iPhone via WatchConnectivity
class WatchConnector: NSObject, WCSessionDelegate {

    static let shared = WatchConnector()

    private var session: WCSession?

    override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
            print("📱 WatchConnector: WCSession setup")
        } else {
            print("📱 WatchConnector: WCSession NOT supported")
        }
    }

    /// Send a match log to the iPhone
    func sendMatchLog(_ log: MatchLog) {
        guard let session = session else {
            print("📱 WC: No session")
            return
        }

        guard session.activationState == .activated else {
            print("📱 WC: Session not activated (state: \(session.activationState.rawValue)), queuing sync")
            // Try to activate and sync later
            session.activate()
            return
        }

        guard let data = try? JSONEncoder().encode(log) else {
            print("📱 WC: Failed to encode match log")
            return
        }

        print("📱 WC: Sending match log, reachable=\(session.isReachable)")

        // Try interactive message first (faster, works when phone is reachable)
        if session.isReachable {
            session.sendMessage(["matchLog": data], replyHandler: { reply in
                print("📱 WC: Message sent successfully")
            }) { error in
                print("📱 WC: sendMessage error: \(error), falling back to transferUserInfo")
                // Fallback to userInfo transfer
                session.transferUserInfo(["matchLog": data])
            }
        } else {
            // Phone not reachable — queue transfer
            print("📱 WC: Phone not reachable, using transferUserInfo")
            session.transferUserInfo(["matchLog": data])
        }

        // Also update applicationContext with all matches as backup
        syncAllMatches()
    }

    /// Sync all match history to phone via applicationContext
    func syncAllMatches() {
        guard let session = session, session.activationState == .activated else {
            print("📱 WC syncAll: Session not ready")
            return
        }

        let matches = MatchHistory.load()
        guard !matches.isEmpty else {
            print("📱 WC syncAll: No matches to sync")
            return
        }

        guard let data = try? JSONEncoder().encode(matches) else {
            print("📱 WC syncAll: Failed to encode matches")
            return
        }

        do {
            try session.updateApplicationContext(["allMatches": data])
            print("📱 WC syncAll: Sent \(matches.count) matches via applicationContext")
        } catch {
            print("📱 WC syncAll error: \(error)")
            // Fallback: try transferUserInfo
            session.transferUserInfo(["allMatches": data])
            print("📱 WC syncAll: Fallback to transferUserInfo")
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("📱 Watch WCSession activated: state=\(activationState.rawValue), error=\(error?.localizedDescription ?? "none")")
        if activationState == .activated {
            syncAllMatches()
        }
    }
}
