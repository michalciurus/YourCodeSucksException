//
//  Container.swift
//  Swinject
//
//  Created by Yoichi Tagaya on 7/23/15.
//  Copyright © 2015 Swinject Contributors. All rights reserved.
//

import Foundation

/// The `Container` class represents a dependency injection container, which stores registrations of services
/// and retrieves registered services with dependencies injected.
///
/// **Example to register:**
///
///     let container = Container()
///     container.register(A.self) { _ in B() }
///     container.register(X.self) { r in Y(a: r.resolve(A.self)!) }
///
/// **Example to retrieve:**
///
///     let x = container.resolve(X.self)!
///
/// where `A` and `X` are protocols, `B` is a type conforming `A`, and `Y` is a type conforming `X` and depending on `A`.
public final class Container {
    private var services = [ServiceKey: ServiceEntryBase]()
    private let parent: Container?
    private var resolutionPool = ResolutionPool()
    internal let lock: SpinLock // Used by SynchronizedResolver.
    
    /// Instantiates a `Container` with its parent `Container`. The parent is optional.
    ///
    /// - Parameter parent: The optional parent `Container`.
    public init(parent: Container? = nil) {
        self.parent = parent
        self.lock = parent.map { $0.lock } ?? SpinLock()
    }
    
    /// Instantiates a `Container` with its parent `Container` and a closure registering services. The parent is optional.
    ///
    /// - Parameters:
    ///     - parent:             The optional parent `Container`.
    ///     - registeringClosure: The closure registering services to the new container instance.
    public convenience init(parent: Container? = nil, @noescape registeringClosure: Container -> Void) {
        self.init(parent: parent)
        registeringClosure(self)
    }
    
    /// Removes all registrations in the container.
    public func removeAll() {
        services.removeAll()
    }
    
    /// Adds a registration for the specified service with the factory closure to specify how the service is resolved with dependencies.
    ///
    /// - Parameters:
    ///   - serviceType: The service type to register.
    ///   - name:        A registration name, which is used to differenciate from other registrations
    ///                  that have the same service and factory types.
    ///   - factory:     The closure to specify how the service type is resolved with the dependencies of the type.
    ///                  It is invoked when the `Container` needs to instantiate the instance.
    ///                  It takes a `Resolvable` to inject dependencies to the instance,
    ///                  and returns the instance of the component type for the service.
    ///
    /// - Returns: A registered `ServiceEntry` to configure more settings with method chaining.
    public func register<Service>(
        serviceType: Service.Type,
        name: String? = nil,
        factory: Resolvable -> Service) -> ServiceEntry<Service>
    {
        return registerImpl(serviceType, factory: factory, name: name)
    }

    internal func registerImpl<Service, Factory>(serviceType: Service.Type, factory: Factory, name: String?) -> ServiceEntry<Service> {
        let key = ServiceKey(factoryType: factory.dynamicType, name: name)
        let entry = ServiceEntry(serviceType: serviceType, factory: factory)
        services[key] = entry
        return entry
    }
    
    /// Returns a synchronized view of the container for thread safety.
    /// The returned container is `Resolvable` type. Call this method after you finish all service registrations to the original container.
    ///
    /// - Returns: A synchronized container as `Resolvable`.
    public func synchronize() -> Resolvable {
        return SynchronizedResolver(container: self)
    }
}

// MARK: - Extension for Storyboard
#if os(iOS) || os(OSX) || os(tvOS)
extension Container {
    /// Adds a registration of the specified view or window controller that is configured in a storyboard.
    ///
    /// - Note: Do NOT explicitly resolve the controller registered by this method.
    ///         The controller is intended to be resolved by `SwinjectStoryboard` implicitly.
    ///
    /// - Parameters:
    ///   - controllerType: The controller type to register as a service type.
    ///                     The type is `UIViewController` in iOS, `NSViewController` or `NSWindowController` in OS X.
    ///   - name:           A registration name, which is used to differenciate from other registrations
    ///                     that have the same view or window controller type.
    ///   - initCompleted:  A closure to specifiy how the dependencies of the view or window controller are injected.
    ///                     It is invoked by the `Container` when the view or window controller is instantiated by `SwinjectStoryboard`.
    public func registerForStoryboard<C: Controller>(controllerType: C.Type, name: String? = nil, initCompleted: (Resolvable, C) -> ()) {
        // Xcode 7.1 workaround for Issue #10. This workaround is not necessary with Xcode 7.
        // The actual controller type is distinguished by the dynamic type name in `nameWithActualType`.
        let nameWithActualType = String(reflecting: controllerType) + ":" + (name ?? "")
        let wrappingClosure: (Resolvable, Controller) -> () = { r, c in initCompleted(r, c as! C) }
        self.register(Controller.self, name: nameWithActualType) { (_: Resolvable, controller: Controller) in controller }
            .initCompleted(wrappingClosure)
    }
}
#endif

// MARK: - Resolvable
extension Container: Resolvable {
    /// Retrieves the instance with the specified service type.
    ///
    /// - Parameter serviceType: The service type to resolve.
    ///
    /// - Returns: The resolved service type instance, or nil if no registration for the service type is found in the `Container`.
    public func resolve<Service>(
        serviceType: Service.Type) -> Service?
    {
        return resolve(serviceType, name: nil)
    }
    
    /// Retrieves the instance with the specified service type and registration name.
    ///
    /// - Parameters:
    ///   - serviceType: The service type to resolve.
    ///   - name:        The registration name.
    ///
    /// - Returns: The resolved service type instance, or nil if no registration for the service type and name is found in the `Container`.
    public func resolve<Service>(
        serviceType: Service.Type,
        name: String?) -> Service?
    {
        typealias FactoryType = Resolvable -> Service
        return resolveImpl(name) { (factory: FactoryType) in factory(self) }
    }
    
    internal func resolveImpl<Service, Factory>(name: String?, invoker: Factory -> Service) -> Service? {
        resolutionPool.incrementDepth()
        defer { resolutionPool.decrementDepth() }
        
        var resolvedInstance: Service?
        let key = ServiceKey(factoryType: Factory.self, name: name)
        if let (entry, fromParent) = getEntry(key) as (ServiceEntry<Service>, Bool)? {
            switch (entry.objectScope) {
            case .None, .Graph:
                resolvedInstance = resolveEntry(entry, key: key, invoker: invoker)
            case .Container:
                let ownEntry: ServiceEntry<Service>
                if fromParent {
                    ownEntry = entry.copyExceptInstance()
                    services[key] = ownEntry
                }
                else {
                    ownEntry = entry
                }
                
                if ownEntry.instance == nil {
                    ownEntry.instance = resolveEntry(entry, key: key, invoker: invoker) as Any
                }
                resolvedInstance = ownEntry.instance as? Service
            case .Hierarchy:
                if entry.instance == nil {
                    entry.instance = resolveEntry(entry, key: key, invoker: invoker) as Any
                }
                resolvedInstance = entry.instance as? Service
            }
        }
        return resolvedInstance
    }
    
    private func getEntry<Service>(key: ServiceKey) -> (ServiceEntry<Service>, Bool)? {
        var fromParent = false
        var entry = services[key] as? ServiceEntry<Service>
        if entry == nil, let parent = self.parent {
            if let (parentEntry, _) = parent.getEntry(key) as (ServiceEntry<Service>, Bool)? {
                entry = parentEntry
                fromParent = true
            }
        }
        return entry.map { ($0, fromParent) }
    }
    
    private func resolveEntry<Service, Factory>(entry: ServiceEntry<Service>, key: ServiceKey, invoker: Factory -> Service) -> Service {
        let usesPool = entry.objectScope != .None
        if usesPool, let pooledInstance = resolutionPool[key] as? Service {
            return pooledInstance
        }
        
        let resolvedInstance = invoker(entry.factory as! Factory)
        if usesPool {
            if let pooledInstance = resolutionPool[key] as? Service {
                // An instance for the key might be added by the factory invocation.
                return pooledInstance
            }
            resolutionPool[key] = resolvedInstance as Any
        }
        
        if let completed = entry.initCompleted as? (Resolvable, Service) -> () {
            completed(self, resolvedInstance)
        }
        return resolvedInstance
    }
}
