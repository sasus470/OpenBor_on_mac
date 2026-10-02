import Foundation

@main
struct InterfaceLanguageTest {
    static func main() {
        for (key, translations) in UIStrings.translations {
            precondition(translations.count == InterfaceLanguage.allCases.count, "Missing language: \(key)")
            precondition(translations.allSatisfy { !$0.isEmpty }, "Empty translation: \(key)")
            let placeholders = translations.map { value in value.filter { $0 == "%" }.count }
            precondition(Set(placeholders).count == 1, "Mismatched format arguments: \(key)")
        }
        precondition(UIStrings.format("Resume game", language: .english) == "Resume game")
        precondition(UIStrings.format("Resume game", language: .italian) == "Riprendi gioco")
        precondition(UIStrings.format("Resume game", language: .spanish) == "Continuar juego")
        precondition(UIStrings.format("Resume game", language: .portuguese) == "Continuar jogo")
        for language in InterfaceLanguage.allCases {
            precondition(UIStrings.format("Shader: %@", language: language, arguments: ["CRT"]) == "Shader: CRT")
            precondition(UIStrings.format("Games available", language: language, arguments: [7]).contains("7"))
        }
        print("PASS: every interface string covers all four languages with matching format arguments.")
    }
}
