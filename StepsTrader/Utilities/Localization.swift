import Foundation

func currentLanguage() -> String {
    UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
}

func loc(_ en: String, _ ru: String) -> String {
    currentLanguage() == "ru" ? ru : en
}

func loc(_ lang: String, _ en: String, _ ru: String) -> String {
    lang == "ru" ? ru : en
}
