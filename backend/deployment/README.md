## Docker
Currently deployment of the backend is pretty manual.

First, get an instance (I'm using the GCP container optimized OS) and setup ssh access.

Next copy over the backend code (run from `backend/`):
```
rsync -avz Dockerfile assets src Cargo.* 34.86.131.30:/home/dport/aptos-hong-bao-backend
```

Next copy in the systemd unit:
```
scp deployment/hong-bao-docker.service 34.86.131.30:~/hong-bao.service
```

Then on the machine:
```
sudo mv hong-bao.service /etc/systemd/system/
sudo systemctl start hong-bao
sudo systemctl enable hong-bao
```

## Source
First get an instance (use something like Debian). Set it up:
```
sudo apt update && sudo apt upgrade
sudo apt install -y libcap2-bin rsync binutils cmake curl clang git pkg-config libssl-dev lld libssl1.1 ca-certificates linux-perf procps gdb curl
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
```

Next copy over the backend code (run from `backend/`):
```
rsync -avz Dockerfile assets src Cargo.* 34.148.77.135:/home/dport/aptos-hong-bao-backend
```

Next copy in the systemd unit:
```
scp deployment/hong-bao-source.service 34.148.77.135:~/hong-bao.service
```

Then on the machine, build the binary:
```
cd aptos-hong-bao-backend
cargo build --release
```

Then start the systemd unit:
```
sudo mv hong-bao.service /etc/systemd/system/
sudo systemctl start hong-bao
sudo systemctl enable hong-bao
```

## Notes
In the end I deployed this on my own server so I could use my existing automation to get SSL certs working easily.
