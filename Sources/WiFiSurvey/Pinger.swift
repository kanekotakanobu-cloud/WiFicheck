import Foundation

/// /sbin/ping を1回実行する。-b でWi-Fiインターフェースに束縛し、有線経由にならないようにする。
enum Pinger {
    static let path = "/sbin/ping"

    static func ping(host: String, interface: String?, timeoutMs: Int = 1000) async -> PingOutcome {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            var args = ["-n", "-q", "-c", "1", "-W", String(timeoutMs)]
            if let interface { args += ["-b", interface] }
            args.append(host)
            p.arguments = args
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe

            p.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(decoding: data, as: UTF8.self)
                cont.resume(returning: parse(proc, text))
            }
            do {
                try p.run()
            } catch {
                cont.resume(returning: .error("ping起動失敗: \(error.localizedDescription)"))
                return
            }
            // 名前解決の停滞などで -W が効かない場合の保険
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(timeoutMs + 2000)) {
                if p.isRunning { p.terminate() }
            }
        }
    }

    private static func parse(_ proc: Process, _ text: String) -> PingOutcome {
        if proc.terminationReason == .uncaughtSignal { return .timeout }
        switch proc.terminationStatus {
        case 0:
            // -q の要約行: "round-trip min/avg/max/stddev = 1.234/1.234/1.234/0.000 ms"
            if let line = text.split(separator: "\n").first(where: { $0.contains("min/avg/max") }),
               let eq = line.range(of: "= ") {
                let nums = line[eq.upperBound...].split(separator: "/")
                if nums.count >= 2, let avg = Double(nums[1]) { return .success(ms: avg) }
            }
            return .error("応答解析失敗")
        case 2:
            return .timeout
        case 68:
            return .error("名前解決失敗")
        default:
            let msg = text.split(separator: "\n").first.map(String.init) ?? "終了コード \(proc.terminationStatus)"
            return .error(msg.trimmingCharacters(in: .whitespaces))
        }
    }
}
