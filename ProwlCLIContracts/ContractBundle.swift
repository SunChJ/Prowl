import Foundation

public enum ProwlCLIContractBundle {
  public static let schemaData: Data = {
    guard let url = Bundle.module.url(forResource: "cli-output-schema", withExtension: "json") else {
      preconditionFailure("Missing Prowl CLI JSON Schema bundle resource.")
    }
    do {
      return try Data(contentsOf: url)
    } catch {
      preconditionFailure("Failed to load Prowl CLI JSON Schema bundle: \(error)")
    }
  }()
}
