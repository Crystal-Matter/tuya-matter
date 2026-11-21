# Tuya Matter

Bridge Tuya LAN power switches to a Matter controller. The bridge exposes each switch as an On/Off Plug-in Unit. It forwards On, Off, and Toggle commands, polls each switch every five seconds, and reports unreachable devices independently. [Tuya client](https://github.com/stakach/tuya-client) · [Crystal Matter](https://github.com/Crystal-Matter/matter)

## Configuration

Copy `config.example.yaml` to `config.yaml` and fill in the local details for each device.

```yaml
power_switch:
  - ip: "192.0.2.10"
    device_id: "your-device-id"
    key: "0123456789abcdef"
    name: "Desk Plug"
    version: "3.5"
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
| `version` | `"3.3"` | Use the device's protocol version, from `"3.1"` through `"3.5"` |
| `port` | `6668` | Tuya TCP port |
| `datapoint` | `1` | Boolean power datapoint |
| `query_datapoints` | Device default | IDs to query for devices that use the device22 query format. Include the power datapoint. |

Restart the bridge after editing the config. Keep the Matter state file or volume to retain pairing and endpoint numbers for devices already configured.

## Docker Compose

On a Linux host on the same LAN as the Matter controller and Tuya devices, run:

```sh
docker compose up -d --build
docker compose logs -f tuya-matter
```

Compose mounts `./config.yaml` read-only and stores Matter state in the `matter-data` volume. The container runs as UID 10001 and needs read access to the config file. Host networking provides Matter UDP and multicast DNS.

Use the manual pairing code or QR payload printed on first start to add the bridge to your Matter controller. The bridge uses the Crystal Matter development attestation identity.

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
