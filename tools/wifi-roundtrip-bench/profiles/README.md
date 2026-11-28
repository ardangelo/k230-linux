# Cold-boot Wi-Fi profiles

These are manual bench profiles for a K230 with the native UART result daemon
and a provisioned Wi-Fi network. The generator emits the same four executables
used in each measurement. The image build does not install them.

| Profile | One-boot kernel argument | Completion and measurement directory |
| --- | --- | --- |
| IPv4 prewarm | `init=/usr/local/sbin/blinix-nettrial-init` | `/run/blinix-nettrial/` |
| IPv6 SLAAC | `init=/usr/local/sbin/blinix-nettrial-v6-init` | `/run/blinix-nettrial-v6/` |

## Build and verify

From this directory, use a fresh output directory:

```sh
profiles=$(pwd)
out=$(mktemp -d)
python3 build.py ipv4 "$out/ipv4"
python3 build.py ipv6 "$out/ipv6"
(cd "$out" && shasum -a 256 -c "$profiles/measured.sha256")
```

The templates in `src/` share the worker startup, input checks, HTTPS validation
and result delivery. `@ipv4` and `@ipv6` select version-specific lines,
`@both` resumes shared lines, and `@PREFIX@` expands to the installed filename
prefix. Compare generated files with `measured.sha256` before deploying.

## Run one profile

1. Copy the four files from the chosen output directory to `/usr/local/sbin/`
   on the unit, keeping mode 0755. The two profiles have distinct filenames.
2. Provision `/root/blinix-boot-bench/wifi.conf` as a root-private
   wpa_supplicant configuration for the test network. An optional
   `/root/blinix-boot-bench/wifi.freq` contains the known frequency in MHz.
   The measured default is 5220 MHz. An explicit frequency in the network
   block takes precedence.
3. For IPv4, supply `CYBERDECK_FETCH_URL=https://your-server.example/status`
   in `/etc/cyberdeck/net-fetch.conf`. Use a response of at most 192 raw bytes.
   The IPv6 profile uses `https://httpbingo.org/uuid` and requires HTTP 200.
   Both profiles use the root-only Unix socket at
   `/run/cyberdeck-service/net-result.sock` for nRF delivery.
4. Add the selected `init=` argument to the kernel command line for a single
   boot. Preserve the kernel and root filesystem arguments used for the trial.
   The wrapper starts the worker alongside real systemd. It excludes wlan0
   from NetworkManager and suppresses the regular fetch unit for that boot.
5. Before reboot, capture `timing`, `fetch.jsonl`, `fetch.err` and
   `worker.log` from the profile's measurement directory. `fetch_complete`
   and `worker_exit` are continuation markers. Compare the JSON request ID,
   HTTP status, byte count and SHA-256 with the body in `k230 net result` on
   PebbleOS. The runtime directory also contains a private WPA configuration.
   Copy the measurement files individually.
6. Boot with the usual kernel arguments to restore ordinary network ownership.

IPv4 preloads Python and the CA store. It requires the actual leased address
and pins the matching DHCP resolver configuration in the client's private
mount namespace before connecting. IPv6 starts in parallel with IPv4 DHCP.
It waits for a non-tentative preferred global address, a wlan0 default route,
and a route through wlan0 to its resolver. Router-advertised IPv6 DNS has
priority, with Cloudflare's `2606:4700:4700::1111` as the bench fallback.
The configured DNS is private to the IPv6 client. Both profiles validate TLS
and run a concurrent ICMP check for their address family.


To prioritize the request before the full Debian startup, install the
adjacent `network-bench.target` and `network-bench-continue.service` in
`/etc/systemd/system/` and the executable `network-bench-continue` in
`/usr/local/sbin/`. Append `systemd.unit=network-bench.target` alongside
the selected `init=` argument for one boot. The continuation starts
`graphical.target` after the request or after its bounded wait.
