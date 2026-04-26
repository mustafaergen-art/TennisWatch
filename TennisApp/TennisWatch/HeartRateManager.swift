import Foundation
import HealthKit
import CoreLocation

@MainActor
class HeartRateManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    // MARK: - Published State

    @Published var heartRate: Int = 0
    @Published var isMonitoring = false
    @Published var calories: Int = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var locationName: String = ""
    @Published var autoStopMessage: String = ""
    @Published var savedCourtConfirmed = false

    // MARK: - Court Side GPS Tracking

    /// Current detected court side: 0 = unknown, 1 = side A (initial), 2 = side B (opposite)
    @Published var gpsCourtSide: Int = 0

    /// Number of GPS-detected side changes
    @Published var gpsSideChangeCount: Int = 0

    /// Whether GPS detected a side mismatch with expected score
    @Published var gpsSideMismatch: Bool = false

    // MARK: - Private

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var heartRateQuery: HKAnchoredObjectQuery?

    private let locationManager = CLLocationManager()
    private var matchLocation: CLLocation?
    private let geocoder = CLGeocoder()

    private var startDate: Date?
    private var elapsedTimer: Timer?

    /// Auto start/stop radius (2 km)
    private let courtRadius: CLLocationDistance = 2000

    /// Court side tracking
    private var sideAPosition: CLLocation?   // Position at initial side
    private var sideBPosition: CLLocation?   // Position at opposite side
    private var lastCourtSide: Int = 0       // Last detected side
    private var courtSideLocations: [CLLocation] = []  // Recent locations for smoothing
    private let courtLength: CLLocationDistance = 24.0  // Tennis court length in meters
    private let sideDetectionThreshold: CLLocationDistance = 8.0  // Min movement to detect side change

    /// Minimum visits at same location before enabling auto-start/stop
    private let minVisitsForAuto = 3

    /// Track consecutive "outside court" updates before auto-stopping
    private var outsideCourtCount = 0
    private let outsideThreshold = 3

    /// UserDefaults keys
    private let savedLatKey = "savedCourtLat"
    private let savedLonKey = "savedCourtLon"
    private let savedNameKey = "savedCourtName"
    private let visitCountKey = "savedCourtVisitCount"
    private let confirmedKey = "savedCourtConfirmed"

    // MARK: - Init

    override init() {
        super.init()
        savedCourtConfirmed = UserDefaults.standard.bool(forKey: confirmedKey)
    }

    // MARK: - Setup (call once on app launch)

    func setup() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 3  // Update every 3 meters
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    // MARK: - Start Workout

    func start() {
        guard !isMonitoring else { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }

        autoStopMessage = ""
        outsideCourtCount = 0

        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!

        let typesToRead: Set<HKObjectType> = [
            heartRateType,
            activeEnergyType,
            distanceType,
        ]
        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            activeEnergyType,
            distanceType,
        ]

        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { [weak self] success, _ in
            guard success else { return }
            Task { @MainActor in
                self?.startWorkoutSession()
            }
        }
    }

    // MARK: - Stop Workout

    func stop() {
        guard let session = workoutSession, let builder = builder else { return }

        session.end()

        let builderRef = builder
        builderRef.endCollection(withEnd: Date()) { [weak self] success, _ in
            guard success else { return }
            builderRef.finishWorkout { [weak self] _, _ in
                Task { @MainActor in
                    self?.cleanup()
                }
            }
        }
    }

    private func cleanup() {
        if let query = heartRateQuery {
            healthStore.stop(query)
        }
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        workoutSession = nil
        builder = nil
        heartRateQuery = nil
        isMonitoring = false
        heartRate = 0
        calories = 0
        elapsedTime = 0
        outsideCourtCount = 0
        resetCourtSideTracking()
    }

    // MARK: - Location Tracking (distance-based, no geofencing)

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            // Use tighter accuracy for court side detection during match
            if self.isMonitoring && location.horizontalAccuracy < 20 {
                self.updateCourtSide(location)
            }
            if location.horizontalAccuracy < 200 {
                self.handleLocationUpdate(location)
            }
        }
    }

    private func handleLocationUpdate(_ location: CLLocation) {
        // During active match: record court location on first fix
        if isMonitoring && matchLocation == nil {
            matchLocation = location
            recordVisit(at: location)
            reverseGeocode(location)
        }

        // Check distance to saved court
        guard let saved = loadSavedCourt() else { return }
        let savedLoc = CLLocation(latitude: saved.coordinate.latitude, longitude: saved.coordinate.longitude)
        let distance = location.distance(from: savedLoc)

        if isMonitoring && savedCourtConfirmed {
            // Auto-stop: if we've been outside court radius for several updates
            if distance > courtRadius {
                outsideCourtCount += 1
                if outsideCourtCount >= outsideThreshold {
                    autoStopMessage = "Left court — workout saved"
                    stop()
                }
            } else {
                outsideCourtCount = 0
            }
        }

        if !isMonitoring && savedCourtConfirmed {
            // Auto-start: arrived at confirmed court
            if distance < courtRadius {
                locationName = saved.name
                start()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location not critical
    }

    // MARK: - Visit Counting & Court Confirmation

    private func recordVisit(at location: CLLocation) {
        if let saved = loadSavedCourt() {
            let savedLoc = CLLocation(latitude: saved.coordinate.latitude, longitude: saved.coordinate.longitude)
            let distance = location.distance(from: savedLoc)

            if distance < courtRadius {
                // Same court — increment visit count
                let count = UserDefaults.standard.integer(forKey: visitCountKey) + 1
                UserDefaults.standard.set(count, forKey: visitCountKey)

                if count >= minVisitsForAuto && !savedCourtConfirmed {
                    savedCourtConfirmed = true
                    UserDefaults.standard.set(true, forKey: confirmedKey)
                }
            } else {
                // Different location — reset
                saveCourt(location: location)
                UserDefaults.standard.set(1, forKey: visitCountKey)
                savedCourtConfirmed = false
                UserDefaults.standard.set(false, forKey: confirmedKey)
            }
        } else {
            // First ever visit
            saveCourt(location: location)
            UserDefaults.standard.set(1, forKey: visitCountKey)
        }
    }

    // MARK: - Persist Court Location

    private func saveCourt(location: CLLocation) {
        UserDefaults.standard.set(location.coordinate.latitude, forKey: savedLatKey)
        UserDefaults.standard.set(location.coordinate.longitude, forKey: savedLonKey)
    }

    private func saveCourtName(_ name: String) {
        UserDefaults.standard.set(name, forKey: savedNameKey)
    }

    private func loadSavedCourt() -> (coordinate: CLLocationCoordinate2D, name: String)? {
        let lat = UserDefaults.standard.double(forKey: savedLatKey)
        let lon = UserDefaults.standard.double(forKey: savedLonKey)
        guard lat != 0 && lon != 0 else { return nil }
        let name = UserDefaults.standard.string(forKey: savedNameKey) ?? ""
        return (CLLocationCoordinate2D(latitude: lat, longitude: lon), name)
    }

    var visitCount: Int {
        UserDefaults.standard.integer(forKey: visitCountKey)
    }

    // MARK: - Reverse Geocode

    private func reverseGeocode(_ location: CLLocation) {
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            Task { @MainActor in
                if let placemark = placemarks?.first {
                    let name = placemark.name ?? ""
                    let locality = placemark.locality ?? ""
                    let area = placemark.subLocality ?? ""

                    var courtName = ""
                    if !name.isEmpty && name != locality {
                        courtName = name
                    } else if !area.isEmpty {
                        courtName = "\(area), \(locality)"
                    } else if !locality.isEmpty {
                        courtName = locality
                    }

                    self?.locationName = courtName
                    self?.saveCourtName(courtName)
                }
            }
        }
    }

    // MARK: - Court Side Detection via GPS

    private func updateCourtSide(_ location: CLLocation) {
        // First location during match → this is side A
        if sideAPosition == nil {
            sideAPosition = location
            gpsCourtSide = 1
            lastCourtSide = 1
            return
        }

        guard let sideA = sideAPosition else { return }
        let distFromA = location.distance(from: sideA)

        if let sideB = sideBPosition {
            // We have both reference points — determine which side we're closer to
            let distFromB = location.distance(from: sideB)
            let newSide: Int

            if distFromA < distFromB && distFromA < sideDetectionThreshold {
                newSide = 1  // Closer to side A
            } else if distFromB < distFromA && distFromB < sideDetectionThreshold {
                newSide = 2  // Closer to side B
            } else if distFromA > distFromB {
                newSide = 2
            } else {
                newSide = 1
            }

            if newSide != lastCourtSide {
                lastCourtSide = newSide
                gpsCourtSide = newSide
                gpsSideChangeCount += 1
            }
        } else {
            // We only have side A — detect when player moves to side B
            if distFromA > sideDetectionThreshold {
                // Player moved significantly — this could be side B
                // Only record if they moved roughly a court length (not just walking sideways)
                if distFromA > 12 && distFromA < 40 {
                    sideBPosition = location
                    gpsCourtSide = 2
                    lastCourtSide = 2
                    gpsSideChangeCount += 1
                }
            }
        }
    }

    /// Check if GPS side matches expected side from score
    /// Call this from ContentView when score changes
    func checkSideMismatch(expectedChangeSides: Bool) {
        guard gpsCourtSide > 0 else {
            gpsSideMismatch = false
            return
        }

        // If score says we should have changed sides, GPS should show side B (or original)
        // expectedChangeSides = true means total games is odd → should be on different side from start
        let gpsSaysChanged = (gpsCourtSide == 2)

        // Mismatch: score says change, GPS says same side (or vice versa)
        // But only flag if we have enough GPS data (both sides recorded)
        if sideBPosition != nil {
            gpsSideMismatch = (expectedChangeSides != gpsSaysChanged)
        } else {
            gpsSideMismatch = false
        }
    }

    /// Reset court side tracking (e.g., for new match)
    func resetCourtSideTracking() {
        sideAPosition = nil
        sideBPosition = nil
        gpsCourtSide = 0
        lastCourtSide = 0
        gpsSideChangeCount = 0
        gpsSideMismatch = false
        courtSideLocations.removeAll()
    }

    // MARK: - Workout Session

    private func startWorkoutSession() {
        let config = HKWorkoutConfiguration()
        config.activityType = .tennis
        config.locationType = .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let liveBuilder = session.associatedWorkoutBuilder()
            liveBuilder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)

            self.workoutSession = session
            self.builder = liveBuilder
            self.startDate = Date()
            self.matchLocation = nil

            session.startActivity(with: Date())
            liveBuilder.beginCollection(withStart: Date()) { [weak self] success, _ in
                guard success else { return }
                Task { @MainActor in
                    self?.isMonitoring = true
                    self?.startHeartRateQuery()
                    self?.startElapsedTimer()
                }
            }
        } catch {
            print("Failed to start workout session: \(error)")
        }
    }

    // MARK: - Heart Rate Query

    private func startHeartRateQuery() {
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let predicate = HKQuery.predicateForSamples(withStart: Date(), end: nil, options: .strictStartDate)

        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            Task { @MainActor in
                self?.processHeartRateSamples(samples)
            }
        }

        query.updateHandler = { [weak self] _, samples, _, _, _ in
            Task { @MainActor in
                self?.processHeartRateSamples(samples)
            }
        }

        self.heartRateQuery = query
        healthStore.execute(query)
    }

    private func processHeartRateSamples(_ samples: [HKSample]?) {
        guard let samples = samples as? [HKQuantitySample], let latest = samples.last else { return }
        let bpm = latest.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        self.heartRate = Int(bpm)
    }

    // MARK: - Elapsed Time & Calories

    private func startElapsedTimer() {
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let start = self.startDate else { return }
                self.elapsedTime = Date().timeIntervalSince(start)
                self.updateCalories()
            }
        }
    }

    private func updateCalories() {
        guard let builder = builder else { return }

        let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        if let energyStats = builder.statistics(for: energyType),
           let sum = energyStats.sumQuantity() {
            calories = Int(sum.doubleValue(for: .kilocalorie()))
        }
    }

    // MARK: - Formatted Time

    var formattedTime: String {
        let mins = Int(elapsedTime) / 60
        let secs = Int(elapsedTime) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - Reset Saved Court

    func resetSavedCourt() {
        UserDefaults.standard.removeObject(forKey: savedLatKey)
        UserDefaults.standard.removeObject(forKey: savedLonKey)
        UserDefaults.standard.removeObject(forKey: savedNameKey)
        UserDefaults.standard.removeObject(forKey: visitCountKey)
        UserDefaults.standard.removeObject(forKey: confirmedKey)
        savedCourtConfirmed = false
    }
}
