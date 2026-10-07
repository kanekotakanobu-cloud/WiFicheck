# WiFiSurvey — macOS Wi-Fi 現場調査アプリ

3m以内の「通信良好地点」と「不良地点」を A/B/C で切り替えながら記録し、電波と通信失敗を比較するための最小構成アプリです。

## 方針
- 使用API: **CoreWLAN**（RSSI/ノイズ/チャネル/SSID/BSSID）、**SystemConfiguration**（ゲートウェイ）、**/sbin/ping**（疎通）、**CoreLocation**（SSID/BSSID取得の許可確認のみ）
- `airport` コマンドは使用しません（macOS 14.4 で廃止）。
- Wi-Fi設定の変更・スキャン・パケットキャプチャ・外部へのデータ送信は行いません。ネットワークに出るのはユーザーが指定したPingのICMPのみ。CSVはローカル保存のみです。
- 位置情報は「許可状態の確認」にのみ使い、座標は取得しません。

## ビルド（macOS 13 以降、Xcode または Command Line Tools）
```sh
./scripts/build_app.sh
open build/WiFiSurvey.app
```
`swift run` でも起動しますが、**バンドル外実行では位置情報を許可できない**ため SSID/BSSID は常に「権限不足」になります。必ず `.app` から起動してください。
アドホック署名のため、再ビルドすると位置情報の許可がリセットされる場合があります。

## 手順1: 対象Macでの取得可否の検証
1. Wi-Fiに接続した状態でアプリを起動し「取得可否の検証…」を開く。
2. 位置情報の許可を求められたら許可（拒否した場合は「権限不足」になることを確認できます）。
3. 各項目の判定を確認し、「レポートをコピー」で記録を残す。

| 項目 | 取得元 | 主な判定 |
|---|---|---|
| 接続状態 | CoreWLAN `rssiValue()` / `ssid()` / `bssid()` / `powerOn()` | 接続中 / 未接続 / Wi-Fiオフ / インターフェースなし |
| RSSI | `rssiValue()` | 0 → 取得不可 |
| ノイズ | `noiseMeasurement()` | 0 → 取得不可（機種/OSにより返らない場合あり） |
| チャネル | `wlanChannel()` | nil → 取得不可 |
| SSID / BSSID | `ssid()` / `bssid()` | nil かつ位置情報未許可 → 権限不足、許可済みでも nil → 取得不可 |
| ゲートウェイ | `State:/Network/Service/*/IPv4` の `Router` | Wi-Fiサービス側を優先 |
| Ping | `/sbin/ping -c1 -W1000 -b <Wi-Fi I/F>` | 成功 / タイムアウト / エラー / 未実施 |

検証画面には判定の根拠として生値（rssi, noise, interfaceMode, serviceActive など）も表示します。
**接続判定は「RSSI<0 または SSID/BSSID が取れる」で行っています。** 対象macOSで未接続時に RSSI が 0 以外を返すような挙動があれば、この判定を見直す必要があります（生値で確認してください）。

## 手順2: 記録
- 地点ボタン A/B/C（⌘1/⌘2/⌘3）で現在地点を切り替え。以後のサンプルにその地点が付きます。
- Ping宛先を入力（空欄なら宛先Pingは「未実施」）。ゲートウェイPingは自動。両者は同時に実行。
- 間隔 1/2/5 秒、記録開始/停止は ⌘Space。
- グラフ: 上段 RSSI/ノイズ（地点別色、灰線=未接続）、下段 Ping RTT（赤線=GW失敗、橙破線=宛先失敗）。
- 「地点別比較」で RSSI平均/最小、ノイズ、SNR、未接続回数、損失率、RTT平均を比較。

## 状態の区別（CSV）
| 値 | 意味 |
|---|---|
| `ok` | 取得できた |
| `unavailable` | 接続中だがAPIが値を返さない（取得不可） |
| `permission_denied` | 位置情報未許可でOSが値を隠している（権限不足） |
| `not_connected` | Wi-Fi未接続（`connection` 列で `not_connected` / `wifi_off` / `no_interface` を区別） |

Ping状態: `ok` / `timeout` / `error`（名前解決失敗、経路なし等。詳細は `*_ping_detail`）/ `skipped`（ゲートウェイ不明・宛先未指定）。損失率は `skipped` を分母に含めません。

### CSV列
`timestamp, point, connection, interface, ssid, ssid_status, bssid, bssid_status, rssi_dbm, rssi_status, noise_dbm, noise_status, snr_db, channel, band, width, channel_status, tx_rate_mbps, gateway_ip, gateway_ping_status, gateway_rtt_ms, gateway_ping_detail, target_host, target_ping_status, target_rtt_ms, target_ping_detail`
（UTF-8 BOM付き、CRLF。Excelでそのまま開けます）

## 既知の制約
- RSSI/ノイズの更新頻度はOS/ドライバ依存で、1秒間隔でも同じ値が続くことがあります。
- 1回の計測ごとにPingは1発のみ（タイムアウト1秒）。間隔より応答待ちが長い場合、次の計測は遅れます（重複実行はしません）。
- ゲートウェイがICMPに応答しない設定の場合、GW Pingは常に失敗します。検証画面で事前に確認してください。
- 有線とWi-Fiを併用している場合も、Pingは `-b` でWi-Fiインターフェースに束縛します。
