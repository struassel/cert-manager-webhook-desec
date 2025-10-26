# Solver testdata directory

Create a `secret.yaml` file based on `secret.tpl` containing a valid token to connect to Desec.io. The token should have the following format:

    token: Base64(<TOKEN>)

    TOKEN="`echo -n "<TOKEN>" | base64`"; sed "s/TOKEN/${TOKEN}/g" secret.tpl > secret.yaml 
