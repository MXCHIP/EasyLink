/*
* Copyright (c) 2019, Nordic Semiconductor
* All rights reserved.
*
* Redistribution and use in source and binary forms, with or without modification,
* are permitted provided that the following conditions are met:
*
* 1. Redistributions of source code must retain the above copyright notice, this
*    list of conditions and the following disclaimer.
*
* 2. Redistributions in binary form must reproduce the above copyright notice, this
*    list of conditions and the following disclaimer in the documentation and/or
*    other materials provided with the distribution.
*
* 3. Neither the name of the copyright holder nor the names of its contributors may
*    be used to endorse or promote products derived from this software without
*    specific prior written permission.
*
* THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
* ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
* WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
* IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
* INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
* NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
* PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
* WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
* ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
* POSSIBILITY OF SUCH DAMAGE.
*/

import Foundation
import CoreBluetooth

/// Base implementation for GATT Proxy bearer.
///
/// This object is not required to be used with nRF Mesh Provisioning library.
/// Bearers are separate from the mesh networking part and the data must be
/// passed to and from by the application.
open class MxPBGattBearer: NSObject, MxProvisioningBearer, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    // MARK: - Properties
    public weak var delegate: BearerDelegate?
    public weak var dataDelegate: BearerDataDelegate?
    public weak var logger: LoggerDelegate?
    
    private let centralManager: CBCentralManager
    private var basePeripheral: CBPeripheral!
    
    /// The protocol used for segmentation and reassembly.
    private let protocolHandler: ProxyProtocolHandler
    /// The queue of PDUs to be sent. Used if the perpheral is busy.
    private var queue: [Data] = []
    /// A flag indicating whether `open()` method was called.
    private var isOpened: Bool = false
    
    // MARK: - Computed properties
    
    public var supportedPduTypes: PduTypes {
        return [.networkPdu, .meshBeacon, .proxyConfiguration, .provisioningPdu]
    }
    
    public var isOpen: Bool {
        return dataOutCharacteristic?.isNotifying ?? false
    }
    
    /// The UUID associated with the peer.
    public let identifier: UUID
    
    /// The name of the peripheral.
    ///
    /// This returns `nil` if the peripheral hasn't been yet retrieved (Bluetooth is off)
    /// or the device does not have a name.
    public var name: String? {
        return basePeripheral?.name
    }
    
    // MARK: - Characteristic properties
    
    private var dataInCharacteristic:  CBCharacteristic?
    private var dataOutCharacteristic: CBCharacteristic?
    
    private var proxyDataInCharacteristic:  CBCharacteristic?
    private var proxyDataOutCharacteristic: CBCharacteristic?
    
    // MARK: - Public API
    
    /// Creates the Gatt Proxy Bearer object. Call `open()` to open connection to the proxy.
    ///
    /// - parameter peripheral: The CBPeripheral poiting a Bluetooth LE device with
    ///                         Bluetooth Mesh GATT service (Provisioning or Proxy Service).
    public convenience init(target peripheral: CBPeripheral) {
        self.init(targetWithIdentifier: peripheral.identifier)
    }
    
    /// Creates the Gatt Proxy Bearer object. Call `open()` to open connection to the proxy.
    ///
    /// - parameter uuid: The UUID associated with the peer.
    public init(targetWithIdentifier uuid: UUID) {
        centralManager  = CBCentralManager()
        identifier = uuid
        protocolHandler = ProxyProtocolHandler()
        super.init()
        centralManager.delegate = self
    }
    
    open func open() {
        if centralManager.state == .poweredOn && basePeripheral?.state == .disconnected {
            logger?.v(.bearer, "Connecting to \(basePeripheral.name ?? "Unknown Device")...")
            centralManager.connect(basePeripheral, options: nil)
        }
        isOpened = true
    }
    
    open func close() {
        if basePeripheral?.state == .connected || basePeripheral?.state == .connecting {
            logger?.v(.bearer, "Cancelling connection...")
            centralManager.cancelPeripheralConnection(basePeripheral)
        }
        isOpened = false
    }
    
    open func switchToProxyBear() -> Bool {
        // Ensure all required characteristics were found.
        guard let dataOutCharacteristic = proxyDataOutCharacteristic, let _ = proxyDataInCharacteristic,
            dataOutCharacteristic.properties.contains(.notify) else {
                logger?.e(.bearer, "Proxy feature is not supported")
                return false
        }
        self.dataOutCharacteristic = dataOutCharacteristic
        self.dataInCharacteristic = proxyDataInCharacteristic
        enableNotifications(for: dataOutCharacteristic)
        return true
    }
    
    open func send(_ data: Data, ofType type: PduType) throws {
        guard supports(type) else {
            throw BearerError.pduTypeNotSupported
        }
        guard isOpen else {
            throw BearerError.bearerClosed
        }
        guard let dataInCharacteristic = dataInCharacteristic else {
            throw GattBearerError.deviceNotSupported
        }
        
        let mtu = basePeripheral.maximumWriteValueLength(for: .withoutResponse)
        let packets = protocolHandler.segment(data, ofType: type, toMtu: mtu)
        
        // On iOS 11+ only the first packet is sent here. When the peripheral is ready
        // to send more data, a `peripheralIsReady(toSendWriteWithoutResponse:)` callback
        // will be called, which will send the next packet.
        if #available(iOS 11.0, *) {
            let queueWasEmpty = queue.isEmpty
            queue.append(contentsOf: packets)
            
            // Don't look at `basePeripheral.canSendWriteWithoutResponse`. If often returns
            // `false` even when nothing was sent before and no callback is called afterwards.
            // Just assume, that the first packet can always be sent.
            if queueWasEmpty {
                let packet = queue.remove(at: 0)
                logger?.d(.bearer, "-> 0x\(packet.hex)")
                basePeripheral.writeValue(packet, for: dataInCharacteristic, type: .withoutResponse)
            }
        } else {
            // For iOS versions before 11, the data must be just sent in a loop.
            // This may not work if there is more than ~20 packets to be sent, as a
            // buffer may overflow. The solution would be to add some delays, but
            // let's hope it will work as is. For now.
            // TODO: Handle very long packets on iOS 9 and 10.
            for packet in packets {
                logger?.d(.bearer, "-> 0x\(packet.hex)")
                basePeripheral.writeValue(packet, for: dataInCharacteristic, type: .withoutResponse)
            }
        }
    }
    
    /// Retrieves the current RSSI value for the peripheral while it is connected
    /// to the central manager.
    ///
    /// The result will be returned using `bearer(_:didReadRSSI)` callback.
    open func readRSSI() {
        guard basePeripheral.state == .connected else {
            return
        }
        basePeripheral.readRSSI()
    }
    
    // MARK: - Implementation
    
    /// Starts service discovery, only given Service.
    private func discoverServices() {
        logger?.v(.bearer, "Discovering services...")
        basePeripheral.discoverServices([MeshProxyService.uuid, MeshProvisioningService.uuid])
    }
    
    /// Starts characteristic discovery for Data In and Data Out Characteristics.
    ///
    /// - parameter service: The service to look for the characteristics in.
    private func discoverCharacteristics(for service: CBService) {
        logger?.v(.bearer, "Discovering characteristrics...")
        if MeshProxyService.matches(service) {
            basePeripheral.discoverCharacteristics([MeshProxyService.dataInUuid, MeshProxyService.dataOutUuid], for: service)
        } else if MeshProvisioningService.matches(service) {
            basePeripheral.discoverCharacteristics([MeshProvisioningService.dataInUuid, MeshProvisioningService.dataOutUuid], for: service)
        }
    }
    
    /// Enables notification for the given characteristic.
    ///
    /// - parameter characteristic: The characteristic to enable notifications for.
    private func enableNotifications(for characteristic: CBCharacteristic) {
        logger?.v(.bearer, "Enabling notifications...")
        basePeripheral.setNotifyValue(true, for: characteristic)
    }
    
    // MARK: - CBCentralManagerDelegate
    
    open func centralManagerDidUpdateState(_ central: CBCentralManager) {
        logger?.i(.bearer, "Central Manager state changed to \(central.state)")
        if central.state == .poweredOn {
            guard let peripheral = centralManager.retrievePeripherals(withIdentifiers: [identifier]).first else {
                logger?.w(.bearer, "Device with identifier \(identifier.uuidString) not found")
                isOpened = false
                return
            }
            basePeripheral = peripheral
            basePeripheral.delegate = self
            if isOpened {
                open()
            }
        } else {
            delegate?.bearer(self, didClose: BearerError.centralManagerNotPoweredOn)
        }
    }
    
    open func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if peripheral == basePeripheral {
            logger?.i(.bearer, "Connected to \(peripheral.name ?? "Unknown Device")")
            if let delegate = delegate as? GattBearerDelegate {
                delegate.bearerDidConnect(self)
            }
            discoverServices()
        }
    }
    
    open func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peripheral == basePeripheral {
            let deviceNotSupported = dataInCharacteristic == nil || dataOutCharacteristic == nil
                || !dataOutCharacteristic!.properties.contains(.notify)
            self.dataInCharacteristic = nil
            self.dataOutCharacteristic = nil
            if let error = error as NSError? {
                switch error.code {
                case 6, 7: logger?.e(.bearer, error.localizedDescription)
                default: logger?.e(.bearer, "Disconnected from \(peripheral.name ?? "Unknown Device") with error: \(error)")
                }
                delegate?.bearer(self, didClose: error)
            } else {
                guard !deviceNotSupported else {
                        logger?.e(.bearer, "Disconnected from \(peripheral.name ?? "Unknown Device") with error: Device not supported")
                        delegate?.bearer(self, didClose: GattBearerError.deviceNotSupported)
                        return
                }
                logger?.i(.bearer, "Disconnected from \(peripheral.name ?? "Unknown Device")")
                delegate?.bearer(self, didClose: nil)
            }
        }
    }
    
    // MARK: - CBPeripheralDelegate
    
    open func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        var serviceFound = false
        if let services = peripheral.services {
            for service in services {
                if MeshProvisioningService.matches(service) || MeshProxyService.matches(service) {
                    serviceFound = true
                    logger?.v(.bearer, "Provisioning service found")
                    discoverCharacteristics(for: service)
                }
            }
        }
        if serviceFound == false {
            // Required service not found.
            logger?.e(.bearer, "Device not supported")
            close()
        }
    }
    
    open func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        // Look for optional proxy characteristics.
        if MeshProxyService.matches(service) {
            if let characteristics = service.characteristics {
                for characteristic in characteristics {
                    if MeshProxyService.dataInUuid == characteristic.uuid {
                        logger?.v(.bearer, "Data In characteristic found")
                        proxyDataInCharacteristic = characteristic
                    } else if MeshProxyService.dataOutUuid == characteristic.uuid {
                        logger?.v(.bearer, "Data Out characteristic found")
                        proxyDataOutCharacteristic = characteristic
                    }
                }
            }
            return
        }
        
        // Look for required characteristics.
        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                if MeshProvisioningService.dataInUuid == characteristic.uuid {
                    logger?.v(.bearer, "Data In characteristic found")
                    dataInCharacteristic = characteristic
                } else if MeshProvisioningService.dataOutUuid == characteristic.uuid {
                    logger?.v(.bearer, "Data Out characteristic found")
                    dataOutCharacteristic = characteristic
                }
            }
        }
        
        // Ensure all required characteristics were found.
        guard let dataOutCharacteristic = dataOutCharacteristic, let _ = dataInCharacteristic,
            dataOutCharacteristic.properties.contains(.notify) else {
                logger?.e(.bearer, "Device not supported")
                close()
                return
        }
        
        if let delegate = delegate as? GattBearerDelegate {
            delegate.bearerDidDiscoverServices(self)
        }
        enableNotifications(for: dataOutCharacteristic)
    }
    
    open func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        // TODO: implement
    }
    
    open func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic == dataOutCharacteristic, characteristic.isNotifying else {
            return
        }
        
        logger?.v(.bearer, "Data Out notifications enabled")
        logger?.i(.bearer, "GATT Bearer open and ready")
        delegate?.bearerDidOpen(self)
    }
    
    open func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic == dataOutCharacteristic, let data = characteristic.value else {
            return
        }
        logger?.d(.bearer, "<- 0x\(data.hex)")
        if let message = protocolHandler.reassemble(data) {
            dataDelegate?.bearer(self, didDeliverData: message.data, ofType: message.messageType)
        }
    }
    
    open func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        // Data is sent without response.
        // This method will not be called.
    }
    
    open func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if let delegate = delegate as? GattBearerDelegate {
            delegate.bearer(self, didReadRSSI: RSSI)
        }
    }
    
    // This method is available only on iOS 11+.
    open func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard !queue.isEmpty else {
            return
        }
        
        let packet = queue.remove(at: 0)
        logger?.d(.bearer, "-> 0x\(packet.hex)")
        peripheral.writeValue(packet, for: dataInCharacteristic!, type: .withoutResponse)
    }
    
}

//extension CBManagerState: CustomDebugStringConvertible {
//
//    public var debugDescription: String {
//        switch self {
//        case .unknown: return ".unknown"
//        case .resetting: return ".resetting"
//        case .unsupported: return ".unsupported"
//        case .unauthorized: return ".unauthorized"
//        case .poweredOff: return ".poweredOff"
//        case .poweredOn: return ".poweredOn"
//        default: return "Unknown"
//        }
//    }
    
//}