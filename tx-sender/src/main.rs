use alloy::{
    primitives::{U256, Address},
    providers::{Provider, ProviderBuilder},
};
use eyre::Result;
use std::time::Duration;
use tokio::task::JoinSet;
use tokio::sync::mpsc;
use alloy::network::TransactionBuilder;
use tx_sender::{utils, MyProvider};
use dashmap::DashMap;

const MAX_CONCURRENT_TASKS: usize = 500;
const NEW_TRANSACTION_INTERVAL: Duration = Duration::from_millis(10);


async fn nonce_manager(providers: Vec<MyProvider>, mut rx: mpsc::Receiver<Address>, nonces: DashMap<Address, u64>) -> Result<()> {
    while let Some(address) = rx.recv().await {
        let provider = providers[utils::random_int(providers.len())].clone();
        if let Ok(nonce) = provider.get_transaction_count(address).await {
            nonces.insert(address, nonce);
        } else {
            println!("Failed to get nonce for address {address}");
        }
    }
    Ok(())
}


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

    let (priv_keys, addresses) = utils::read_keys_from_file("private_keys.txt", None)?;
    let nonces = DashMap::new();

    println!("Get initial nonces...");
    let initial_nonces = utils::get_nonces_concurrent(addresses.clone(), providers.clone(), MAX_CONCURRENT_TASKS).await?;
    println!("Retrieved {} nonces", initial_nonces.len());
    for (address, nonce) in initial_nonces {
        nonces.insert(address, nonce);
    }

    let chain_id = providers[0].get_chain_id().await.unwrap();

    let (tx_nonce, rx_nonce) = mpsc::channel(100);
    tokio::spawn(nonce_manager(providers.clone(), rx_nonce, nonces.clone()));

    let mut join_set = JoinSet::new();
    let mut key_index = 0;
    let mut provider_index = 0;

    let mut send_interval = tokio::time::interval(NEW_TRANSACTION_INTERVAL);
    loop {
        tokio::select! {
            // Add new tasks
            _ = send_interval.tick() => {
                if join_set.len() < MAX_CONCURRENT_TASKS {
                    let wallet = priv_keys[key_index].clone();
                    let from_address = addresses[key_index];
                    let provider = providers[provider_index].clone();

                    let mut to_index = utils::random_int(addresses.len());
                    if from_address == addresses[to_index] {
                        to_index = (to_index + 1) % addresses.len();
                    }
                    let to_address = addresses[to_index];

                    key_index = (key_index + 1) % priv_keys.len();
                    provider_index = (provider_index + 1) % providers.len();

                    let tx_nonce_clone = tx_nonce.clone();
                    let nonces_clone = nonces.clone();
                    join_set.spawn(async move {
                        let value = U256::from(10_000_000_000_000_000u128); // 0.01 ETH in wei

                        // Build a transaction to send 100 wei from Alice to Bob.
                        // The `from` field is automatically filled to the first signer's address (Alice).
                        let mut tx = alloy::rpc::types::TransactionRequest::default()
                            .to(to_address);
                        
                        let nonce = *nonces_clone.get(&from_address).unwrap();
                        // Optimistically increment the nonce
                        nonces_clone.insert(from_address, nonce + 1);

                        tx.set_value(value);
                        tx.set_nonce(nonce);
                        tx.set_chain_id(chain_id);
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
                                // We assume that the transaction failed because the nonce,
                                // so we send the address back to the nonce manager to update the nonce
                                tokio::spawn(async move {
                                    tx_nonce_clone.send(from_address).await.unwrap();
                                });
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
