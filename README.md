# Omarchy Dotfiles & Configuration

Персональный репозиторий настроек рабочей среды Omarchy Linux.

## Быстрое развертывание на новом устройстве

1. Склонируйте данный репозиторий:
```bash
git clone <URL_РЕПОЗИТОРИЯ> ~/omarchy-dotfiles
```

2. Запустите мастер восстановления:
```bash
~/.local/bin/omarchy-sync restore
# или из корня репозитория:
./config/omarchy-sync/omarchy-sync restore
```

3. Для восстановления секретов (SSH, Telegram, Keyring, Wi-Fi):
Скопируйте `secrets-bundle.tar.gz` в домашнюю директорию и выберите пункт `Секреты и сессии` в мастере восстановления.
