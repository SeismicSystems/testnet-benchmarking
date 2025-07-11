use alloy::{
    primitives::U256,
    providers::{Provider, ProviderBuilder},
};
use eyre::Result;
use std::time::Duration;
use tokio::task::JoinSet;
use alloy::network::TransactionBuilder;
use tx_sender::utils;


#[tokio::main]
async fn main() -> Result<()> {

    // Parse IP addresses from inventory file
    let ips = utils::parse_inventory_ips("../ansible/inventory.ini")?;
    let mut providers = Vec::new();
    for ip in ips {
        let rpc_url = format!("http://{ip}:8545").parse()?;
        let provider = ProviderBuilder::new().connect_http(rpc_url);
        providers.push(provider);
    }

    let max_concurrent_tasks = 500;
    let new_transaction_interval = Duration::from_millis(500);

    let (priv_keys, addresses) = utils::read_keys_from_file("private_keys.txt")?;

    let mut join_set = JoinSet::new();
    let mut key_index = 0;
    let mut provider_index = 0;

    let mut send_interval = tokio::time::interval(new_transaction_interval);
    loop {
        tokio::select! {
            // Add new tasks
            _ = send_interval.tick() => {
                if join_set.len() < max_concurrent_tasks {
                    let wallet = priv_keys[key_index].clone();
                    let from_address = addresses[key_index];
                    let provider = providers[provider_index].clone();
                    println!("Address {from_address}");

                    let mut to_index = utils::random_int(addresses.len());
                    if from_address == addresses[to_index] {
                        to_index = (to_index + 1) % addresses.len();
                    }
                    let to_address = addresses[to_index];

                    key_index = (key_index + 1) % priv_keys.len();
                    provider_index = (provider_index + 1) % providers.len();

                    join_set.spawn(async move {
                        let value = U256::from(10_000_000_000_000_000u128); // 0.01 ETH in wei

                        // Build a transaction to send 100 wei from Alice to Bob.
                        // The `from` field is automatically filled to the first signer's address (Alice).
                        let mut tx = alloy::rpc::types::TransactionRequest::default()
                            .to(to_address);

                        tx.set_value(value);
                        tx.set_nonce(provider.get_transaction_count(from_address).await.unwrap());
                        tx.set_chain_id(provider.get_chain_id().await.unwrap());
                        tx.set_max_priority_fee_per_gas(1_000_000_000);
                        tx.set_max_fee_per_gas(20_000_000_000);
                        tx.set_gas_limit(21_000);

                        // Build and sign the transaction using the `EthereumWallet` with the provided wallet.
                        let tx_envelope = tx.build(&wallet).await.unwrap();

                        // Send the raw transaction and retrieve the transaction receipt.
                        // [Provider::send_tx_envelope] is a convenience method that encodes the transaction using
                        // EIP-2718 encoding and broadcasts it to the network using [Provider::send_raw_transaction].

                        //match provider.send_transaction(signed_tx).await {
                        match provider.send_tx_envelope(tx_envelope).await {
                            Ok(pending_tx) => {
                                match pending_tx.get_receipt().await {
                                    Ok(receipt) => {
                                    println!("✅ Transaction sent successfully!: {receipt:?}");
                                    }
                                    Err(e) => {
                                        println!("❌ Failed to get receipt: {e}");
                                    }
                                }
                            }
                            Err(e) => {
                                println!("❌ Failed to send transaction: {e}");
                            }
                        }
                    });
                }
            }
            
            // Await completions
            Some(_result) = join_set.join_next() => {
            }
            
            // Exit condition
            else => break, // JoinSet is empty and we're done spawning
        }
    }

    Ok(())
} 
