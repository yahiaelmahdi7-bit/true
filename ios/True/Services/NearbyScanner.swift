import Foundation
import UIKit
@preconcurrency import CoreBluetooth

/// What the phone knows about Bluetooth right now. Only `.poweredOn` can find a Mac.
enum BluetoothState: Equatable { case unknown, poweredOn, poweredOff, unauthorized, unsupported }

/// The phone side of "nearby pairing". Real Bluetooth sits behind this so the simulator (which has none)
/// and tests drive a fake. Discovery only: the pairing code is never sent over Bluetooth.
@MainActor
protocol NearbyScanning: AnyObject {
    var onState: (BluetoothState) -> Void { get set }
    var onMac: (NearbyPairing.NearbyMac?) -> Void { get set }
    var onPaired: () -> Void { get set }
    func start()
    func stop()
}

/// Stable per-install id so the Mac can rate-limit one phone. Not a hardware id.
enum NearbyPhoneID {
    static var value: String {
        let d = UserDefaults.standard
        if let v = d.string(forKey: "nearbyPhoneId") { return v }
        let v = UUID().uuidString
        d.set(v, forKey: "nearbyPhoneId")
        return v
    }
}

@MainActor
final class CoreBluetoothScanner: NSObject, NearbyScanning {
    var onState: (BluetoothState) -> Void = { _ in }
    var onMac: (NearbyPairing.NearbyMac?) -> Void = { _ in }
    var onPaired: () -> Void = {}

    private var central: CBCentralManager?
    private var wanted = false
    private var peripheral: CBPeripheral?
    private var localName = ""
    private var address: String?
    private var helloChar: CBCharacteristic?
    private var helloSent = false
    private let serviceID = CBUUID(string: NearbyPairing.serviceUUID)

    func start() {
        wanted = true
        // Creating the manager is what triggers the Bluetooth permission prompt, so it happens here (Pair screen), not at launch.
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        else { scanIfReady() }
    }

    func stop() {
        wanted = false
        central?.stopScan()
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        reset()
    }

    private func reset() {
        peripheral = nil; address = nil; helloChar = nil; helloSent = false
    }

    private func scanIfReady() {
        guard wanted, let central, central.state == .poweredOn, peripheral == nil else { return }
        central.scanForPeripherals(withServices: [serviceID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func publishIfReady() {
        guard let address else { return }
        onMac(.init(name: NearbyPairing.macName(fromLocalName: localName), address: address))
        sendHelloIfReady()
    }

    private func sendHelloIfReady() {
        guard !helloSent, address != nil, let p = peripheral, let c = helloChar else { return }
        helloSent = true
        let hello = NearbyPairing.Hello(name: UIDevice.current.name, id: NearbyPhoneID.value)
        p.writeValue(NearbyPairing.encodeHello(hello), for: c, type: .withoutResponse)
    }
}

extension CoreBluetoothScanner: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: onState(.poweredOn); scanIfReady()
        case .poweredOff: onState(.poweredOff); reset(); onMac(nil)
        case .unauthorized: onState(.unauthorized)
        case .unsupported: onState(.unsupported)
        default: onState(.unknown)
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard self.peripheral == nil, NearbyPairing.isNearby(rssi: RSSI.intValue) else { return }
        localName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        self.peripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([serviceID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        reset(); scanIfReady()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let had = address != nil
        reset()
        if had { onMac(nil) }
        scanIfReady()
    }
}

extension CoreBluetoothScanner: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = peripheral.services?.first(where: { $0.uuid == serviceID }) else { return }
        peripheral.discoverCharacteristics([CBUUID(string: NearbyPairing.addressUUID),
                                            CBUUID(string: NearbyPairing.helloUUID),
                                            CBUUID(string: NearbyPairing.pairedUUID)], for: s)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            switch c.uuid.uuidString.uppercased() {
            case NearbyPairing.addressUUID: peripheral.readValue(for: c)
            case NearbyPairing.helloUUID: helloChar = c
            case NearbyPairing.pairedUUID: peripheral.setNotifyValue(true, for: c)
            default: break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else { return }
        switch characteristic.uuid.uuidString.uppercased() {
        case NearbyPairing.addressUUID:
            guard let data = characteristic.value, let a = NearbyPairing.decodeAddress(data) else { return }
            address = a
            publishIfReady()
        case NearbyPairing.pairedUUID:
            if characteristic.value?.first == 1 { onPaired() }
        default: break
        }
    }
}

/// Stand-in for the simulator and screenshots: reports a Mac straight away.
@MainActor
final class FakeNearbyScanner: NearbyScanning {
    var onState: (BluetoothState) -> Void = { _ in }
    var onMac: (NearbyPairing.NearbyMac?) -> Void = { _ in }
    var onPaired: () -> Void = {}
    let state: BluetoothState
    let mac: NearbyPairing.NearbyMac?

    init(state: BluetoothState = .poweredOn,
         mac: NearbyPairing.NearbyMac? = .init(name: "Yahia's MacBook", address: "yoshii-mac.tail1234.ts.net:8444")) {
        self.state = state; self.mac = mac
    }

    func start() {
        onState(state)
        if state == .poweredOn, let mac { onMac(mac) }
    }
    func stop() { onMac(nil) }
}
