# Проверка pull requests Forkop

Снимок GitHub: 11 октября 2026, база `ushan0v/forkop@dd483297be0ac4e52bb8f482e2640238b75af532`.
Проверены все 23 доступных PR (12 открытых, 11 закрытых; закрытие не означает merge).
20 изменений включены в коммит `6938bf4de92bb0d30c0ba5a3ec6736b67b974840` нового форка.
Сохранённые SHA ниже определяют проверенную версию; последующие изменения PR требуют новой проверки.

Основание решения: анализ диффов и зависимостей, применение к общей базе, синтаксис ucode в обычном и строгом режимах, весь набор backend-тестов, lint, 510 frontend-тестов и воспроизводимость LuCI bundle. Необнаруженные ошибки остаются возможны; это не гарантия отсутствия любых дефектов. Реальный Redmi AX6000 в этих испытаниях не использовался.

| PR | Состояние | Проверенный head SHA | Решение | Основание |
| --- | --- | --- | --- | --- |
| [#66](https://github.com/ushan0v/forkop/pull/66) | open | `b62d0576b615a7f939e90fd0ecb9945443044e2a` | Включён | Настраиваемые заголовки устройств для подписок; изменения UI и backend согласованы. |
| [#67](https://github.com/ushan0v/forkop/pull/67) | open | `b88115b1b10de177ebe57506b0c498f6ed911070` | Включён | Пороги отказа и восстановления DNS; проверены валидация и watchdog. |
| [#68](https://github.com/ushan0v/forkop/pull/68) | open | `7bffb034dc55f171d69fc40d256d7dd65011192f` | Включён | Восстановление WebSocket после перезапуска; проверены lifecycle и очистка обработчиков. |
| [#80](https://github.com/ushan0v/forkop/pull/80) | open | `547b650e0b3ff68e6c6fed2c86292a8210ffdd58` | Включён | idle_timeout согласован с интервалом URLTest более 30 минут. |
| [#82](https://github.com/ushan0v/forkop/pull/82) | closed | `7011b9278e41e8f9ab8fbfb06c45ef579842f439` | Включён | Реальное разрешение адреса проверки прокси предотвращает петлю FakeIP. |
| [#83](https://github.com/ushan0v/forkop/pull/83) | closed | `4bab6e931fca25b3b4742f41715b5e82e974be51` | Включён | DNS hijack выполняется по распознанному протоколу; обычный трафик на порту 53 не перехватывается как DNS. |
| [#86](https://github.com/ushan0v/forkop/pull/86) | open | `8751655a73a1f6650ae89d48395026f1e2cbfac3` | Включён | Актуальный источник APK/IPK Zapret2; сохранена проверка архитектуры. |
| [#90](https://github.com/ushan0v/forkop/pull/90) | open | `b031a4b1c218eba38d55304b4c222ec9b1a71bbb` | Включён | Исключения серверов применяются также к дочерним URLTest/Priority outbound. |
| [#100](https://github.com/ushan0v/forkop/pull/100) | open | `7f03f8f495e207d04cb6f108d87d51b7d564dc4b` | Включён | Прерывание зависших загрузок по низкой скорости и увеличение общего таймаута. |
| [#101](https://github.com/ushan0v/forkop/pull/101) | open | `e70519b2174efc2dae0b2be138e05955d2dde614` | Включён | ACL разрешает чтение необходимых файлов runtime в /tmp/run. |
| [#103](https://github.com/ushan0v/forkop/pull/103) | closed | `e31fd392fc50fc261c31bb14646b63458bbbe349` | Включён | Учитывается удаление independent_cache в sing-box 1.14. |
| [#104](https://github.com/ushan0v/forkop/pull/104) | closed | `b971c373d815225f614db27c3a4fba03980e902d` | Включён | Вызов mwan3 через ucode совместим с OpenWrt 25.12. |
| [#105](https://github.com/ushan0v/forkop/pull/105) | closed | `b56da1f664241458e954722cb56d32551d77924b` | Включён | Проверка свободного tmpfs перед скачиванием большого sing-box extended. |
| [#106](https://github.com/ushan0v/forkop/pull/106) | closed | `70edc28edd1189af89e1664b3fd4200cc2fa2b67` | Включён | Отдельный пользователь ByeDPI и исключение его исходящего трафика из перехвата. |
| [#107](https://github.com/ushan0v/forkop/pull/107) | closed | `0d5ec728d94154d7156552e45945fc94fae2f88e` | Включён | Разрешение TPROXY трафика через input fw4; включены проверки lifecycle include. |
| [#109](https://github.com/ushan0v/forkop/pull/109) | closed | `57775d93d521ac90f5f856b908f9a304c2fca2cf` | Включён | Планирование Priority использует монотонное время вместо часов системы. |
| [#112](https://github.com/ushan0v/forkop/pull/112) | open | `3f82403a2e573643f75ff20b9d90d82ff171ec82` | Включён | term_timeout=30 позволяет sing-box сохранить FakeIP cache при остановке. |
| [#113](https://github.com/ushan0v/forkop/pull/113) | closed | `e84ec713ca17cb1371f0f1363b7dd25f404a1f0a` | Включён | IPv6 TPROXY не настраивается при отключённом IPv6. |
| [#119](https://github.com/ushan0v/forkop/pull/119) | closed | `57ff0568a389af40c8a1d878c219af95affd0513` | Включён | Таймаут измерения задержки увеличен до 10 секунд. |
| [#121](https://github.com/ushan0v/forkop/pull/121) | open | `73d1f9da3dee6b7c912a98b67f822a158bc718e7` | Не включён | Отложен: наличие fallback определяется через runtime_supports_xhttp. Это не проверяет поддержку fallback конкретной версией extended. Нужны проверка capability и испытание failover на реальных соединениях. |
| [#130](https://github.com/ushan0v/forkop/pull/130) | closed | `58d1da698160575a799a2e799e8f7e1e7b3475a4` | Не включён | Отклонён для этой базы: массовое переименование 375 файлов без содержательного описания, с удалённым исходным репозиторием; нет обоснования и проверок миграции. |
| [#135](https://github.com/ushan0v/forkop/pull/135) | open | `4431daaf07258f5a5c5a9164b5967b1ce831be9d` | Не включён | Отклонён в текущем виде: parallel curl выводит тела ответов в общий stdout без гарантированного разделения и привязки к запросу, а код читает и разбирает по строкам. Ошибки транспорта не учитываются надёжно; count затем принудительно становится total. Нужны отдельные результаты каждого запроса и тесты частичных отказов. |
| [#138](https://github.com/ushan0v/forkop/pull/138) | open | `7bf711a90f8f6b45036ff705678f65a68ca00827` | Включён | Отказ для не-DNS трафика на source-dns-in устраняет самоподключение после redirect. |

## Проверки объединённой версии

- [Интеграционные проверки исходной объединённой базы](https://github.com/m-bezrukoff/forkop-plus/actions/runs/38089568754): backend и frontend прошли.
- [Первая ARM64-сборка](https://github.com/m-bezrukoff/forkop-plus/actions/runs/38089568813): успешное создание APK и запуск всех четырёх ARM64-бинарников под QEMU.
- Последующие сборки добавляют передачу HTTP через Hysteria 2 и Xray, а также AmneziaWG 3.1 handshake между двумя сетевыми пространствами. Их результаты доступны в Actions и примечаниях релиза.

Первый CI запуск выявил отсутствие исторического тега `0.7.19.9` в новом fork, необходимого contract-тесту. Workflow теперь получает этот тег явно из upstream. Это исправление инфраструктуры; сам contract-тест сохранён.

PR #121 может стать пригодным после дополнительной проверки. PR #135 требует исправления обработки результатов. PR #130 не входит в целевой объём работ.
