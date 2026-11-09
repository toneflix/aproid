import CoreBluetooth
import CoreLocation
import Foundation
import OSLog
import AproidKit

/// Finds a paired phone over Bluetooth when Wi-Fi discovery fails, and asks it where it is.
/// With `.hotspot` it also asks the phone to put its hotspot switch in front of the user.
final class NearbyFinder: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    /// Called on a background queue with the phone's sealed-and-opened answer.
    var onAnswer: ((Nearby.Answer) -> Void)?

    /// Called on a background queue when a phone is in Bluetooth range, or when a search ends with nothing.
    var onNearby: ((Bool) -> Void)?

    private let ownId: String
    private var privateKeyPEM: String?
    private let queue = DispatchQueue(label: "com.toneflix.aproid.nearby")
    private let log = Logger(subsystem: "com.toneflix.aproid.app", category: "nearby")
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var answer: CBCharacteristic?
    private var want = Nearby.Want.connect
    private var searching = false

    private let service = CBUUID(string: Nearby.service)
    private let requestId = CBUUID(string: Nearby.request)
    private let answerId = CBUUID(string: Nearby.answer)

    /// Location is only needed to read the Wi-Fi name when learning the phone's hotspot.
    private lazy var location = CLLocationManager()

    init(ownId: String) {
        self.ownId = ownId
        super.init()
    }

    /// Our certificate's key, which opens the phone's answers. Set once the certificate is loaded.
    func use(privateKeyPEM: String) {
        queue.async { self.privateKeyPEM = privateKeyPEM }
    }

    /// Looks for a phone for about 20 seconds. Bluetooth asks the user once, the first time.
    func search(_ want: Nearby.Want) {
        queue.async {
            self.want = want
            self.searching = true

            if let central = self.central {
                if central.state == .poweredOn { self.scan() }
            } else {
                self.central = CBCentralManager(delegate: self, queue: self.queue)
            }

            self.queue.asyncAfter(deadline: .now() + 20) { [weak self] in self?.giveUp() }
        }
    }

    func askForLocation() {
        DispatchQueue.main.async { self.location.requestWhenInUseAuthorization() }
    }

    private func scan() {
        guard let central, searching, peripheral == nil else { return }

        central.scanForPeripherals(withServices: [service])
    }

    private func giveUp() {
        guard searching else { return }

        finish()
        onNearby?(false)
    }

    private func finish() {
        searching = false
        central?.stopScan()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        answer = nil
    }

    // MARK: Bluetooth

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { scan() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard self.peripheral == nil else { return }

        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
        onNearby?(true)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        self.peripheral = nil
        scan()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral == self.peripheral else { return }

        self.peripheral = nil
        answer = nil
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let found = peripheral.services?.first(where: { $0.uuid == service }) else { return }

        peripheral.discoverCharacteristics([requestId, answerId], for: found)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let characteristics = service.characteristics ?? []
        guard let request = characteristics.first(where: { $0.uuid == requestId }),
              let answer = characteristics.first(where: { $0.uuid == answerId })
        else { return }

        self.answer = answer
        peripheral.setNotifyValue(true, for: answer)
        peripheral.writeValue(Nearby.Request(deviceId: ownId, want: want).bytes(), for: request, type: .withResponse)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == answerId, let value = characteristic.value else { return }

        // A one byte note says the answer is ready; then we read it, which may take several pieces.
        if value.count <= 1 {
            peripheral.readValue(for: characteristic)
            return
        }

        guard let pem = privateKeyPEM, let opened = try? Nearby.open(value, privateKeyPEM: pem) else {
            log.info("Could not read the phone's Bluetooth answer")
            return
        }

        finish()
        onAnswer?(opened)
    }
}
