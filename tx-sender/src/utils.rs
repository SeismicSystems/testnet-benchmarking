use crate::MyProvider;
use alloy::{
    network::EthereumWallet,
    primitives::{Address, U256},
    providers::Provider,
    signers::local::PrivateKeySigner,
};
use eyre::Result;
use rand::Rng;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::task::JoinSet;

/// Parse IP addresses from ansible inventory file
pub fn parse_inventory_ips(inventory: &str) -> Result<Vec<String>> {
    let mut ips = Vec::new();
    let lines = inventory.split("\n");

    for line in lines {
        let line = line.trim();
        if line.starts_with("instance-") && line.contains("ansible_host=") {
            // Extract IP address from line like: instance-0 ansible_host=35.94.11.26 ansible_user=ec2-user
            if let Some(host_part) = line
                .split_whitespace()
                .find(|part| part.starts_with("ansible_host="))
            {
                if let Some(ip) = host_part.strip_prefix("ansible_host=") {
                    ips.push(ip.to_string());
                }
            }
        }
    }

    Ok(ips)
}

/// Generate a random integer in range 0 to n
pub fn random_int(n: usize) -> usize {
    let mut rng = rand::thread_rng();
    rng.gen_range(0..n)
}

/// Read private keys and addresses from a CSV file
pub fn read_keys_from_file(
    file_content: &str,
    limit: Option<usize>,
) -> Result<(Vec<EthereumWallet>, Vec<Address>)> {
    let mut keys = Vec::new();
    let mut addresses = Vec::new();

    let lines = file_content.split("\n");

    for (counter, (line_num, line)) in lines.enumerate().enumerate() {
        if let Some(limit) = limit {
            if counter > limit {
                break;
            }
        }

        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue; // Skip empty lines and comments
        }

        let parts: Vec<&str> = line.split(',').collect();
        if parts.len() != 2 {
            return Err(eyre::eyre!(
                "Invalid format on line {}: expected 'private_key,address'",
                line_num + 1
            ));
        }

        let private_key = parts[0].trim();
        let address_str = parts[1].trim();

        // Validate private key format (remove 0x prefix if present)
        let private_key = if let Some(private_key) = private_key.strip_prefix("0x") {
            private_key
        } else {
            private_key
        };

        let private_key_bytes = hex::decode(private_key)?;
        let private_key_fixed = alloy::primitives::FixedBytes::from_slice(&private_key_bytes);
        let signer: PrivateKeySigner = PrivateKeySigner::from_bytes(&private_key_fixed)?;
        let wallet = EthereumWallet::from(signer);
        keys.push(wallet);

        let address_str = if let Some(address_str) = address_str.strip_prefix("0x") {
            address_str
        } else {
            address_str
        };

        let address_bytes = hex::decode(address_str)?;
        let address_bytes: [u8; 20] = address_bytes.try_into().unwrap();
        let address = Address::new(address_bytes);
        addresses.push(address);
    }

    Ok((keys, addresses))
}

/// Request current nonces for a list of addresses using round-robin provider selection
/// with controlled concurrency
pub async fn get_nonces_concurrent(
    addresses: &[Address],
    providers: Arc<Vec<MyProvider>>,
    max_concurrent_req: usize,
) -> Result<HashMap<Address, u64>> {
    let mut results = HashMap::new();
    let mut join_set = JoinSet::new();
    let mut provider_index = 0;
    let mut address_index = 0;

    // Process addresses in batches to control concurrency
    while address_index < addresses.len() {
        // Spawn up to max_concurrent_req tasks
        while join_set.len() < max_concurrent_req && address_index < addresses.len() {
            let address = addresses[address_index];
            let provider = providers[provider_index].clone();

            join_set.spawn(async move {
                match provider.get_transaction_count(address).await {
                    Ok(nonce) => Ok((address, nonce)),
                    Err(e) => Err(eyre::eyre!("Failed to get nonce for {}: {}", address, e)),
                }
            });

            address_index += 1;
            provider_index = (provider_index + 1) % providers.len();
        }

        // Wait for some tasks to complete
        if let Some(result) = join_set.join_next().await {
            match result {
                Ok(Ok((address, nonce))) => {
                    results.insert(address, nonce);
                }
                Ok(Err(e)) => {
                    eprintln!("Error getting nonce: {e}");
                }
                Err(e) => {
                    eprintln!("Task join error: {e}");
                }
            }
        }
    }

    // Wait for remaining tasks
    while let Some(result) = join_set.join_next().await {
        match result {
            Ok(Ok((address, nonce))) => {
                results.insert(address, nonce);
            }
            Ok(Err(e)) => {
                eprintln!("Error getting nonce: {e}");
            }
            Err(e) => {
                eprintln!("Task join error: {e}");
            }
        }
    }

    Ok(results)
}

/// Request current balances for a list of addresses using round-robin provider selection
/// with controlled concurrency
pub async fn get_balances_concurrent(
    addresses: &[Address],
    providers: Arc<Vec<MyProvider>>,
    max_concurrent_req: usize,
) -> Result<HashMap<Address, U256>> {
    let mut results = HashMap::new();
    let mut join_set = JoinSet::new();
    let mut provider_index = 0;
    let mut address_index = 0;

    // Process addresses in batches to control concurrency
    while address_index < addresses.len() {
        // Spawn up to max_concurrent_req tasks
        while join_set.len() < max_concurrent_req && address_index < addresses.len() {
            let address = addresses[address_index];
            let provider = providers[provider_index].clone();

            join_set.spawn(async move {
                match provider.get_balance(address).await {
                    Ok(balance) => Ok((address, balance)),
                    Err(e) => Err(eyre::eyre!("Failed to get balance for {}: {}", address, e)),
                }
            });

            address_index += 1;
            provider_index = (provider_index + 1) % providers.len();
        }

        // Wait for some tasks to complete
        if let Some(result) = join_set.join_next().await {
            match result {
                Ok(Ok((address, balance))) => {
                    results.insert(address, balance);
                }
                Ok(Err(e)) => {
                    eprintln!("Error getting balance: {e}");
                }
                Err(e) => {
                    eprintln!("Task join error: {e}");
                }
            }
        }
    }

    // Wait for remaining tasks
    while let Some(result) = join_set.join_next().await {
        match result {
            Ok(Ok((address, balance))) => {
                results.insert(address, balance);
            }
            Ok(Err(e)) => {
                eprintln!("Error getting balance: {e}");
            }
            Err(e) => {
                eprintln!("Task join error: {e}");
            }
        }
    }

    Ok(results)
}
