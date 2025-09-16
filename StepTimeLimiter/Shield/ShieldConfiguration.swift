import ManagedSettingsUI

struct ShieldConfigDataSource: ShieldConfigurationDataSource {
    var shieldConfiguration: ManagedSettingsUI.ShieldConfiguration {
        ManagedSettingsUI.ShieldConfiguration(
            title: .text("Доступ на сегодня исчерпан"),
            subtitle: .text("Заработайте время шагами :)"),
            primaryButtonLabel: .text("Ок")
        )
    }
}
