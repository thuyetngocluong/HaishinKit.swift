import Foundation

/// Atomic<T> class
/// - seealso: https://www.objc.io/blog/2018/12/18/atomic-variables/
///
@propertyWrapper
public struct Atomic<A> {
    private let queue = DispatchQueue(label: "com.haishinkit.HaishinKit.Atomic", attributes: .concurrent)
    private var _wrappedValue: A
    
    init(_ wrappedValue: A) {
        self._wrappedValue = wrappedValue
    }
    
    public var value: A {
        queue.sync { self._wrappedValue }
    }
    
    public var wrappedValue: A {
        get {
            queue.sync { self._wrappedValue }
        }
        set {
            queue.sync(flags: .barrier) {
                _wrappedValue = newValue
            }
        }
    }
    /// Setter for the value.
    public mutating func mutate(_ transform: (inout A) -> Void) {
        queue.sync(flags: .barrier) {
            transform(&self._wrappedValue)
        }
    }
}
