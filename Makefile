all: json historical

json:
	curl "https://dlx-app.vercel.app/api/historical" >json/historical.json

historical:
	forge script script/GLPRewards.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
