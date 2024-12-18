import React, { useEffect, useState } from "react";
import Web3 from "web3";
import "./App.css";
import BigNumber from 'bignumber.js';

// ABI and contract address
import FRAxSwapfABI from './FraxSwapfABI.json';

const web3 = new Web3(window.ethereum);

// Token addresses
const tokenAddresses = {
  MATIC: '0xc91AE0358186f67A71d6F53f628219b07cfA69fd',
  LINK: '0xe2ED92909D719C1530B55400C6B01fb40E20F6A5',
  INRC: '0x86c3e6610DD229127A3522B2321e0806c722FB62',
  RCOIN: '0x7C722c5E5ce73dE9138F7C2C210dA918DdC6Bb8e',
};

const FRAxSwapfAddress = "0xA9276f8FE4984EDC2bB5799034d65CB5A19EFE72"; // Replace with your contract address

function App() {
  const [account, setAccount] = useState(null);
  const [pair, setPair] = useState("");
  const [amountIn, setAmountIn] = useState(0);
  const [amountOut, setAmountOut] = useState(0);
  const [tokenIn, setTokenIn] = useState("");
  const [tokenOut, setTokenOut] = useState("");
  const [rewardToken, setRewardToken] = useState("");
  const [tokenId, setTokenId] = useState(0);
  const [reward, setReward] = useState(0);
  const [feeRate, setFeeRate] = useState(30);
  const [gasEstimate, setGasEstimate] = useState(null);
  // Handle changes for the 'tokenIn' input field
  const handleTokenInChange = (e) => {
    setTokenIn(e.target.value); // Update tokenIn state when input changes
  };

  // Handle changes for the 'tokenOut' input field
  const handleTokenOutChange = (e) => {
    setTokenOut(e.target.value); // Update tokenOut state when input changes
  };

  useEffect(() => {
    if (window.ethereum) {
      window.ethereum.request({ method: "eth_requestAccounts" }).then((accounts) => {
        setAccount(accounts[0]);
      });
    }
  }, []);

  const connectWallet = async () => {
    if (window.ethereum) {
      const accounts = await window.ethereum.request({
        method: "eth_requestAccounts",
      });
      setAccount(accounts[0]);
    }
  };

 
 const claimRewards = async () => {
    const contract = new web3.eth.Contract(FRAxSwapfABI, FRAxSwapfAddress);
    const gas = await contract.methods
      .claimRewards(tokenId, rewardToken)
      .estimateGas({ from: account });
    
    setGasEstimate(gas);

    await contract.methods
      .claimRewards(tokenId, rewardToken)
      .send({ from: account, gas });
  };

  const ERC20_ABI = [ {
    "constant": true,
    "inputs": [
      {
        "name": "_owner",
        "type": "address"
      },
      {
        "name": "_spender",
        "type": "address"
      }
    ],
    "name": "allowance",
    "outputs": [
      {
        "name": "",
        "type": "uint256"
      }
    ],
    "payable": false,
    "stateMutability": "view",
    "type": "function"
  },
  {
    "constant": false,
    "inputs": [
      {
        "name": "_spender",
        "type": "address"
      },
      {
        "name": "_value",
        "type": "uint256"
      }
    ],
    "name": "approve",
    "outputs": [
      {
        "name": "",
        "type": "bool"
      }
    ],
    "payable": false,
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "constant": true,
    "inputs": [
      {
        "name": "_owner",
        "type": "address"
      }
    ],
    "name": "balanceOf",
    "outputs": [
      {
        "name": "",
        "type": "uint256"
      }
    ],
    "payable": false,
    "stateMutability": "view",
    "type": "function"
  },
  {
    "constant": false,
    "inputs": [
      {
        "name": "_to",
        "type": "address"
      },
      {
        "name": "_value",
        "type": "uint256"
      }
    ],
    "name": "transfer",
    "outputs": [
      {
        "name": "",
        "type": "bool"
      }
    ],
    "payable": false,
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "constant": false,
    "inputs": [
      {
        "name": "_from",
        "type": "address"
      },
      {
        "name": "_to",
        "type": "address"
      },
      {
        "name": "_value",
        "type": "uint256"
      }
    ],
    "name": "transferFrom",
    "outputs": [
      {
        "name": "",
        "type": "bool"
      }
    ],
    "payable": false,
    "stateMutability": "nonpayable",
    "type": "function"
  }];
  const addLiquidity = async () => {
    // Initialize token contracts for both tokens
    const tokenInContract = new web3.eth.Contract(ERC20_ABI, tokenIn);
    const tokenOutContract = new web3.eth.Contract(ERC20_ABI, tokenOut);
  
    // Check allowance for tokenIn
    const allowanceIn = await tokenInContract.methods
      .allowance(account, FRAxSwapfAddress)
      .call();
  
    // If tokenIn allowance is less than amountIn, approve it
    if (allowanceIn < amountIn) {
      try {
        const approvalIn = await tokenInContract.methods
          .approve(FRAxSwapfAddress, amountIn)
          .send({ from: account });
        console.log("TokenIn approval successful:", approvalIn);
      } catch (error) {
        console.error("TokenIn approval failed:", error);
        return;
      }
    }
  
    // Now, call the addLiquidity function (passing only amountIn)
    const contract = new web3.eth.Contract(FRAxSwapfABI, FRAxSwapfAddress);
  
    try {
      const gas = await contract.methods
        .addLiquidity(tokenIn, tokenOut, amountIn) // Pass only amountIn
        .estimateGas({ from: account });
  
      setGasEstimate(gas);
  
      await contract.methods
        .addLiquidity(tokenIn, tokenOut, amountIn) // Pass only amountIn
        .send({ from: account, gas });
  
      console.log("Liquidity added successfully");
    } catch (error) {
      console.error("Add liquidity failed:", error);
    }
  };
  
  const swapTokens = async () => {
    try {
      // Initialize token contracts for both tokens
      const tokenInContract = new web3.eth.Contract(ERC20_ABI, tokenIn);
      const tokenOutContract = new web3.eth.Contract(ERC20_ABI, tokenOut);
  
      // Convert amountIn to Wei using web3.utils.toWei (assuming tokenIn uses "ether" decimals, adjust if needed)
      const amountInWei = web3.utils.toWei(amountIn.toString(), "ether");
  
      // Check allowance for tokenIn
      const allowanceIn = await tokenInContract.methods
        .allowance(account, FRAxSwapfAddress)
        .call();
  
      // Use BigNumber to compare the values
      const allowanceInBigNum = new BigNumber(allowanceIn); // Convert allowance to BigNumber
      const amountInWeiBigNum = new BigNumber(amountInWei); // Convert amountInWei to BigNumber
  
      // If allowanceIn is less than amountIn, approve it
      if (allowanceInBigNum.isLessThan(amountInWeiBigNum)) {
        try {
          const approvalIn = await tokenInContract.methods
            .approve(FRAxSwapfAddress, amountInWei)
            .send({ from: account });
          console.log("TokenIn approval successful:", approvalIn);
        } catch (error) {
          console.error("TokenIn approval failed:", error);
          return;
        }
      }
  
      // Now, call the swap function on the contract
      const contract = new web3.eth.Contract(FRAxSwapfABI, FRAxSwapfAddress);
  
      try {
        const tokenId = 1; // Example: Set tokenId here, it might be dynamically set based on your use case
        const gas = await contract.methods
          .swap(tokenIn, amountInWei, tokenOut, tokenId)
          .estimateGas({ from: account });
  
        // Set gas estimate
        setGasEstimate(gas);
  
        // Execute the swap transaction
        await contract.methods
          .swap(tokenIn, amountInWei, tokenOut, tokenId)
          .send({ from: account, gas });
  
        console.log("Swap successful");
        alert("Swap completed successfully!");
      } catch (error) {
        console.error("Swap failed:", error.message);
        alert(`Swap failed: ${error.message}`);
      }
    } catch (error) {
      console.error("Error in swap:", error.message);
      alert(`Swap failed: ${error.message}`);
    }
  };
  

  const removeLiquidity = async () => {
    const contract = new web3.eth.Contract(FRAxSwapfABI, FRAxSwapfAddress);
  
    try {
      console.log("Removing liquidity...");
      
      // Add more logging to check token addresses and amounts
      console.log("Token In:", tokenIn);
      console.log("Token Out:", tokenOut);
      console.log("Token ID:", tokenId);
  
      // Check token allowances
      const tokenInContract = new web3.eth.Contract(ERC20_ABI, tokenIn);
      const tokenOutContract = new web3.eth.Contract(ERC20_ABI, tokenOut);
  
      const allowanceIn = await tokenInContract.methods
        .allowance(account, FRAxSwapfAddress)
        .call();
      const allowanceOut = await tokenOutContract.methods
        .allowance(account, FRAxSwapfAddress)
        .call();
  
      console.log("Allowance In:", allowanceIn);
      console.log("Allowance Out:", allowanceOut);
  
      if (new BigNumber(allowanceIn).isLessThan(amountIn)) {
        await tokenInContract.methods
          .approve(FRAxSwapfAddress, amountIn)
          .send({ from: account });
      }
      if (new BigNumber(allowanceOut).isLessThan(amountIn)) {
        await tokenOutContract.methods
          .approve(FRAxSwapfAddress, amountIn)
          .send({ from: account });
      }
  
      // Estimate gas for removeLiquidity
      const gas = await contract.methods
        .removeLiquidity(tokenId, tokenIn, tokenOut)
        .estimateGas({ from: account });
  
      console.log("Estimated Gas:", gas);
      
      // Execute the removeLiquidity function
      await contract.methods
        .removeLiquidity(tokenId, tokenIn, tokenOut)
        .send({ from: account, gas });
  
      console.log("Liquidity removed successfully");
  
    } catch (error) {
      console.error("Remove liquidity failed:", error.message);
      alert(`Error: ${error.message}`);
    }
  };
  
  
  return (
    <div className="App">
      <header>
        <h1>FraxSwapf DApp</h1>
        <button onClick={connectWallet}>Connect Wallet</button>
        {account && <p>Connected: {account}</p>}
      </header>

      <section>
        <h2>Swap Tokens</h2>
        <input
          type="text"
          placeholder="Amount In"
          value={amountIn}
          onChange={(e) => setAmountIn(e.target.value)}
        />
        <select onChange={handleTokenInChange} value={tokenIn}>
          <option value="">Select Token In</option>
          {Object.keys(tokenAddresses).map((token) => (
            <option key={token} value={tokenAddresses[token]}>
              {token}
            </option>
          ))}
        </select>
        <select onChange={handleTokenOutChange} value={tokenOut}>
          <option value="">Select Token Out</option>
          {Object.keys(tokenAddresses).map((token) => (
            <option key={token} value={tokenAddresses[token]}>
              {token}
            </option>
          ))}
        </select>
        
        <button onClick={swapTokens}>Swap Tokens</button>
        {gasEstimate && <p>Estimated Gas: {gasEstimate}</p>}
      </section>

      <section>
  <h2>Claim Rewards</h2>
  <input
    type="number"
    placeholder="Token ID"
    value={tokenId}
    onChange={(e) => setTokenId(e.target.value)}
  />
  <select onChange={(e) => setRewardToken(e.target.value)} value={rewardToken}>
    <option value="">Select Reward Token</option>
    {Object.keys(tokenAddresses).map((token) => (
      <option key={token} value={tokenAddresses[token]}>
        {token}
      </option>
    ))}
  </select>
  <p>Reward: {reward}</p>
  <button onClick={claimRewards}>Claim Rewards</button>
  {gasEstimate && <p>Estimated Gas: {gasEstimate}</p>}
</section>


      <section>
        <h2>Add Liquidity</h2>
        <select onChange={handleTokenInChange} value={tokenIn}>
          <option value="">Select Token In</option>
          {Object.keys(tokenAddresses).map((token) => (
            <option key={token} value={tokenAddresses[token]}>
              {token}
            </option>
          ))}
        </select>
        <select onChange={handleTokenOutChange} value={tokenOut}>
          <option value="">Select Token Out</option>
          {Object.keys(tokenAddresses).map((token) => (
            <option key={token} value={tokenAddresses[token]}>
              {token}
            </option>
          ))}
        </select>
        <input
          type="text"
          placeholder="Amount In"
          value={amountIn}
          onChange={(e) => setAmountIn(e.target.value)}
        />
       
        <input
          type="number"
          placeholder="Fee Rate"
          value={feeRate}
          onChange={(e) => setFeeRate(e.target.value)}
        />
        <button onClick={addLiquidity}>Add Liquidity</button>
        {gasEstimate && <p>Estimated Gas: {gasEstimate}</p>}
      </section>

      <section>
        <h2>Remove Liquidity</h2>
        <input
          type="number"
          placeholder="Token ID"
          value={tokenId}
          onChange={(e) => setTokenId(e.target.value)}
        />
        <select onChange={(e) => setTokenIn(e.target.value)} value={tokenIn}>
          <option value="">Select Token In</option>
          {Object.keys(tokenAddresses).map((token) => (
            <option key={token} value={tokenAddresses[token]}>
              {token}
            </option>
          ))}
        </select>
        <select onChange={(e) => setTokenOut(e.target.value)} value={tokenOut}>
          <option value="">Select Token Out</option>
          {Object.keys(tokenAddresses).map((token) => (
            <option key={token} value={tokenAddresses[token]}>
              {token}
            </option>
          ))}
        </select>
        <button onClick={removeLiquidity}>Remove Liquidity</button>
        {gasEstimate && <p>Estimated Gas: {gasEstimate}</p>}
      </section>

    </div>
  );
}

export default App;
