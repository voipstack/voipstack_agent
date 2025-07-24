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
