## Directories
- `terraform`: Scripts that are used to provision EC2 instances. Mainly spin up N instances across K regions.
-  `ansible` - Scripts that are used to deploy the `seismic-reth` and `seismic-consensus` Docker images to the EC2 instances, pull logs from the EC2 instances, etc.
- `seismic-reth`: Dockerfile for seismic-reth. Pulls the latest version from Github.
- `seismic-consensus`: Dockerfile for seismic-consensus. Pulls the latest version from Github.
- `tx-sender`: Transaction spammer. 

# Getting started
Follow these instructions to spin up a testnet and spam it with transactions.

### 1. Installation
1. Install [terraform](https://developer.hashicorp.com/terraform/installhttp:// "terraform") on your local machine 
2. Install [ansible](https://docs.ansible.com/ansible/latest/installation_guide/index.html "ansible") on your local machine
3. Install [Rust](https://rustup.rs/ "Rust") on your local machine
4. Install [Prometheus](https://prometheus.io/docs/prometheus/latest/getting_started/ "Prometheus")
5. Install [Grafana](https://grafana.com/docs/grafana/latest/setup-grafana/installation/ "Grafana")

### 2. Setup
Make sure that you have valid AWS credentials at `~/.aws/credentials`. The file should look something like this:
```
[default]
aws_access_key_id = ...
aws_secret_access_key = ...
aws_session_token = ...
```

### 3. Deploy EC2 instances
In `terraform/terraform.tfvars`, you can specify the number of instances, and the different regions:
```
regions = ["us-west-2", "eu-central-1", "us-east-1", "ap-northeast-1", "sa-east-1"]
instances_per_region = 4

```
You also have to provide the path to your ssh pubkey that will be copied to the servers:

```
ssh_public_key_path = "~/.ssh/id_ed25519.pub"
```

Finally, run the terraform commands:
```sh
cd terraform
terraform init
terraform plan
terraform apply
```

### 4. Deploy the Docker containers
After deploying the EC2 instances, we use the terraform output to create the ansible inventory file.
Provide your ssh pubkey and the jwt secret in `ansible/generate_inventory.sh`:
```
[ec2_instances:vars]
ansible_ssh_private_key_file=~/.ssh/id_ed25519
jwt_secret=...
```
Generate the `inventory.ini`:
```sh
cd ansible
chmod +x generate_inventory.sh
./generate_inventory.sh
```

There are two options. You can either build the Docker image on each instance, or build the image locally, and then ship the pre-built image to the EC2 instances.
Building locally and then shipping the pre-built image will be much faster (unless your laptop is old), however, it requires you to install Docker locally.

#### Option 1: Ship the pre-built images
Build the images (you have to only do this the first time, or when updating repos):
```sh
cd ../summit
docker build -t summit .
docker save summit > ../summit.tar
```
```sh
cd ../seismic-reth/
docker build -t seismic-reth .
docker save seismic-reth > ../seismic-reth.tar
```

Deploy the seismic-reth image first:
```sh
ansible-playbook -i inventory.ini deploy-seismic-reth.yml -e "pre_built_image_tar=../seismic-reth.tar" -e "jwt_secret=..."  -e "force_rebuild=true"
```
Then deploy the summit image:
```sh
ansible-playbook -i inventory.ini deploy-summit.yml \
  -e "pre_built_image_tar=../summit.tar" \
  -e "engine_jwt=..." \
  -e "base_port=8080" \
  -e "base_prom_port=9090" \
  -e "clear_state=true" \
  -e "force_rebuild=true"
```

#### Option 2: Build the images on the instances
For seismic-reth:
```sh
ansible-playbook -i inventory.ini deploy-seismic-reth.yml -e "jwt_secret=..."  -e "force_rebuild=true"
```
For summit:
```sh
ansible-playbook -i inventory.ini deploy-summit.yml \
  -e "engine_jwt=..." \
  -e "base_port=8080" \
  -e "base_prom_port=9090" \
  -e "clear_state=true" \
  -e "force_rebuild=true"
```

### 5. Spam transactions
In `terraform-spamnet/terraform.tfvars`, you can specify the number of instances, and the different regions:
```
regions = ["us-west-2", "eu-central-1", "us-east-1", "ap-northeast-1", "sa-east-1"]
instances_per_region = 4
```

You also have to provide the path to your ssh pubkey that will be copied to the servers:

```
ssh_public_key_path = "~/.ssh/id_ed25519.pub"
```

Finally, run the terraform commands:
```sh
cd terraform-spamnet
terraform init
terraform plan
terraform apply
```

Build the Docker image:
(You can skip these steps if you want to build Docker image on the instances)
```sh
cd tx-sender
cp ../ansible/inventory.ini .
docker build -t tx-sender .
docker save tx-sender > ../tx-sender.tar
```

Generate the `inventory_spamnet.ini`:
```sh
cd ../ansible
./generate_inventory.sh
```

Deploy tx-sender:
```sh
ansible-playbook -i inventory_spamnet.ini deploy-tx-sender.yml -e "num_keys=2000" -e "pre_built_image_tar=../tx-sender.tar"
```
If you didn't built the Docker image, drop the `pre_built_image_tar` flag

### 6. Prometheus
Generate the Prometheus config from the terraform output:
```sh
chmod +x generate_prometheus.sh
./generate_prometheus.sh
```
Start Prometheus:
```sh
prometheus --config.file=prometheus.yml
```
Check that we are collecting metrics at http://localhost:9090/targets

### 7. Grafana
Start Grafana server:
```sh
sudo systemctl daemon-reload
sudo systemctl start grafana-server
```
Open Grafana dashboard at http://localhost:3000/ and select Prometheus as a data source.

