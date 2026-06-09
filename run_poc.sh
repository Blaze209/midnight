#!/bin/bash
# Ensure forge is in PATH
if ! command -v forge &> /dev/null
then
    export PATH="$PATH:$HOME/.foundry/bin"
fi

# Run the integrated PoC
forge test --match-path test/Exploit.t.sol -vv
