## Surf

We use [Surf](https://github.com/ThalaLabs/surf). Surf requires the ABI of the Move module in the JSON format that comes from the node API. First, spin up the localnet environment (run this from the root of the repo):

```
python scripts/start_local_env.py -f
```

Run this to get the ABIs as JSON:

```
curl -s http://127.0.0.1:8080/v1/accounts/0x5322ac25e855378909b517008c4a16137fc9dbd6c6ff8c5e762ab887002442e5/modules | jq .[].abi | pbcopy
```

Paste those into this file in this directory:

```
./abis.ts
```

Make sure to make them `as const`.
