use alloy::{
    network::EthereumWallet,
    primitives::Address,
    signers::local::PrivateKeySigner,
};
use eyre::Result;
use std::fs;
use rand::Rng;

/// Parse IP addresses from ansible inventory file
pub fn parse_inventory_ips(inventory_path: &str) -> Result<Vec<String>> {
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
pub fn random_int(n: usize) -> usize {
    let mut rng = rand::thread_rng();
    rng.gen_range(0..n)
}

/// Read private keys and addresses from a CSV file
pub fn read_keys_from_file(file_path: &str) -> Result<(Vec<EthereumWallet>, Vec<Address>)> {
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

        bar.inc(1);
    }
    bar.finish();
    
    Ok((keys, addresses))
}