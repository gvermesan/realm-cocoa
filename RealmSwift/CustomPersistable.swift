////////////////////////////////////////////////////////////////////////////
//
// Copyright 2021 Realm Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
////////////////////////////////////////////////////////////////////////////

import Foundation
import Realm

// MARK: Public API

public protocol CustomPersistable: _CustomPersistable {
    // Construct an instance of the user's type from the persisted type
    init(persistedValue: PersistedType)
    // Construct an instance of the persisted type from the user's type
    var persistableValue: PersistedType { get }
}

public protocol FailableCustomPersistable: _CustomPersistable {
    // Construct an instance of the user's type from the persisted type,
    // returning nil if the conversion is not possible
    init?(persistedValue: PersistedType)
    // Construct an instance of the persisted type from the user's type
    var persistableValue: PersistedType { get }
}

// MARK: - Implementation

public protocol _CustomPersistable: _PersistableInOptional where PersistedType: _DefaultConstructible {}

extension _CustomPersistable { // _RealmSchemaDiscoverable
    public static var _rlmType: PropertyType { PersistedType._rlmType }
    public static var _rlmOptional: Bool { PersistedType._rlmOptional }
    public static var _rlmRequireObjc: Bool { false }
    public func _rlmPopulateProperty(_ prop: RLMProperty) { }
    public static func _rlmPopulateProperty(_ prop: RLMProperty) {
        prop.customMappingIsOptional = prop.optional
        if prop.type == .object && (!prop.collection || prop.dictionary) {
            prop.optional = true
        }
        PersistedType._rlmPopulateProperty(prop)
    }
}

extension CustomPersistable { // _Persistable
    public static func _rlmGetProperty(_ obj: ObjectBase, _ key: PropertyKey) -> Self {
        return Self(persistedValue: PersistedType._rlmGetProperty(obj, key))
    }
    public static func _rlmGetPropertyOptional(_ obj: ObjectBase, _ key: PropertyKey) -> Self? {
        return PersistedType._rlmGetPropertyOptional(obj, key).flatMap(Self.init)
    }
    public static func _rlmSetProperty(_ obj: ObjectBase, _ key: PropertyKey, _ value: Self) {
        PersistedType._rlmSetProperty(obj, key, value.persistableValue)
    }
    public static func _rlmSetAccessor(_ prop: RLMProperty) {
        if prop.customMappingIsOptional {
            prop.swiftAccessor = BridgedPersistedPropertyAccessor<Optional<Self>>.self
        } else if prop.optional {
            prop.swiftAccessor = CustomPersistablePropertyAccessor<Self>.self
        } else {
            prop.swiftAccessor = BridgedPersistedPropertyAccessor<Self>.self
        }
    }
    public static func _rlmDefaultValue(_ forceDefaultInitialization: Bool) -> Self {
        Self(persistedValue: PersistedType())
    }
}

extension FailableCustomPersistable { // _Persistable
    public static func _rlmGetProperty(_ obj: ObjectBase, _ key: PropertyKey) -> Self {
        let persistedValue = PersistedType._rlmGetProperty(obj, key)
        if let value = Self(persistedValue: persistedValue) {
            return value
        }
        throwRealmException("Failed to convert persisted value '\(persistedValue)' to type '\(Self.self)' in a non-optional context.")
    }
    public static func _rlmGetPropertyOptional(_ obj: ObjectBase, _ key: PropertyKey) -> Self? {
        return PersistedType._rlmGetPropertyOptional(obj, key).flatMap(Self.init)
    }
    public static func _rlmSetProperty(_ obj: ObjectBase, _ key: PropertyKey, _ value: Self) {
        PersistedType._rlmSetProperty(obj, key, value.persistableValue)
    }
    public static func _rlmSetAccessor(_ prop: RLMProperty) {
        if prop.customMappingIsOptional {
            prop.swiftAccessor = BridgedPersistedPropertyAccessor<Optional<Self>>.self
        } else if prop.optional {
            prop.swiftAccessor = CustomPersistablePropertyAccessor<Self>.self
        } else {
            prop.swiftAccessor = BridgedPersistedPropertyAccessor<Self>.self
        }
    }

    public static func _rlmDefaultValue(_ forceDefaultInitialization: Bool) -> Self {
        if let value = Self(persistedValue: PersistedType()) {
            return value
        }
        throwRealmException("Failed to default construct a \(Self.self) using the default value for persisted type \(PersistedType.self). " +
                            "This conversion must either succeed, the property must be optional, or you must explicitly specify a default value for the property.")
    }
}

extension CustomPersistable { // _ObjcBridgeable
    public static func _rlmFromObjc(_ value: Any, insideOptional: Bool) -> Self? {
        if let value = PersistedType._rlmFromObjc(value) {
            return Self(persistedValue: value)
        }
        if let value = value as? Self {
            return value
        }
        if !insideOptional && value is NSNull {
            return Self._rlmDefaultValue(false)
        }
        return nil
    }
    public var _rlmObjcValue: Any { persistableValue }
}

extension FailableCustomPersistable { // _ObjcBridgeable
    public static func _rlmFromObjc(_ value: Any, insideOptional: Bool) -> Self? {
        if let value = PersistedType._rlmFromObjc(value) {
            return Self(persistedValue: value)
        }
        if let value = value as? Self {
            return value
        }
        return nil
    }
    public var _rlmObjcValue: Any { persistableValue }
}
