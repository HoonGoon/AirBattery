//
//  MagicBattery.swift
//  AirBattery
//
//  Created by apple on 2024/2/9.
//
import SwiftUI
import Foundation

class SPBluetoothDataModel {
    static var data: String = "{}"
}

class MagicBattery {
    var scanTimer: Timer?
    @AppStorage("readBTDevice") var readBTDevice = true
    
    func startScan() {
        scanTimer = Timer.scheduledTimer(timeInterval: 10.0, target: self, selector: #selector(scanDevices), userInfo: nil, repeats: true)
        Thread.detachNewThread {
            if !self.readBTDevice { return }
            self.getMagicBattery()
            self.getOtherBTBattery()
        }
    }
    
    @objc func scanDevices() { Thread.detachNewThread {
        if !self.readBTDevice { return }
        self.getMagicBattery()
        self.getOtherBTBattery()
    } }
    
    func findParentKey(forValue value: Any, in json: [String: Any]) -> String? {
        for (key, subJson) in json {
            if let subJsonDictionary = subJson as? [String: Any] {
                if subJsonDictionary.values.contains(where: { $0 as? String == value as? String }) {
                    return key
                } else if let parentKey = findParentKey(forValue: value, in: subJsonDictionary) {
                    return parentKey
                }
            } else if let subJsonArray = subJson as? [[String: Any]] {
                for subJsonDictionary in subJsonArray {
                    if subJsonDictionary.values.contains(where: { $0 as? String == value as? String }) {
                        return key
                    } else if let parentKey = findParentKey(forValue: value, in: subJsonDictionary) {
                        return parentKey
                    }
                }
            }
        }
        return nil
    }
    
    func getDeviceName(_ mac: String, _ def: String) -> String {
        //guard let result = process(path: "/usr/sbin/system_profiler", arguments: ["SPBluetoothDataType", "-json"]) else { return def }
        if let json = try? JSONSerialization.jsonObject(with: Data(SPBluetoothDataModel.data.utf8), options: []) as? [String: Any] {
            if let parent = findParentKey(forValue: mac, in: json) {
                return parent
            }
        }
        return def
    }

    func getMagicBattery() {
        var serialPortIterator = io_iterator_t()
        var object : io_object_t
        let masterPort: mach_port_t
        if #available(macOS 12.0, *) {
            masterPort = kIOMainPortDefault // New name in macOS 12 and higher
        } else {
            masterPort = kIOMasterPortDefault // Old name in macOS 11 and lower
        }
        let matchingDict : CFDictionary = IOServiceMatching("AppleDeviceManagementHIDEventService")
        let kernResult = IOServiceGetMatchingServices(masterPort, matchingDict, &serialPortIterator)
        
        if KERN_SUCCESS == kernResult {
            repeat {
                object = IOIteratorNext(serialPortIterator)
                if object != 0 {
                    var mac = ""
                    var type = "hid"
                    var status = 0
                    var percent = 0
                    var productName = ""
                    let lastUpdate = Date().timeIntervalSince1970
                    if let productProperty = IORegistryEntryCreateCFProperty(object, "DeviceAddress" as CFString, kCFAllocatorDefault, 0) {
                        mac = productProperty.takeRetainedValue() as! String
                        mac = mac.replacingOccurrences(of:"-", with:":").uppercased()
                    }
                    if let percentProperty = IORegistryEntryCreateCFProperty(object, "BatteryStatusFlags" as CFString, kCFAllocatorDefault, 0) {
                        status = percentProperty.takeRetainedValue() as! Int
                    }
                    if let percentProperty = IORegistryEntryCreateCFProperty(object, "BatteryPercent" as CFString, kCFAllocatorDefault, 0) {
                        percent = percentProperty.takeRetainedValue() as! Int
                    }
                    if let productProperty = IORegistryEntryCreateCFProperty(object, "Product" as CFString, kCFAllocatorDefault, 0) {
                        productName = productProperty.takeRetainedValue() as! String
                        if productName.contains("Trackpad") { type = "Trackpad" }
                        if productName.contains("Keyboard") { type = "Keyboard" }
                        if productName.contains("Mouse") { type = "Mouse" }
                        productName = getDeviceName(mac, productName)
                    }
                    if !productName.contains("Internal"){
                        AirBatteryModel.updateDevices(Device(deviceID: mac, deviceType: type, deviceName: productName, batteryLevel: percent, isCharging: status, lastUpdate: lastUpdate))
                    }
                }
            } while object != 0
            IOObjectRelease(object)
        }
        IOObjectRelease(serialPortIterator)
    }
    
    func getOtherBTBattery() {
        //guard let result = process(path: "/usr/sbin/system_profiler", arguments: ["SPBluetoothDataType", "-json"]) else { return }
        if let json = try? JSONSerialization.jsonObject(with: Data(SPBluetoothDataModel.data.utf8), options: []) as? [String: Any],
        let SPBluetoothDataTypeRaw = json["SPBluetoothDataType"] as? [Any],
        let SPBluetoothDataType = SPBluetoothDataTypeRaw[0] as? [String: Any]{
            if let device_connected = SPBluetoothDataType["device_connected"] as? [Any]{
                for device in device_connected{
                    let d = device as! [String: Any]
                    if let n = d.keys.first, let info = d[n] as? [String: Any] {
                        if let level = info["device_batteryLevelMain"] as? String,
                           let id = info["device_address"] as? String,
                           let type = info["device_minorType"] as? String,
                           (info["device_vendorID"] as? String) != "0x004C" {
                            let batLevel = Int(level.replacingOccurrences(of: "%", with: "")) ?? 255
                            AirBatteryModel.updateDevices(Device(deviceID: id, deviceType: type, deviceName: n, batteryLevel: batLevel, isCharging: 0, lastUpdate: Date().timeIntervalSince1970))
                        }
                    }
                }
            }
        }
    }
}