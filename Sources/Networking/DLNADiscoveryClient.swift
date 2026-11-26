import Foundation
import Network

struct DLNADevice: Identifiable, Hashable, Sendable {
    var id: String { locationURL.absoluteString }
    let friendlyName: String
    let locationURL: URL
    let controlURL: URL
}

/// 局域网 DLNA / UPnP ContentDirectory 浏览客户端
final class DLNADiscoveryClient: Sendable {
    /// 通过 UPnP ContentDirectory:1 SOAP Browse 浏览指定对象 ID（根目录为 "0"）
    func browse(controlURL: URL, objectId: String = "0", sourceId: UUID? = nil) async throws -> [MediaItem] {
        let soapBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
              <ObjectID>\(objectId)</ObjectID>
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

        let session = NetworkPitfallGuards.makeResilientSession(allowSelfSignedLAN: true)
        let (data, _) = try await session.data(for: req)
        let didlXML = DLNASOAPResultExtractor.extractResultXML(from: data)
        guard let didlData = didlXML.data(using: .utf8) else { return [] }
        return DIDLLiteParser.parse(data: didlData, controlURL: controlURL, sourceId: sourceId)
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
