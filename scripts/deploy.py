from brownie import options, accounts

def main():
    acct = accounts.load('local_deployment_account')
    options.deploy(1, 2, 3, {"from": acct})