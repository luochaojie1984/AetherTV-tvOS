import Foundation
import Network

struct DiscoveredLANService: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let protocolType: MediaProtocolType
    let host: String
    let port: Int
    let useHTTPS: Bool
    let dlnaControlPath: String?
}

/// 局域网设备自动发现服务：
/// 1. 使用 Network.framework `NWBrowser` 扫描 Bonjour 服务（SMB / WebDAV / WebDAVS / Emby / Jellyfin / Plex）
/// 2. 并发执行 SSDP `239.255.255.250:1900` 探测发现 DLNA 媒体服务器（自签无多播权限时优雅降级提示）
@MainActor
final class LANServiceBrowser: ObservableObject {
    @Published private(set) var discoveredServices: [DiscoveredLANService] = []
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var dlnaMulticastBlocked: Bool = false

    private var browsers: [NWBrowser] = []
    private var resolveConnections: [NWConnection] = []
    private var ssdpTask: Task<Void, Never>?
    private let queue = DispatchQueue(label: "com.aethertv.lan-service-browser")

    private static let bonjourTargets: [(type: String, proto: MediaProtocolType, https: Bool)] = [
        ("_smb._tcp", .smb, false),
        ("_webdav._tcp", .webdav, false),
        ("_webdavs._tcp", .webdav, true),
        ("_emby._tcp", .emby, false),
        ("_jellyfin._tcp", .jellyfin, false),
        ("_plexmediasvr._tcp", .plex, false)
    ]

    func start(allowSelfSignedLAN: Bool) {
        stop()
        discoveredServices = []
        dlnaMulticastBlocked = false
        isScanning = true

        for target in Self.bonjourTargets {
            let params = NWParameters.tcp
            params.includePeerToPeer = false
            let browser = NWBrowser(for: .bonjour(type: target.type, domain: "local."), using: params)
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                Task { @MainActor [weak self] in
                    self?.handleBonjourResults(results, protocolType: target.proto, useHTTPS: target.https)
                }
            }
            browser.start(queue: queue)
            browsers.append(browser)
        }

        ssdpTask = Task { [weak self] in
            let result = await DLNADiscoveryClient(allowSelfSignedLAN: allowSelfSignedLAN).discoverDevices()
            guard !Task.isCancelled, let self else { return }
            self.dlnaMulticastBlocked = result.multicastBlocked
            for device in result.devices {
                let host = device.controlURL.host ?? device.locationURL.host ?? ""
                guard !host.isEmpty else { continue }
                let useHTTPS = device.controlURL.scheme?.lowercased() == "https"
                let defaultPort = useHTTPS ? 443 : 80
                let port = device.controlURL.port ?? defaultPort
                let path = device.controlURL.path.isEmpty ? "/" : device.controlURL.path
                let service = DiscoveredLANService(
                    id: "dlna:\(device.controlURL.absoluteString)",
                    name: device.friendlyName,
                    protocolType: .dlna,
                    host: host,
                    port: port,
                    useHTTPS: useHTTPS,
                    dlnaControlPath: path
                )
                self.appendUniqueService(service)
            }
            self.isScanning = false
        }
    }

    func stop() {
        ssdpTask?.cancel()
        ssdpTask = nil
        for browser in browsers {
            browser.cancel()
        }
        browsers.removeAll()
        for conn in resolveConnections {
            conn.cancel()
        }
        resolveConnections.removeAll()
        isScanning = false
    }

    private func handleBonjourResults(
        _ results: Set<NWBrowser.Result>,
        protocolType: MediaProtocolType,
        useHTTPS: Bool
    ) {
        for result in results {
            guard case .service(let serviceName, _, _, _) = result.endpoint else { continue }
            resolveEndpoint(result.endpoint, serviceName: serviceName, protocolType: protocolType, useHTTPS: useHTTPS)
        }
    }

    private func resolveEndpoint(
        _ endpoint: NWEndpoint,
        serviceName: String,
        protocolType: MediaProtocolType,
        useHTTPS: Bool
    ) {
        let params = NWParameters.tcp
        params.prohibitedInterfaceTypes = [.cellular]
        let connection = NWConnection(to: endpoint, using: params)
        resolveConnections.append(connection)

        var resolvedOnce = false
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            switch state {
            case .ready:
                guard !resolvedOnce else { return }
                resolvedOnce = true
                let remote = connection?.currentPath?.remoteEndpoint
                connection?.cancel()
                if case .hostPort(let nwHost, let nwPort) = remote,
                   let hostString = Self.formatHost(nwHost) {
                    let portInt = Int(nwPort.rawValue)
                    let item = DiscoveredLANService(
                        id: "\(protocolType.rawValue):\(hostString):\(portInt)",
                        name: serviceName,
                        protocolType: protocolType,
                        host: hostString,
                        port: portInt > 0 ? portInt : protocolType.defaultPort,
                        useHTTPS: useHTTPS,
                        dlnaControlPath: nil
                    )
                    Task { @MainActor [weak self] in
                        self?.appendUniqueService(item)
                    }
                }
            case .failed, .cancelled:
                guard !resolvedOnce else { return }
                resolvedOnce = true
                connection?.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)

        queue.asyncAfter(deadline: .now() + 3.0) { [weak connection] in
            if !resolvedOnce {
                resolvedOnce = true
                connection?.cancel()
            }
        }
    }

    private func appendUniqueService(_ service: DiscoveredLANService) {
        if !discoveredServices.contains(where: { $0.id == service.id }) {
            discoveredServices.append(service)
            discoveredServices.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    private nonisolated static func formatHost(_ host: NWEndpoint.Host) -> String? {
        switch host {
        case .ipv4(let v4):
            let bytes = [UInt8](v4.rawValue)
            guard bytes.count == 4 else { return nil }
            return "\(bytes[0]).\(bytes[1]).\(bytes[2]).\(bytes[3])"
        case .ipv6(let v6):
            let raw = "\(v6)"
            if raw.lowercased().hasPrefix("fe80:") {
                return nil
            }
            return "[\(raw)]"
        case .name(let hostname, _):
            return hostname
        @unknown default:
            return nil
        }
    }
}
