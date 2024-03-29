//
//  Volume.swift
//  EjectKey
//
//  Created by fus1ondev on 2022/08/07.
//

// ref: https://github.com/bradleybernard/EjectBar/blob/master/EjectBar/Classes/Volume.swift
// ref: https://github.com/nielsmouthaan/ejectify-macos/blob/main/ejectify/Model/ExternalVolume.swift
// ref: https://github.com/phu54321/Semulov/blob/master/SLListCulprits.m
// ref: https://github.com/CloverHackyColor/CloverBootloader/blob/master/CloverApp/Clover/Disks.swift

import Dispatch
import Cocoa
import IOKit.kext

class Volume {

    private let diskInfo: [NSString: Any]
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

        let type = resourceValues.volumeLocalizedFormatDescription ?? ""

        self.diskInfo = diskInfo
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
        self.isVirtual = deviceProtocol == "Virtual Interface"
        self.isDiskImage = self.isVirtual && deviceVendor == "Apple" && deviceModel == "Disk Image"
    }
    
    var icon: NSImage? {
        if let iconPath = getIconPath() {
            return NSImage(byReferencingFile: iconPath)
        } else {
            return nil
        }
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
    
    private func getIconPath() -> String? {
        let iconPath = url.appending(path: "/.VolumeIcon.icns").path()
        
        if FileManager.default.fileExists(atPath: iconPath) {
            return iconPath
        }
        
        if let iconDict = diskInfo[kDADiskDescriptionMediaIconKey] as? NSDictionary,
              let iconName = iconDict.object(forKey: kIOBundleResourceFileKey ) as? NSString {
            // swiftlint:disable force_cast
            let identifier = iconDict.object(forKey: kCFBundleIdentifierKey as String) as! CFString
            // swiftlint:enable force_cast

            let bundleUrl = Unmanaged.takeRetainedValue(KextManagerCreateURLForBundleIdentifier(kCFAllocatorDefault, identifier))() as URL
            if let bundle = Bundle(url: bundleUrl),
               let iconPath = bundle.path(forResource: iconName.deletingPathExtension, ofType: iconName.pathExtension) {
                return iconPath
            }
        }
        return nil
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
