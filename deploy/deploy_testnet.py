import subprocess


def run(cmd_str):
    print(cmd_str)
    s = subprocess.run(cmd_str, shell=True, capture_output=True, text=True)
    print(s.stdout)
    lines = s.stdout.split('\n')
    for line in lines:
        if line.startswith('Deployed to: '):
            return line.replace('Deployed to: ', '')
    return ''


def cast(cmd_str):
    print(cmd_str)
    s = subprocess.run(cmd_str, shell=True, capture_output=True, text=True)
    print(s.stdout)
    print(s.stderr)
    return s.stdout


def cast_address(cmd_str):
    s = subprocess.run(cmd_str, shell=True, capture_output=True, text=True)
    return s.stdout.strip()


def deploy_yield_source():
    return '0x682e1FE9409D31915D0EA8daf8474a78698d01bf'
    return run(
        'forge create '
        '--rpc-url https://goerli-rollup.arbitrum.io/rpc '
        '--private-key 0x89792c8d8606ea8180b87ecd2026cbeb2628b83e2f9f468eca9f78da85e0f416 '
        'test/helpers/FakeYieldSource.sol:FakeYieldSource '
        '--constructor-args 10000000000000')


def deploy_data_debt():
    return '0xfB41D52df960fCDa04f174Aad142A3FBBa0A43cf'
    return run(
        'forge create '
        ' --rpc-url https://goerli-rollup.arbitrum.io/rpc '
        '--private-key 0x89792c8d8606ea8180b87ecd2026cbeb2628b83e2f9f468eca9f78da85e0f416 '
        'src/data/YieldData.sol:YieldData '
        '--constructor-args 20')


def deploy_data_credit():
    return '0xAb960C2e5c42b44a77A09cf32a6A5841f8c8Ae20'
    return run(
        'forge create '
        ' --rpc-url https://goerli-rollup.arbitrum.io/rpc '
        '--private-key 0x89792c8d8606ea8180b87ecd2026cbeb2628b83e2f9f468eca9f78da85e0f416 '
        'src/data/YieldData.sol:YieldData '
        '--constructor-args 20')


def deploy_npv_token():
    return '0x52d2d79D2F2E7e04775Bcd44F74588Aac0635A63'
    return run(
        'forge create '
        ' --rpc-url https://goerli-rollup.arbitrum.io/rpc '
        '--private-key 0x89792c8d8606ea8180b87ecd2026cbeb2628b83e2f9f468eca9f78da85e0f416 '
        'src/tokens/NPVToken.sol:NPVToken '
        '--constructor-args "npv[ETH] of FAKE" "npvE:FAKE"')


def deploy_discounter():
    return '0xC97F9348c8a7a88ed59A1A49858Ba73FdFABF7CC'
    return run(
        'forge create '
        ' --rpc-url https://goerli-rollup.arbitrum.io/rpc '
        '--private-key 0x89792c8d8606ea8180b87ecd2026cbeb2628b83e2f9f468eca9f78da85e0f416 '
        'src/data/Discounter.sol:Discounter '
        '--constructor-args 10000000000000 500 360 18')


def deploy_slice(npv_token_address,
                 yield_source_address,
                 data_debt_address,
                 data_credit_address,
                 discounter_address):
    return '0xC77bda405Bd94C04d402869302445c4a32f7ADba'
    return run(
        'forge create '
        ' --rpc-url https://goerli-rollup.arbitrum.io/rpc '
        '--private-key 0x89792c8d8606ea8180b87ecd2026cbeb2628b83e2f9f468eca9f78da85e0f416 '
        'src/core/YieldSlice.sol:YieldSlice '
        '--constructor-args %s %s %s %s %s 1000000000000000000' % (
            npv_token_address,
            yield_source_address,
            data_debt_address,
            data_credit_address,
            discounter_address
        ))


def deploy_pool(uniswap_v3_pool, swap_router, quoter):
    return '0x82b9e44cDfcB52ADeA5Dc7B24fF13E9e49AC27A1'
    return run(
        'forge create '
        '--rpc-url https://goerli-rollup.arbitrum.io/rpc '
        '--etherscan-api-key 2T191FT9KNN4JBWIQ9IRD2KMATWKADA5DP '
        '--verify '
        '--private-key 0x89792c8d8606ea8180b87ecd2026cbeb2628b83e2f9f468eca9f78da85e0f416 '
        'src/liquidity/UniswapV3LiquidityPool.sol:UniswapV3LiquidityPool '
        '--constructor-args %s %s %s' % (
            uniswap_v3_pool,
            swap_router,
            quoter,
        ))

def deploy_npv_swap(npv_token_address, slice_address, pool_address):
    #return '0x3a603C48235585F3461130165b93D169564aC3aE'
    return run(
        'forge create '
        '--rpc-url https://goerli-rollup.arbitrum.io/rpc '
        '--etherscan-api-key 2T191FT9KNN4JBWIQ9IRD2KMATWKADA5DP '
        '--verify '
        '--private-key 0x89792c8d8606ea8180b87ecd2026cbeb2628b83e2f9f468eca9f78da85e0f416 '
        'src/core/NPVSwap.sol:NPVSwap '
        '--constructor-args %s %s %s' % (
            npv_token_address,
            slice_address,
            pool_address,
        ))

def set_data_writer(data_address, writer_address):
    cast('cast send '
         '--private-key 0x89792c8d8606ea8180b87ecd2026cbeb2628b83e2f9f468eca9f78da85e0f416 '
         '--rpc-url https://goerli-rollup.arbitrum.io/rpc %s '
         '"setWriter(address)" %s' % (data_address, writer_address))


def create_uniswap_v3_pool(uniswap_v3_factory, npv_token_address, yield_token):
    if npv_token_address < yield_token:
        token0 = npv_token_address
        token1 = yield_token
    else:
        token0 = yield_token
        token1 = npv_token_address
    existing = cast_address(
        'cast call '
        '--rpc-url https://goerli-rollup.arbitrum.io/rpc '
        '%s "getPool(address,address,uint24)(address)" %s %s 3000' % (uniswap_v3_factory, token0, token1))
    print('Found existing Uniswap pool', existing)
    if existing != '0x0000000000000000000000000000000000000000':
        return existing

    address = cast(
        'cast send '
        '--private-key 0x89792c8d8606ea8180b87ecd2026cbeb2628b83e2f9f468eca9f78da85e0f416 '
        '--rpc-url https://goerli-rollup.arbitrum.io/rpc '
        '%s "createPool(address,address,uint24)(address)" %s %s 3000' % (uniswap_v3_factory, token0, token1))
    new_uniswap_pool = cast_address(
        'cast call '
        '--rpc-url https://goerli-rollup.arbitrum.io/rpc '
        '%s "getPool(address,address,uint24)(address)" %s %s 3000' % (uniswap_v3_factory, token0, token1))
    cast(
        'cast send '
        '--private-key 0x89792c8d8606ea8180b87ecd2026cbeb2628b83e2f9f468eca9f78da85e0f416 '
        '--rpc-url https://goerli-rollup.arbitrum.io/rpc '
        '%s "initialize(uint160)" 79228162514264337593543950336' % (new_uniswap_pool))

    return new_uniswap_pool


def main():
    # -- Constants -- #
    deployer_address = '0xD8Dc00e6744D41730b907Dc859827B90c46226a8'
    dev_address = '0xD8Dc00e6744D41730b907Dc859827B90c46226a8'

    # Arbitrum Goerli addresses. These are different from Arbitrum live.
    uniswap_v3_factory = '0x4893376342d5D7b3e31d4184c08b265e5aB2A3f6'
    swap_router = '0xab7664500b19a7a2362Ab26081e6DfB971B6F1B0'
    quoter = '0x1dd92b83591781D0C6d98d07391eea4b9a6008FA'

    etherscan_api_key = '2T191FT9KNN4JBWIQ9IRD2KMATWKADA5DP'


    # -- Start deployment -- #
    yield_source_address = deploy_yield_source()
    print('yield_source_address', yield_source_address)

    generator_token = cast_address('cast call --rpc-url https://goerli-rollup.arbitrum.io/rpc %s "generatorToken()(address)"' % yield_source_address)
    yield_token = cast_address('cast call --rpc-url https://goerli-rollup.arbitrum.io/rpc %s "yieldToken()(address)"' % yield_source_address)

    print('generator_token', generator_token)
    print('yield_token    ', yield_token)

    data_debt_address = deploy_data_debt()
    data_credit_address = deploy_data_credit()

    print('data_debt_address  ', data_debt_address)
    print('data_credit_address', data_credit_address)

    npv_token_address = deploy_npv_token()
    print('npv_token_address', npv_token_address)

    discounter_address = deploy_discounter()
    print('discounter_address', discounter_address)

    slice_address = deploy_slice(
        npv_token_address,
        yield_source_address,
        data_debt_address,
        data_credit_address,
        discounter_address)
    print('slice_address', slice_address)

    owner_address = cast_address(
        'cast call '
        '--private-key 0x89792c8d8606ea8180b87ecd2026cbeb2628b83e2f9f468eca9f78da85e0f416 '
        '--rpc-url https://goerli-rollup.arbitrum.io/rpc '
        '%s "owner()(address)"' % (yield_source_address))
    print('owner_address', owner_address)

    print('??', owner_address.lower(), slice_address.lower())
    if owner_address.lower() != slice_address.lower():
        cast('cast send --private-key 0x89792c8d8606ea8180b87ecd2026cbeb2628b83e2f9f468eca9f78da85e0f416 --rpc-url https://goerli-rollup.arbitrum.io/rpc %s "setOwner(address)" %s' % (yield_source_address, slice_address))

    # set_data_writer(data_debt_address, slice_address)
    # set_data_writer(data_credit_address, slice_address)

    # cast('cast send '
    #      '--private-key 0x89792c8d8606ea8180b87ecd2026cbeb2628b83e2f9f468eca9f78da85e0f416 '
    #      '--rpc-url https://goerli-rollup.arbitrum.io/rpc %s '
    #      '"mintGenerator(address,uint256)" %s 1000000000000000000' % (
    #          yield_source_address,
    #          dev_address))

    uniswap_v3_pool = create_uniswap_v3_pool(uniswap_v3_factory, npv_token_address, yield_token)
    print('uniswap_v3_pool', uniswap_v3_pool)
    pool_address = deploy_pool(uniswap_v3_pool, swap_router, quoter)
    print('pool_address', pool_address)

    npv_swap_address = deploy_npv_swap(npv_token_address, slice_address, pool_address)
    print('npv_swap_address', npv_swap_address)

main()

