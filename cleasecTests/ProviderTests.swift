//
//  ProviderTests.swift
//  cleasecTests
//
//  Created by Sebastian Edward Shanus on 4/22/20.
//  Copyright © 2020 Square, Inc. All rights reserved.
//

import Foundation
import swift_ast_parser
@testable import cleasec
import XCTest


class ProviderTests: XCTestCase {
    var configureVisitor = ConfigureVisitor()
    
    func testDanglingProviders() {
        let node = NodeSyntaxParser.parse(text: ProviderFixtures.danglingProviderFixtures).first!
        configureVisitor.walk(node)
        XCTAssertEqual(configureVisitor.danglingProviders.count, 2)
    }
    
    func testDanglingAndReferenceConnected() {
        let node = NodeSyntaxParser.parse(text: ProviderFixtures.danglingAndReferenceProvidersFixture).first!
        configureVisitor.walk(node)
        XCTAssertEqual(configureVisitor.providers.count, 0)
        XCTAssertEqual(configureVisitor.danglingProviders.count, 1)
        XCTAssertEqual(configureVisitor.referenceProviders.count, 1)
        XCTAssertEqual(configureVisitor.referenceProviders.first!.reference, configureVisitor.referenceProviders.first!.reference)
    }
    
    func testPropertyInjectorBinding() {
        let node = NodeSyntaxParser.parse(text: ProviderFixtures.propertyInjectionBindingFixture).first!
        configureVisitor.walk(node)
        XCTAssertEqual(configureVisitor.providers.count, 1)
        XCTAssertEqual(configureVisitor.providers.first!.type, "PropertyInjector<A>")
        XCTAssertEqual(configureVisitor.providers.first!.dependencies, ["Int"])
    }
    
    func testPropertyInjectorRoot() {
        let node = NodeSyntaxParser.parse(text: ProviderFixtures.rootPropertyInjectorProvider).first!
        configureVisitor.walk(node)
        XCTAssertEqual(configureVisitor.danglingProviders.count, 1)
        XCTAssertEqual(configureVisitor.referenceProviders.count, 1)
        XCTAssertEqual(configureVisitor.providers.count, 0)
        XCTAssertEqual(configureVisitor.referenceProviders.first!.reference, configureVisitor.referenceProviders.first!.reference)
    }
    
    func testAssistedFactoryProvider() {
        let node = NodeSyntaxParser.parse(text: ProviderFixtures.assistedFactoryProviderFixture).first!
        configureVisitor.walk(node)
        XCTAssertEqual(configureVisitor.providers.count, 1)
        XCTAssertEqual(configureVisitor.providers.first!, StandardProvider(type: "Factory<AssistedSeed>", dependencies: ["String"], tag: nil, scoped: nil))
    }
    
    func testTaggedProviderDependency() {
        let node = NodeSyntaxParser.parse(text: ProviderFixtures.taggedProviderDependencyFixture).first!
        configureVisitor.walk(node)
        XCTAssertEqual(configureVisitor.providers.count, 1)
        XCTAssertEqual(configureVisitor.providers.first!.dependencies, ["TaggedProvider<MyTag>"])
    }
}
