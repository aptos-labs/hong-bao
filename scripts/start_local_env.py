"""
Run this from the root of the repo. In general, you probably want to include the `-f` flag.
"""

import argparse
import json
import logging
import subprocess
import time
import urllib.request

logging.basicConfig(level="INFO", format="%(asctime)s - %(levelname)s - %(message)s")


# The contract deployer. We also use this account to create a gift.
DEPLOYER_PRIVATE_KEY = (
    "0xc7e8f661af55fa7e8e52f5b2f5d3daf3f3f49040ea1f05c07c29c47c3ad877c0"
)
DEPLOYER_ADDRESS = "0x5322ac25e855378909b517008c4a16137fc9dbd6c6ff8c5e762ab887002442e5"
DEPLOYER_PROFILE_NAME = "deployer"

# Player 1 and 2 are snatchers. We make snatcher1 snatch right here from the start.
PLAYER1_PRIVATE_KEY = (
    "0xece937b5a5f1df41ba6a550e212492ee98573d3799d0035aa20c29674cd0ceff"
)
PLAYER1_ADDRESS = "0x296102a3893d43e11de2aa142fbb126377120d7d71c246a2f95d5b4f3ba16b30"
PLAYER1_PROFILE_NAME = "local"

PLAYER2_PRIVATE_KEY = (
    "0xece937b5a5f1df41ba6a550e212492ee98573d3799d0035aa20c29674cd0cefd"
)
PLAYER2_ADDRESS = "0xaf769425b319270f91768e8910ed4cde16c4cea32751062c9ab3f2b21adc27b4"
PLAYER2_PROFILE_NAME = "player2"


PACKAGE = "hongbao"
HONGBAO_MODULE = "hongbao"


DEFAULT_SUBPROCESS_KWARGS = {
    "check": True,
    "universal_newlines": True,
    "cwd": "move/",
}


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("-d", "--debug", action="store_true")
    parser.add_argument(
        "-f", "--force-restart", action="store_true", help="Start afresh"
    )
    parser.add_argument(
        "--offline",
        action="store_true",
        help="Set flags that make this work offline, assuming the deps are present",
    )
    parser.add_argument("--aptos-cli-path", default="aptos")
    args = parser.parse_args()
    return args


def main():
    args = parse_args()

    if args.debug:
        logging.setLevel("DEBUG")

    # Kill any existing localnet.
    kill_process_at_port(8080)

    # Run the localnet.
    cmd = [args.aptos_cli_path, "node", "run-localnet", "--with-indexer-api"]
    if args.force_restart:
        cmd += ["--force-restart", "--assume-yes"]
    local_testnet_handle = subprocess.Popen(cmd)

    # Wait for the localnet to start.
    print("[Local] Waiting for localnet to start up...")
    while True:
        # Hit the ready server.
        logging.debug("Checking if localnet up")
        try:
            response = urllib.request.urlopen("http://127.0.0.1:8070")
            if response.status == 200:
                break
        except:
            if local_testnet_handle.poll():
                print("[Local] Localnet crashed on startup, exiting...")
                return
        time.sleep(0.25)
    print("[Local] Localnet came up!")

    if args.force_restart:
        fresh_start(args)

    # Sit here while the localnet runs.
    print("[Local] Setup complete, localnet is ready and running")

    try:
        local_testnet_handle.wait()
    except KeyboardInterrupt:
        print("[Local] Received ctrl-c, shutting down localnet")
        # No need to send another signal, the localnet receives ctrl-c the first
        # time.
        local_testnet_handle.wait()
        print("[Local] Localnet shut down")

    print("[Local] Done, goodbye!")


# Called when --force-restart is used.
def fresh_start(args):
    # Create all the accounts.
    for profile_name, private_key in [
        (DEPLOYER_PROFILE_NAME, DEPLOYER_PRIVATE_KEY),
        (PLAYER1_PROFILE_NAME, PLAYER1_PRIVATE_KEY),
        (PLAYER2_PROFILE_NAME, PLAYER2_PRIVATE_KEY),
    ]:
        # Create an account.
        subprocess.run(
            [
                args.aptos_cli_path,
                "init",
                "--network",
                "local",
                "--private-key",
                # Use a predefined private key so the rest of the steps / tech stack
                # can use a predefined account address.
                private_key,
                "--assume-yes",
                "--profile",
                profile_name,
            ],
            **DEFAULT_SUBPROCESS_KWARGS,
        )
        print(f"[Local] Created account {profile_name} on localnet")

    move_cmd_extra = []
    if args.offline:
        move_cmd_extra.append("--skip-fetch-latest-git-deps")

    # Publish the module as the deployer.
    subprocess.run(
        [
            args.aptos_cli_path,
            "move",
            "publish",
            "--named-addresses",
            f"addr={DEPLOYER_ADDRESS}",
            "--assume-yes",
            "--profile",
            DEPLOYER_PROFILE_NAME,
        ]
        + move_cmd_extra,
        **DEFAULT_SUBPROCESS_KWARGS,
    )
    print(f"[Local] Published the {PACKAGE} Move module at {DEPLOYER_ADDRESS}")

    # Create a gift as the deployer.
    result = subprocess.run(
        [
            args.aptos_cli_path,
            "move",
            "run",
            "--assume-yes",
            "--profile",
            DEPLOYER_PROFILE_NAME,
            "--function-id",
            f"{DEPLOYER_PROFILE_NAME}::{HONGBAO_MODULE}::create_gift_coin",
            "--type-args",
            "0x1::aptos_coin::AptosCoin",
            "--args",
            "u64:4",  # Number of packets
            f"u64:{int(time.time() + 60 * 30)}",  # 30 minutes from now
            f"u64:{10 ** 7}",  # 0.1 APT
            "u8:[]",  # Option none for paylink public key
            "bool:false",  # Keyless only
        ],
        **DEFAULT_SUBPROCESS_KWARGS,
    )

    print(result.stdout)

    # Get the txn hash of the txn we just submitted.
    txn_hash = json.loads(result.stdout)["Result"]["transaction_hash"]

    # Get the data of the txn we just submitted.
    response = urllib.request.urlopen(
        f"http://127.0.0.1:8080/v1/transactions/by_hash/{txn_hash}"
    )
    data = json.loads(response.read().decode("utf-8"))

    # Get and print the address of the collection we just created.
    for change in data["changes"]:
        print(change)
        if change["data"].get("type") == f"{DEPLOYER_ADDRESS}::{HONGBAO_MODULE}::Gift":
            gift_address = change["address"]
            break
    print(f"[Local] Created gift at {gift_address}")

    # Have player 1 snatch.
    subprocess.run(
        [
            args.aptos_cli_path,
            "move",
            "run",
            "--assume-yes",
            "--profile",
            PLAYER1_PROFILE_NAME,
            "--function-id",
            f"{DEPLOYER_PROFILE_NAME}::{HONGBAO_MODULE}::snatch_packet",
            "--args",
            ",".join(
                [
                    (
                        "address",
                        gift_address,
                    ),
                    (
                        "vector<u8>",
                        [],
                    ),
                    (
                        "vector<u8>",
                        [],
                    ),
                ]
            ),
        ],
        **DEFAULT_SUBPROCESS_KWARGS,
    )
    print(f"[Local] Snatched  as {PLAYER1_PROFILE_NAME}")

    print("[Local] Done, you can now interact with the localnet!")


# Kill the process running at the given port.
def kill_process_at_port(port: int):
    out = subprocess.run(
        ["lsof", "-i", f":{port}"], capture_output=True, universal_newlines=True
    )
    pid = None
    for line in out.stdout.splitlines():
        if line.startswith("aptos"):
            pid = line.split()[1]
    if pid:
        subprocess.run(["kill", pid])
        print(f"[Local] Killed existing process occupying port {port} with PID {pid}")


if __name__ == "__main__":
    main()
