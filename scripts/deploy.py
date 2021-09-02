from brownie import options, accounts

def main():
    acct = accounts.load('0x6629985a1B15799c4330673458Fc899E545AeB4e')
    options.deploy(0, 0, 0, {"from": acct})