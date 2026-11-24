import Foundation

/// A string of the interface, from the String Catalog in this package (zh and en). The wording comes
/// from the spec's design/terms.md; see scripts/strings.py.
public func L(_ key: String, _ args: CVarArg...) -> String {
    let format = Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    return args.isEmpty ? format : String(format: format, locale: .current, arguments: args)
}
