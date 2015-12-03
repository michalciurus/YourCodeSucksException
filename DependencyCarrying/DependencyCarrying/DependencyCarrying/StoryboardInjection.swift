//
//  StoryboardInjection.swift
//  DependencyCarrying
//
//  Created by Michal Ciurus on 03/12/15.
//  Copyright © 2015 Ciurus. All rights reserved.
//

import Swinject

extension SwinjectStoryboard {
    class func setup() {
        
        defaultContainer.register(DatabaseContext.self) { _ in DatabaseContext() }.inObjectScope(.Container)
        defaultContainer.register(NetworkingContext.self) { _ in NetworkingContext() }.inObjectScope(.Container)
        defaultContainer.register(LocalConfigContext.self) { _ in LocalConfigContext() }.inObjectScope(.Container)
        defaultContainer.register(ViewModelContext.self){ _ in ViewModelContext() }.inObjectScope(.Container)
        
        defaultContainer.registerForStoryboard(ViewController.self) { r, c in
            c.database = r.resolve(DatabaseContext.self)
            c.networking = r.resolve(NetworkingContext.self)
            c.config = r.resolve(LocalConfigContext.self)
            c.viewModel = r.resolve(ViewModelContext.self)
        }

        defaultContainer.registerForStoryboard(SecondViewController.self) { r, c in
            c.database = r.resolve(DatabaseContext.self)
            c.networking = r.resolve(NetworkingContext.self)
            c.viewModel = r.resolve(ViewModelContext.self)
        }

    }
    
}

    