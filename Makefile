all: json historical

json:
	curl "https://dlx-app.vercel.app/api/historical" >json/historical.json

historical:
	forge script script/GLPRewards.s.sol --rpc-url http://127.0.0.1:8545 --broadcast

glp_localhost: deploy_glp_localhost
	NETWORK=localhost forge script script/AddGLPLiquidity.s.sol --rpc-url http://127.0.0.1:8545  -vv --broadcast

fakeglp: deploy_fakeglp_localhost
	NETWORK=localhost forge script script/AddFakeGLPLiquidity.s.sol --rpc-url http://127.0.0.1:8545  -vv --broadcast

deploy_fakeglp_localhost:
	NETWORK=localhost forge script script/DeployFakeGLPMarket.s.sol --rpc-url http://127.0.0.1:8545  --broadcast
	python3 python/consolidate_config.py

deploy_glp_localhost:
	NETWORK=localhost forge script script/DeployGLPMarket.s.sol --rpc-url http://127.0.0.1:8545  --broadcast
	python3 python/consolidate_config.py
