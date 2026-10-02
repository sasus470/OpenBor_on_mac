import Foundation

enum OpenBORLaunchArgumentBuilder {
    static func makeArguments(from configuration: EngineLaunchConfiguration) -> [String] {
        var arguments: [String] = []

        if let pakURL = configuration.pakURL {
            arguments.append(pakURL.path)
        }

        arguments.append(contentsOf: configuration.extraArguments)
        return arguments
    }
}
