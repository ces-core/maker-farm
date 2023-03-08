#!/bin/bash
set -eo pipefail

set +e
[ -f "${BASH_SOURCE%/*}/../.env" ] && source "${BASH_SOURCE%/*}/../.env"
FORGE_SCRIPT="${BASH_SOURCE%/*}/forge-script.sh"
set -e

simulate-deploy() {
	if ! grep -- '--fork-url' <<<"$@" >/dev/null; then
		echo "Missing --fork-url argument" >&2
		echo -e "\n$(usage)\n" >&2
		exit 1
	fi

	ANVIL_PORT=${ANVIL_PORT:-8546}
	local ANVIL_RPC_URL="http://localhost:${ANVIL_PORT}"

	# Start anvil
	anvil --port $ANVIL_PORT $@ &
	local ANVIL_PID=$!

	# Wait until anvil is listening on the proper port
	{
		while ! echo -n >"/dev/tcp/localhost/${ANVIL_PORT}"; do
			sleep 1
		done
	} 2>/dev/null

	local RESPONSE=$($FORGE_SCRIPT DeployRwaRegistry -vvv --broadcast --rpc-url $ANVIL_RPC_URL | tee >(cat 1>&2))
	local MIP21_REGISTRY=$(jq -Rr 'fromjson? | .returns["0"].value' <<<"$RESPONSE")

	# Impersonate MCD_PAUSE_PROXY to be able to modify the changelog
	local MCD_PAUSE_PROXY=$(cast call --rpc-url $ANVIL_RPC_URL $CHANGELOG 'getAddress(bytes32)(address)' $(cast --from-ascii 'MCD_PAUSE_PROXY'))
	# We will need some balance to be able to send txs
	cast rpc --rpc-url $ANVIL_RPC_URL anvil_setBalance $MCD_PAUSE_PROXY $(cast --to-wei 10 ETH)
	# Impersionate must be called right before the actual transaction
	cast rpc --rpc-url $ANVIL_RPC_URL anvil_impersonateAccount $MCD_PAUSE_PROXY
	cast send --rpc-url $ANVIL_RPC_URL $CHANGELOG 'setAddress(bytes32,address)' $(cast --from-ascii 'MIP21_REGISTRY') $MIP21_REGISTRY --from $MCD_PAUSE_PROXY

	cat <<MSG


#RwaRegistry instance deployed and added to the CHANGELOG:

###############################################################
##                                                            #
## MIP21_REGISTRY: ${MIP21_REGISTRY} #
##                                                            #
###############################################################

MSG

	wait $ANVIL_PID
}

usage() {
	cat <<MSG
[ ANVIL_PORT=8888 ] simulate-deploy.sh --fork-url <MAINNET_RPC_ENDPOINT>
MSG
}

if [ "$0" = "$BASH_SOURCE" ]; then
	[ "$1" = "-h" -o "$1" = "--help" ] && {
		echo -e "\n$(usage)\n"
		exit 0
	}

	simulate-deploy "$@"
fi
