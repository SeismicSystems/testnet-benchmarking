use alloy::{
    network::EthereumWallet,
    primitives::{Address, U256},
    providers::{Provider, ProviderBuilder},
    signers::local::PrivateKeySigner,
};
use eyre::Result;
use std::str::FromStr;
use std::time::{Duration, Instant};
use tokio;

#[tokio::main]
async fn main() -> Result<()> {
    println!("🚀 Sending Ethereum transaction...");

    // Configuration
    let rpc_url = "http://52.25.1.50:8545".parse()?;

    // Create a signer from a private key (Hardhat's default private key)
    // WARNING: Use a test private key only! Never use a real private key in code
    let private_key_hex = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
    let private_key_bytes = hex::decode(private_key_hex)?;
    let private_key_fixed = alloy::primitives::FixedBytes::from_slice(&private_key_bytes);
    let signer: PrivateKeySigner = PrivateKeySigner::from_bytes(&private_key_fixed)?;
    let wallet = EthereumWallet::from(signer);

    let from_address = wallet.default_signer().address();
    let to_address = Address::from_str("0x70997970C51812dc3A010C7d01b50e0d17dc79C8")?;

    // Create provider
    let provider = ProviderBuilder::new().wallet(wallet).connect_http(rpc_url);

    println!("From address: {}", from_address);
    println!("To address: {}", to_address);
    println!("Amount: 0.01 ETH");

    // Check initial balance
    let initial_balance = provider.get_balance(from_address).await?;
    println!("Initial balance: {} wei", initial_balance);

    // Create transaction request
    let balance_before = provider.get_balance(from_address).await?;
    let value = U256::from(10_000_000_000_000_000u128); // 0.01 ETH in wei
    let tx = alloy::rpc::types::TransactionRequest::default()
        .from(from_address)
        .to(to_address)
        .value(value);

    println!("Sending transaction...");
    let start_time = Instant::now();

    // Send the transaction
    match provider.send_transaction(tx).await {
        Ok(pending_tx) => {
            let tx_hash = *pending_tx.tx_hash();
            println!("✅ Transaction sent successfully!");
            println!("Transaction hash: {}", tx_hash);

            // Wait for confirmation
            println!("Waiting for confirmation...");
            let confirm_start = Instant::now();

            loop {
                let balance = provider.get_balance(from_address).await?;
                if balance < balance_before {
                    println!("✅ Transaction confirmed in {:.2?}!", confirm_start.elapsed());
                    break;
                }
                tokio::time::sleep(Duration::from_millis(100)).await;
                //match provider.get_transaction_receipt(tx_hash).await? {
                //    Some(receipt) => {
                //        let confirm_duration = confirm_start.elapsed();
                //        println!("✅ Transaction confirmed in {:.2?}!", confirm_duration);
                //        println!("Block number: {}", receipt.block_number.unwrap_or_default());

                //        if receipt.status() {
                //            println!("✅ Transaction successful!");
                //        } else {
                //            println!("❌ Transaction failed!");
                //        }
                //        break;
                //    }
                //    None => {
                //        let elapsed = confirm_start.elapsed();
                //        if elapsed > Duration::from_secs(60) {
                //            println!("❌ Transaction not confirmed within 60 seconds");
                //            break;
                //        }
                //        println!(
                //            "Waiting for confirmation... ({:.1}s)",
                //            elapsed.as_secs_f32()
                //        );
                //        tokio::time::sleep(Duration::from_millis(100)).await;
                //    }
                //}
            }

            let total_duration = start_time.elapsed();
            println!("Total time: {:.2?}", total_duration);
        }
        Err(e) => {
            println!("❌ Failed to send transaction: {}", e);
        }
    }

    // Check final balance
    let final_balance = provider.get_balance(from_address).await?;
    let spent = initial_balance.saturating_sub(final_balance);
    println!("Final balance: {} wei", final_balance);
    println!("Total spent: {} wei", spent);

    Ok(())
}

