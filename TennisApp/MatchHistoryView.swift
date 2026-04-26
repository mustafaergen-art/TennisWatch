import SwiftUI
import MapKit

// MARK: - iPhone Match Summary Card (for rendering share images)

struct PhoneMatchCard: View {
    let match: MatchLog

    private var setsWonA: Int { match.sets.filter { $0.a > $0.b }.count }
    private var setsWonB: Int { match.sets.filter { $0.b > $0.a }.count }
    private var isFinished: Bool { match.winner != "?" }

    var body: some View {
        VStack(spacing: 10) {
            // Header
            HStack {
                Text("🎾 TennisWatch")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                Spacer()
                if isFinished {
                    Text("🏆 \(match.winner)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.yellow)
                }
            }

            // Player A row
            sharePlayerRow(
                name: match.playerA.isEmpty ? "Player A" : match.playerA,
                setScores: match.sets.map { $0.a },
                setsWon: setsWonA,
                isWinner: isFinished && setsWonA > setsWonB,
                color: .cyan
            )

            // Player B row
            sharePlayerRow(
                name: match.playerB.isEmpty ? "Player B" : match.playerB,
                setScores: match.sets.map { $0.b },
                setsWon: setsWonB,
                isWinner: isFinished && setsWonB > setsWonA,
                color: .orange
            )

            // Info row
            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                    Text(match.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 12))
                }
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 12))
                    Text(match.durationText)
                        .font(.system(size: 12))
                }
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.5))

            // Location
            if !match.locationName.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 12))
                    Text(match.locationName)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer()
                }
                .foregroundStyle(.blue.opacity(0.8))
            }
        }
        .padding(20)
        .frame(width: 340)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.black)
        )
    }

    private func sharePlayerRow(name: String, setScores: [Int], setsWon: Int, isWinner: Bool, color: Color) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                if isWinner {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                }
                Text(name)
                    .font(.system(size: 15, weight: isWinner ? .bold : .regular))
                    .foregroundStyle(isWinner ? color : .white.opacity(0.85))
                    .lineLimit(1)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(Array(setScores.enumerated()), id: \.offset) { i, score in
                    let opScore = color == .cyan ? match.sets[i].b : match.sets[i].a
                    Text("\(score)")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(score > opScore ? .green : score < opScore ? .red.opacity(0.6) : .white.opacity(0.4))
                        .frame(width: 22)
                }
            }
            Text("\(setsWon)")
                .font(.system(size: 17, weight: .heavy, design: .monospaced))
                .foregroundStyle(isWinner ? .green : .white.opacity(0.6))
                .frame(width: 24)
        }
    }
}

// MARK: - Main History View

struct MatchHistoryView: View {
    @StateObject private var connector = PhoneConnector()
    @State private var matchToDelete: MatchLog?
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if connector.matches.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "tennis.racket")
                            .font(.system(size: 50))
                            .foregroundStyle(.green.opacity(0.4))
                        Text(L.noMatchesYet)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text(L.matchesWillAppear)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            // Map with match locations connected by lines
                            MatchLocationsMap(matches: connector.matches)
                                .padding(.horizontal, 16)

                            ForEach(connector.matches) { match in
                                MatchImageCard(match: match, onShare: {
                                    shareMatch(match)
                                }, onDelete: {
                                    matchToDelete = match
                                    showDeleteConfirm = true
                                })
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .navigationTitle(L.myMatches)
            .toolbar {
                if !connector.matches.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Text(L.matchCount(connector.matches.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .alert(L.deleteMatch, isPresented: $showDeleteConfirm) {
                Button(L.delete, role: .destructive) {
                    if let match = matchToDelete {
                        connector.deleteMatch(match.id)
                    }
                    matchToDelete = nil
                }
                Button(L.cancel, role: .cancel) {
                    matchToDelete = nil
                }
            } message: {
                if let match = matchToDelete {
                    Text("\(match.playerA) vs \(match.playerB) — \(match.scoreSummary)")
                }
            }
        }
    }

    // MARK: - Share Match

    @MainActor
    private func shareMatch(_ match: MatchLog) {
        let card = PhoneMatchCard(match: match)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3.0

        guard let cgImage = renderer.cgImage else { return }

        let uiImage = UIImage(cgImage: cgImage)
        let text = "🎾 \(match.playerA) vs \(match.playerB)\n\(match.scoreSummary)\n\(match.durationText)"
        let items: [Any] = [uiImage, text]

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

// MARK: - Match Image Card (Today's Matches style with player rows)

struct MatchImageCard: View {
    let match: MatchLog
    let onShare: () -> Void
    let onDelete: () -> Void
    @State private var showTranscripts = false

    private var setsWonA: Int { match.sets.filter { $0.a > $0.b }.count }
    private var setsWonB: Int { match.sets.filter { $0.b > $0.a }.count }
    private var isFinished: Bool { match.winner != "?" }

    var body: some View {
        VStack(spacing: 8) {
            // Header: status + winner + share/delete
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
                // Share button
                Button {
                    onShare()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13))
                        .foregroundStyle(.blue)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.blue.opacity(0.2)))
                }
                // Delete button
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.red.opacity(0.8))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.red.opacity(0.15)))
                }
            }

            // Player A row
            playerRow(
                name: match.playerA.isEmpty ? "Player A" : match.playerA,
                setScores: match.sets.map { $0.a },
                finalGame: match.finalGames.a,
                setsWon: setsWonA,
                isWinner: isFinished && setsWonA > setsWonB,
                color: .cyan
            )

            // Player B row
            playerRow(
                name: match.playerB.isEmpty ? "Player B" : match.playerB,
                setScores: match.sets.map { $0.b },
                finalGame: match.finalGames.b,
                setsWon: setsWonB,
                isWinner: isFinished && setsWonB > setsWonA,
                color: .orange
            )

            // Info row: date + duration + points
            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                    Text(match.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 12))
                }
                .foregroundStyle(.white.opacity(0.5))

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                    Text(match.durationText)
                        .font(.system(size: 12))
                }
                .foregroundStyle(.white.opacity(0.5))

                HStack(spacing: 4) {
                    Image(systemName: "sportscourt")
                        .font(.system(size: 11))
                    Text("\(match.totalPointsA)-\(match.totalPointsB) pts")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.white.opacity(0.5))

                Spacer()
            }

            // Location + outs
            HStack(spacing: 10) {
                if !match.locationName.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 11))
                        Text(match.locationName)
                            .font(.system(size: 12))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.blue.opacity(0.8))
                }

                // GPS coordinates if available
                if match.latitude != 0 && match.longitude != 0 && match.locationName.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "location")
                            .font(.system(size: 11))
                        Text(String(format: "%.4f, %.4f", match.latitude, match.longitude))
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.blue.opacity(0.6))
                }

                if match.totalOuts > 0 {
                    HStack(spacing: 4) {
                        Text("🚫")
                            .font(.system(size: 11))
                        Text(match.outsSummary)
                            .font(.system(size: 12))
                            .foregroundStyle(.red.opacity(0.6))
                    }
                }

                Spacer()
            }

            // Transcripts section (expandable)
            if !match.transcripts.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showTranscripts.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showTranscripts ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10))
                        Image(systemName: "waveform")
                            .font(.system(size: 11))
                        Text(L.isTurkish ? "Konuşmalar (\(match.transcripts.count))" : "Transcripts (\(match.transcripts.count))")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(.purple.opacity(0.8))
                }
                .buttonStyle(.plain)

                if showTranscripts {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(match.transcripts.enumerated()), id: \.offset) { i, text in
                            HStack(alignment: .top, spacing: 6) {
                                Text("\(i + 1).")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.3))
                                    .frame(width: 22, alignment: .trailing)
                                Text(text)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.7))
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.05))
                    )
                }
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

    // MARK: - Player Row (same style as Today's Matches LiveMatchCard)

    private func playerRow(name: String, setScores: [Int], finalGame: Int, setsWon: Int, isWinner: Bool, color: Color) -> some View {
        HStack(spacing: 8) {
            // Player name
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

            // Set scores
            HStack(spacing: 6) {
                ForEach(Array(setScores.enumerated()), id: \.offset) { i, score in
                    let opScore = color == .cyan ? match.sets[i].b : match.sets[i].a
                    Text("\(score)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(score > opScore ? .green : score < opScore ? .red.opacity(0.6) : .white.opacity(0.4))
                        .frame(width: 20)
                }
                // Ongoing set
                if finalGame > 0 || (color == .cyan ? match.finalGames.b : match.finalGames.a) > 0 {
                    Text("\(finalGame)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 20)
                }
            }

            // Sets won
            Text("\(setsWon)")
                .font(.system(size: 16, weight: .heavy, design: .monospaced))
                .foregroundStyle(isWinner ? .green : .white.opacity(0.6))
                .frame(width: 22)
        }
    }
}

// MARK: - Match Locations Map

struct MatchLocationsMap: View {
    let matches: [MatchLog]

    /// Only matches with valid GPS
    private var geoMatches: [MatchLog] {
        matches.filter { $0.latitude != 0 && $0.longitude != 0 }
    }

    private var coordinates: [CLLocationCoordinate2D] {
        geoMatches.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private var region: MKCoordinateRegion {
        guard !coordinates.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0),
                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
            )
        }
        let lats = coordinates.map { $0.latitude }
        let lons = coordinates.map { $0.longitude }
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (lats.max()! - lats.min()!) * 1.5),
            longitudeDelta: max(0.01, (lons.max()! - lons.min()!) * 1.5)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    var body: some View {
        if geoMatches.isEmpty { EmptyView() }
        else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "map")
                        .font(.system(size: 12))
                    Text(L.isTurkish ? "Maç Lokasyonları" : "Match Locations")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.7))

                Map(initialPosition: .region(region)) {
                    // Pins for each match
                    ForEach(geoMatches) { match in
                        Annotation(match.locationName.isEmpty ? match.scoreSummary : match.locationName,
                                   coordinate: CLLocationCoordinate2D(latitude: match.latitude, longitude: match.longitude)) {
                            ZStack {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 12, height: 12)
                                Circle()
                                    .stroke(.white, lineWidth: 2)
                                    .frame(width: 12, height: 12)
                            }
                        }
                    }

                    // Lines connecting matches in chronological order
                    if coordinates.count > 1 {
                        MapPolyline(coordinates: coordinates)
                            .stroke(.green.opacity(0.6), lineWidth: 2)
                    }
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
        }
    }
}

#Preview {
    MatchHistoryView()
}
