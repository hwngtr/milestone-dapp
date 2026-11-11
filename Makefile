.PHONY: test snapshot anvil deploy-local

test:
	forge test -vvv

snapshot:
	forge snapshot

anvil:
	anvil

deploy-local:
	forge script deploy/DeployFactory.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 -vvv
