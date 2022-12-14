Currently deployment of the backend is pretty manual.

First, get an instance (I'm using the GCP container optimized OS) and setup ssh access.

Next copy over the backend code (run from `backend/`):
```
rsync -avz Dockerfile assets src Cargo.* 34.86.131.30:/home/dport/aptos-hong-bao-backend
```

Next copy in the systemd unit:
```
scp deployment/hong-bao.service 34.86.131.30:~/
```

Then on the machine:
```
sudo mv hong-bao.service /etc/systemd/system/
sudo systemctl start hong-bao
sudo systemctl enable hong-bao
```
