terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.3"
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
  description = "Reguli pentru nodurile K3s (master + worker)"
}

# --- Reguli TCP pentru K3s ---
resource "openstack_networking_secgroup_rule_v2" "k3s_cluster_tcp" {
  for_each = toset([
    "22", "6443", "2379:2380", "10250", "10257", "10259", "30000:32767"
  ])

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = tonumber(split(":", each.key)[0])
  port_range_max    = length(split(":", each.key)) > 1 ? tonumber(split(":", each.key)[1]) : tonumber(each.key)
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k3s_cluster_sg.id
}

# --- Reguli UDP pentru K3s ---
resource "openstack_networking_secgroup_rule_v2" "k3s_cluster_udp" {
  for_each = toset([
    "8472", "51820", "51821"
  ])

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = tonumber(each.key)
  port_range_max    = tonumber(each.key)
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k3s_cluster_sg.id
}

resource "openstack_networking_secgroup_v2" "k3s_lb_sg" {
  name        = "k3s-lb-sg"
  description = "Reguli pentru Load Balancer-ul K3s"
}

# --- Reguli TCP pentru LB ---
resource "openstack_networking_secgroup_rule_v2" "k3s_lb_tcp" {
  for_each = toset([
    "22", "80", "443", "6443"
  ])

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = tonumber(each.key)
  port_range_max    = tonumber(each.key)
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k3s_lb_sg.id
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
%{if can(regex("^lb", name))}${name} ansible_host=${inst.access_ip_v4} ansible_user=root
%{endif~}
%{endfor~}

[master]
%{for name, inst in openstack_compute_instance_v2.itschool_vms~}
%{if can(regex("^master", name))}${name} ansible_host=${inst.access_ip_v4} ansible_user=root
%{endif~}
%{endfor~}

[worker]
%{for name, inst in openstack_compute_instance_v2.itschool_vms~}
%{if can(regex("^worker", name))}${name} ansible_host=${inst.access_ip_v4} ansible_user=root
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
  bucket = "itschool-s3"
  key    = "inventory.ini"
  content = file("${abspath(path.module)}/../ansible/inventory.ini")
}


