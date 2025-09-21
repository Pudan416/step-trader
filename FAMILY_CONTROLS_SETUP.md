# 🛡️ Настройка Family Controls для Steps Trader

Теперь когда у вас есть платный Apple Developer Program, нужно настроить Xcode:

## 📋 Шаги настройки

### 1. Обновите Team в Xcode
1. Откройте **Steps4.xcodeproj** 
2. Выберите **Steps4** target
3. В **Signing & Capabilities**:
   - Установите **Team**: ваш платный Apple Developer аккаунт
   - Убедитесь что **Bundle Identifier** уникальный

### 2. Добавьте Capabilities
В **Signing & Capabilities** нажмите **+ Capability**:

✅ **HealthKit** (уже добавлен)
✅ **Family Controls** 
✅ **Device Activity**

### 3. Обновите Provisioning Profile
1. В **Signing & Capabilities** выберите **Automatically manage signing**
2. Xcode автоматически создаст профиль с нужными capabilities

### 4. Проверьте entitlements
Файл `Steps4.entitlements` должен содержать:
```xml
<key>com.apple.developer.healthkit</key>
<true/>
<key>com.apple.developer.family-controls</key>
<true/>
<key>com.apple.developer.deviceactivity</key>
<true/>
```

## 🎯 Новый функционал

### Family Activity Picker
- Кнопка **"📱 Выбрать приложения (Family Controls)"**
- Откроет системный picker для выбора реальных приложений

### Реальная блокировка
- Кнопка **"🛡️ Включить блокировку"** 
- Использует Device Activity для мониторинга времени
- Автоматически блокирует приложения через ManagedSettings

### Как это работает:
1. **Выберите приложения** через Family Activity Picker
2. **Включите блокировку** - Device Activity начнет отслеживать время
3. **При превышении лимита** - приложения автоматически заблокируются
4. **Снятие блокировки** - только через Steps Trader

## 🔧 Тестирование

1. Запустите на **реальном устройстве** (не симулятор)
2. Разрешите **Family Controls** при первом запуске
3. Выберите тестовые приложения (например, Safari)
4. Установите небольшой лимит (1-2 минуты)
5. Включите блокировку и используйте выбранное приложение
6. Через лимит времени приложение должно заблокироваться

## ⚠️ Важные особенности

- **Device Activity Extensions** работают в фоне независимо от приложения
- **Блокировка сохраняется** даже если закрыть Steps Trader
- **Сброс блокировки** происходит автоматически в полночь
- **Family Controls** требует явного разрешения пользователя

## 🚀 Готово!

После настройки capabilities у вас будет полноценная система блокировки приложений в Steps Trader! 🎉
