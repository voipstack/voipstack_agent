# VOIPStack Agent

[Client for voipstack platform](https://www.voipstack.io)

## Installation

### Github releases

1. Go to [releases page](https://github.com/voipstack/voipstack_agent/releases)
2. Download the latest release for your platform
3. Extract the downloaded archive
4. Move the binary to a location in your PATH:

```sh
sudo mv voipstack_agent /usr/local/bin/
```

## Usage

### Production

For production deployment use systemd service unit. The file should be located at `/etc/systemd/system/voipstack_agent.service`.

[voipstack_agent.service](voipstack_agent.service)

```sh
sudo useradd voipstack_agent
sudo chown -R voipstack_agent:voipstack_agent /etc/voipstack
sudo systemctl enable voipstack_agent
sudo systemctl start voipstack_agent
```

#### Media Server

To enable real-time stream support, you must use the `voipstack_agent_media` application.

1. Install `voipstack_agent`
2. Download `voipstack_agent_media`
3. Update the `voipstack_agent.service` file and set the path to `voipstack_agent_media`

## Development

Step by step to run the agent:

1. Generate the priv/pub keys in the same project:

```sh
./voipstack_agent --generate-private-key voipstack_agent.key
```

2. Execute the agent:

```sh
VOIPSTACK_AGENT_PRIVATE_KEY_PEM_PATH=voipstack_agent.key ./voipstack_agent -s fs://ClueCon:ClueCon@ip
```

## Asterisk Media Support

For Asterisk media support, you can use a custom YAML configuration file. The agent includes default handlers for Asterisk that can be customized via YAML.

### Default Asterisk Handlers

The agent provides built-in handlers for Asterisk:

1. **Hangup Handler** - Handles hangup actions
2. **Listen Handler** - Handles audio stream start actions (with `break: true` to stop further processing)

### Custom YAML Configuration

Create a custom YAML file (e.g., `asterisk.yml`) to customize Asterisk handlers:

```yaml
executor:
  listen:
    type: softswitch-interface
    only_for: "asterisk"
    break: true
    when:
      action: start
      app_id: audio
    command: Originate
    interface:
      Channel: PJSIP/<OUTBOUND ENDPOINT>/sip:voipstack@${VOIPSTACK_GLOBAL_AGENT_MEDIA_SIP_HOST}:${VOIPSTACK_GLOBAL_AGENT_MEDIA_SIP_PORT}
      Application: ChanSpy
      Data: ${VOIPSTACK_ACTION_VENDOR_CHANNEL},q
      Variable: "PJSIP_HEADER(add,X-VOIPSTACK-STREAM-IN-URL)=${VOIPSTACK_ACTION_INPUT_INPUT_STREAM_IN_URL}"
      Async: true
```

### Running with Custom YAML

```sh
./voipstack_agent -s asterisk://ClueCon:ClueCon@ip -c /path/to/asterisk.yml
```

### Environment Variables for Asterisk

The following environment variables are available for customization:

- `VOIPSTACK_AGENT_MEDIA_SIP_HOST` - Media SIP host (default: 127.0.0.1)
- `VOIPSTACK_AGENT_MEDIA_SIP_PORT` - Media SIP port (default: 6070)

### Example Asterisk Configuration

See [examples/asterisk.yml](examples/asterisk.yml) for a complete example configuration.

## Considerations

- The application stops on presence of any error.

## Contributing

1. Fork it (<https://github.com/voipstack/voipstack_agent/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Jovany Leandro G.C](https://github.com/voipstack/voipstack_agent) - creator and maintainer
