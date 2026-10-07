import Foundation

enum SurveyPoint: String, CaseIterable, Identifiable {
    case A, B, C
    var id: String { rawValue }
}

/// 各項目の取得結果の区別。
enum ReadStatus: String {
    case ok
    /// Wi-Fi接続中だがAPIが値を返さない（ハードウェア/OS非対応など）
    case unavailable
    /// 位置情報の許可がないためOSが値を隠している
    case permissionDenied = "permission_denied"
    /// Wi-Fi未接続（電源OFF・インターフェースなしを含む。詳細は ConnectionState）
    case notConnected = "not_connected"

    var label: String {
        switch self {
        case .ok: return "取得可"
        case .unavailable: return "取得不可"
        case .permissionDenied: return "権限不足"
        case .notConnected: return "未接続"
        }
    }
}

struct Field<T> {
    let value: T?
    let status: ReadStatus

    static func ok(_ v: T) -> Field { Field(value: v, status: .ok) }
    static func missing(_ s: ReadStatus) -> Field { Field(value: nil, status: s) }
}

enum ConnectionState: String {
    case connected
    case notConnected = "not_connected"
    case wifiOff = "wifi_off"
    case noInterface = "no_interface"

    var label: String {
        switch self {
        case .connected: return "接続中"
        case .notConnected: return "未接続"
        case .wifiOff: return "Wi-Fiオフ"
        case .noInterface: return "Wi-Fiインターフェースなし"
        }
    }
}

struct ChannelInfo {
    let number: Int
    let band: String
    let width: String
    var text: String { "\(number) (\(band), \(width))" }
}

struct WiFiSnapshot {
    let interfaceName: String?
    let connection: ConnectionState
    let ssid: Field<String>
    let bssid: Field<String>
    let rssi: Field<Int>
    let noise: Field<Int>
    let channel: Field<ChannelInfo>
    let txRate: Double?

    var snr: Int? {
        guard let r = rssi.value, let n = noise.value else { return nil }
        return r - n
    }
}

enum PingOutcome {
    case success(ms: Double)
    case timeout
    case error(String)
    case skipped(String)
}

struct PingResult {
    let target: String?
    let outcome: PingOutcome

    var rtt: Double? {
        if case .success(let ms) = outcome { return ms }
        return nil
    }

    /// 実際に送信して応答がなかった/失敗したもの。skippedは含めない。
    var failed: Bool {
        switch outcome {
        case .timeout, .error: return true
        case .success, .skipped: return false
        }
    }

    var attempted: Bool {
        if case .skipped = outcome { return false }
        return true
    }

    var statusCode: String {
        switch outcome {
        case .success: return "ok"
        case .timeout: return "timeout"
        case .error: return "error"
        case .skipped: return "skipped"
        }
    }

    var detail: String {
        switch outcome {
        case .success(let ms): return String(format: "%.1f ms", ms)
        case .timeout: return "タイムアウト"
        case .error(let m): return "エラー: \(m)"
        case .skipped(let m): return "未実施: \(m)"
        }
    }
}

struct Sample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let point: SurveyPoint
    let wifi: WiFiSnapshot
    let gatewayIP: String?
    let gateway: PingResult
    let target: PingResult
}
