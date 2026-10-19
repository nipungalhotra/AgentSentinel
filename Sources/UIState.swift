import SwiftUI

/// A resilient SwiftUI property wrapper that wraps `SwiftUI.State` directly,
/// bypassing the missing `SwiftUIMacros` compiler plugin in standalone Command Line Tools.
@propertyWrapper
public struct UIState<Value>: DynamicProperty {
    private var _state: SwiftUI.State<Value>

    public init(wrappedValue: Value) {
        self._state = SwiftUI.State(initialValue: wrappedValue)
    }

    public init(initialValue: Value) {
        self._state = SwiftUI.State(initialValue: initialValue)
    }

    public var wrappedValue: Value {
        get { _state.wrappedValue }
        nonmutating set { _state.wrappedValue = newValue }
    }

    public var projectedValue: Binding<Value> {
        _state.projectedValue
    }
}
