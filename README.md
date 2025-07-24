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

### FreeSWITCH

```
./voipstack_agent -s "fs://none:<PASS>@<IP>" -i "<TOKEN>"
```

### Asterisk

```
./voipstack_agent -s "asterisk://<AMI USER>:<AMI PASS>@<IP>" -i "<TOKEN>"
```

### Production

For production deployment use systemd service unit. The file should be located at `/etc/systemd/system/voipstack_agent.service`:

```
[Unit]
Description=VOIPStack Agent Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/voipstack_agent -s "fs://none:pass@host" -i "token"
Restart=always

[Install]
WantedBy=multi-user.target
```

Enable and start the service:

```sh
sudo systemctl enable voipstack_agent
sudo systemctl start voipstack_agent
```

## Development

Step by step to run the agent:

1. Generate the priv/pub keys in the same project:

```sh
openssl genrsa -out ./agent.key 2048
openssl rsa -pubout -in agent.key -out agent.pem
```

2. Copy the agent.pem to the clipboard
3. Go to the admin webpage, create or open a tenant and inside of some softswitch add the agent public key.
4. Copy the token from the softswitch you added the agent public key
5. Open a terminal and run `voipstack_agent -s fs://ClueCon:ClueCon@ip`

## Contributing

1. Fork it (<https://github.com/voipstack/voipstack_agent/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Jovany Leandro G.C](https://github.com/voipstack/voipstack_agent) - creator and maintainer
