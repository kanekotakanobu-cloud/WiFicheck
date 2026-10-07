import AppKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var recorder: Recorder
    @ObservedObject var location: LocationAuthorizer
    @State private var showProbe = false
    @State private var saveError: String?

    private let chartWindow = 900

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            pointBar
            controls
            if !location.isAuthorized { locationBanner }
            StatusPanel(sample: recorder.latest)
            let shown = Array(recorder.samples.suffix(chartWindow))
            GroupBox("電波（RSSI / ノイズ）  灰線 = 未接続") { SignalChart(samples: shown).frame(minHeight: 170) }
            GroupBox("通信（Ping RTT）  縦線 = 失敗") { PingChart(samples: shown).frame(minHeight: 150) }
            GroupBox("地点別比較") { SummaryTable(rows: PointSummary.make(recorder.samples)) }
        }
        .padding()
        .sheet(isPresented: $showProbe) { ProbeView(location: location) }
        .alert("保存に失敗しました", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK") { saveError = nil }
        } message: { Text(saveError ?? "") }
    }

    private var pointBar: some View {
        HStack(spacing: 12) {
            Text("測定地点").font(.headline)
            ForEach(Array(SurveyPoint.allCases.enumerated()), id: \.element) { idx, p in
                Button { recorder.point = p } label: {
                    Text(p.rawValue).font(.system(size: 28, weight: .bold)).frame(width: 70, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(recorder.point == p ? pointColor(p) : .gray.opacity(0.4))
                .keyboardShortcut(KeyEquivalent(Character(String(idx + 1))), modifiers: .command)
                .help("⌘\(idx + 1)")
            }
            Spacer()
            Text("記録数 \(recorder.samples.count)").monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Text("Ping宛先")
            TextField("例: 8.8.8.8 / 社内サーバ", text: $recorder.target)
                .textFieldStyle(.roundedBorder).frame(width: 220)
            Picker("間隔", selection: $recorder.interval) {
                Text("1秒").tag(1.0)
                Text("2秒").tag(2.0)
                Text("5秒").tag(5.0)
            }
            .frame(width: 120)
            if recorder.isRunning {
                Button("停止") { recorder.stop() }.keyboardShortcut(.space, modifiers: .command)
            } else {
                Button("記録開始") { recorder.start() }.keyboardShortcut(.space, modifiers: .command)
            }
            Button("クリア") { recorder.clear() }.disabled(recorder.isRunning || recorder.samples.isEmpty)
            Button("CSV保存…") { saveCSV() }.disabled(recorder.samples.isEmpty)
            Spacer()
            Button("取得可否の検証…") { showProbe = true }
        }
    }

    private var locationBanner: some View {
        HStack {
            Image(systemName: "location.slash")
            Text("位置情報が未許可（\(location.label)）のため、SSID/BSSIDは「権限不足」として記録されます。他の項目は記録できます。")
                .font(.callout)
            Spacer()
            Button("許可を要求") { location.request() }
            Button("システム設定を開く") { location.openSystemSettings() }
        }
        .padding(8)
        .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
    }

    private func saveCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        panel.nameFieldStringValue = "wifi-survey-\(f.string(from: Date())).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CSVExporter.write(recorder.samples, to: url)
        } catch {
            saveError = error.localizedDescription
        }
    }
}

func pointColor(_ p: SurveyPoint) -> Color {
    switch p {
    case .A: return .blue
    case .B: return .green
    case .C: return .purple
    }
}

struct StatusPanel: View {
    let sample: Sample?

    var body: some View {
        let w = sample?.wifi
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            GridRow {
                cell("接続", w?.connection.label ?? "-", nil)
                cell("RSSI", w?.rssi.value.map { "\($0) dBm" }, w?.rssi.status)
                cell("ノイズ", w?.noise.value.map { "\($0) dBm" }, w?.noise.status)
                cell("SNR", w?.snr.map { "\($0) dB" } ?? "-", nil)
            }
            GridRow {
                cell("チャネル", w?.channel.value?.text, w?.channel.status)
                cell("SSID", w?.ssid.value, w?.ssid.status)
                cell("BSSID", w?.bssid.value, w?.bssid.status)
                cell("I/F", w?.interfaceName ?? "-", nil)
            }
            GridRow {
                cell("GW \(sample?.gatewayIP ?? "")", sample?.gateway.detail ?? "-", nil)
                    .foregroundStyle(sample?.gateway.failed == true ? .red : .primary)
                cell("宛先 \(sample?.target.target ?? "")", sample?.target.detail ?? "-", nil)
                    .foregroundStyle(sample?.target.failed == true ? .red : .primary)
                cell("地点", sample?.point.rawValue ?? "-", nil)
                cell("時刻", sample.map { $0.timestamp.formatted(date: .omitted, time: .standard) } ?? "-", nil)
            }
        }
        .font(.system(.body, design: .monospaced))
    }

    private func cell(_ title: String, _ value: String?, _ status: ReadStatus?) -> some View {
        let text: String
        if let value {
            text = value
        } else if let status {
            text = "(\(status.label))"
        } else {
            text = "-"
        }
        return VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(text).lineLimit(1)
        }
        .frame(minWidth: 180, alignment: .leading)
    }
}

struct SignalChart: View {
    let samples: [Sample]

    var body: some View {
        Chart {
            ForEach(samples) { s in
                if let r = s.wifi.rssi.value {
                    PointMark(x: .value("時刻", s.timestamp), y: .value("dBm", r))
                        .foregroundStyle(by: .value("系列", "RSSI \(s.point.rawValue)"))
                        .symbolSize(16)
                }
                if let n = s.wifi.noise.value {
                    PointMark(x: .value("時刻", s.timestamp), y: .value("dBm", n))
                        .foregroundStyle(by: .value("系列", "Noise \(s.point.rawValue)"))
                        .symbolSize(8)
                }
                if s.wifi.connection != .connected {
                    RuleMark(x: .value("時刻", s.timestamp))
                        .foregroundStyle(by: .value("系列", "未接続"))
                }
            }
        }
        .chartForegroundStyleScale([
            "RSSI A": Color.blue, "RSSI B": Color.green, "RSSI C": Color.purple,
            "Noise A": Color.blue.opacity(0.35), "Noise B": Color.green.opacity(0.35), "Noise C": Color.purple.opacity(0.35),
            "未接続": Color.gray.opacity(0.4),
        ])
        .chartYScale(domain: -100 ... -20)
        .chartYAxisLabel("dBm")
    }
}

struct PingChart: View {
    let samples: [Sample]

    var body: some View {
        Chart {
            ForEach(samples) { s in
                if let ms = s.gateway.rtt {
                    PointMark(x: .value("時刻", s.timestamp), y: .value("ms", ms))
                        .foregroundStyle(by: .value("系列", "GW RTT"))
                        .symbolSize(14)
                }
                if let ms = s.target.rtt {
                    PointMark(x: .value("時刻", s.timestamp), y: .value("ms", ms))
                        .foregroundStyle(by: .value("系列", "宛先 RTT"))
                        .symbolSize(14)
                }
                if s.gateway.failed {
                    RuleMark(x: .value("時刻", s.timestamp))
                        .foregroundStyle(by: .value("系列", "GW失敗"))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                if s.target.failed {
                    RuleMark(x: .value("時刻", s.timestamp))
                        .foregroundStyle(by: .value("系列", "宛先失敗"))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
            }
        }
        .chartForegroundStyleScale([
            "GW RTT": Color.teal, "宛先 RTT": Color.indigo,
            "GW失敗": Color.red.opacity(0.6), "宛先失敗": Color.orange.opacity(0.8),
        ])
        .chartYAxisLabel("ms")
    }
}

struct SummaryTable: View {
    let rows: [PointSummary]

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 4) {
            GridRow {
                ForEach(["地点", "件数", "RSSI平均", "RSSI最小", "ノイズ平均", "SNR平均", "未接続", "GW損失", "GW RTT", "宛先損失", "宛先 RTT"], id: \.self) {
                    Text($0).font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(rows) { r in
                GridRow {
                    Text(r.point.rawValue).bold().foregroundStyle(pointColor(r.point))
                    Text("\(r.count)")
                    Text(fmt(r.rssiAvg, "%.1f"))
                    Text(r.rssiMin.map(String.init) ?? "-")
                    Text(fmt(r.noiseAvg, "%.1f"))
                    Text(fmt(r.snrAvg, "%.1f"))
                    Text("\(r.disconnected)")
                    Text(fmt(r.gwLoss, "%.1f%%"))
                    Text(fmt(r.gwRttAvg, "%.1f"))
                    Text(fmt(r.targetLoss, "%.1f%%"))
                    Text(fmt(r.targetRttAvg, "%.1f"))
                }
            }
        }
        .font(.system(.body, design: .monospaced))
    }

    private func fmt(_ v: Double?, _ f: String) -> String {
        v.map { String(format: f, $0) } ?? "-"
    }
}

struct ProbeView: View {
    @ObservedObject var location: LocationAuthorizer
    @Environment(\.dismiss) private var dismiss
    @State private var items: [ProbeItem] = []
    @State private var running = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("取得可否の検証").font(.title2).bold()
            Text("このMacで各項目を取得できるかを確認します。Wi-Fi設定は変更しません。Wi-Fiに接続した状態で実行してください。")
                .font(.callout).foregroundStyle(.secondary)
            List(items) { i in
                HStack(alignment: .top) {
                    Text(i.name).frame(width: 150, alignment: .leading)
                    Text(i.verdict).bold().frame(width: 90, alignment: .leading).foregroundStyle(color(i.verdict))
                    Text(i.detail).textSelection(.enabled)
                }
            }
            .frame(minHeight: 380)
            HStack {
                Button(running ? "検証中…" : "再検証") { Task { await run() } }.disabled(running)
                if !location.isAuthorized { Button("位置情報の許可を要求") { location.request() } }
                Button("レポートをコピー") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(CapabilityProbe.report(items), forType: .string)
                }
                .disabled(items.isEmpty)
                Spacer()
                Button("閉じる") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(width: 820)
        .task { await run() }
        .onChange(of: location.statusRaw) { _ in Task { await run() } }
    }

    private func run() async {
        running = true
        items = await CapabilityProbe.run(locationAuthorized: location.isAuthorized, locationLabel: location.label)
        running = false
    }

    private func color(_ v: String) -> Color {
        switch v {
        case "取得可", "OK", "許可", "成功", "接続中", "電源オン": return .green
        case "権限不足", "未許可", "未実施": return .orange
        case "取得不可", "NG", "失敗", "なし": return .red
        default: return .primary
        }
    }
}
