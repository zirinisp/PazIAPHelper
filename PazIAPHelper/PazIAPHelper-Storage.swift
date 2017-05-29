//
//  PazIAPHelper-Storage.swift
//  PazIAPHelper
//
//  Created by Pantelis Zirinis on 29/05/2017.
//  Copyright © 2017 Pantelis Zirinis. All rights reserved.
//

import Foundation

@available(iOS 8.0, *)
public extension PazIAPHelper { // Store file managment
    
    var productsFilePath: String? {
        return self.productsFilePathUrl?.path
    }
    
    public var productsFilePathUrl: URL? {
        let documentsDirectory = FileManager.default.urls(for:.cachesDirectory, in: .userDomainMask).first
        return  documentsDirectory?.appendingPathComponent("products.plist", isDirectory: false)
    }
    
    public func restoreProductsFromMemery()  {
        guard let path = self.productsFilePath else {
            print("Error restoring products from memory")
            return
        }
        if let items = NSKeyedUnarchiver.unarchiveObject(withFile: path) as? Set<PazIAPProduct>, items.count != 0 {
            print("restored \(items.count) products from \(path)")
            self.products.formUnion(items)
        } else {
            print("Error - could not restore products from \(path)")
        }
    }
    
    public func saveProductsToMemory() {
        guard let url = self.productsFilePathUrl else {
            print("Error saving products to memory")
            return
        }
        let data = NSKeyedArchiver.archivedData(withRootObject: self.products)
        do {
            print("Saving products \(self.products.count)")
            #if os(macOS) || os(Linux)
                try data.write(to: url)
            #else
                try data.write(to: url, options: [.atomicWrite, .completeFileProtection])
            #endif
        } catch {
            print("Failed to save purchased items: \(error.localizedDescription)")
        }
    }
}
