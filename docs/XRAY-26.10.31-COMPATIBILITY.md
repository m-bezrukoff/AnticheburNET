# Совместимость с Xray 26.10.29 и 26.10.31

После аудита для выпуска [1.0.35](RELEASE-1.0.35.md) внесены изменения: MPTCP отключён по умолчанию в сборке sing-box ревизии `.7`, Xray закреплён на 26.10.31, добавлены Linux socket tracing и расширенные XHTTP runtime checks. Ниже сохранены исходные результаты аудита до реализации. Проверка физического роутера по-прежнему не выполнялась.

Дата: 3 ноября 2026 года. Проверены текущие исходники AnticheburNET, изменения обеих версий относительно нашей 26.10.21, импорт и локальная передача трафика. Версии продукта, сборочные скрипты и установленные устройства в рамках аудита не изменялись.

## Вывод

Проверенные клиентские протоколы нашего sing-box совместимы с обеими версиями Xray. Обновлять реализацию VLESS/REALITY/XHTTP ради подключения к новым серверам не требуется. Нужен отдельный выпуск безопасности: отключение MPTCP по умолчанию в нашей сборке sing-box и обновление опционального Xray непосредственно до 26.10.31. Версия 26.10.29 отозвана upstream и не подходит для обновления.

Это вывод о необходимости изменений, а не подтверждение эксплуатации уязвимости на конкретном роутере. Версия, патчи и конфигурация ядра OpenWrt, доступность MPTCP и сетевых listeners устройства не проверялись.

## Проверенная база

| Компонент | Состояние |
| --- | --- |
| sing-box | `d9442d14b19ddd02605bf3ee893a171947038e19`, `1.14.3-extended-2.7.3-anticheburnet.6` |
| Toolchain sing-box | Go 1.26.10, security patches и browser presets проекта |
| Опциональный Xray в проекте | 26.10.21, отдельный процесс с SOCKS-мостом |
| Xray 26.10.29 | исходники commit `0afec66085a85191e9dd2a4a6646c7c9a94688d1`, локальная Windows amd64 сборка Go 1.27.3 |
| Xray 26.10.31 | официальный Windows amd64 asset, commit `a4a3dff5b20c2faae567b742c172c7b95e75c083`, Go 1.27.3 |

На момент проверки GitHub `/releases/latest` возвращает 26.10.31 от 31 октября. Release и tag 26.10.29 удалены (API возвращает 404); её исходники доступны по сохранённому SHA. Поэтому тест 26.10.29 проверяет локальную сборку соответствующих исходников, а не удалённый официальный бинарник. Бинарник для итогового прогона помечен `0afec66-audit`, VCS автоподстановка отключена.

Первичная навигация через graphify обнаружила устаревшие пути forkop; выводы проверены по текущим файлам.

## Изменения 26.10.21 → 26.10.29

До release commit 26.10.29 включительно — 19 коммитов после нашей базы.

- XDRIVE получил S3 backend и передачу Google Drive сессий через ring of slots. Обычный конвертер AnticheburNET по-прежнему явно отклоняет XDRIVE, включая S3; эти возможности требуют нативного Xray. Работа реальных облачных хранилищ не проверялась.
- Обновлены встроенные private IP ranges. Проверка допустимости VLESS/Trojan без TLS стала использовать более узкие условия: private, loopback и link-local IP вместо общего matcher специальных адресов. Подтверждён пример: plaintext VLESS к `100.64.0.1` проходит `run -test` в 26.10.21, но отвергается в 26.10.29 и 26.10.31. Это изменение нативной проверки конфигурации; обычные VLESS с TLS/REALITY/Encryption им не затрагиваются.
- Встроенная загрузка geodata ограничена HTTPS, размером 256 MiB, разрешёнными расширениями и частотой обновления. Наш helper распаковывает локально поставляемые geodata и передаёт `XRAY_LOCATION_ASSET`; он не зависит от встроенного HTTP downloader. Произвольные native JSON с HTTP geodata URL нужно проверять отдельно.
- Исправлены Freedom `blockDelay`, Linux IPv6 process routing, DNS replies, нормальное закрытие WebSocket, загрузка файлов через symlinks и порядок инициализации inbound-модуля. Windows/macOS interface binding не меняет OpenWrt клиентский путь.
- Предупреждение Freedom о переносе `fragment`/`noises` в Finalmask не означает автоматическую поддержку Finalmask в sing-box. Неподдерживаемый импорт уже отклоняется.
- Изменений wire-формата основных VLESS, Vision, REALITY и VLESS Encryption в просмотренном diff нет; uTLS revision осталась прежней.

## Изменения 26.10.29 → 26.10.31

Ещё 10 коммитов, всего 29 относительно 26.10.21.

- Главное исправление: `DefaultListener` явно отключает MPTCP по умолчанию. Upstream связывает срочный выпуск и отзыв 26.10.29 с удалённой уязвимостью ядра Linux при IPv4 MPTCP listener и рекомендует также обновить само ядро. Явный `tcpMptcp: true` по-прежнему может включить MPTCP.
- XHTTP server различает CORS preflight и реальный uplink с методом OPTIONS, добавлен серверный `h2Params`. Наш клиент уже умеет передавать OPTIONS, импорт сохраняет `uplinkHTTPMethod`. Переносить серверный `h2Params` в клиентский outbound не требуется.
- Исправлены QUIC sniffing с gaps в ClientHello, короткий HTTP 100 Continue и API balancer info; добавлена потоковая распаковка gzip geodata. Новые Windows WFP/TUN правила не относятся к OpenWrt.

## Подтверждённая проблема нашей сборки

`components/build.sh:56` и `:60` собирают sing-box напрямую и не используют upstream `release/LDFLAGS`, содержащий `-X runtime.godebugDefault=multipathtcp=0,tlssha1=1`. Наш init-скрипт также не задаёт `GODEBUG=multipathtcp=0`.

В закреплённом Go 1.26.10 `net.ListenConfig` включает MPTCP на listeners по умолчанию. `common/listener/listener_tcp.go` нашей базы вызывает `SetMultipathTCP(true)` только при положительном параметре и не вызывает `SetMultipathTCP(false)` при его отсутствии. Следовательно, отсутствие `tcp_multi_path` в JSON само по себе MPTCP не отключает. Это касается поддерживаемых Linux kernels с доступным MPTCP; фактический socket protocol конкретного роутера не измерялся.

Проверена build info существующего локального ARM64 бинарника `.6`: Go 1.26.10, флаг отключения отсутствует. Контрольная программа на том же toolchain сообщает `ListenConfig.MultipathTCP() == true`; с `-X runtime.godebugDefault=multipathtcp=0` — `false`. Это проверка значения по умолчанию, не Linux runtime test и не проверка exploit.

Для исправления следует добавить только `multipathtcp=0` в обе команды сборки sing-box, включая бинарник для govulncheck, и повысить ревизию пакета. Не следует копировать сопутствующий upstream `tlssha1=1`: для этой задачи разрешение SHA-1 сертификатов не требуется. Явное включение `tcp_multi_path: true` переопределяет глобальное значение и требует отдельного решения. Альтернатива или дополнительная защита — явный `SetMultipathTCP(false)` по умолчанию в source patch с сохранением контролируемой настройки.

## Проверки

Использован `tests/xray_compat_runtime.py`, клиент — существующий Windows бинарник текущей `.6`, сервер — соответствующий Xray. Все адреса loopback, credentials синтетические.

| Проверка | 26.10.29 | 26.10.31 |
| --- | --- | --- |
| Основная матрица | 25/25 | 25/25 |
| HTTP 256 KiB, HTTPS/TLS 1.3 256 KiB, UDP echo | 69/69 | 69/69 |
| Отклонение неверного и отсутствующего ML-DSA proof | 2/2 | 2/2 |
| Дополнительные XHTTP OPTIONS: packet-up, stream-up, stream-one | packet-up воспроизводит timeout старого сервера | 3/3, по три проверки трафика |
| XHTTP с server h2Params | отдельно не проверялось | 1/1, три проверки трафика |

Основная матрица: VLESS RAW, Vision/TLS, REALITY с Chrome/Firefox/Safari с Vision и без, четыре XHTTP/TLS режима, два VLESS Encryption режима, четыре XHTTP/REALITY режима, SOCKS-мост, ML-DSA positive/negative, split XHTTP download, gRPC/TLS и gRPC/REALITY.

Дополнительно прошли ucode/WASM fixtures импорта REALITY password/ML-DSA, XHTTP split download, OPTIONS и отклонения XDRIVE S3; suite selection/update/migration/handoff/UI checks. Официальные geodata 26.10.31 проходят native `run -test` с `geosite:cn`, `geoip:private` и outbound mark.

Windows archive 26.10.31 SHA256 сверена с GitHub API:
`2e04a9995a6f2ad1b28c0bb25c708ecb2695e43a1c9c7889c4b6ac2b48cf7a6a`.

Материалы аудита: `.audit/xray-26.10.31-compat/upstream-evidence.json`, `runtime-29-verified/results.json`, `runtime-31/results.json`, `extra-31/results.json`, `extra-29-options/results.json`, `config-checks.json`, `sing-box-arm64-buildinfo.json`, дополнительные scripts и логи в том же каталоге. `.audit` игнорируется Git.

## Необходимое обновление и границы проверки

1. Выпустить новую ревизию нашего sing-box с отключённым по умолчанию MPTCP. Замена только Xray эту проблему отдельного процесса sing-box не исправит. Новая база протоколов sing-box по результатам этого аудита не требуется.
2. Обновить опциональный Xray до 26.10.31 и контрольные суммы. По GitHub API ARM64 ZIP SHA256: `1811c8f1da0c3b6dc707ebaf1c8390e987ba39859a8f0a7aadd8526157f2ec8d`; Linux amd64 ZIP: `e4bd9119f50ae7c41658b1abd0679ae06f98bd864a2907ff33f2f2cf7081b214`. Перед выпуском сверить скачанные архивы. Текущий `components/build.sh` уже формирует APK version как `$XRAY_VERSION-r1`.
3. Сохранить опциональность: новые установщик и обновлятор не выбирают Xray; release workflow по умолчанию публикует его для совместимости со старыми обновляторами. Новому sing-box обновление необходимо независимо от установки Xray.
4. Перед выпуском выполнить ARM64/UPX/QEMU проверки, контроль лимита 35 MB с новыми geodata, Linux socket-level проверку отключения MPTCP, затем OpenWrt smoke test. Определить необходимость обновления ядра по фактической прошивке и backports. Отключение MPTCP в приложениях не заменяет исправление ядра.

Готовые новые APK не собирались и не публиковались, устройства не обновлялись. Windows стенд не подтверждает Linux MPTCP mitigation, OpenWrt TPROXY/marks/firewall, throughput, работу облачного XDRIVE/S3 и произвольных native JSON. Тесты не требуют обновлять AmneziaWG или другие компоненты ради протокольной совместимости с этими Xray; их независимая безопасность этим аудитом не исчерпывается.

## Первичные источники

- [Последний релиз 26.10.31 и уведомление об отзыве 26.10.29](https://github.com/XTLS/Xray-core/releases/tag/v26.10.31).
- [Commit отозванной 26.10.29](https://github.com/XTLS/Xray-core/commit/0afec66085a85191e9dd2a4a6646c7c9a94688d1).
- [Полный diff 26.10.21 → 26.10.31](https://github.com/XTLS/Xray-core/compare/v26.10.21...v26.10.31).
- [Отключение MPTCP #7291](https://github.com/XTLS/Xray-core/pull/7291).
- [XHTTP OPTIONS #7290](https://github.com/XTLS/Xray-core/pull/7290), [h2Params #7295](https://github.com/XTLS/Xray-core/pull/7295).
- [XDRIVE S3 #7231](https://github.com/XTLS/Xray-core/pull/7231), [Google Drive slots #7217](https://github.com/XTLS/Xray-core/pull/7217).
