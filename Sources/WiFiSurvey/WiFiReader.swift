import CoreWLAN

/// CoreWLANから得た生の値。検証画面でそのまま表示する。
struct RawWiFi {
    let interfaceName: String?
    let powerOn: Bool
    let modeRaw: Int
    let serviceActive: Bool
    let rssi: Int
    let noise: Int
    let channel: CWChannel?
    let ssid: String?
    let bssid: String?
    let txRate: Double
}

enum WiFiReader {
    static func readRaw() -> RawWiFi? {
        guard let iface = CWWiFiClient.shared().interface() else { return nil }
        return RawWiFi(
            interfaceName: iface.interfaceName,
            powerOn: iface.powerOn(),
            modeRaw: iface.interfaceMode().rawValue,
            serviceActive: iface.serviceActive(),
            rssi: iface.rssiValue(),
            noise: iface.noiseMeasurement(),
            channel: iface.wlanChannel(),
            ssid: iface.ssid(),
            bssid: iface.bssid(),
            txRate: iface.transmitRate()
        )
    }

    static func snapshot(locationAuthorized: Bool) -> WiFiSnapshot {
        classify(readRaw(), locationAuthorized: locationAuthorized)
    }

    /// 生の値を「取得可/取得不可/権限不足/未接続」に分類する。
    ///
    /// 接続判定: CoreWLANは未接続時に rssiValue() == 0 を返す。SSID/BSSIDは
    /// 権限がないと接続中でも nil になるため、RSSIを主な判定材料にする。
    static func classify(_ raw: RawWiFi?, locationAuthorized: Bool) -> WiFiSnapshot {
        guard let raw else {
            return disconnected(interface: nil, state: .noInterface)
        }
        guard raw.powerOn else {
            return disconnected(interface: raw.interfaceName, state: .wifiOff)
        }
        let associated = raw.rssi < 0 || raw.ssid != nil || raw.bssid != nil
        guard associated else {
            return disconnected(interface: raw.interfaceName, state: .notConnected)
        }

        let hidden: ReadStatus = locationAuthorized ? .unavailable : .permissionDenied
        let ssid: Field<String> = (raw.ssid?.isEmpty == false) ? .ok(raw.ssid!) : .missing(hidden)
        let bssid: Field<String> = (raw.bssid?.isEmpty == false) ? .ok(raw.bssid!) : .missing(hidden)
        let rssi: Field<Int> = raw.rssi < 0 ? .ok(raw.rssi) : .missing(.unavailable)
        let noise: Field<Int> = raw.noise < 0 ? .ok(raw.noise) : .missing(.unavailable)
        let channel: Field<ChannelInfo>
        if let ch = raw.channel, ch.channelNumber > 0 {
            channel = .ok(channelInfo(ch))
        } else {
            channel = .missing(.unavailable)
        }

        return WiFiSnapshot(
            interfaceName: raw.interfaceName,
            connection: .connected,
            ssid: ssid,
            bssid: bssid,
            rssi: rssi,
            noise: noise,
            channel: channel,
            txRate: raw.txRate > 0 ? raw.txRate : nil
        )
    }

    static func channelInfo(_ ch: CWChannel) -> ChannelInfo {
        let band: String
        switch ch.channelBand.rawValue {
        case 1: band = "2.4GHz"
        case 2: band = "5GHz"
        case 3: band = "6GHz"
        default: band = "不明"
        }
        let width: String
        switch ch.channelWidth.rawValue {
        case 1: width = "20MHz"
        case 2: width = "40MHz"
        case 3: width = "80MHz"
        case 4: width = "160MHz"
        default: width = "不明"
        }
        return ChannelInfo(number: ch.channelNumber, band: band, width: width)
    }

    private static func disconnected(interface: String?, state: ConnectionState) -> WiFiSnapshot {
        WiFiSnapshot(
            interfaceName: interface,
            connection: state,
            ssid: .missing(.notConnected),
            bssid: .missing(.notConnected),
            rssi: .missing(.notConnected),
            noise: .missing(.notConnected),
            channel: .missing(.notConnected),
            txRate: nil
        )
    }
}
