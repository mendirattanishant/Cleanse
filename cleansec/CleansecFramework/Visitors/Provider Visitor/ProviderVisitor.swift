//
//  ProviderVisitor.swift
//  Cleansec
//
//  Created by Sebastian Edward Shanus on 5/12/20.
//  Copyright © 2020 Square. All rights reserved.
//

import Foundation
import SwiftAstParser

enum ProviderResult {
    case provider(StandardProvider)
    case danglingProviderBuilder(DanglingProviderBuilder)
    case referenceBuilder(ReferenceProviderBuilder)
}

/**
 Parses an individual binding to discern its provider type, dependencies, and any decorated types (i.e Tagged, Scoped, Factory).
 */
struct ProviderVisitor: SyntaxVisitor {
    private var binding: BindingType = .unknown
    private var dependencies: [String] = []
    private var bindingTypeBuilder = BaseBindingTypeBuilder.instance
    
    let type: String
    
    init(type: String) {
        self.type = type
    }
    
    // We just want to visit the first declrefExpr to discern the API used.
    mutating func visit(node: DeclrefExpr) {
        guard binding == .unknown else {
            return
        }
        
        guard let api = BindingAPI.allCases.first(where: { (bindingApi) -> Bool in
            node.raw.contains(bindingApi.rawValue)
        }) else {
            return
        }
        
        switch api {
        case .toValue:
            binding = .provider
        case .toFactory, .toFactoryPropertyInjector, .toFactoryAssistedInjection:
            dependencies = node.raw.allCaptures(#"substitution\sP_[\d]+\s->\s(\S*)\)"#)
            // Sanitizes trailing ')' character from regex pattern. Worth fixing the regex.
            if var last = dependencies.popLast() {
                last.removeLast()
                dependencies.append(last)
            }
            binding = .provider
        case .configure, .configurePropertyInjector:
            binding = .reference
        }
    }
    
    mutating func visit(node: CallExpr) {
        if let receiptType = node.type.firstCapture("BindingReceipt<(.*)>") {
            if let loc = node.raw.firstCapture(#"location=(.*)\srange"#) {
                bindingTypeBuilder = bindingTypeBuilder.setDebugData(.location(loc))
            }
            if let danglingProviderType = receiptType.firstCapture(#"^ReceiptBinder<(.*)>"#) {
                bindingTypeBuilder = bindingTypeBuilder.setType(type: danglingProviderType)
            } else if let danglingPropertyInjectorType = receiptType.firstCapture(#"PropertyInjectionReceiptBinder<(.*)>\.Element>"#) {
                bindingTypeBuilder = bindingTypeBuilder.setType(type: "PropertyInjector<\(danglingPropertyInjectorType)>")
            } else if receiptType.matches(#"^PropertyInjector<.*>"#) {
                bindingTypeBuilder = bindingTypeBuilder.setType(type: receiptType)
            }
            return
        }
        
        guard let firstType = node.type.allCaptures(#"(\w+)(?=<)"#).first,
            let baseBindingType = BaseBindingType(rawValue: firstType) else {
            return
        }
        switch baseBindingType {
        case .provider:
            bindingTypeBuilder = bindingTypeBuilder.setBaseGraphBinding()
            if let type = node.type.firstCapture(#"BaseBindingBuilder<(.*),\sBinder"#) {
                bindingTypeBuilder = bindingTypeBuilder.setType(type: type)
            } else {
                print("Found base binding but couldnt parse type")
            }
        case .propertyInjector:
            bindingTypeBuilder = bindingTypeBuilder.setBaseGraphBinding()
            if let type = node.type.firstCapture(#"PropertyInjectorBindingBuilder<.*,\s(.*)(?>)>"#) {
                bindingTypeBuilder = bindingTypeBuilder.setType(type: "PropertyInjector<\(type)>")
            } else {
                print("Found base binding but couldnt parse type")
            }
        case .assistedInjectionProvider:
            bindingTypeBuilder = bindingTypeBuilder.setBaseGraphBinding()
            if let type = node.type.firstCapture(#"AssistedInjectionSeedDecorator<.*,\s(.*)(?>)>"#) {
                bindingTypeBuilder = bindingTypeBuilder.setType(type: "Factory<\(type)>")
            } else {
                print("Found base binding but couldnt parse type")
            }
        case .singularCollectionProvider:
            bindingTypeBuilder = bindingTypeBuilder.setCollectionBinding(singular: true)
        case .collectionProvider:
            bindingTypeBuilder = bindingTypeBuilder.setCollectionBinding(singular: false)
        case .taggedProvider:
            if let tag = node.type.allCaptures(#"(\w+(?:\.\w+)*)(?=>)"#).last {
                bindingTypeBuilder = bindingTypeBuilder.setTaggedBinding(tag: tag)
            } else {
                print("Found tagged provider, but failed to parse Tag")
            }
        case .scopedProvider:
            if let scope = node.type.firstCapture(#"ScopedBindingDecorator.*\sBinder<(.*)>(?=\.Scope)"#) {
                bindingTypeBuilder = bindingTypeBuilder.setScopedBinding(scope: scope)
            } else {
                print("Found scoped provider, but failed to parse scope")
            }
        }
    }
    
    func finalize() -> ProviderResult? {
        bindingTypeBuilder.build(bindingType: binding, dependencies: dependencies)
    }
}


fileprivate struct BaseBindingTypeBuilder {
    let type: String?
    let graphBinding: Bool
    let collectionBinding: Bool
    let singularCollectionBinding: Bool
    let taggedBinding: String?
    let scopedBinding: String?
    let debugData: DebugData
    
    static var instance: BaseBindingTypeBuilder {
        return BaseBindingTypeBuilder(
            type: nil,
            graphBinding: false,
            collectionBinding: false,
            singularCollectionBinding: false,
            taggedBinding: nil,
            scopedBinding: nil,
            debugData: .empty
        )
    }
    
    func setDebugData(_ data: DebugData) -> BaseBindingTypeBuilder {
        return BaseBindingTypeBuilder(
            type: type,
            graphBinding: graphBinding,
            collectionBinding: collectionBinding,
            singularCollectionBinding: singularCollectionBinding,
            taggedBinding: taggedBinding,
            scopedBinding: scopedBinding,
            debugData: data
        )
    }
    
    func setType(type: String) -> BaseBindingTypeBuilder {
       return BaseBindingTypeBuilder(
            type: type,
            graphBinding: graphBinding,
            collectionBinding: collectionBinding,
            singularCollectionBinding: singularCollectionBinding,
            taggedBinding: taggedBinding,
            scopedBinding: scopedBinding,
            debugData: debugData
        )
    }
    
    func setBaseGraphBinding() -> BaseBindingTypeBuilder {
        return BaseBindingTypeBuilder(
            type: type,
            graphBinding: true,
            collectionBinding: collectionBinding,
            singularCollectionBinding: singularCollectionBinding,
            taggedBinding: taggedBinding,
            scopedBinding: scopedBinding,
            debugData: debugData
        )
    }
    
    func setCollectionBinding(singular: Bool) -> BaseBindingTypeBuilder {
        if singular {
            return BaseBindingTypeBuilder(
                type: type,
                graphBinding: graphBinding,
                collectionBinding: collectionBinding,
                singularCollectionBinding: true,
                taggedBinding: taggedBinding,
                scopedBinding: scopedBinding,
                debugData: debugData
            )
        } else {
            return BaseBindingTypeBuilder(
                type: type,
                graphBinding: graphBinding,
                collectionBinding: true,
                singularCollectionBinding: singularCollectionBinding,
                taggedBinding: taggedBinding,
                scopedBinding: scopedBinding,
                debugData: debugData
            )
        }
    }
    
    func setTaggedBinding(tag: String) -> BaseBindingTypeBuilder {
        return BaseBindingTypeBuilder(
            type: type,
            graphBinding: graphBinding,
            collectionBinding: collectionBinding,
            singularCollectionBinding: singularCollectionBinding,
            taggedBinding: tag,
            scopedBinding: scopedBinding,
            debugData: debugData
        )
    }
    
    func setScopedBinding(scope: String) -> BaseBindingTypeBuilder {
        return BaseBindingTypeBuilder(
            type: type,
            graphBinding: graphBinding,
            collectionBinding: collectionBinding,
            singularCollectionBinding: singularCollectionBinding,
            taggedBinding: taggedBinding,
            scopedBinding: scope,
            debugData: debugData
        )
    }
    
    func build(bindingType: ProviderVisitor.BindingType, dependencies: [String]) -> ProviderResult? {
        guard let type = type else {
            return nil
        }
        var collectionType: String? = nil
        if collectionBinding {
            if type.matches(#"[.*]"#) {
                collectionType = type
            } else {
                collectionType = "[\(type)]"
            }
        } else if singularCollectionBinding {
            collectionType = "[\(type)]"
        }
        switch bindingType {
        case .provider:
            // If bound into graph, full standard. Otherwise it's a dangling reference.
            if graphBinding {
                return .provider(StandardProvider(
                    type: type,
                    dependencies: dependencies,
                    tag: taggedBinding,
                    scoped: scopedBinding,
                    collectionType: collectionType,
                    debugData: debugData
                    )
                )
            } else {
                return .danglingProviderBuilder(DanglingProviderBuilder(
                    type: type,
                    dependencies: dependencies,
                    reference: nil,
                    debugData: debugData
                    )
                )
            }
        case .reference:
            return .referenceBuilder(ReferenceProviderBuilder(
                type: type,
                tag: taggedBinding,
                scope: scopedBinding,
                collectionType: collectionType,
                dependencies: nil,
                reference: nil,
                debugData: debugData
                )
            )
        case .unknown:
            return nil
        }
    }
}

extension ProviderVisitor {
    fileprivate enum Binding {
        case provider
        case taggedProvider(tag: String)
        case scopedProvider(scope: String)
        case collectionProvider(isSingular: Bool)
    }
    
    fileprivate enum BindingType {
        case unknown
        case reference
        case provider
    }
    
    fileprivate enum BaseBindingType: String, CaseIterable {
        case provider = "BaseBindingBuilder"
        case taggedProvider = "TaggedBindingBuilderDecorator"
        case scopedProvider = "ScopedBindingDecorator"
        case propertyInjector = "PropertyInjectorBindingBuilder"
        case assistedInjectionProvider = "AssistedInjectionSeedDecorator"
        case singularCollectionProvider = "SingularCollectionBindingBuilderDecorator"
        case collectionProvider = "CollectionBindingBuilderDecorator"
    }
    
    fileprivate enum BindingAPI: String, CaseIterable {
        case toValue = "decl=Cleanse.(file).BindToable extension.to(value:file:line:function:)"
        case toFactory = "decl=Cleanse.(file).BindToable extension.to(file:line:function:factory:)"
        case configure = "decl=Cleanse.(file).BindToable extension.configured(with:)"
        case toFactoryPropertyInjector = "decl=Cleanse.(file).PropertyInjectorBindingBuilderProtocol extension.to(file:line:function:injector:)"
        case configurePropertyInjector = "decl=Cleanse.(file).BindToable extension.propertyInjector(configuredWith:)"
        case toFactoryAssistedInjection = "decl=Cleanse.(file).AssistedInjectionBuilder extension.to(file:line:function:factory:)"
    }
}
