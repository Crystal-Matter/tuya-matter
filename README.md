# Tuya Matter

Bridge Tuya LAN power switches to a Matter controller. The bridge exposes each switch as an On/Off Plug-in Unit. It forwards On, Off, and Toggle commands, polls each switch every 30 seconds, and reports unreachable devices independently. [Tuya client](https://github.com/stakach/tuya-client) · [Crystal Matter](https://github.com/Crystal-Matter/matter)

## Configuration

1. Set up your devices in the **Tuya** app. This includes compatible Kogan and Mercator Ikuu kettles.
2. Retrieve each device's `device_id` and local `key` by following the [Tuya Local Key guide](https://github.com/vineetchoudhary/tuya-local-key).
3. Copy `config.example.yaml` to `config.yaml` and fill in each device's local IP address, `device_id`, and `key`.

```yaml
power_switch:
  - ip: "192.0.2.10"
    device_id: "your-device-id"
    key: "0123456789abcdef"
    name: "Desk Plug"
  - ip: "192.0.2.11"
    device_id: "another-device-id"
    key: "fedcba9876543210"
```

| Field | Default | Purpose |
| --- | --- | --- |
| `ip` | Required | LAN IP address of the device |
| `device_id` | Required | Tuya device ID, unique within the config |
| `key` | Required | 16-byte Tuya local key |
| `name` | Generated | Matter label, up to 32 bytes |
| `version` | Automatic | Optional protocol override, from `"3.1"` through `"3.5"` |
| `port` | `6668` | Tuya TCP port |
| `datapoint` | `1` | Boolean power datapoint |
| `assume_off_when_missing` | `true` | Report Off when a successful status reply omits the power datapoint |
| `query_datapoints` | Device default | IDs to query for devices that use the device22 query format. Include the power datapoint. |

The bridge detects each device’s Tuya version using LAN announcements and a status query. Devices that are offline are retried in the background. Restart the bridge after editing the config.

Set `assume_off_when_missing: false` to treat a status reply that omits the power datapoint as a failed poll. The bridge always uses an explicit power value when the device reports one.

### Matter endpoints and connectivity

Endpoint 0 is the Matter root and endpoint 1 is the bridge aggregator. On a fresh setup, the first two switches use endpoints 2 and 3. The bridge keeps assigned endpoint numbers in Matter state across restarts and identifies each switch by name and address in its logs.

A switch becomes reachable after its first successful status poll or power command. After that, a failed power command marks it unreachable. Failed status polls are logged at debug level and leave the last reported state in place. A successful poll or power command restores reachability.

The bridge opens a fresh TCP connection for each poll or power command and closes it afterward. Some Tuya devices accept only one local TCP client at a time. If a device resets connections, close other apps or integrations using it before retrying. [TinyTuya troubleshooting](https://github.com/jasonacox/tinytuya#troubleshooting)

## Docker Compose

Run these commands on a Linux host on the same LAN as the Matter controller and Tuya devices.

Compose mounts `./config.yaml` read-only and stores Matter state in `./matter-data/`. Host networking provides Matter UDP and multicast DNS. The container user needs read access to `config.yaml`.

After a host reboot, the bridge waits for a usable LAN address before advertising itself to Matter controllers.

Compose runs as UID and GID 1000 by default. To run as a different deployment account, set `MATTER_UID` and `MATTER_GID` in `.env` to that account's `id -u` and `id -g`.

Make sure the container user can write to `matter-data/` and any restored files before starting Compose. If you need to fix ownership, this command uses the default IDs.

```sh
sudo chown -R 1000:1000 ./matter-data/
```

Replace both numbers with the configured IDs if you changed them.

```sh
docker compose pull
docker compose up -d
docker compose logs -f tuya-matter
```

To build locally, uncomment `build: .` in `docker-compose.yml` and run `docker compose up -d --build`.

Use the manual pairing code or QR payload printed on first start to add the bridge to your Matter controller. The bridge uses the Crystal Matter development attestation identity.

### Back up or move the bridge

Stop the bridge before backing up `matter-data/`. Copy that directory and `config.yaml` to the new host, then check ownership before starting Compose. Keep the backup private because it contains Matter pairing keys and Tuya local keys.

### Publish the Docker image

Sign in to Docker Hub with access to `stakach/tuya-matter`, then run the publish script.

```sh
docker login
./scripts/publish-image.sh
```

The script pulls the latest Crystal Alpine builder, builds statically linked binaries for `linux/amd64` and `linux/arm64`, and publishes both as `stakach/tuya-matter:latest` with a scratch runtime.

## Run locally

Requires Crystal 1.22 or later and OpenSSL.

```sh
shards install
shards build tuya-matter
bin/tuya-matter
```

| Environment variable | Default |
| --- | --- |
| `TUYA_CONFIG_FILE` | `config.yaml` |
| `MATTER_STORAGE_FILE` | `data/tuya-matter.yml` |
| `MATTER_PORT` | `5540` |
| `LOG_LEVEL` | `info` |

## Development

```sh
shards install
shards build ameba
bin/ameba
crystal spec
```
