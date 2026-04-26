import SwiftUI
import UIKit

// MARK: - Watch Matches View (Community Feed)

struct WatchMatchesView: View {
    @StateObject private var cloudKit = CloudKitService.shared

    var body: some View {
        NavigationStack {
            Group {
                if cloudKit.isLoading && cloudKit.communityMatches.isEmpty {
                    loadingView
                } else if let error = cloudKit.errorMessage, cloudKit.communityMatches.isEmpty {
                    errorView(error)
                } else if cloudKit.communityMatches.isEmpty {
                    emptyView
                } else {
                    matchListView
                }
            }
            .navigationTitle(L.watchMatches)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await cloudKit.fetchCommunityMatches() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                    }
                    .disabled(cloudKit.isLoading)
                }
            }
        }
        .task {
            await cloudKit.fetchCommunityMatches()
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text(L.loadingMatches)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 40))
                .foregroundStyle(.red.opacity(0.5))
            Text(L.couldNotLoad)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(error)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button {
                Task { await cloudKit.fetchCommunityMatches() }
            } label: {
                Label(L.tryAgain, systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3")
                .font(.system(size: 50))
                .foregroundStyle(.green.opacity(0.4))
            Text(L.noCommunityMatches)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(L.communityMatchesWillAppear)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var matchListView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(cloudKit.communityMatches) { match in
                    CommunityMatchCard(match: match)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .refreshable {
            await cloudKit.fetchCommunityMatches()
        }
    }
}

// MARK: - Community Match Card (same style as My Matches / Today's Matches)

struct CommunityMatchCard: View {
    let match: CommunityMatch

    private var setsWonA: Int { match.sets.filter { $0.a > $0.b }.count }
    private var setsWonB: Int { match.sets.filter { $0.b > $0.a }.count }
    private var isFinished: Bool { match.winner != "?" }

    var body: some View {
        VStack(spacing: 8) {
            // Header: status + winner + time ago + share
            HStack {
                Text(isFinished ? L.finished : L.ongoingShort)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isFinished ? .green : .yellow)
                if isFinished {
                    Text("·")
                        .foregroundStyle(.white.opacity(0.4))
                    Text("🏆 \(match.winner)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.yellow)
                }
                Spacer()
                Text(match.timeAgo)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                // Share button
                Button {
                    shareCommunityMatch(match)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13))
                        .foregroundStyle(.blue)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.blue.opacity(0.2)))
                }
            }

            // Player A row
            communityPlayerRow(
                name: match.playerA.isEmpty ? "Player A" : match.playerA,
                setScores: match.sets.map { $0.a },
                setsWon: setsWonA,
                isWinner: isFinished && setsWonA > setsWonB,
                color: .cyan
            )

            // Player B row
            communityPlayerRow(
                name: match.playerB.isEmpty ? "Player B" : match.playerB,
                setScores: match.sets.map { $0.b },
                setsWon: setsWonB,
                isWinner: isFinished && setsWonB > setsWonA,
                color: .orange
            )

            // Info row: date + duration
            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                    Text(match.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 12))
                }
                .foregroundStyle(.white.opacity(0.5))

                if !match.durationText.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                        Text(match.durationText)
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()
            }

            // Location
            if !match.locationName.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 11))
                    Text(match.locationName)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer()
                }
                .foregroundStyle(.blue.opacity(0.8))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
    }

    // MARK: - Player Row

    private func communityPlayerRow(name: String, setScores: [Int], setsWon: Int, isWinner: Bool, color: Color) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                if isWinner {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                }
                Text(name)
                    .font(.system(size: 14, weight: isWinner ? .bold : .regular))
                    .foregroundStyle(isWinner ? color : .white.opacity(0.85))
                    .lineLimit(1)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(Array(setScores.enumerated()), id: \.offset) { i, score in
                    let opScore = color == .cyan ? match.sets[i].b : match.sets[i].a
                    Text("\(score)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(score > opScore ? .green : score < opScore ? .red.opacity(0.6) : .white.opacity(0.4))
                        .frame(width: 20)
                }
            }
            Text("\(setsWon)")
                .font(.system(size: 16, weight: .heavy, design: .monospaced))
                .foregroundStyle(isWinner ? .green : .white.opacity(0.6))
                .frame(width: 22)
        }
    }

    private func shareCommunityMatch(_ match: CommunityMatch) {
        let setScores = match.sets.map { "\($0.a)-\($0.b)" }.joined(separator: ", ")
        var text = "🎾 \(match.playerA) vs \(match.playerB)"
        if !setScores.isEmpty { text += "\n\(setScores)" }
        if !match.durationText.isEmpty { text += "\n⏱ \(match.durationText)" }
        if !match.locationName.isEmpty { text += "\n📍 \(match.locationName)" }

        let items: [Any] = [text]
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)

        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = scene.windows.first?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            activityVC.popoverPresentationController?.sourceView = topVC.view
            activityVC.popoverPresentationController?.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
            topVC.present(activityVC, animated: true)
        }
    }
}

#Preview {
    WatchMatchesView()
}
