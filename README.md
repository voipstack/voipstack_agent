# agent

TODO: Write a description here

## Installation

TODO: Write installation instructions here

## Usage

TODO: Write usage instructions here

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
5. Open a terminal and run `rake endpoint`
6. Open a new terminal and run `rake "agent[ADD_HERE_THE_TOKEN_FROM_ADMIN]"`


## Contributing

1. Fork it (<https://github.com/your-github-user/agent/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Jovany Leandro G.C](https://github.com/your-github-user) - creator and maintainer
