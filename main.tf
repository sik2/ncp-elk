terraform {
  required_providers {
    ncloud = {
      source  = "NaverCloudPlatform/ncloud"
      version = "3.3.0"
    }
  }
}

provider "ncloud" {
  support_vpc = true
  access_key  = var.access_key
  secret_key  = var.secret_key
  region      = var.region
}

# VPC 생성
resource "ncloud_vpc" "vpc_1" {
  name            = "${var.prefix}-vpc"
  ipv4_cidr_block = "10.0.0.0/16"
}

# 서브넷 생성
resource "ncloud_subnet" "subnet_1" {
  vpc_no          = ncloud_vpc.vpc_1.vpc_no
  name            = "${var.prefix}-subnet"
  subnet          = "10.0.1.0/24"
  zone            = var.zone
  network_acl_no  = ncloud_vpc.vpc_1.default_network_acl_no
  subnet_type     = "PUBLIC"
}

# 퍼블릭 IP 생성
resource "ncloud_public_ip" "public_ip_1" {
  server_instance_no = ncloud_server.server_1.id
}

# 보안 그룹 생성
resource "ncloud_access_control_group" "sg_1" {
  name   = "${var.prefix}-sg"
  vpc_no = ncloud_vpc.vpc_1.vpc_no
}

# 보안 그룹 규칙 추가
resource "ncloud_access_control_group_rule" "sg_rule_ssh" {
  access_control_group_no = ncloud_access_control_group.sg_1.id
  inbound {
    protocol    = "TCP"
    ip_block    = "0.0.0.0/0"
    port_range  = "22"
    description = "SSH Access"
  }
}

resource "ncloud_access_control_group_rule" "sg_rule_es" {
  access_control_group_no = ncloud_access_control_group.sg_1.id
  inbound {
    protocol    = "TCP"
    ip_block    = "0.0.0.0/0"
    port_range  = "9200"
    description = "Elasticsearch Access"
  }
}

resource "ncloud_access_control_group_rule" "sg_rule_kibana" {
  access_control_group_no = ncloud_access_control_group.sg_1.id
  inbound {
    protocol    = "TCP"
    ip_block    = "0.0.0.0/0"
    port_range  = "5601"
    description = "Kibana Access"
  }
}

resource "ncloud_access_control_group_rule" "sg_rule_logstash" {
  access_control_group_no = ncloud_access_control_group.sg_1.id
  inbound {
    protocol    = "TCP"
    ip_block    = "0.0.0.0/0"
    port_range  = "5044"
    description = "Logstash Access"
  }
}

resource "ncloud_access_control_group_rule" "sg_rule_all_outbound" {
  access_control_group_no = ncloud_access_control_group.sg_1.id
  outbound {
    protocol    = "TCP"
    ip_block    = "0.0.0.0/0"
    port_range  = "1-65535"
    description = "Allow All Outbound"
  }
}

# Init script 생성
resource "ncloud_init_script" "init" {
  name    = "${var.prefix}-init"
  content = <<-EOF
              #!/bin/bash
              
              # Setup logging
              exec 1> >(tee -a "/var/log/user-data.log") 2>&1
              
              echo "[INFO] Starting installation..."
              
              # Update system and install docker
              echo "[INFO] Installing Docker..."
              sudo apt-get update
              sudo apt-get install -y docker.io
              
              # Start and enable Docker
              echo "[INFO] Starting Docker service..."
              sudo systemctl start docker
              sudo systemctl enable docker
              
              # Install Docker Compose
              echo "[INFO] Installing Docker Compose..."
              sudo apt-get install -y docker-compose
              
              # Create directory for ELK
              echo "[INFO] Setting up ELK stack..."
              sudo mkdir -p /root/elk
              
              # Create docker-compose.yml
              sudo cat > /root/elk/docker-compose.yml << 'DOCKEREOF'
              version: '3'
              services:
                elasticsearch:
                  image: docker.elastic.co/elasticsearch/elasticsearch:8.3.3
                  container_name: elasticsearch
                  environment:
                    - discovery.type=single-node
                    - xpack.security.enabled=false
                    - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
                  ulimits:
                    memlock:
                      soft: -1
                      hard: -1
                  ports:
                    - "9200:9200"
                  networks:
                    - elastic
                
                kibana:
                  image: docker.elastic.co/kibana/kibana:8.3.3
                  container_name: kibana
                  environment:
                    - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
                  ports:
                    - "5601:5601"
                  depends_on:
                    - elasticsearch
                  networks:
                    - elastic
              
              networks:
                elastic:
                  driver: bridge
              DOCKEREOF
              
              # Run docker-compose
              echo "[INFO] Starting containers..."
              cd /root/elk
              sudo docker-compose up -d
              
              # Check installation
              echo "[INFO] Checking container status..."
              sudo docker ps
              
              echo "[INFO] Installation completed!"
              EOF
}

# 서버 생성
resource "ncloud_server" "server_1" {
  subnet_no                 = ncloud_subnet.subnet_1.id
  name                      = "${var.prefix}-server"
  server_image_product_code = var.server_image_product_code
  server_product_code       = var.server_product_code
  login_key_name           = var.login_key_name
  init_script_no           = ncloud_init_script.init.id
}

