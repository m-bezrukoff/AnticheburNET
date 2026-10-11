# AnticheburNET 1.0.0 — OpenWrt 25.12

Система VPN, прокси и маршрутизации для всех устройств с OpenWrt 25.12. Поддерживаются VLESS, Hysteria 2, XHTTP и AmneziaWG 3.1, а также полное ядро Xray 26.10.10.

Комплект APK для `aarch64_cortex-a53`:

- AnticheburNET backend, LuCI и русский перевод 1.0.0.
- sing-box 1.14.1-extended-2.7.2-anticheburnet.1 с VLESS, Hysteria 2, XHTTP, uTLS и Clash API.
- Официальное полное ядро Xray 26.10.10 через локальный SOCKS-вход; версии и SHA256 архива закреплены.
- Официальные AmneziaWG Go 3.1.20260828 и tools 3.1.20260812, userspace TUN, procd и импорт параметров 3.1.

Архив `anticheburnet-filogic-25.12.tar.gz` содержит шесть APK, контрольные суммы и manifest исходников. Перед установкой выполните `sha256sum -c SHA256SUMS` внутри распакованной папки. [Инструкция установки и настройки](https://github.com/m-bezrukoff/AnticheburNET/blob/main/docs/OPENWRT-25.12.md).

Бинарники Go упакованы UPX 5.2.1. Полные GeoIP/GeoSite хранятся с gzip-сжатием и разворачиваются в RAM. Протоколы и geodata сохранены. Все шесть APK устанавливают **31 144 154 байта файлов**; консервативная оценка размещения — **32 016 602 байта**. AmneziaWG сохранён. Контроль будущих сборок ограничивает комплект 35 MB. Результаты находятся в `installed-sizes.txt`, сравнение gzip/bzip2/xz/zstd/SquashFS — в `packing-comparison.csv`. Рабочая память остаётся зависимой от нагрузки. [Подробный отчёт упаковки](https://github.com/m-bezrukoff/AnticheburNET/blob/main/docs/FLASH-BUDGET.md).

Проверено: backend/ucode, lint, 510 frontend-тестов, воспроизводимость LuCI bundle, создание APK и запуск упакованных ARM64-бинарников. Под QEMU выполнены передача HTTP через зашифрованный Hysteria 2 и SOCKS Xray с полными geodata, а также AmneziaWG 3.1 handshake и трафик между двумя изолированными сетями. Проверена настоящая IPv4/IPv6 socket mark в ядре Linux; AWG применяет конфигурацию через рабочий importer. [Журнал итогового испытания](https://github.com/m-bezrukoff/AnticheburNET/actions/runs/38092351620). APK собраны из `b0ef4c67fb8f4b29620cd0b1a07dfac0448bb7ec`.

Работа и производительность на физических устройствах не проверены. sing-box не содержит весь Xray: новые возможности Xray используются штатным отдельным ядром. Xray 26.10.10 имеет статус prerelease upstream. База sing-box extended — 1.14.1; Naive/Chromium исключён. Это набор приложений, не прошивка. APK не подписаны ключами OpenWrt; установка локальных пакетов описана в инструкции.

Исходники компонентов и лицензии: [components/README.md](https://github.com/m-bezrukoff/AnticheburNET/blob/main/components/README.md). Конфигурации Xray и AWG от ваших серверов не входят в релиз.
