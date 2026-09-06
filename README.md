# Extended Meta Protocol for Counter-Strike 1.6

[English](README.md) | [Русский](README.ru.md)

Extended Meta Protocol (EMP) is an AMX Mod X plugin that publishes structured server metadata through server cvars prefixed with `em_`. Monitoring services and other consumers can retrieve these values through the standard `A2S_RULES` query.

- Plugin version: `2026.0.15`
- Protocol schema: `1`
- Author: `Lagnetic Team`

## Features

- Short server description safely split into multiple lines.
- Game mode, keywords, voice languages and interface languages.
- Server icon and other image URLs.
- Extensible links and explicitly marked custom metadata.
- Optional discovery of public AMX Mod X commands.

## AMX Mod X compatibility

| AMX Mod X | Support | `em_updated` |
|---|---|---|
| 1.8.2 | Supported | Not registered |
| 1.8.3 | Supported through the 1.8.2-compatible build | Not registered |
| 1.9 | Supported | Unix modification time of `extended_meta_protocol.ini` |

AMXX 1.8.2 and 1.8.3 do not publish a substitute value for `em_updated`. Monitoring software must treat an absent field as “configuration modification time unavailable”.

## Installation

1. Compile `extended_meta_protocol.sma` with the compiler for the target AMX Mod X version.
2. Copy `extended_meta_protocol.amxx` to `addons/amxmodx/plugins/`.
3. Add the following line to `addons/amxmodx/configs/plugins.ini`:

   ```ini
   extended_meta_protocol.amxx
   ```

4. Copy `extended_meta_protocol.ini` to `addons/amxmodx/configs/`.
5. Replace all demonstration values in `extended_meta_protocol.ini`.
6. Change the map or run `em_reload` from a console with RCON access.

## Configuration example

```ini
; The file must be UTF-8. Comments must occupy a complete line.

[meta]
description = "Public deathmatch server with sentry guns"
mod = "Deathmatch"
keywords = "cs16,deathmatch,sentry"
icon = "https://your-domain.tld/images/server-icon-64x64.png"
map_image = "https://your-domain.tld/maps/{map}.jpg"
voice_languages = "en,ru"
interface_languages = "en,ru"
publish_commands = 0

[links]
site = "https://your-domain.tld"
discord = "https://discord.gg/your-community"

[custom]
season = "summer-2026"
```

Only `description` and `mod` are required. Optional text fields may be removed, commented out or left empty in `[meta]`. If `publish_commands` is present, its value must be `0` or `1`. Entire `[links]` and `[custom]` sections may be omitted.

Comments are recognized after trimming when the first character is `;`. Inline comments are not supported:

```ini
; Valid comment
icon = "https://your-domain.tld/icon.png"

; Invalid: the comment becomes part of the value
icon = "https://your-domain.tld/icon.png" ; comment
```

## Published cvars

### Protocol state

| Cvar | Description |
|---|---|
| `em_status` | Plugin version and publication state in `version-state` format |
| `em_error` | Empty on success; otherwise contains a stable error code |
| `em_schema` | Metadata schema version |
| `em_updated` | Config file modification time on AMXX 1.9; absent on 1.8.2/1.8.3 |

`em_status` examples:

```text
2026.0.15-1
2026.0.15-0
```

States:

- `0` – configuration is invalid and application metadata has been cleared.
- `1` – configuration is valid and metadata has been published.

### Standard metadata

| Cvar | Description |
|---|---|
| `em_desc`, `em_desc_2`…`em_desc_4` | UTF-8-safe chunks of the short description |
| `em_desc_parts` | Number of published description chunks |
| `em_mod` | Game mode or mod name |
| `em_keywords` | Comma-separated search keywords |
| `em_icon` | URL of the recommended 64×64 server icon |
| `em_map_img` | Current map image URL after replacing `{map}` |
| `em_lang_voice` | Comma-separated player communication languages |
| `em_lang_ui` | Comma-separated server interface languages |
| `em_commands`, `em_commands_2`…`em_commands_4` | Optional chunks of public AMXX commands |
| `em_command_parts` | Number of command chunks |

### Links and custom fields

| Cvar | Description |
|---|---|
| `em_links` | Comma-separated manifest of active link keys |
| `em_link_<key>` | URL from the `[links]` section |
| `em_custom` | Comma-separated manifest of active custom keys |
| `em_x_<key>` | Non-standard field from the `[custom]` section |

Consumers must use `em_links` and `em_custom` as the authoritative manifests. Unknown `em_x_*` fields are explicitly non-standard and must not be interpreted as protocol-defined fields.

When a dynamic entry is removed from the configuration, the plugin clears its value and removes `FCVAR_SERVER` after the next map change or `em_reload`. If the key is added again, publication is restored.

The GoldSrc engine cannot completely unregister a cvar without a server restart. Restart the server after permanently uninstalling EMP to guarantee that all previously registered cvars are removed from engine memory.

## URL rules

URLs in `icon`, `map_image` and `[links]` must meet all of the following requirements:

- `http://` or `https://` scheme;
- non-empty DNS hostname containing at least one dot and one ASCII letter;
- hostname labels of 1–63 characters using ASCII letters, digits and hyphens;
- no label may begin or end with a hyphen;
- optional port in the range `1–65535`;
- no spaces, control characters, double quotes, backslashes, `<` or `>`.

Literal IPv4 addresses, literal IPv6 addresses, `localhost` and single-label hostnames are rejected. Use Punycode for internationalized domain names.

Base64 images are not supported. Publish an HTTP(S) URL instead.

## Public command discovery

Command discovery is disabled by default. This is an experimental feature.

```ini
publish_commands = 0
```

## Monitoring recommendations

- Read metadata through `A2S_RULES`.
- Parse `em_status` before consuming application fields.
- Treat state `0` as unpublished metadata and inspect `em_error`.
- Treat an absent `em_updated` as unsupported, not as timestamp zero.
- Reassemble numbered chunks using `em_desc_parts` and `em_command_parts`.
- Use `em_links` and `em_custom` to determine active dynamic keys.
- Treat every server-provided string and URL as untrusted input.
- Do not duplicate hostname, map, player count, bot count, password, VAC state or server version from EMP; those values already exist in standard A2S responses.
