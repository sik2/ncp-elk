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
              exec 1> >(logger -s -t $(basename $0)) 2>&1
              
              # Update system
              echo "[1/6] Updating system..."
              apt-get update
              apt-get upgrade -y
              
              # Install docker prerequisites
              echo "[2/6] Installing docker prerequisites..."
              apt-get install -y apt-transport-https ca-certificates curl software-properties-common
              
              # Add docker repository
              echo "[3/6] Adding docker repository..."
              curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
              add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
              apt-get update
              
              # Install docker
              echo "[4/6] Installing docker..."
              apt-get install -y docker-ce docker-ce-cli containerd.io
              systemctl enable docker
              systemctl start docker
              
              # Install docker-compose
              echo "[5/6] Installing docker-compose..."
              curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
              chmod +x /usr/local/bin/docker-compose
              
              # Setup and run ELK stack
              echo "[6/6] Setting up ELK stack..."
              mkdir -p /root/elk
              cat > /root/elk/docker-compose.yml << 'DOCKEREOF'
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
              cd /root/elk
              docker-compose up -d
              
              # Check installation
              echo "Installation completed. Checking services..."
              docker ps
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

