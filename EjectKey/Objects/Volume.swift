//
//  Volume.swift
//  EjectKey
//
//  Created by fus1ondev on 2022/08/07.
//

// ref: https://github.com/bradleybernard/EjectBar/blob/master/EjectBar/Classes/Volume.swift
// ref: https://github.com/nielsmouthaan/ejectify-macos/blob/main/ejectify/Model/ExternalVolume.swift
// ref: https://github.com/phu54321/Semulov/blob/master/SLListCulprits.m

import Dispatch
import Cocoa

class Volume {

    let disk: DADisk
    let bsdName: String
    let name: String
    let url: URL
    let size: Int
    let deviceProtocol: String
    let deviceModel: String
    let deviceVendor: String
    let devicePath: String
    let type: String
    let unitNumber: Int
    let id: String
    let icon: NSImage
    let isVirtual: Bool
    let isDiskImage: Bool
    
    init?(url: URL) {
        guard let resourceValues = try? url.resourceValues(forKeys: [.volumeIsInternalKey, .volumeLocalizedFormatDescriptionKey]) else {
            return nil
        }
        
        let isInternalVolume = resourceValues.volumeIsInternal ?? false
        
        if isInternalVolume {
            return nil
        }
        
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
              let diskInfo = DADiskCopyDescription(disk) as? [NSString: Any],
              let name = diskInfo[kDADiskDescriptionVolumeNameKey] as? String,
              let bsdName = diskInfo[kDADiskDescriptionMediaBSDNameKey] as? String,
              let size = diskInfo[kDADiskDescriptionMediaSizeKey] as? Int,
              let deviceProtocol = diskInfo[kDADiskDescriptionDeviceProtocolKey] as? String,
              let deviceModel = diskInfo[kDADiskDescriptionDeviceModelKey] as? String,
              let deviceVendor = diskInfo[kDADiskDescriptionDeviceVendorKey] as? String,
              let devicePath = diskInfo[kDADiskDescriptionDevicePathKey] as? String,
              let unitNumber = diskInfo[kDADiskDescriptionMediaBSDUnitKey] as? Int,
              let idVal = diskInfo[kDADiskDescriptionVolumeUUIDKey]
        else {
            return nil
        }
        
        // swiftlint:disable force_cast
        let uuid = idVal as! CFUUID
        // swiftlint:enable force_cast
        guard let cfID = CFUUIDCreateString(kCFAllocatorDefault, uuid) else {
            return nil
        }
        let id = cfID as String

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let type = resourceValues.volumeLocalizedFormatDescription ?? ""

        self.disk = disk
        self.bsdName = bsdName
        self.name = name
        self.url = url
        self.size = size
        self.deviceProtocol = deviceProtocol
        self.deviceModel = deviceModel
        self.deviceVendor = deviceVendor
        self.devicePath = devicePath
        self.type = type
        self.unitNumber = unitNumber
        self.id = id
        self.icon = icon
        self.isVirtual = deviceProtocol == "Virtual Interface"
        self.isDiskImage = self.isVirtual && deviceVendor == "Apple" && deviceModel == "Disk Image"
    }
    
    func unmount(unmountAndEject: Bool, withoutUI: Bool, completionHandler: @escaping (Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            let options: FileManager.UnmountOptions = [
                unmountAndEject ? .allPartitionsAndEjectDisk : [],
                withoutUI ? .withoutUI: []
            ]
            
            fileManager.unmountVolume(at: self.url, options: options, completionHandler: completionHandler)
        }
    }

    func getCulpritApps() -> [NSRunningApplication] {
        let volumePath = url.path(percentEncoded: false)
        let command = Command("/usr/sbin/lsof", ["-Fn", "+D", volumePath])
        
        guard let result = command.run() else {
            return []
        }
        
        let lines = result.components(separatedBy: .newlines)
        
        let pids = lines.compactMap({ line in
            if line.starts(with: "p") {
                return Int32(line.dropFirst(1))
            } else {
                return nil
            }
        }).unique
        
        let apps = pids.compactMap({ NSRunningApplication(processIdentifier: $0) })
        
        return apps
    }
}
