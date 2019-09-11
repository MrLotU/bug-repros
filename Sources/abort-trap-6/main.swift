@propertyWrapper
public final class Wrapper {
    let name: String
    
    public var wrappedValue: String
    
    public init() {
        preconditionFailure("Commands must always have a name.")
    }
    
    // This line causes the Abort trap: 6
    public init(wrappedValue c: String, _ name: String, _ others: String...) {
    // This line works just fine
//    public init(wrappedValue c: String, _ name: String) {
        self.wrappedValue = c
        self.name = name
    }
    
    public init(_ name: String) {
        self.name = name
        self.wrappedValue = ""
    }
}


struct WrappedInside {
    
    @Wrapper("some_name")
    var value = "ABC" /// Removing `= "ABC"` here will not result in an Abort trap: 6
}
