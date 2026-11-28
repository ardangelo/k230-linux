# Sending an HTTPS result to PebbleOS

On the development test card, install the client and unit from this directory:

```sh
install -Dm755 cyberdeck-net-fetch /usr/local/libexec/cyberdeck-net-fetch
install -Dm644 cyberdeck-net-fetch.service /etc/systemd/system/cyberdeck-net-fetch.service
systemctl daemon-reload
systemctl enable cyberdeck-net-fetch.service
```

The bench needs Python 3, the Debian CA bundle, iputils-ping, Wi-Fi and the
native UART package version 0.1+native.3-1 or later with its result socket.
Use a normal development firmware build with application receipt support.

For a single request, run as root:

```sh
/usr/local/libexec/cyberdeck-net-fetch https://your-server.example/status --interface wlan0 --timeout 60
```

To select the endpoint at boot, create `/etc/cyberdeck/net-fetch.conf` with
`CYBERDECK_FETCH_URL=https://your-server.example/status` and run
`systemctl start cyberdeck-net-fetch.service` to test it immediately.
Removing the file disables future automatic requests.

The client waits for an IPv4 address, measures one ICMP echo independently of
the TLS connection and binds the TCP connection to the selected interface.
Debian's CA store validates the server certificate and hostname. Use an endpoint
returning at most 192 bytes without content encoding. Final HTTP status and raw
body are delivered together, including error responses. Redirects are reported
as responses. Logs include boot-relative timestamps, the random request ID,
status, body length and SHA-256. `transport_ack` records the nRF transport ACK.
Compare the same request ID, status and body using `k230 net result` on PebbleOS.
