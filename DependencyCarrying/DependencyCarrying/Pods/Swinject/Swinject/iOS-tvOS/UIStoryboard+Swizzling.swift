//
//  UIStoryboard+Swizzling.swift
//  Swinject
//
//  Created by Yoichi Tagaya on 10/10/15.
//  Copyright © 2015 Swinject Contributors. All rights reserved.
//

import UIKit

extension UIStoryboard {
    // Class method `load` is not available in Swift. Instead `initialize` is used.
    // http://nshipster.com/swift-objc-runtime/
    public override class func initialize() {
        if self !== UIStoryboard.self {
            return
        }
        
        struct Static {
            static var token: dispatch_once_t = 0
        }
        dispatch_once(&Static.token) {
            let original = class_getClassMethod(UIStoryboard.self, "storyboardWithName:bundle:")
            let swizzled = class_getClassMethod(UIStoryboard.self, "swinject_storyboardWithName:bundle:")
            method_exchangeImplementations(original, swizzled)
        }
    }
    
    @objc
    private class func swinject_storyboardWithName(name: String, bundle storyboardBundleOrNil: NSBundle) -> UIStoryboard {
        if self === UIStoryboard.self {
            // Instantiate SwinjectStoryboard if UIStoryboard is tried to be instantiated.
            return SwinjectStoryboard.create(name: name, bundle: storyboardBundleOrNil)
        }
        else {
            // Call original `storyboardWithName:bundle:` method swizzled with `swinject_storyboardWithName:bundle:`
            // if SwinjectStoryboard is tried to be instantiated.
            return self.swinject_storyboardWithName(name, bundle: storyboardBundleOrNil)
        }
    }
}
