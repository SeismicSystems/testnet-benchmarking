use alloy::network::TransactionBuilder;
use alloy::{
    consensus::{EthereumTxEnvelope, TxEip4844Variant},
    network::EthereumWallet,
    primitives::{Address, Uint, U256},
    providers::{Provider, ProviderBuilder},
    signers::local::PrivateKeySigner,
};
use clap::Parser;
use eyre::Result;
use hyper::service::{make_service_fn, service_fn};
use hyper::{header::HeaderValue, Body, Request, Response, Server};
use prometheus::{register_counter, Counter, Encoder, TextEncoder};
use std::collections::VecDeque;
use std::sync::Arc;
use std::sync::LazyLock;
use std::time::Duration;
use tokio::task::JoinSet;
use tx_sender::{utils, MyProvider};

#[derive(Parser)]
#[command(author, version, about, long_about = None)]
struct Args {
    /// Instance index for this worker
    #[arg(long)]
    instance_index: usize,

    /// Total number of instances
    #[arg(long)]
    num_instances: usize,

    /// Number of keys to use
    #[arg(long)]
    num_keys: usize,

    /// Port for metrics server
    #[arg(long, default_value = "9090")]
    metrics_port: u16,
}

const MAX_CONCURRENT_TASKS: usize = 400;
const NEW_TRANSACTION_INTERVAL: Duration = Duration::from_millis(20);
const SLEEP_DURATION: Duration = Duration::from_secs(5);
const TIMEOUT_DURATION: Duration = Duration::from_secs(5);
const MAX_RETRY_ATTEMPTS: u32 = 5;
const MAX_GAS_MULTIPLIER: f64 = 10.0;

// Global metrics counters
static TX_SENT: LazyLock<Counter> = LazyLock::new(|| {
    register_counter!("transactions_sent_total", "Total transactions sent").unwrap()
});
static TX_SUCCESS: LazyLock<Counter> = LazyLock::new(|| {
    register_counter!(
        "transactions_successful_total",
        "Total successful transactions"
    )
    .unwrap()
});
static TX_FAILED: LazyLock<Counter> = LazyLock::new(|| {
    register_counter!("transactions_failed_total", "Total failed transactions").unwrap()
});
static TX_RECEIPT_FAILED: LazyLock<Counter> = LazyLock::new(|| {
    register_counter!(
        "transactions_receipt_failed_total",
        "Total receipt failed transactions"
    )
    .unwrap()
});

async fn tx_sender_worker(
    chain_id: u64,
    providers: Arc<Vec<MyProvider>>,
    wallet: EthereumWallet,
    from_address: Address,
    addresses: Arc<Vec<Address>>,
) -> Result<()> {
    let provider = providers[utils::random_int(providers.len())].clone();
    let mut nonce = provider
        .get_transaction_count(from_address)
        .await
        .expect("failed to get initial nonce");

    let value = U256::from(10_000_000_000_000_000u128); // 0.01 ETH in wei
    let mut retry_count = 0u32;
    let mut consecutive_failures = 0u32;
    let base_max_fee = 20_000_000_000u64; // 20 gwei
    let base_priority_fee = 1_000_000_000u64; // 1 gwei
    let mut current_to_address: Option<Address> = None;
    
    loop {
        // Select recipient address only for new transactions (not retries)
        let to_address = if retry_count == 0 {
            let mut to_index = utils::random_int(addresses.len());
            if from_address == addresses[to_index] {
                to_index = (to_index + 1) % addresses.len();
            }
            let addr = addresses[to_index];
            current_to_address = Some(addr);
            addr
        } else {
            // For retries, use the same address as previous attempt
            current_to_address.unwrap()
        };
        // Build a transaction to send 100 wei from Alice to Bob.
        // The `from` field is automatically filled to the first signer's address (Alice).
        let mut tx = alloy::rpc::types::TransactionRequest::default().to(to_address);

        tx.set_value(value);
        tx.set_nonce(nonce);
        tx.set_chain_id(chain_id);

        // Calculate gas fees based on retry count
        let gas_multiplier = if retry_count == 0 {
            1.0
        } else {
            (1.5_f64.powi(retry_count as i32)).min(MAX_GAS_MULTIPLIER)
        };
        
        let max_fee = (base_max_fee as f64 * gas_multiplier) as u64;
        let priority_fee = (base_priority_fee as f64 * gas_multiplier) as u64;
        
        tx.set_max_priority_fee_per_gas(priority_fee.into());
        tx.set_max_fee_per_gas(max_fee.into());
        
        if retry_count > 0 {
            println!("🔄 Retry attempt {}/{} with {}x gas fees (max: {} gwei, priority: {} gwei)", 
                retry_count, MAX_RETRY_ATTEMPTS, gas_multiplier, max_fee / 1_000_000_000, priority_fee / 1_000_000_000);
        }
        tx.set_gas_limit(21_000);

        // Optimistically increment the nonce
        nonce += 1;

        // Build and sign the transaction using the `EthereumWallet` with the provided wallet.
        let tx_envelope = tx.build(&wallet).await.unwrap();

        match provider.send_tx_envelope(tx_envelope).await {
            Ok(pending_tx) => {
                TX_SENT.inc();
                retry_count = 0; // Reset retry count after successful send
                consecutive_failures = 0; // Reset consecutive failures
                match pending_tx.get_receipt().await {
                    Ok(_receipt) => {
                        TX_SUCCESS.inc();
                        //println!("✅ Transaction sent successfully!: {receipt:?}");
                    }
                    Err(e) => {
                        TX_RECEIPT_FAILED.inc();
                        println!("❌ Failed to get receipt: {e}");
                    }
                }
            }
            Err(e) => {
                TX_FAILED.inc();
                retry_count += 1;
                consecutive_failures += 1;
                
                println!("❌ Failed to send transaction (attempt {retry_count}/{MAX_RETRY_ATTEMPTS}): {e}");
                
                // Circuit breaker: pause if too many consecutive failures
                if consecutive_failures >= 10 {
                    println!("🚨 Circuit breaker: too many consecutive failures, pausing for 30 seconds");
                    tokio::time::sleep(TIMEOUT_DURATION).await;
                    consecutive_failures = 0;
                }
                
                // Check if we've exceeded max retries
                if retry_count >= MAX_RETRY_ATTEMPTS {
                    println!("⚠️ Max retry attempts reached, moving to next transaction");
                    retry_count = 0;
                    
                    // Get fresh nonce and continue with next transaction
                    loop {
                        if let Ok(new_nonce) = provider.get_transaction_count(from_address).await {
                            nonce = new_nonce;
                            break;
                        } else {
                            println!("Failed to get nonce for address {from_address}");
                            tokio::time::sleep(SLEEP_DURATION).await;
                        }
                    }
                } else {
                    // Retry with same nonce but higher gas (handled by gas calculation above)
                    nonce -= 1; // Revert the optimistic increment to retry same nonce
                    tokio::time::sleep(Duration::from_millis(1000 * retry_count as u64)).await; // Exponential backoff
                    continue;
                }
            }
        }
        tokio::time::sleep(NEW_TRANSACTION_INTERVAL).await;
    }
}

async fn send_txn_batch(
    providers: Arc<Vec<MyProvider>>,
    txns: Vec<(u64, EthereumTxEnvelope<TxEip4844Variant>)>,
) {
    let txns: VecDeque<(u64, EthereumTxEnvelope<TxEip4844Variant>)> = txns.into();
    let mut futs = Vec::with_capacity(txns.len());
    for (_n, txn) in &txns {
        let provider = providers[utils::random_int(providers.len())].clone();
        let fut = async move {
            match provider.send_tx_envelope(txn.clone()).await {
                Ok(pending_tx) => match pending_tx.get_receipt().await {
                    Ok(receipt) => Ok(receipt),
                    Err(e) => {
                        println!("❌ Failed to get receipt: {e}");
                        Err(e)
                    }
                },
                Err(e) => {
                    println!("❌ Failed to send transaction: {e}");
                    Err(e.into())
                }
            }
        };
        futs.push(fut);
    }
    let _ = futures::future::try_join_all(futs).await;
}

async fn redistribute_wealth(
    chain_id: u64,
    providers: Arc<Vec<MyProvider>>,
    wallets: Vec<EthereumWallet>,
    addresses: Vec<Address>,
    num_keys: usize,
) -> (Vec<EthereumWallet>, Vec<Address>) {
    let mut new_wallets = Vec::with_capacity(num_keys);
    let mut new_addresses = Vec::with_capacity(num_keys);
    for _ in 0..num_keys {
        let priv_key_signer = PrivateKeySigner::random();
        let address = priv_key_signer.address();
        new_addresses.push(address);

        let wallet = EthereumWallet::from(priv_key_signer);
        new_wallets.push(wallet);
    }

    let chunk_size = new_addresses.len().div_ceil(addresses.len());
    let recv_addresses_chunks: Vec<Vec<Address>> = new_addresses
        .chunks(chunk_size)
        .take(new_addresses.len())
        .map(|chunk| chunk.to_vec())
        .collect();

    println!("Get nonces...");
    let nonces = utils::get_nonces_concurrent(&addresses, providers.clone(), MAX_CONCURRENT_TASKS)
        .await
        .expect("failed to get nonces");

    println!("Get balances...");
    let balances =
        utils::get_balances_concurrent(&addresses, providers.clone(), MAX_CONCURRENT_TASKS)
            .await
            .expect("failed to get balances");

    let one_eth = U256::from(1e18 as u128);
    let mut txns = Vec::with_capacity(new_addresses.len());

    for i in 0..recv_addresses_chunks.len() {
        let wallet = wallets[i].clone();
        let from_address = addresses[i];
        let mut nonce = *nonces.get(&from_address).unwrap();

        let chunk = recv_addresses_chunks[i].clone();

        let balance = *balances.get(&from_address).unwrap();

        for to_address in &chunk {
            // Leave one eth for gas
            let ubi_amount = (balance - one_eth) / Uint::from(chunk.len());

            let mut tx = alloy::rpc::types::TransactionRequest::default().to(*to_address);
            tx.set_value(ubi_amount);
            tx.set_nonce(nonce);
            tx.set_chain_id(chain_id);
            tx.set_max_priority_fee_per_gas(1_000_000_000);
            tx.set_max_fee_per_gas(20_000_000_000);
            tx.set_gas_limit(21_000);

            let tx_envelope = tx.build(&wallet).await.unwrap();
            txns.push((nonce, tx_envelope));
            nonce += 1;
        }
    }

    for txn_chunk in txns.chunks(200) {
        println!("Sending batch...");
        send_txn_batch(providers.clone(), txn_chunk.to_vec()).await;
        println!("Sent batch");
    }

    (new_wallets, new_addresses)
}

async fn start_prometheus_server(port: u16) -> Result<()> {
    let make_svc = make_service_fn(move |_| async move {
        Ok::<_, hyper::Error>(service_fn(move |req: Request<Body>| async move {
            let path = req.uri().path();
            if path == "/metrics" || path == "/" {
                let encoder = TextEncoder::new();
                let metric_families = prometheus::gather();
                let mut buffer = Vec::new();
                encoder.encode(&metric_families, &mut buffer).unwrap();

                let mut response = Response::new(Body::from(buffer));
                response.headers_mut().insert(
                    hyper::header::CONTENT_TYPE,
                    HeaderValue::from_static("text/plain; version=0.0.4; charset=utf-8"),
                );
                Ok::<hyper::Response<hyper::Body>, hyper::Error>(response)
            } else {
                let mut response = Response::new(Body::from("Metrics available at /metrics"));
                *response.status_mut() = hyper::StatusCode::NOT_FOUND;
                Ok::<hyper::Response<hyper::Body>, hyper::Error>(response)
            }
        }))
    });

    let addr = ([0, 0, 0, 0], port).into();
    println!("Starting metrics server on http://0.0.0.0:{port}");

    Server::bind(&addr).serve(make_svc).await?;

    Ok(())
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();

    println!(
        "Starting instance {} of {} with {} keys",
        args.instance_index, args.num_instances, args.num_keys
    );

    // Start metrics server
    tokio::spawn(async move {
        if let Err(e) = start_prometheus_server(args.metrics_port).await {
            eprintln!("Metrics server failed: {e}");
        }
    });

    // Parse IP addresses from inventory file
    let inventory_str = include_str!("../inventory.ini");
    let ips = utils::parse_inventory_ips(inventory_str)?;

    let mut providers = Vec::new();
    for ip in ips {
        let rpc_url = format!("http://{ip}:8545").parse()?;
        let provider = ProviderBuilder::new().connect_http(rpc_url);
        providers.push(provider);
    }
    let providers = Arc::new(providers);

    let private_keys_str = include_str!("../private_keys.txt");
    let (priv_keys, addresses) = utils::read_keys_from_file(private_keys_str, None)?;

    let num_key_per_instance = priv_keys.len() / args.num_instances;
    let mut wallet_chunks: Vec<Vec<EthereumWallet>> = priv_keys
        .chunks(num_key_per_instance)
        .map(|chunk| chunk.to_vec())
        .collect();
    let mut addresses_chunks: Vec<Vec<Address>> = addresses
        .chunks(num_key_per_instance)
        .map(|chunk| chunk.to_vec())
        .collect();

    let priv_keys = wallet_chunks.swap_remove(args.instance_index);
    let addresses = addresses_chunks.swap_remove(args.instance_index);

    let chain_id = providers[0].get_chain_id().await.unwrap();
    let (priv_keys, addresses) = redistribute_wealth(
        chain_id,
        providers.clone(),
        priv_keys,
        addresses,
        args.num_keys,
    )
    .await;

    let mut join_set = JoinSet::new();
    let addresses = Arc::new(addresses);
    for i in 0..priv_keys.len() {
        let wallet = priv_keys[i].clone();
        let from_address = addresses[i];
        let addresses_clone = addresses.clone();
        let providers_clone = providers.clone();
        join_set.spawn(async move {
            tx_sender_worker(
                chain_id,
                providers_clone,
                wallet,
                from_address,
                addresses_clone,
            )
            .await
            .expect("failed to run worker");
        });
    }

    loop {
        tokio::select! {
            // Await completions
            Some(_result) = join_set.join_next() => {
            }

            // Exit condition
            else => break, // JoinSet is empty and we're done spawning
        }
    }

    Ok(())
}
