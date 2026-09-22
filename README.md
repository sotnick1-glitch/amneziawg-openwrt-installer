# AmneziaWG Installer Toolkit

Two one-command scripts that set up [AmneziaWG](https://amnezia.org) end-to-end: one for **your own VPS** (the server), one for **your OpenWrt router** (the client). No servers, keys, or accounts are bundled — everything is generated fresh on your own machines.

[Русская версия ниже](#набор-установщиков-amneziawg)

## The flow

1. Run `install-server.sh` on a VPS you control (Ubuntu/Debian). It installs AmneziaWG, sets up the server, and prints a ready-to-use client `.conf`.
2. Copy that `.conf`.
3. Run `install-router.sh` on your OpenWrt router, paste the `.conf` in when asked.

Done — your router now has a one-button AmneziaWG toggle inside LuCI.

Don't have a router, or don't want to touch it? Skip step 3 entirely — see [Installing on a phone or computer](#installing-on-a-phone-or-computer-no-router-needed) below, it's just an app + the same `.conf` file.

---

## `install-server.sh` — sets up the VPS

Requirements: a fresh Ubuntu (or Debian) VPS you control, root access.

```sh
curl -fsSL https://raw.githubusercontent.com/sotnick1-glitch/amneziawg-openwrt-installer/main/install-server.sh | bash
```

It will:
- Detect your server's public IP (or ask you to confirm/enter it).
- Install AmneziaWG (kernel module + tools) via the official PPA.
- Generate a server keypair and randomized obfuscation parameters (Jc/Jmin/Jmax/S1/S2/H1-H4) — a fresh, unique set each install, not a shared default.
- Bring up the `awg0` interface with NAT already configured.
- Ask for a client name, generate a client keypair, and print + save a client `.conf` file.

Run it again any time to add another client — it detects the server is already set up and only adds a new peer.

## Installing on a phone or computer (no router needed)

No script needed here — just an app and the `.conf` file `install-server.sh` gave you. This covers a single device, not your whole home network; if you want everything on your Wi-Fi protected at once without installing anything per-device, that's what `install-router.sh` is for.

**iOS / macOS**
1. Install **AmneziaWG** from the App Store (a lighter, dedicated client) — or **AmneziaVPN** if you also want a bundled VPN-management UI.
2. Open the app → **Add tunnel from file or archive** (or scan a QR code, if you generated one from the `.conf`).
3. Select your `.conf` file.
4. Flip the toggle to connect.

**Android**
1. Install **AmneziaWG** or **AmneziaVPN** from Google Play (or **WG Tunnel**, a third-party client that also supports AmneziaWG).
2. Import the `.conf` the same way — from file, or by scanning a QR code.
3. Connect.

**Windows**
1. Download the official client from [amnezia-vpn/amneziawg-windows-client](https://github.com/amnezia-vpn/amneziawg-windows-client/releases/latest).
2. Import the `.conf` file.
3. Activate.

**Linux**
Use `awg-quick` from `amneziawg-tools` (same package family as the router installer) with the `.conf` file directly: `awg-quick up ./client.conf`.

**Turning a `.conf` into a QR code**, if your VPS doesn't have a desktop to view it on: `install-server.sh` prints the file to your terminal — copy it to a machine with `qrencode` installed and run `qrencode -o client-qr.png -r client.conf`, then open the PNG and scan it with the app.

---

## `install-router.sh` — sets up an OpenWrt router

Requirements: an OpenWrt router whose build carries (or can install) `kmod-amneziawg`, `amneziawg-tools`, and `luci-proto-amneziawg`. Not every OpenWrt target has these in its feed — see [amnezia-vpn/amneziawg-openwrt](https://github.com/amnezia-vpn/amneziawg-openwrt) if `opkg install` fails.

```sh
wget -O- https://raw.githubusercontent.com/sotnick1-glitch/amneziawg-openwrt-installer/main/install-router.sh | sh
```

Paste the client `.conf` (from `install-server.sh`, or from anywhere else) when prompted, then Enter + Ctrl-D.

It will:
- Install AmneziaWG packages if missing.
- Create the `awg0` interface and firewall NAT rule from your pasted config.
- Install a toggle page inside LuCI (**Services → AmneziaWG**), or directly at `http://<router-ip>/cgi-bin/amnezia`.
- Leave the tunnel **off by default** — nothing routes through it until you choose a mode.

### Two modes, or three if you already run Podkop

If you don't have [Podkop](https://github.com/itdoginfo/podkop) installed, the toggle page is a plain on/off switch: **off** (normal routing) or **full tunnel** (everything via AmneziaWG).

If the installer detects an existing Podkop selective-routing section (the one with its own domain/subnet list — Telegram, YouTube, etc.), it adds a third option:

- **Off** — Podkop routes its list through its own proxy (e.g. Hysteria2/VLESS), as before.
- **Selective** — the *same* Podkop domain/subnet list is instead routed through AmneziaWG, everything else goes direct. Nothing about the list itself changes, only which tunnel carries it.
- **Full tunnel** — Podkop is stopped, and *all* traffic goes through AmneziaWG.

This is useful when your Podkop proxy protocol gets blocked on some networks but AmneziaWG still gets through (or vice versa) — flip the mode instead of reconfiguring anything.

Safe to re-run: it only touches the `awg0` interface it creates, the firewall zone that already has masquerading enabled, and (in selective mode) the `connection_type`/`interface` fields of your existing Podkop section — your existing WAN, LAN, and Podkop's own domain lists are left alone. If you ever lose internet after toggling, reload the LuCI page — the toggle has a built-in fallback that restores your normal default route.

## License

MIT

---

# Набор установщиков AmneziaWG

Два скрипта в одну команду, которые полностью разворачивают [AmneziaWG](https://amnezia.org): один — для **вашего VPS** (сервер), второй — для **вашего роутера на OpenWrt** (клиент). Внутри нет ни серверов, ни ключей, ни аккаунтов — всё генерируется заново на ваших собственных машинах.

## Как это работает

1. Запускаете `install-server.sh` на своём VPS (Ubuntu/Debian). Он ставит AmneziaWG, поднимает сервер и выводит готовый клиентский `.conf`.
2. Копируете этот `.conf`.
3. Запускаете `install-router.sh` на роутере с OpenWrt, вставляете `.conf`, когда попросит.

Готово — на роутере появляется кнопка включения/выключения AmneziaWG прямо в LuCI.

Нет роутера, или не хотите его трогать? Пропустите шаг 3 полностью — смотрите [«Установка на телефон или компьютер»](#установка-на-телефон-или-компьютер-без-роутера) ниже, это просто приложение + тот же `.conf`-файл.

---

## `install-server.sh` — настройка VPS

Нужно: чистый VPS на Ubuntu (или Debian), доступ root.

```sh
curl -fsSL https://raw.githubusercontent.com/sotnick1-glitch/amneziawg-openwrt-installer/main/install-server.sh | bash
```

Скрипт сам:
- Определит внешний IP сервера (или попросит подтвердить/ввести).
- Поставит AmneziaWG (модуль ядра + утилиты) через официальный PPA.
- Сгенерирует пару ключей сервера и случайные параметры обфускации (Jc/Jmin/Jmax/S1/S2/H1-H4) — каждый раз новые, не общий дефолт для всех.
- Поднимет интерфейс `awg0` с уже настроенным NAT.
- Спросит имя клиента, сгенерирует его ключ и выведет + сохранит клиентский `.conf`.

Можно запускать повторно, чтобы добавить ещё одного клиента — скрипт увидит, что сервер уже настроен, и просто добавит нового пира.

## Установка на телефон или компьютер (без роутера)

Скрипт тут не нужен — только приложение и `.conf`-файл, который выдал `install-server.sh`. Это закрывает одно устройство, а не всю домашнюю сеть; если хотите защитить сразу весь Wi-Fi без установки на каждое устройство — для этого `install-router.sh`.

**iOS / macOS**
1. Установите **AmneziaWG** из App Store (лёгкое специализированное приложение) — или **AmneziaVPN**, если нужен ещё и встроенный интерфейс управления VPN.
2. В приложении: **Импортировать туннель из файла** (или отсканируйте QR-код, если сделали его из `.conf`).
3. Выберите ваш `.conf`-файл.
4. Включите переключатель — готово.

**Android**
1. Установите **AmneziaWG** или **AmneziaVPN** из Google Play (либо **WG Tunnel** — сторонний клиент, тоже понимающий AmneziaWG).
2. Импортируйте `.conf` так же — файлом или через QR-код.
3. Подключитесь.

**Windows**
1. Скачайте официальный клиент: [amnezia-vpn/amneziawg-windows-client](https://github.com/amnezia-vpn/amneziawg-windows-client/releases/latest).
2. Импортируйте `.conf`-файл.
3. Активируйте.

**Linux**
Используйте `awg-quick` из пакета `amneziawg-tools` (та же семья пакетов, что и в установщике роутера) прямо с `.conf`-файлом: `awg-quick up ./client.conf`.

**Как сделать QR-код из `.conf`**, если на VPS нет рабочего стола, чтобы его посмотреть: `install-server.sh` выводит содержимое файла в терминал — скопируйте его на машину, где стоит `qrencode`, и выполните `qrencode -o client-qr.png -r client.conf`, затем откройте PNG и отсканируйте его приложением.

---

## `install-router.sh` — настройка роутера на OpenWrt

Нужно: роутер на OpenWrt, в прошивке которого есть (или можно поставить) `kmod-amneziawg`, `amneziawg-tools`, `luci-proto-amneziawg`. Есть не во всех сборках/платформах — если `opkg install` не находит пакеты, смотрите [amnezia-vpn/amneziawg-openwrt](https://github.com/amnezia-vpn/amneziawg-openwrt).

```sh
wget -O- https://raw.githubusercontent.com/sotnick1-glitch/amneziawg-openwrt-installer/main/install-router.sh | sh
```

Когда попросит — вставьте клиентский `.conf` (от `install-server.sh`, или откуда угодно ещё), нажмите Enter и Ctrl-D.

Скрипт сам:
- Поставит пакеты AmneziaWG, если их нет.
- Создаст интерфейс `awg0` и правило NAT в firewall из вставленного конфига.
- Установит страницу-переключатель прямо в LuCI (**Services → AmneziaWG**), либо напрямую по адресу `http://<router-ip>/cgi-bin/amnezia`.
- Оставит туннель **выключенным по умолчанию** — ничего не маршрутизируется через него, пока вы не выберете режим.

### Два режима, а если у вас уже стоит Podkop — три

Если [Podkop](https://github.com/itdoginfo/podkop) не установлен, переключатель простой: **выключено** (обычная маршрутизация) или **весь трафик** (всё через AmneziaWG).

Если установщик находит у вас уже настроенную секцию выборочной маршрутизации Podkop (ту, где свой список доменов/подсетей — Telegram, YouTube и т.д.), добавляется третий вариант:

- **Выключено** — список Podkop идёт через его обычный прокси (например Hysteria2/VLESS), как и было.
- **Выборочно** — **тот же самый** список доменов/подсетей Podkop вместо прокси идёт через AmneziaWG, всё остальное — напрямую. Сам список не меняется, меняется только то, какой туннель его несёт.
- **Весь трафик** — Podkop останавливается, и **всё** идёт через AmneziaWG.

Это полезно, когда протокол вашего Podkop-прокси где-то блокируется, а AmneziaWG всё ещё пробивает (или наоборот) — просто переключаете режим, ничего не перенастраивая заново.

Можно запускать повторно — трогает только созданный им интерфейс `awg0`, firewall-зону с уже включённым masquerading, и (в режиме «Выборочно») поля `connection_type`/`interface` вашей существующей секции Podkop — сами списки доменов Podkop, WAN и LAN не затрагиваются. Если после переключения пропал интернет — обновите страницу LuCI, в переключателе есть встроенная защита, которая сама восстанавливает обычный маршрут.

## Лицензия

MIT
