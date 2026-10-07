import Foundation

@MainActor
final class Recorder: ObservableObject {
    @Published var point: SurveyPoint = .A
    @Published var target: String = ""
    @Published var interval: Double = 2
    @Published private(set) var samples: [Sample] = []
    @Published private(set) var isRunning = false

    let location = LocationAuthorizer()
    private var task: Task<Void, Never>?

    var latest: Sample? { samples.last }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let started = Date()
                await self.tick()
                let wait = max(0.2, self.interval - Date().timeIntervalSince(started))
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    func clear() {
        samples.removeAll()
    }

    private func tick() async {
        let now = Date()
        let point = self.point
        let wifi = WiFiReader.snapshot(locationAuthorized: location.isAuthorized)
        let iface = wifi.interfaceName
        let gw = GatewayResolver.resolve(interface: iface)
        let host = target.trimmingCharacters(in: .whitespaces)

        async let gwPing = Self.pingOrSkip(gw.router, iface, reason: "ゲートウェイ不明")
        async let tgPing = Self.pingOrSkip(host.isEmpty ? nil : host, iface, reason: "宛先未指定")
        let (g, t) = await (gwPing, tgPing)

        guard isRunning else { return }
        samples.append(Sample(
            timestamp: now,
            point: point,
            wifi: wifi,
            gatewayIP: gw.router,
            gateway: PingResult(target: gw.router, outcome: g),
            target: PingResult(target: host.isEmpty ? nil : host, outcome: t)
        ))
    }

    nonisolated private static func pingOrSkip(_ host: String?, _ iface: String?, reason: String) async -> PingOutcome {
        guard let host else { return .skipped(reason) }
        return await Pinger.ping(host: host, interface: iface)
    }
}

/// 地点別の比較用集計
struct PointSummary: Identifiable {
    let point: SurveyPoint
    let count: Int
    let rssiAvg: Double?
    let rssiMin: Int?
    let noiseAvg: Double?
    let snrAvg: Double?
    let disconnected: Int
    let gwLoss: Double?
    let gwRttAvg: Double?
    let targetLoss: Double?
    let targetRttAvg: Double?
    var id: String { point.rawValue }

    static func make(_ samples: [Sample]) -> [PointSummary] {
        SurveyPoint.allCases.map { p in
            let s = samples.filter { $0.point == p }
            let rssi = s.compactMap { $0.wifi.rssi.value }
            let noise = s.compactMap { $0.wifi.noise.value }
            let snr = s.compactMap { $0.wifi.snr }
            return PointSummary(
                point: p,
                count: s.count,
                rssiAvg: avg(rssi.map(Double.init)),
                rssiMin: rssi.min(),
                noiseAvg: avg(noise.map(Double.init)),
                snrAvg: avg(snr.map(Double.init)),
                disconnected: s.filter { $0.wifi.connection != .connected }.count,
                gwLoss: loss(s.map(\.gateway)),
                gwRttAvg: avg(s.compactMap { $0.gateway.rtt }),
                targetLoss: loss(s.map(\.target)),
                targetRttAvg: avg(s.compactMap { $0.target.rtt })
            )
        }
    }

    private static func avg(_ v: [Double]) -> Double? {
        v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }

    private static func loss(_ r: [PingResult]) -> Double? {
        let tried = r.filter(\.attempted)
        guard !tried.isEmpty else { return nil }
        return Double(tried.filter(\.failed).count) / Double(tried.count) * 100
    }
}
