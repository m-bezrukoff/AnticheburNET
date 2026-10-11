# AnticheburNET 1.0.1 — подписки Happ и маршрутизация

HTTP(S)-подписки Happ теперь импортируют правила вместе с узлами. AnticheburNET применяет
порядок block/proxy/direct, глобальный выход, домены и подсети, GeoIP/GeoSite,
Remote/Domestic DNS и DnsHosts. Правила привязаны к секции; обновление только правил
перегенерирует конфигурацию. DNS сохраняет соответствие реальных IP доменам для
маршрутизации IP-соединений клиентов, sniffing охватывает IPv4/IPv6.

Hysteria 2 принимает ECHConfigList из ссылки подписки. Для REALITY сохраняется явно
выбранный uTLS fingerprint; при его отсутствии используется chrome с ML-KEM.

AmneziaWG 3.1 можно импортировать из HTTP(S)-подписки: `.conf`, sing-box extended
endpoint/outbound или Mihomo JSON/YAML с `amnezia-wg-option`. Несколько профилей
требуют выбора точного имени. Конфигурация и маршрутизация Happ сохраняются вместе;
ошибка загрузки или проверки не заменяет рабочий файл. После обновления AWG примените
настройки AnticheburNET или перезапустите его, чтобы обновить маршрутизацию.

Система для всех устройств с OpenWrt 25.12. Поддерживаемые протоколы: VLESS, Hysteria 2, XHTTP и AmneziaWG 3.1. Поддерживается полное ядро Xray 26.10.10. Готовый комплект этого релиза: OpenWrt 25.12 / mediatek/filogic / aarch64_cortex-a53:
AnticheburNET и LuCI 1.0.1, sing-box extended 1.14.1 / 2.7.2, полное ядро Xray 26.10.10,
официальные AmneziaWG Go и tools 3.1. AmneziaWG APK обновлён до r2.
Шесть APK и контрольные суммы находятся в архиве `anticheburnet-filogic-25.12.tar.gz`.
[Установка и настройка](https://github.com/m-bezrukoff/AnticheburNET/blob/main/docs/OPENWRT-25.12.md).

Все шесть APK устанавливают **31 183 666 байт файлов**; консервативная оценка размещения —
**32 080 690 байт**. Точные данные и сравнение сжатия включены в архив.

Проверено: 81 backend-проверка, 510 frontend-тестов, ucode, ShellCheck, воспроизводимость
LuCI bundle и запуск точных упакованных ARM64-бинарников под QEMU. HTTP-соединения
подтвердили Direct/Proxy/Block, приоритет пересекающихся доменных правил, GeoIP после DNS,
DnsHosts и маршрутизацию IP-соединений по сохранённому домену. Проверен Hysteria 2 с ECH,
полные GeoIP/GeoSite DAT, SOCKS Xray и импорт AWG по HTTP с реальным шифрованным туннелем.
Полная сгенерированная конфигурация проходит `sing-box check`; передача данных в Happ-тесте
выполняется через mixed proxy и DNS-входы, поскольку QEMU user mode не поддерживает TPROXY.
[Журнал сборки и протокольного испытания](https://github.com/m-bezrukoff/AnticheburNET/actions/runs/38126196363).
APK собраны из `94d9f9d0d04b4443fdb9c0d4104feeb36218a417`.

Новые provider DAT и преобразованные rule-set хранятся только в RAM. Бинарники остаются
упакованными UPX, полные встроенные базы Xray — в gzip. AmneziaWG сохранён в комплекте.
[Отчёт упаковки](https://github.com/m-bezrukoff/AnticheburNET/blob/main/docs/FLASH-BUDGET.md).

Ограничения: профили с `FakeDNS=true` отклоняются с явной ошибкой; `happ://crypt...`
требует исходной HTTP(S)-ссылки провайдера. Android Per-App-Proxy не применим к роутеру.
Если клиент обходит DNS роутера, правила по доменам зависят от sniffing протокола.
В проверенной пользовательской подписке пока нет AWG: его импорт и туннель проверены
на контролируемых профилях. Работа fw4/TPROXY и производительность на физических устройствах не испытаны.
Это набор приложений, не firmware; APK устанавливаются по инструкции как локальные пакеты.
sing-box использует собственный extended, полное ядро Xray работает отдельно.
