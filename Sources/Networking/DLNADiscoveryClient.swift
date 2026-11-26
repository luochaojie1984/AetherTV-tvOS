import Foundation
import Darwin

struct DLNADevice: Identifiable, Hashable, Sendable {
    var id: String { locationURL.absoluteString }
    let friendlyName: String
    let locationURL: URL
    let controlURL: URL
}

struct DLNADiscoveryResult: Sendable {
    let devices: [DLNADevice]
    let multicastBlocked: Bool
}

/// 局域网 DLNA / UPnP ContentDirectory 浏览与 SSDP 发现客户端
final class DLNADiscoveryClient: Sendable {
    private let allowSelfSignedLAN: Bool

    init(allowSelfSignedLAN: Bool = true) {
        self.allowSelfSignedLAN = allowSelfSignedLAN
    }

    /// 对拼接进 SOAP XML 节点的参数做标准 XML 转义，防止注入与解析损坏
    static func xmlEscape(_ raw: String) -> String {
        var out = ""
        out.reserveCapacity(raw.count)
        for ch in raw {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.append(ch)
            }
        }
        return out
    }

    /// 通过 UPnP ContentDirectory:1 SOAP Browse 浏览指定对象 ID（根目录为 "0"）
    func browse(controlURL: URL, objectId: String = "0", sourceId: UUID? = nil) async throws -> [MediaItem] {
        let escapedObjectId = Self.xmlEscape(objectId)
        let soapBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
              <ObjectID>\(escapedObjectId)</ObjectID>
              <BrowseFlag>BrowseDirectChildren</BrowseFlag>
              <Filter>*</Filter>
              <StartingIndex>0</StartingIndex>
              <RequestedCount>200</RequestedCount>
              <SortCriteria></SortCriteria>
            </u:Browse>
          </s:Body>
        </s:Envelope>
        """

        var req = URLRequest(url: controlURL)
        req.httpMethod = "POST"
        req.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        req.setValue("\"urn:schemas-upnp-org:service:ContentDirectory:1#Browse\"", forHTTPHeaderField: "SOAPACTION")
        req.httpBody = soapBody.data(using: .utf8)

        let session = NetworkPitfallGuards.sharedSession(allowSelfSignedLAN: allowSelfSignedLAN)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw MediaServerError.serverError("未收到有效的 HTTP 响应")
        }
        guard (200...299).contains(http.statusCode) else {
            throw MediaServerError.serverError("DLNA SOAP 请求失败（HTTP \(http.statusCode)）")
        }

        let didlXML = DLNASOAPResultExtractor.extractResultXML(from: data)
        guard let didlData = didlXML.data(using: .utf8) else { return [] }
        return DIDLLiteParser.parse(data: didlData, controlURL: controlURL, sourceId: sourceId)
    }

    /// 局域网 SSDP UDP 239.255.255.250:1900 广播扫描支持 ContentDirectory 的 DLNA 媒体服务器。
    /// 若在未授予 Apple 多播受限权限（`com.apple.developer.networking.multicast`）的自签环境下被系统拦截，
    /// 会优雅返回 `multicastBlocked: true`，引导用户回退手动填写 Control 路径。
    func discoverDevices(timeoutSeconds: TimeInterval = 2.4) async -> DLNADiscoveryResult {
        let probeResult = await Task.detached(priority: .utility) {
            Self.sendSSDPProbe(timeoutSeconds: timeoutSeconds)
        }.value

        if probeResult.multicastBlocked || probeResult.locations.isEmpty {
            return DLNADiscoveryResult(devices: [], multicastBlocked: probeResult.multicastBlocked)
        }

        let session = NetworkPitfallGuards.sharedSession(allowSelfSignedLAN: allowSelfSignedLAN)
        var devices: [DLNADevice] = []

        await withTaskGroup(of: DLNADevice?.self) { group in
            for locationURL in probeResult.locations {
                group.addTask {
                    var req = URLRequest(url: locationURL)
                    req.timeoutInterval = 4
                    guard let (data, resp) = try? await session.data(for: req),
                          let http = resp as? HTTPURLResponse,
                          (200...299).contains(http.statusCode) else {
                        return nil
                    }
                    return Self.parseDeviceDescription(data: data, locationURL: locationURL)
                }
            }
            for await device in group {
                if let device, !devices.contains(where: { $0.controlURL == device.controlURL }) {
                    devices.append(device)
                }
            }
        }

        devices.sort { $0.friendlyName.localizedStandardCompare($1.friendlyName) == .orderedAscending }
        return DLNADiscoveryResult(devices: devices, multicastBlocked: false)
    }

    /// 从 SSDP M-SEARCH 响应文本中提取 `LOCATION` URL
    static func parseSSDPResponseLocations(_ raw: String) -> [URL] {
        var urls: [URL] = []
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let range = trimmed.range(of: "location:", options: [.caseInsensitive, .anchored]) {
                let value = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if let url = URL(string: value), !urls.contains(url) {
                    urls.append(url)
                }
            }
        }
        return urls
    }

    /// 解析 UPnP 设备描述 XML，提取 `friendlyName` 与 `ContentDirectory` 的 `controlURL`
    static func parseDeviceDescription(data: Data, locationURL: URL) -> DLNADevice? {
        DLNADeviceDescriptionParser.parse(data: data, locationURL: locationURL)
    }

    private static func sendSSDPProbe(timeoutSeconds: TimeInterval) -> (locations: [URL], multicastBlocked: Bool) {
        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            return ([], errno == EPERM || errno == EACCES)
        }
        defer { Darwin.close(fd) }

        var reuse: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var ttl: UInt8 = 2
        _ = setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))

        var rcvTimeout = timeval(tv_sec: 0, tv_usec: 300_000)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &rcvTimeout, socklen_t(MemoryLayout<timeval>.size))

        var bindAddr = sockaddr_in()
        bindAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        bindAddr.sin_family = sa_family_t(AF_INET)
        bindAddr.sin_port = 0
        bindAddr.sin_addr = in_addr(s_addr: INADDR_ANY)
        let bindRes = withUnsafePointer(to: &bindAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bindRes < 0 {
            return ([], errno == EPERM || errno == EACCES)
        }

        var mcastAddr = sockaddr_in()
        mcastAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        mcastAddr.sin_family = sa_family_t(AF_INET)
        mcastAddr.sin_port = UInt16(1900).bigEndian
        _ = "239.255.255.250".withCString { cstr in
            inet_pton(AF_INET, cstr, &mcastAddr.sin_addr)
        }

        let searchTargets = [
            "urn:schemas-upnp-org:service:ContentDirectory:1",
            "urn:schemas-upnp-org:device:MediaServer:1"
        ]

        var multicastBlocked = false
        for st in searchTargets {
            let packet = [
                "M-SEARCH * HTTP/1.1",
                "HOST: 239.255.255.250:1900",
                "MAN: \"ssdp:discover\"",
                "MX: 2",
                "ST: \(st)",
                "",
                ""
            ].joined(separator: "\r\n")

            if let data = packet.data(using: .utf8) {
                let sent = data.withUnsafeBytes { rawBuf -> ssize_t in
                    guard let base = rawBuf.baseAddress else { return -1 }
                    return withUnsafePointer(to: &mcastAddr) { addrPtr in
                        addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                            Darwin.sendto(fd, base, rawBuf.count, 0, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }
                if sent < 0 && (errno == EPERM || errno == EACCES) {
                    multicastBlocked = true
                    break
                }
            }
        }

        if multicastBlocked {
            return ([], true)
        }

        var seenLocations = Set<URL>()
        var orderedLocations: [URL] = []
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var buffer = [UInt8](repeating: 0, count: 4096)

        while Date() < deadline {
            var sender = sockaddr_storage()
            var senderLen = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let n = withUnsafeMutablePointer(to: &sender) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    Darwin.recvfrom(fd, &buffer, buffer.count, 0, sockPtr, &senderLen)
                }
            }
            if n > 0 {
                let msg = String(decoding: buffer[0..<n], as: UTF8.self)
                for url in parseSSDPResponseLocations(msg) {
                    if seenLocations.insert(url).inserted {
                        orderedLocations.append(url)
                    }
                }
            } else {
                let err = errno
                if err != EAGAIN && err != EWOULDBLOCK && err != EINTR {
                    break
                }
            }
        }

        return (orderedLocations, false)
    }
}

private final class DLNADeviceDescriptionParser: NSObject, XMLParserDelegate {
    private let locationURL: URL
    private var friendlyName = ""
    private var inDevice = false
    private var inService = false
    private var currentServiceType = ""
    private var currentControlURL = ""
    private var matchedControlURL: String?
    private var buffer = ""

    private init(locationURL: URL) {
        self.locationURL = locationURL
    }

    static func parse(data: Data, locationURL: URL) -> DLNADevice? {
        let delegate = DLNADeviceDescriptionParser(locationURL: locationURL)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.parse()

        guard let rawControl = delegate.matchedControlURL,
              !rawControl.isEmpty,
              let resolvedControl = URL(string: rawControl, relativeTo: locationURL)?.absoluteURL else {
            return nil
        }
        let name = delegate.friendlyName.isEmpty
            ? (locationURL.host ?? "DLNA 媒体服务器")
            : delegate.friendlyName
        return DLNADevice(friendlyName: name, locationURL: locationURL, controlURL: resolvedControl)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let local = stripNamespace(elementName)
        buffer = ""
        if local == "device" {
            inDevice = true
        } else if local == "service" {
            inService = true
            currentServiceType = ""
            currentControlURL = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let local = stripNamespace(elementName)
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch local {
        case "friendlyname":
            if inDevice && friendlyName.isEmpty && !text.isEmpty {
                friendlyName = text
            }
        case "servicetype":
            if inService { currentServiceType = text }
        case "controlurl":
            if inService { currentControlURL = text }
        case "service":
            if inService,
               currentServiceType.lowercased().contains("contentdirectory"),
               !currentControlURL.isEmpty,
               matchedControlURL == nil {
                matchedControlURL = currentControlURL
            }
            inService = false
        default:
            break
        }
        buffer = ""
    }

    private func stripNamespace(_ name: String) -> String {
        if let idx = name.lastIndex(of: ":") {
            return String(name[name.index(after: idx)...]).lowercased()
        }
        return name.lowercased()
    }
}

private final class DLNASOAPResultExtractor: NSObject, XMLParserDelegate {
    private var capturing = false
    private var result = ""

    static func extractResultXML(from data: Data) -> String {
        let delegate = DLNASOAPResultExtractor()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.result
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName.lowercased().hasSuffix("result") {
            capturing = true
            result = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturing { result += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName.lowercased().hasSuffix("result") {
            capturing = false
        }
    }
}

private final class DIDLLiteParser: NSObject, XMLParserDelegate {
    private let controlURL: URL
    private let sourceId: UUID?
    private var items: [MediaItem] = []

    private var currentId: String = ""
    private var currentTitle: String = ""
    private var currentResURL: String = ""
    private var currentSize: Int64?
    private var isContainer = false
    private var buffer = ""

    init(controlURL: URL, sourceId: UUID?) {
        self.controlURL = controlURL
        self.sourceId = sourceId
    }

    static func parse(data: Data, controlURL: URL, sourceId: UUID?) -> [MediaItem] {
        let delegate = DIDLLiteParser(controlURL: controlURL, sourceId: sourceId)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let local = elementName.lowercased()
        buffer = ""
        if local == "container" {
            isContainer = true
            currentId = attributeDict["id"] ?? ""
            currentTitle = ""
            currentResURL = ""
            currentSize = nil
        } else if local == "item" {
            isContainer = false
            currentId = attributeDict["id"] ?? ""
            currentTitle = ""
            currentResURL = ""
            currentSize = nil
        } else if local == "res" {
            if let sizeStr = attributeDict["size"] {
                currentSize = NetworkPitfallGuards.parseContentLength(sizeStr)
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let local = elementName.lowercased()
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if local.hasSuffix("title") {
            currentTitle = text
        } else if local == "res" && currentResURL.isEmpty {
            currentResURL = text
        } else if local == "container" {
            items.append(MediaItem(
                id: "dlna:\(controlURL.absoluteString):\(currentId)",
                title: currentTitle.isEmpty ? "文件夹" : currentTitle,
                subtitle: "DLNA 目录",
                isDirectory: true,
                sourceId: sourceId,
                protocolType: .dlna,
                remotePath: currentId
            ))
        } else if local == "item", let stream = URL(string: currentResURL) {
            items.append(MediaItem(
                id: "dlna:\(controlURL.absoluteString):\(currentId)",
                title: currentTitle.isEmpty ? stream.lastPathComponent : currentTitle,
                subtitle: "DLNA 媒体",
                isDirectory: false,
                streamURL: stream,
                fileSize: currentSize,
                sourceId: sourceId,
                protocolType: .dlna,
                remotePath: currentId
            ))
        }
        buffer = ""
    }
}
