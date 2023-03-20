all: json historical

json:
	curl "https://dlx-app.vercel.app/api/historical" >json/historical.json

historical:
	forge script script/GLPRewards.s.sol --rpc-url http://127.0.0.1:8545 --broadcast

fakeglp: deploy_localhost
	NETWORK=localhost forge script script/AddFakeGLPLiquidity.s.sol --rpc-url http://127.0.0.1:8545  -vv --broadcast

deploy_localhost:
	NETWORK=localhost forge script script/DeployFakeGLPMarket.s.sol --rpc-url http://127.0.0.1:8545  --broadcast
	python3 python/consolidate_config.py
