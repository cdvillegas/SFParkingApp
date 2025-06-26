import CoreBluetooth

class BluetoothPermissionDelegate: NSObject, CBCentralManagerDelegate {
    private let completion: () -> Void
    private var centralManager: CBCentralManager?
    
    init(completion: @escaping () -> Void) {
        self.completion = completion
        super.init()
        // Initialize the CBCentralManager to trigger permission request
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // Once the state is updated (permission granted or denied), we proceed
        // The actual permission handling will be done by the main app's BluetoothManager
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.completion()
        }
    }
}