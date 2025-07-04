# VOIPStack Agent

[Client for voipstack platform](https://www.voipstack.io)

## Installation

TODO: Write installation instructions here

## Usage

`voipstack_agent -s "fs://ClueCon:<PASS>@<IP>" -i "<TOKEN>"`

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
