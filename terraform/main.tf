terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.3"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket  = "itschool-s3"
    key     = "terraform.tfstate"
    region  = "eu-north-1"
    encrypt = true
  }
}

provider "openstack" {}

provider "aws" {
  region = "eu-north-1"
}

resource "openstack_networking_network_v2" "itschool_network" {
  name = "itschool-network"
}

resource "openstack_networking_subnet_v2" "itschool_subnet" {
  name        = "itschool-subnet"
  network_id  = openstack_networking_network_v2.itschool_network.id
  cidr        = "192.168.10.0/24"
  ip_version  = 4
  gateway_ip  = "192.168.10.1"
  enable_dhcp = true
}

resource "openstack_compute_keypair_v2" "itschool_key" {
  name       = "itschool-key"
  public_key = file("~/.ssh/id_ed25519.pub")
}

resource "openstack_networking_secgroup_v2" "k3s_cluster_sg" {
  name        = "k3s-cluster-sg"
  description = "Reguli pentru nodurile K3s (master + worker) - acces doar intern"
}

# --- Comunicare internă între noduri ---
resource "openstack_networking_secgroup_rule_v2" "k3s_cluster_internal" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 1
  port_range_max    = 65535
  remote_ip_prefix  = "192.168.10.0/24"
  security_group_id = openstack_networking_secgroup_v2.k3s_cluster_sg.id
  description       = "Comunicare completă internă între nodurile clusterului (privată)"
}

# --- Porturi critice pentru K3s (intern only) ---
resource "openstack_networking_secgroup_rule_v2" "k3s_cluster_required" {
  for_each = toset([
    "2379:2380", # etcd
    "6443",      # Kubernetes API server (accesat doar prin LB)
    "10250",     # Kubelet
    "10257",     # Controller Manager
    "10259"      # Scheduler
  ])
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = tonumber(split(":", each.key)[0])
  port_range_max    = length(split(":", each.key)) > 1 ? tonumber(split(":", each.key)[1]) : tonumber(each.key)
  remote_ip_prefix  = "192.168.10.0/24"
  security_group_id = openstack_networking_secgroup_v2.k3s_cluster_sg.id
  description       = "Porturi interne K3s"
}

resource "openstack_networking_secgroup_v2" "k3s_lb_sg" {
  name        = "k3s-lb-sg"
  description = "Reguli pentru Load Balancer-ul K3s"
}

# --- Porturi publice necesare ---
resource "openstack_networking_secgroup_rule_v2" "k3s_lb_public" {
  for_each = toset([
    "22",  # SSH pentru administrare
    "80",  # HTTP
    "443", # HTTPS
    "6443" # K3s API server (redirecționat către mastere)
  ])
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = tonumber(each.key)
  port_range_max    = tonumber(each.key)
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k3s_lb_sg.id
  description       = "Acces public Load Balancer (HTTP/HTTPS/API)"
}

# --- Comunicare între LB și nodurile interne ---
resource "openstack_networking_secgroup_rule_v2" "k3s_lb_internal" {
  direction         = "egress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 1
  port_range_max    = 65535
  remote_ip_prefix  = "192.168.10.0/24"
  security_group_id = openstack_networking_secgroup_v2.k3s_lb_sg.id
  description       = "Permite traficul de la LB către nodurile interne"
}

locals {
  roles = {
    master = {
      count           = 3
      flavor          = "smi.1c-2g"
      image           = "docker-ubuntu-20.04"
      public_network  = true
      private_network = true
      security_groups = [openstack_networking_secgroup_v2.k3s_cluster_sg.name]
    }
    worker = {
      count           = 2
      flavor          = "smi.1c-2g"
      image           = "docker-ubuntu-20.04"
      public_network  = true
      private_network = true
      security_groups = [openstack_networking_secgroup_v2.k3s_cluster_sg.name]
    }
    lb = {
      count           = 1
      flavor          = "smi.2c-4g"
      image           = "minimal-ubuntu-20.04"
      public_network  = true
      private_network = true
      security_groups = [openstack_networking_secgroup_v2.k3s_lb_sg.name]
    }
  }

  instances = merge([
    for role, cfg in local.roles : {
      for i in range(cfg.count) :
      "${role}-${i + 1}" => merge(cfg, { role = role, index = i + 1 })
    }
  ]...)
}

resource "openstack_compute_instance_v2" "itschool_vms" {
  for_each    = local.instances
  name        = each.key
  image_name  = each.value.image
  flavor_name = each.value.flavor
  key_pair    = openstack_compute_keypair_v2.itschool_key.name

  dynamic "network" {
    for_each = each.value.public_network ? [1] : []
    content {
      name = "public"
    }
  }

  dynamic "network" {
    for_each = each.value.private_network ? [1] : []
    content {
      uuid = openstack_networking_network_v2.itschool_network.id
    }
  }

  security_groups = concat(["default"], each.value.security_groups)
}

resource "openstack_dns_zone_v2" "itschool_zone" {
  name        = "itschool.live."
  email       = "admin@itschool.live"
  description = "Zona DNS pentru platforma de monitorizare"
  ttl         = 60
}

resource "openstack_dns_recordset_v2" "itschool_live" {
  zone_id = openstack_dns_zone_v2.itschool_zone.id
  name    = "itschool.live."
  type    = "A"
  ttl     = 60

  # Colectează toate IP-urile din instanțele care au nume ce încep cu "lb"
  records = [
    for name, inst in openstack_compute_instance_v2.itschool_vms :
    inst.access_ip_v4 if can(regex("^lb", name))
  ]

  depends_on = [openstack_compute_instance_v2.itschool_vms]
}

resource "openstack_dns_recordset_v2" "itschool_www" {
  zone_id = openstack_dns_zone_v2.itschool_zone.id
  name    = "www.itschool.live."
  type    = "CNAME"
  ttl     = 60
  records = ["itschool.live."]

  depends_on = [openstack_dns_recordset_v2.itschool_live]
}

output "instance_ips" {
  value = {
    for name, inst in openstack_compute_instance_v2.itschool_vms :
    name => inst.access_ip_v4
  }
}

resource "null_resource" "generate_inventory" {
  provisioner "local-exec" {
    command = <<EOT
mkdir -p ${abspath(path.module)}/../ansible

cat > "${abspath(path.module)}/../ansible/inventory.ini" <<'EOF'
[lb]
%{for name, inst in openstack_compute_instance_v2.itschool_vms~}
%{if can(regex("^lb", name))}${name} ansible_host=${inst.access_ip_v4} ansible_user=root private_ip=${inst.network[1].fixed_ip_v4}
%{endif~}
%{endfor~}

[master]
%{for name, inst in openstack_compute_instance_v2.itschool_vms~}
%{if can(regex("^master", name))}${name} ansible_host=${inst.access_ip_v4} ansible_user=root private_ip=${inst.network[1].fixed_ip_v4}
%{endif~}
%{endfor~}

[worker]
%{for name, inst in openstack_compute_instance_v2.itschool_vms~}
%{if can(regex("^worker", name))}${name} ansible_host=${inst.access_ip_v4} ansible_user=root private_ip=${inst.network[1].fixed_ip_v4}
%{endif~}
%{endfor~}

[all_servers:children]
lb
master
worker
EOF
EOT
  }

  triggers = {
    always_run = timestamp()
  }

  depends_on = [openstack_compute_instance_v2.itschool_vms]
}

resource "aws_s3_object" "inventory" {
  bucket       = "itschool-s3"
  key          = "inventory.ini"
  source       = "${abspath(path.module)}/../ansible/inventory.ini"
  content_type = "text/plain"

  lifecycle {
    ignore_changes = [etag, content]
  }

  depends_on = [null_resource.generate_inventory]
}


