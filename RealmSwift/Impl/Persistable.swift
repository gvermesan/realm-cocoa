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

import Realm
import Realm.Private

// An opaque identifier for each property on a class. Happens to currently be
// the property's index in the object schema, but that's not something that any
// of the Swift code should rely on. In the future it may make sense to change
// this to the ColKey.
public typealias PropertyKey = UInt16

// A tag protocol used in schema discovery to find @Persisted properties
internal protocol DiscoverablePersistedProperty: _RealmSchemaDiscoverable {}

// A protocol marking types which can be used inside an `Optional<T>` in a
// Realm collection or a `@Persisted` property.
public protocol _PersistableInOptional: RealmCollectionValue where PersistedType: _PersistableInOptional {
    // Read an optional value of this type from the target object
    static func _rlmGetPropertyOptional(_ obj: ObjectBase, _ key: PropertyKey) -> Self?
}

/**
 A type which can be stored by the @Persisted property wrapper.

 As with all underscore-prefixed names, this protocol is not part of the public
 API and may change without warning. To make custom types conform to this
 protocol, conform to CustomPersistable or FailableCustomPersistable rather than
 conforming to this directly.

 Our protocol heirarchy for types which we can store has four levels, from most
 restrictive to least restrictive:

 1. `_PersistableInOptional`: Anything which can appear inside an `Optional<T>`:
    the primitive types (int, string, etc.), Object and EmbeddedObject subclasses,
    and custom mapped types.
 2. `RealmCollectionValue`: Anything which can appear inside a Realm collection.
    The above types, plus the Optional variants of them.
 3. `_Persistable`: The types which can appear on managed property. The above
    types, plus any of those types in a List, MutableSet, or Map.
 4. `_ObjcBridgeable`: Everything which we can convert to/from Any. The above
    types, plus a few assorted things like NSNumber that we never store but
    can be used as the result of aggregate operations.
*/
public protocol _Persistable: _RealmSchemaDiscoverable, _ObjcBridgeable {
    // Read a value of this type from the target object
    static func _rlmGetProperty(_ obj: ObjectBase, _ key: PropertyKey) -> Self
    // Set a value of this type on the target object
    static func _rlmSetProperty(_ obj: ObjectBase, _ key: PropertyKey, _ value: Self)
    // Set the swiftAccessor for this type if the default PersistedPropertyAccessor
    // is not suitable.
    static func _rlmSetAccessor(_ prop: RLMProperty)
    // Do the values of this type need to be cached on the Persisted?
    static var _rlmRequiresCaching: Bool { get }
    // Get the zero/empty/nil value for this type. Used to supply a default
    // when the user does not declare one in their model. When `forceDefaultInitialization`
    // is true we *must* return a non-nil, default instance of `Self`. The latter is
    // used in conjunction with key path string tracing.
    static func _rlmDefaultValue(_ forceDefaultInitialization: Bool) -> Self
    // If we are in key path tracing mode, instantiate an empty object and forward
    // the lastAccessedNames array.
    static func _rlmKeyPathRecorder(with lastAccessedNames: NSMutableArray) -> Self
    // The type which is actually stored in the Realm. This is Self for types
    // we support directly, but may be a different type for enums and mapped types.
    associatedtype PersistedType: _Persistable & _RealmSchemaDiscoverable
}

extension _Persistable {
    // Only the collections need caching, so define a default for the rest of the types
    public static var _rlmRequiresCaching: Bool {
        false
    }
}

extension _RealmSchemaDiscoverable where Self: _Persistable {
    public static func _rlmKeyPathRecorder(with lastAccessedNames: NSMutableArray) -> Self {
        let value = Self._rlmDefaultValue(true)

        if let value = value as? ObjectBase {
            value.lastAccessedNames = lastAccessedNames
            value.prepareForRecording()
            return value as! Self
        }

        if var value = value as? PropertyNameConvertible {
            value.lastAccessedNames = lastAccessedNames
            return value as! Self
        }
        return value
    }
}

extension _PersistableInOptional {
    public static func _rlmSetAccessor(_ prop: RLMProperty) {
        if prop.optional {
            prop.swiftAccessor = PersistedPropertyAccessor<Optional<Self>>.self
        } else {
            prop.swiftAccessor = PersistedPropertyAccessor<Self>.self
        }
    }
}

// Default definition of _rlmDefaultValue used by everything exception for
// Optional, which requires doing Optional<T>.none rather than Optional<T>().
public protocol _DefaultConstructible {
    init()
}
extension _Persistable where Self: _DefaultConstructible {
    public static func _rlmDefaultValue(_ forceDefaultInitialization: Bool) -> Self {
        .init()
    }
}
