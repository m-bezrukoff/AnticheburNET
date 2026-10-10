# Redmi AX6000: установка Forkop Plus

Цель: Xiaomi Redmi Router AX6000, OpenWrt **25.12**, target **mediatek/filogic**, arch **aarch64_cortex-a53**. Пакеты приложений собраны с SDK 25.12.3; модули `kmod-tun` и nft устанавливаются из feeds вашей прошивки и должны соответствовать её ядру. IPK из общего builder предназначены для старых OpenWrt и для этой цели не используются.

Это набор приложений, не образ firmware. CI проверяет исходники, создание APK и работу точных ARM64-бинарников под QEMU. Физический AX6000, работа fw4/TPROXY на нём и скорость VPN пока не испытаны. Xray 26.10.10 — официальный prerelease; версия закреплена по запросу.

У AX6000 [128 MB NAND и 512 MB RAM](https://openwrt.org/toh/hwdata/xiaomi/xiaomi_redmi_ax6000). Лимит проекта — **40 000 000 байт установленных файлов на flash**. Три Go-бинарника упакованы UPX 5.2.1; полные GeoIP/GeoSite сохраняются в gzip-архиве и проверяются/распаковываются только в RAM (`/var/run/forkop-xray/assets`). Сборка считает файлы всех шести APK и их размещение в блоках 4 KiB; при размере больше 35 MB останавливается, оставляя 5 MB для базы пакетов, конфигурации и накладных расходов. Точные размеры находятся в `installed-sizes.txt`, сравнение способов сжатия — в `packing-comparison.csv` релиза. Рабочая RAM процессов и распакованных баз не уменьшается из-за сжатия; перед установкой проверяйте свободный overlay.

## Установка

Сохраните резервную копию настроек через LuCI / System / Backup, скачайте её на компьютер. Проверьте архитектуру и свободное место:

```sh
ubus call system board
df -h /overlay /tmp
```

Скачайте [релиз 1.0.0](https://github.com/m-bezrukoff/forkop-plus/releases/tag/1.0.0) на роутер. Архив содержит шесть APK, `SHA256SUMS` и версии исходников. Для установки всех компонентов потребуется место под sing-box, Xray и его geodata; проверяйте фактический размер APK и свободный overlay. Хранить приватные конфигурации нужно с правами `600`.

```sh
mkdir -p /tmp/forkop-plus
cd /tmp/forkop-plus
wget -O packages.tar.gz https://github.com/m-bezrukoff/forkop-plus/releases/download/1.0.0/forkop-plus-filogic-25.12.tar.gz
tar -xzf packages.tar.gz
sha256sum -c SHA256SUMS
apk update
```

Остановите существующие Forkop/sing-box перед заменой. Для уже установленного стандартного `sing-box` или `sing-box-tiny` удалите только соответствующий пакет перед установкой extended; APK объявляет конфликт с ними. Не удаляйте конфигурацию. Backend также сохраняет upstream-конфликты с Passwall, NextDNS и https-dns-proxy.

```sh
/etc/init.d/forkop stop 2>/dev/null || true
/etc/init.d/sing-box stop 2>/dev/null || true
# Только если пакет установлен: apk del sing-box (или sing-box-tiny).
apk add --allow-untrusted ./forkop_1.0.0.apk ./luci-app-forkop_1.0.0.apk ./luci-i18n-forkop-ru_1.0.0.apk \
  ./sing-box-extended_1.14.1-extended-2.7.2-forkop.1_openwrt_aarch64_cortex-a53.apk \
  ./forkop-xray_26.10.10-r1_aarch64_cortex-a53.apk \
  ./forkop-amneziawg_3.1.20260828-r1_aarch64_cortex-a53.apk
/etc/init.d/forkop enable
/etc/init.d/forkop restart
```

APK подписываются не ключом OpenWrt, поэтому для этих локально проверенных пакетов указан `--allow-untrusted`. Не используйте это флагом для глобального обновления системы. Сервисы Xray и AWG зарегистрированы в procd, но по умолчанию выключены до добавления пользовательской конфигурации. Обновления Forkop и обычного extended берутся из этого форка. Legacy compressed extended по-прежнему использует источник shtorm-7; он не входит в этот комплект. Xray/AWG обновляются установкой соответствующих новых APK из релиза.

## Hysteria 2

Добавьте в секцию Forkop ссылку `hysteria2://` от сервера или собственный sing-box outbound. Например, в поле JSON outbound:

```json
{
  "type": "hysteria2",
  "tag": "HY2",
  "server": "vpn.example.com",
  "server_port": 443,
  "password": "REPLACE_WITH_SERVER_PASSWORD",
  "tls": {"enabled": true, "server_name": "vpn.example.com"}
}
```

При необходимости добавьте согласованные с сервером параметры obfs/port hopping. В рабочей конфигурации используйте действительный сертификат и имя сервера. Набор сборки включает `with_quic`; тест передаёт HTTP через реальный зашифрованный Hysteria 2 туннель. Naive/Chromium в комплект не включён.

## Полное ядро Xray 26.10.10

sing-box extended сохраняет свою реализацию XHTTP. Для параметров, доступных именно в Xray, используйте штатный Xray: импортируйте нативный JSON с `outbounds`, `routing`, `dns`, `policy` и необходимыми настройками, полученный от вашего сервера. В частности, `vless`, REALITY, XHTTP и их дополнительные поля не преобразуются в ограниченную схему sing-box.

```sh
chmod 600 /root/xray-native.json
forkop-xray-import /root/xray-native.json
uci set forkop_xray.settings.enabled='1'
uci commit forkop_xray
/etc/init.d/forkop-xray restart
```

Импорт сначала создаёт кандидат с правами `600`, проверяет его самим `xray run -test` и только после успеха заменяет рабочий файл. Подготовка управляет двумя вещами: заменяет `inbounds` единственным SOCKS-входом **127.0.0.1:10810 с UDP** и устанавливает `streamSettings.sockopt.mark=134217728` каждому outbound для обхода повторного TPROXY. Остальные поля сохраняются. Если ваши routing rules ссылались на старые inbound tags, замените их на `forkop-socks`. Полные GeoIP/GeoSite из официального архива входят в пакет в `/usr/share/xray/geodata.tar.gz`; helper `forkop-xray-assets` автоматически предоставляет Xray проверенную копию в RAM. Ручной запуск Xray с geo-rules требует `export XRAY_LOCATION_ASSET=$(forkop-xray-assets)`.

В нужную секцию Forkop добавьте:

```json
{"type":"socks","tag":"Xray 26.10.10","server":"127.0.0.1","server_port":10810,"version":"5"}
```

При routing через FakeIP оставьте разрешение доменов в Forkop. Для сложной собственной DNS-конфигурации Xray проверьте, что её запросы направляются через маркированный outbound и не возвращаются в TPROXY. Нативное ядро предоставляет все свои протоколы; importer управляет локальным входом и не публикует серверные входы в WAN. CI проверяет SOCKS-передачу данных, но не все возможные серверные комбинации Xray.

## AmneziaWG 3.1

Скопируйте конфигурацию AWG 3.1 от вашего сервера в `/etc/forkop/awg0.conf` и установите права. Настройки клиента должны совпадать с сервером: частный/публичный ключи, Endpoint, Address, AllowedIPs и параметры обфускации.

```sh
chmod 600 /etc/forkop/awg0.conf
uci set forkop_awg.settings.enabled='1'
uci commit forkop_awg
/etc/init.d/forkop-awg restart
awg show awg0
ip link show awg0
```

В Forkop выберите тип outbound **интерфейс** и устройство **awg0**. Если `awg0` не появляется в списке netifd, добавьте интерфейс `awg_forkop` с protocol `none`, device `awg0`, без default route; затем выберите его в Forkop. Данные направляются через sing-box `bind_interface=awg0`; создание самого туннеля выполняет `forkop-awg`.

Поддержаны `Jc/Jmin/Jmax`, `S1..S4`, диапазоны `H1..H4`, `I1..I5`, `HeaderProtectionKey`, `ContentPaddingAddition`, диапазоны времени rekey/keepalive/handshake, `RandomTrailers` и `DisableCookies`. Их окончательно проверяет официальный `awg-tools` 3.1. Неподдерживаемые поля и `PreUp/PostUp/PreDown/PostDown` отклоняются; shell hooks не выполняются. `Address` и `MTU` применяются сервисом; `DNS`, `Table` и пользовательский `FwMark` не применяются, поскольку DNS и выбор маршрута принадлежат Forkop. Endpoint может содержать DNS-имя.

`AdvancedSecurity=on` в `[Peer]` принимается как штатный режим userspace 3.1. Этот legacy-флаг tools предназначен для kernel API и не передаётся Go-демону, который всегда работает в режиме AWG. Значение `off` отклоняется с пояснением; обычный WireGuard используйте отдельным интерфейсом.

Сервис использует `/dev/net/tun` и userspace `amneziawg-go`, поэтому внешний модуль ядра AWG не нужен. Поддерживается один управляемый туннель, по умолчанию `awg0`, с отдельной routing table **311** и rules priority **10400** только для трафика, привязанного к интерфейсу. Основной WAN default route не заменяется. Занятая таблица 311 или существующий `awg0` блокируют старт; сервис не должен управлять интерфейсом одновременно с netifd AWG или другим VPN-клиентом.

## Проверка и диагностика

```sh
sing-box version
xray version
amneziawg-go --version
awg --version
sing-box check -c /etc/sing-box/config.json
logread -e forkop -e sing-box -e xray -e amnezia
awg show awg0 latest-handshakes
```

Успешная сборка и QEMU-проверка не измеряют производительность AX6000. Для подтверждения работы на устройстве нужны сохранение состояния после reboot, проверки IPv4/IPv6/DNS через выбранные секции, реальные HY2/Xray/AWG серверы и замер скорости. Не включайте одновременно несколько независимых программ перехвата трафика без согласованной маршрутизации.
