use alloy::{
    network::EthereumWallet,
    primitives::{Address, U256},
    providers::{Provider, ProviderBuilder},
    signers::local::PrivateKeySigner,
};
use eyre::Result;
use std::time::Duration;
use tokio;
use std::fs;
use rand::Rng;
use tokio::task::JoinSet;
use std::str::FromStr;
use alloy::network::TransactionBuilder;


/// Parse IP addresses from ansible inventory file
fn parse_inventory_ips(inventory_path: &str) -> Result<Vec<String>> {
    let content = fs::read_to_string(inventory_path)?;
    let mut ips = Vec::new();
    
    for line in content.lines() {
        let line = line.trim();
        if line.starts_with("instance-") && line.contains("ansible_host=") {
            // Extract IP address from line like: instance-0 ansible_host=35.94.11.26 ansible_user=ec2-user
            if let Some(host_part) = line.split_whitespace().find(|part| part.starts_with("ansible_host=")) {
                if let Some(ip) = host_part.strip_prefix("ansible_host=") {
                    ips.push(ip.to_string());
                }
            }
        }
    }
    
    Ok(ips)
}

/// Generate a random integer in range 0 to n 
fn random_int(n: usize) -> usize {
    let mut rng = rand::thread_rng();
    rng.gen_range(0..n)
}

/// Read private keys and addresses from a CSV file
fn read_keys_from_file(file_path: &str) -> Result<(Vec<EthereumWallet>, Vec<Address>)> {
    let content = fs::read_to_string(file_path)?;
    let mut keys = Vec::new();
    let mut addresses = Vec::new();

    let bar = indicatif::ProgressBar::new(content.lines().count() as u64);
    
    let mut counter = 0;
    for (line_num, line) in content.lines().enumerate() {

        counter += 1;
        if counter > 100 {
            break;
        }

        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue; // Skip empty lines and comments
        }
        
        let parts: Vec<&str> = line.split(',').collect();
        if parts.len() != 2 {
            return Err(eyre::eyre!("Invalid format on line {}: expected 'private_key,address'", line_num + 1));
        }
        
        let private_key = parts[0].trim();
        let address_str = parts[1].trim();
        
        // Validate private key format (remove 0x prefix if present)
        let private_key = if private_key.starts_with("0x") {
            &private_key[2..]
        } else {
            private_key
        };

        let private_key_bytes = hex::decode(private_key)?;
        let private_key_fixed = alloy::primitives::FixedBytes::from_slice(&private_key_bytes);
        let signer: PrivateKeySigner = PrivateKeySigner::from_bytes(&private_key_fixed)?;
        let wallet = EthereumWallet::from(signer);
        keys.push(wallet);
        
        let address_str = if address_str.starts_with("0x") {
            &address_str[2..]
        } else {
            address_str
        };

        let address_bytes = hex::decode(address_str)?;
        let address_bytes: [u8; 20] = address_bytes.try_into().unwrap();
        let address = Address::new(address_bytes);
        addresses.push(address);

        bar.inc(1);
    }
    bar.finish();
    
    Ok((keys, addresses))
}

#[tokio::main]
async fn main() -> Result<()> {

    // Parse IP addresses from inventory file
    let ips = parse_inventory_ips("../ansible/inventory.ini")?;
    let mut providers = Vec::new();
    for ip in ips {
        let rpc_url = format!("http://{}:8545", ip).parse()?;
        let provider = ProviderBuilder::new().connect_http(rpc_url);
        providers.push(provider);
    }

    let max_concurrent_tasks = 500;
    let new_transaction_interval = Duration::from_millis(500);

    let (priv_keys, addresses) = read_keys_from_file("private_keys.txt")?;

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
                    println!("Address {}", from_address);

                    let mut to_index = random_int(addresses.len());
                    if from_address == addresses[to_index] {
                        to_index = (to_index + 1) % addresses.len();
                    }
                    let to_address = addresses[to_index];

                    key_index = (key_index + 1) % priv_keys.len();
                    provider_index = (provider_index + 1) % providers.len();

                    join_set.spawn(async move {
                        let value = U256::from(10_000_000_000_000_000u128); // 0.01 ETH in wei
                        let tx = alloy::rpc::types::TransactionRequest::default()
                            .from(from_address)
                            .to(to_address)
                            .value(value);


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
                                    println!("✅ Transaction sent successfully!: {:?}", receipt);
                                    }
                                    Err(e) => {
                                        println!("❌ Failed to get receipt: {}", e);
                                    }
                                }
                            }
                            Err(e) => {
                                println!("❌ Failed to send transaction: {}", e);
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
