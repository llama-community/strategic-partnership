Factory is deployed that allows users to specify a depositToken, withdrawalToken, fundPeriod, vestingCliff, vestingPeriod, investors (whitelist of addresses and amounts), exchange rate
Depositor must approve the contract to transfer the fundingAmount. Depositing to the contract kicks off the funding period
Investors can send the exact amount of USDC they are whitelisted for during the funding period
When that ends the depositor can withdraw the difference if not all has been invested along with the withdrawalToken
Now we have a group of investors, a contract with a depositToken locked in. The contract has the logic to determine how investors can withdraw. Usually there will be some cliff and periodic amount. Also there are view functions to see progress