# Forkop Plus 1.0.0 — Redmi AX6000 / Filogic / OpenWrt 25.12

Основа: 20 проверенных PR из `ushan0v/forkop`. [Аудит всех 23 PR](https://github.com/m-bezrukoff/forkop-plus/blob/main/docs/PR-AUDIT.md); #121, #130 и #135 не включены.

Комплект APK для `aarch64_cortex-a53`:

- Forkop backend, LuCI и русский перевод 1.0.0.
- sing-box 1.14.1-extended-2.7.2-forkop.1 с Hysteria 2, XHTTP, uTLS, WireGuard и Clash API.
- Официальное полное ядро Xray 26.10.10 через локальный SOCKS-вход; версии и SHA256 архива закреплены.
- Официальные AmneziaWG Go 3.1.20260828 и tools 3.1.20260812, userspace TUN, procd и импорт параметров 3.1.

Архив `forkop-plus-filogic-25.12.tar.gz` содержит шесть APK, контрольные суммы и manifest исходников. Перед установкой выполните `sha256sum -c SHA256SUMS` внутри распакованной папки. [Инструкция установки и настройки](https://github.com/m-bezrukoff/forkop-plus/blob/main/docs/REDMI-AX6000.md).

Бинарники Go упакованы UPX 5.2.1 для 128 MB NAND AX6000. Протоколы и geodata сохранены; точный установленный размер указан в `installed-sizes.txt`. На диске требуется меньше места, рабочая память остаётся зависимой от нагрузки.

Проверено: backend/ucode, lint, 510 frontend-тестов, воспроизводимость LuCI bundle, создание APK и запуск ARM64-бинарников. Под QEMU выполнены передача HTTP через зашифрованный Hysteria 2 и SOCKS Xray, а также AmneziaWG 3.1 handshake и трафик между двумя изолированными сетями. [Журнал протокольного испытания](https://github.com/m-bezrukoff/forkop-plus/actions/runs/38089960038).

Физический Redmi AX6000 и производительность на нём не проверены. sing-box не содержит весь Xray: новые возможности Xray используются штатным отдельным ядром. Xray 26.10.10 имеет статус prerelease upstream. База sing-box extended — 1.14.1; Naive/Chromium исключён. Это набор приложений, не прошивка. APK не подписаны ключами OpenWrt; установка локальных пакетов описана в инструкции.

Исходники компонентов и лицензии: [components/README.md](https://github.com/m-bezrukoff/forkop-plus/blob/main/components/README.md). Конфигурации Xray и AWG от ваших серверов не входят в релиз.
