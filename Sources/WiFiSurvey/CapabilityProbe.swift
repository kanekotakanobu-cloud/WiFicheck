import CoreLocation
import CoreWLAN
import Foundation

struct ProbeItem: Identifiable {
    let id = UUID()
    let name: String
    let verdict: String
    let detail: String
}

/// 対象Macで各項目が取得できるかを検証する。設定は一切変更しない。
enum CapabilityProbe {
    static func run(locationAuthorized: Bool, locationLabel: String) async -> [ProbeItem] {
        var items: [ProbeItem] = []
        let os = ProcessInfo.processInfo.operatingSystemVersion
        items.append(ProbeItem(
            name: "macOS",
            verdict: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            detail: ProcessInfo.processInfo.operatingSystemVersionString
        ))

        let bundleID = Bundle.main.bundleIdentifier
        let hasUsage = Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") != nil
        items.append(ProbeItem(
            name: "実行形態",
            verdict: (bundleID != nil && hasUsage) ? "OK" : "NG",
            detail: bundleID.map { "バンドルID \($0) / 位置情報説明文 \(hasUsage ? "あり" : "なし")" }
                ?? "バンドル外で実行中。位置情報を許可できないため build_app.sh で作成した .app から起動してください"
        ))

        let servicesOn = await Task.detached { CLLocationManager.locationServicesEnabled() }.value
        items.append(ProbeItem(
            name: "位置情報",
            verdict: locationAuthorized ? "許可" : "未許可",
            detail: "位置情報サービス全体: \(servicesOn ? "オン" : "オフ") / 本アプリ: \(locationLabel)"
        ))

        let names = CWWiFiClient.interfaceNames() ?? []
        let raw = WiFiReader.readRaw()
        let snap = WiFiReader.classify(raw, locationAuthorized: locationAuthorized)

        if let raw {
            items.append(ProbeItem(
                name: "Wi-Fiインターフェース",
                verdict: raw.powerOn ? "電源オン" : "電源オフ",
                detail: "使用: \(raw.interfaceName ?? "?") / 一覧: \(names.joined(separator: ","))"
            ))
            items.append(ProbeItem(
                name: "接続状態",
                verdict: snap.connection.label,
                detail: "生値 rssi=\(raw.rssi) noise=\(raw.noise) interfaceMode=\(raw.modeRaw) serviceActive=\(raw.serviceActive) ssid=\(raw.ssid == nil ? "nil" : "あり") bssid=\(raw.bssid == nil ? "nil" : "あり")"
            ))
        } else {
            items.append(ProbeItem(name: "Wi-Fiインターフェース", verdict: "なし",
                                   detail: "CWWiFiClient.interface() が nil / 一覧: \(names.joined(separator: ","))"))
        }

        items.append(field("RSSI", snap.rssi.status, snap.rssi.value.map { "\($0) dBm" }))
        items.append(field("ノイズ", snap.noise.status, snap.noise.value.map { "\($0) dBm" }))
        items.append(field("チャネル", snap.channel.status, snap.channel.value?.text))
        items.append(field("SSID", snap.ssid.status, snap.ssid.value))
        items.append(field("BSSID", snap.bssid.status, snap.bssid.value))
        items.append(ProbeItem(name: "送信レート(参考)", verdict: snap.txRate == nil ? "取得不可" : "取得可",
                               detail: snap.txRate.map { String(format: "%.0f Mbps", $0) } ?? "-"))

        let gw = GatewayResolver.resolve(interface: snap.interfaceName)
        var gwDetail = "Wi-Fiゲートウェイ: \(gw.router ?? "なし") / 優先インターフェース: \(gw.primaryInterface ?? "なし")"
        if let p = gw.primaryInterface, p != snap.interfaceName {
            gwDetail += "（Wi-Fi以外が優先経路。Pingは -b でWi-Fiに束縛）"
        }
        items.append(ProbeItem(name: "ゲートウェイ", verdict: gw.router == nil ? "取得不可" : "取得可", detail: gwDetail))

        let pingExists = FileManager.default.isExecutableFile(atPath: Pinger.path)
        if pingExists, let router = gw.router {
            let r = PingResult(target: router, outcome: await Pinger.ping(host: router, interface: snap.interfaceName))
            items.append(ProbeItem(name: "Ping(ゲートウェイ)", verdict: r.failed ? "失敗" : "成功", detail: r.detail))
        } else {
            items.append(ProbeItem(name: "Ping(ゲートウェイ)", verdict: "未実施",
                                   detail: pingExists ? "ゲートウェイ不明" : "\(Pinger.path) が実行できません"))
        }

        items.append(ProbeItem(name: "airportコマンド", verdict: "不使用",
                               detail: "CoreWLAN / SystemConfiguration / /sbin/ping のみ使用"))
        return items
    }

    static func report(_ items: [ProbeItem]) -> String {
        var s = "WiFiSurvey 取得可否検証 \(Date())\n"
        for i in items { s += "[\(i.verdict)] \(i.name): \(i.detail)\n" }
        return s
    }

    private static func field(_ name: String, _ status: ReadStatus, _ value: String?) -> ProbeItem {
        ProbeItem(name: name, verdict: status.label, detail: value ?? "-")
    }
}
