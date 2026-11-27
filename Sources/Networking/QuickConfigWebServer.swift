import Foundation
import Network
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Darwin

/// 局域网手机扫码快速配置媒体源的轻量级本地 HTTP 服务（基于 NWListener + CoreImage 二维码）
@MainActor
final class QuickConfigWebServer: ObservableObject {
    @Published private(set) var accessURLString: String?
    @Published private(set) var qrImage: UIImage?
    @Published private(set) var statusMessage: String = "正在启动局域网配置服务…"
    @Published private(set) var receivedConfig: MediaSourceConfig?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.aethertv.quick-config-http")
    private let sessionToken: String = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))

    func start() {
        stop()
        receivedConfig = nil
        statusMessage = "正在启动局域网配置服务…"

        guard let ip = Self.localLANIPv4Address() else {
            statusMessage = "未检测到可用的局域网 IPv4 地址，请确认 Apple TV 已连接 Wi-Fi 或有线局域网。"
            return
        }

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let newListener = try NWListener(using: params, on: .any)
            self.listener = newListener

            newListener.stateUpdateHandler = { [weak self, weak newListener] state in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        if let port = newListener?.port?.rawValue, port > 0 {
                            let urlStr = "http://\(ip):\(port)/?t=\(self.sessionToken)"
                            self.accessURLString = urlStr
                            self.qrImage = Self.generateQRCode(for: urlStr)
                            self.statusMessage = "请用手机扫描上方二维码，或在手机浏览器输入下方地址填写媒体源信息。"
                        }
                    case .failed(let err):
                        self.statusMessage = "局域网监听启动失败：\(err.localizedDescription)"
                    default:
                        break
                    }
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                self?.acceptConnection(connection)
            }

            newListener.start(queue: queue)
        } catch {
            statusMessage = "无法创建局域网监听：\(error.localizedDescription)"
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        accessURLString = nil
        qrImage = nil
    }

    // MARK: - HTTP 请求处理

    private nonisolated func acceptConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHTTPRequest(connection: connection, buffer: Data())
    }

    private nonisolated func receiveHTTPRequest(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if let error {
                _ = error
                connection.cancel()
                return
            }

            var accumulated = buffer
            if let data, !data.isEmpty {
                accumulated.append(data)
            }

            if accumulated.count > 65_536 {
                self.sendResponse(on: connection, status: "413 Payload Too Large", contentType: "text/plain; charset=utf-8", body: Data("请求体过大".utf8))
                return
            }

            let separator = Data("\r\n\r\n".utf8)
            if let headerRange = accumulated.range(of: separator) {
                let headerData = accumulated[..<headerRange.lowerBound]
                let bodyStart = headerRange.upperBound
                let headerText = String(data: headerData, encoding: .utf8) ?? ""
                let contentLength = Self.extractContentLength(from: headerText)

                if accumulated.count - bodyStart >= contentLength || isComplete {
                    let bodyData = accumulated[bodyStart..<min(accumulated.count, bodyStart + contentLength)]
                    self.handleParsedHTTP(headerText: headerText, bodyData: Data(bodyData), connection: connection)
                    return
                }
            }

            if isComplete {
                connection.cancel()
                return
            }

            self.receiveHTTPRequest(connection: connection, buffer: accumulated)
        }
    }

    private nonisolated func handleParsedHTTP(headerText: String, bodyData: Data, connection: NWConnection) {
        let lines = headerText.components(separatedBy: "\r\n")
        let requestLine = lines.first ?? ""
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendResponse(on: connection, status: "400 Bad Request", contentType: "text/plain; charset=utf-8", body: Data("Bad Request".utf8))
            return
        }

        let method = String(parts[0]).uppercased()
        let rawTarget = String(parts[1])
        let components = URLComponents(string: "http://localhost" + rawTarget)
        let path = components?.path ?? "/"
        let queryToken = components?.queryItems?.first(where: { $0.name == "t" })?.value ?? ""

        guard queryToken == sessionToken else {
            sendResponse(on: connection, status: "403 Forbidden", contentType: "text/plain; charset=utf-8", body: Data("访问令牌无效，请重新扫码。".utf8))
            return
        }

        if method == "GET" && path == "/" {
            let html = Self.configPageHTML(token: sessionToken)
            sendResponse(on: connection, status: "200 OK", contentType: "text/html; charset=utf-8", body: Data(html.utf8))
        } else if method == "POST" && path == "/submit" {
            do {
                let payload = try JSONDecoder().decode(QuickConfigPayload.self, from: bodyData)
                let proto = MediaProtocolType.allCases.first(where: { $0.rawValue == payload.protocolType }) ?? .webdav
                let portInt = Int(payload.port) ?? proto.defaultPort
                let config = MediaSourceConfig(
                    name: payload.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? payload.host
                        : payload.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    protocolType: proto,
                    host: payload.host.trimmingCharacters(in: .whitespacesAndNewlines),
                    port: portInt,
                    useHTTPS: payload.useHTTPS,
                    basePath: payload.basePath.trimmingCharacters(in: .whitespacesAndNewlines),
                    username: payload.username,
                    password: payload.password,
                    apiToken: payload.apiToken,
                    userId: payload.userId,
                    shareName: payload.shareName.trimmingCharacters(in: .whitespacesAndNewlines),
                    limitSingleConnection: payload.limitSingleConnection,
                    holdSourceConnection: payload.holdSourceConnection
                )
                Task { @MainActor [weak self] in
                    self?.receivedConfig = config
                    self?.statusMessage = "已收到手机提交的配置：\(config.name)"
                }
                sendResponse(on: connection, status: "200 OK", contentType: "application/json; charset=utf-8", body: Data("{\"ok\":true}".utf8))
            } catch {
                sendResponse(on: connection, status: "400 Bad Request", contentType: "application/json; charset=utf-8", body: Data("{\"ok\":false}".utf8))
            }
        } else {
            sendResponse(on: connection, status: "404 Not Found", contentType: "text/plain; charset=utf-8", body: Data("Not Found".utf8))
        }
    }

    private nonisolated func sendResponse(on connection: NWConnection, status: String, contentType: String, body: Data) {
        let headers = [
            "HTTP/1.1 \(status)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Connection: close",
            "Cache-Control: no-store",
            "",
            ""
        ].joined(separator: "\r\n")

        var packet = Data(headers.utf8)
        packet.append(body)
        connection.send(content: packet, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private nonisolated static func extractContentLength(from headerText: String) -> Int {
        for line in headerText.components(separatedBy: "\r\n") {
            if let range = line.range(of: "content-length:", options: [.caseInsensitive, .anchored]) {
                let raw = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return max(0, Int(raw) ?? 0)
            }
        }
        return 0
    }

    // MARK: - 局域网 IP 与二维码生成

    static func localLANIPv4Address() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var preferredIP: String?
        var fallbackIP: String?

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let flags = Int32(interface.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            let ip = String(cString: hostname)
            guard !ip.hasPrefix("169.254."), !ip.hasPrefix("127.") else { continue }

            let name = String(cString: interface.ifa_name)
            if name == "en0" || name == "en1" {
                preferredIP = ip
                break
            } else if fallbackIP == nil {
                fallbackIP = ip
            }
        }
        return preferredIP ?? fallbackIP
    }

    static func generateQRCode(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private nonisolated static func configPageHTML(token: String) -> String {
        """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
          <title>AetherTV 手机快速配置</title>
          <style>
            :root { color-scheme: dark; --bg: #0f111a; --card: #191c28; --accent: #38bdf8; --text: #f3f4f6; --muted: #9ca3af; }
            body { margin: 0; padding: 20px; background: var(--bg); color: var(--text); font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
            .card { max-width: 520px; margin: 0 auto; background: var(--card); border-radius: 16px; padding: 20px; box-shadow: 0 12px 30px rgba(0,0,0,.45); }
            h1 { margin: 0 0 6px; font-size: 20px; }
            p.sub { margin: 0 0 18px; color: var(--muted); font-size: 13px; }
            label { display: block; font-size: 13px; color: var(--muted); margin: 12px 0 6px; }
            input, select { width: 100%; box-sizing: border-box; padding: 11px 12px; border-radius: 10px; border: 1px solid #2d3245; background: #10131d; color: var(--text); font-size: 15px; }
            .row { display: flex; gap: 10px; align-items: center; margin-top: 12px; }
            .row input[type=checkbox] { width: auto; transform: scale(1.2); }
            button { margin-top: 20px; width: 100%; padding: 13px; border: 0; border-radius: 12px; background: var(--accent); color: #05131e; font-weight: 700; font-size: 16px; }
            #msg { margin-top: 14px; font-size: 14px; text-align: center; }
          </style>
        </head>
        <body>
          <div class="card">
            <h1>AetherTV 媒体源配置</h1>
            <p class="sub">填写完成后点击发送，电视端表单将自动填入。</p>
            <label>协议类型</label>
            <select id="protocolType" onchange="syncDefaults()">
              <option value="SMB" selected>SMB</option>
              <option value="WebDAV">WebDAV</option>
              <option value="Emby">Emby</option>
              <option value="Jellyfin">Jellyfin</option>
              <option value="Plex">Plex</option>
              <option value="DLNA">DLNA</option>
              <option value="HTTP 直链">HTTP 直链</option>
            </select>
            <label>媒体源名称</label>
            <input id="name" placeholder="例如：家庭 NAS" value="" />
            <label>服务器 IP 或主机名</label>
            <input id="host" placeholder="例如：192.168.1.100 或 nas.local" />
            <label>端口（0 为默认端口）</label>
            <input id="port" type="number" value="445" />
            <div class="row">
              <input id="useHTTPS" type="checkbox" />
              <label style="margin:0">启用 HTTPS</label>
            </div>
            <div id="shareWrap">
              <label>SMB 共享名（如 media / share）</label>
              <input id="shareName" placeholder="例如：media" />
            </div>
            <div id="pathWrap" style="display:none">
              <label>基础路径 / DLNA Control 路径</label>
              <input id="basePath" value="/" placeholder="例如：/dav 或 /ctl/ContentDir" />
            </div>
            <div id="userWrap">
              <label>用户名（访客可留空）</label>
              <input id="username" placeholder="例如：admin" />
              <label>密码</label>
              <input id="password" type="password" />
            </div>
            <div id="tokenWrap" style="display:none">
              <label>API Key / X-Plex-Token</label>
              <input id="apiToken" />
              <label>用户 ID（可留空）</label>
              <input id="userId" />
            </div>
            <div class="row">
              <input id="limitSingleConnection" type="checkbox" />
              <label style="margin:0">单连接限流模式（Alist / 网盘反代）</label>
            </div>
            <div class="row">
              <input id="holdSourceConnection" type="checkbox" />
              <label style="margin:0">保持长连接拉流</label>
            </div>
            <button onclick="submitForm()">发送到 Apple TV</button>
            <div id="msg"></div>
          </div>
          <script>
            const defaults = { "SMB": 445, "WebDAV": 5005, "Emby": 8096, "Jellyfin": 8096, "Plex": 32400, "DLNA": 0, "HTTP 直链": 80 };
            function syncDefaults() {
              const p = document.getElementById('protocolType').value;
              document.getElementById('port').value = defaults[p] ?? 80;
              document.getElementById('shareWrap').style.display = p === 'SMB' ? 'block' : 'none';
              document.getElementById('pathWrap').style.display = p === 'SMB' ? 'none' : 'block';
              const isMediaSrv = (p === 'Emby' || p === 'Jellyfin' || p === 'Plex');
              document.getElementById('tokenWrap').style.display = isMediaSrv ? 'block' : 'none';
              document.getElementById('userWrap').style.display = (isMediaSrv || p === 'DLNA') ? 'none' : 'block';
              if (p === 'DLNA' && document.getElementById('basePath').value === '/') {
                document.getElementById('basePath').value = '/MediaServer/ContentDirectory/Control';
              }
            }
            async function submitForm() {
              const msg = document.getElementById('msg');
              const host = document.getElementById('host').value.trim();
              if (!host) { msg.style.color = '#fb923c'; msg.textContent = '请填写服务器 IP 或主机名'; return; }
              const payload = {
                protocolType: document.getElementById('protocolType').value,
                name: document.getElementById('name').value,
                host: host,
                port: document.getElementById('port').value,
                useHTTPS: document.getElementById('useHTTPS').checked,
                shareName: document.getElementById('shareName').value,
                basePath: document.getElementById('basePath').value,
                username: document.getElementById('username').value,
                password: document.getElementById('password').value,
                apiToken: document.getElementById('apiToken').value,
                userId: document.getElementById('userId').value,
                limitSingleConnection: document.getElementById('limitSingleConnection').checked,
                holdSourceConnection: document.getElementById('holdSourceConnection').checked
              };
              try {
                const res = await fetch('/submit?t=\(token)', {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json' },
                  body: JSON.stringify(payload)
                });
                if (res.ok) {
                  msg.style.color = '#4ade80';
                  msg.textContent = '已发送！请在电视端检查并点击保存。';
                } else {
                  msg.style.color = '#f87171';
                  msg.textContent = '发送失败（HTTP ' + res.status + '）';
                }
              } catch (e) {
                msg.style.color = '#f87171';
                msg.textContent = '连接失败：' + e;
              }
            }
          </script>
        </body>
        </html>
        """
    }
}

private struct QuickConfigPayload: Decodable {
    let name: String
    let protocolType: String
    let host: String
    let port: String
    let useHTTPS: Bool
    let shareName: String
    let basePath: String
    let username: String
    let password: String
    let apiToken: String
    let userId: String
    let limitSingleConnection: Bool
    let holdSourceConnection: Bool
}
