import Foundation

enum CSVExporter {
    static let header = [
        "timestamp", "point", "connection", "interface",
        "ssid", "ssid_status", "bssid", "bssid_status",
        "rssi_dbm", "rssi_status", "noise_dbm", "noise_status", "snr_db",
        "channel", "band", "width", "channel_status", "tx_rate_mbps",
        "gateway_ip", "gateway_ping_status", "gateway_rtt_ms", "gateway_ping_detail",
        "target_host", "target_ping_status", "target_rtt_ms", "target_ping_detail",
    ]

    static func csv(_ samples: [Sample]) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso.timeZone = .current

        var lines = [header.joined(separator: ",")]
        for s in samples {
            let w = s.wifi
            let row: [String] = [
                iso.string(from: s.timestamp),
                s.point.rawValue,
                w.connection.rawValue,
                w.interfaceName ?? "",
                w.ssid.value ?? "", w.ssid.status.rawValue,
                w.bssid.value ?? "", w.bssid.status.rawValue,
                w.rssi.value.map(String.init) ?? "", w.rssi.status.rawValue,
                w.noise.value.map(String.init) ?? "", w.noise.status.rawValue,
                w.snr.map(String.init) ?? "",
                w.channel.value.map { String($0.number) } ?? "",
                w.channel.value?.band ?? "",
                w.channel.value?.width ?? "",
                w.channel.status.rawValue,
                w.txRate.map { String(format: "%.0f", $0) } ?? "",
                s.gatewayIP ?? "",
                s.gateway.statusCode,
                s.gateway.rtt.map { String(format: "%.3f", $0) } ?? "",
                s.gateway.detail,
                s.target.target ?? "",
                s.target.statusCode,
                s.target.rtt.map { String(format: "%.3f", $0) } ?? "",
                s.target.detail,
            ]
            lines.append(row.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Excelで文字化けしないようBOM付きUTF-8で書き出す。ローカル保存のみ。
    static func write(_ samples: [Sample], to url: URL) throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(csv(samples).utf8))
        try data.write(to: url, options: .atomic)
    }

    private static func escape(_ s: String) -> String {
        if s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
}
