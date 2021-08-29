from brownie import options, accounts

def main():
    acct = accounts.load('local_deployment_account')
    options.deploy(0, 0, 0, {"from": acct, "value": "10 ether"})