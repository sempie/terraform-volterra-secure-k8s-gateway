resource "volterra_cloud_credentials" "this" {
  name        = format("%s-aws-cred", var.skg_name)
  description = format("AWS credential will be used to create site %s", var.skg_name)
  namespace   = "system"
  aws_secret_key {
    access_key = var.aws_access_key
    secret_key {
      clear_secret_info {
        url = "string:///${base64encode(var.aws_secret_key)}"
      }
    }
  }
}

resource "volterra_network_policy_view" "this" {
  name        = format("%s-net-policy", var.skg_name)
  description = format("Network Policy defined for site %s", var.skg_name)
  namespace   = "system"
  endpoint {
    any              = false
    inside_endpoints = false
    prefix_list {
      prefixes = values(var.aws_subnet_eks_cidr)
    }
  }
  ingress_rules {
    rule_name = ""
    metadata {
      name = "allow-eks-node-port-ranges"
    }
    action = "ALLOW"
    any    = true
    protocol_port_range {
      port_ranges = var.eks_port_range
      protocol    = "TCP"
    }
    all_tcp_traffic = false
    all_traffic     = false
    all_udp_traffic = false
    keys            = []
  }
  egress_rules {
    rule_name = ""
    metadata {
      name = "deny-dns-1"
    }
    action = "DENY"
    prefix_list {
      prefixes = var.deny_dns_list
    }
    any = false
    applications {
      applications = ["APPLICATION_DNS"]
    }
    all_tcp_traffic = false
    all_traffic     = false
    all_udp_traffic = false
    keys            = []
  }
  egress_rules {
    rule_name = ""
    metadata {
      name = "allow-dns-2"
    }
    action = "ALLOW"
    prefix_list {
      prefixes = var.allow_dns_list
    }
    any = false
    applications {
      applications = ["APPLICATION_DNS"]
    }
    all_tcp_traffic = false
    all_traffic     = false
    all_udp_traffic = false
    keys            = []
  }
  egress_rules {
    rule_name = ""
    metadata {
      name = "allow-rest-traffic"
    }
    action          = "ALLOW"
    any             = true
    all_tcp_traffic = false
    all_traffic     = true
    all_udp_traffic = false
    keys            = []
  }
}

resource "volterra_forward_proxy_policy" "this" {
  name        = format("%s-proxy-policy", var.skg_name)
  description = format("Fwd Proxy Policy defined for site %s", var.skg_name)
  namespace   = "system"
  any_proxy   = true
  allow_list {
    dynamic "tls_list" {
      for_each = toset(var.allow_tls_prefix_list)
      content {
        suffix_value = tls_list.value
      }
    }
    metadata {
      name = "allow-tls-eks"
    }
    default_action_next_policy = true
    default_action_deny        = false
    default_action_allow       = false
  }
}

resource "volterra_aws_vpc_site" "this" {
  name       = var.skg_name
  namespace  = "system"
  aws_region = var.aws_region
  aws_cred {
    name      = volterra_cloud_credentials.this.name
    namespace = "system"
  }
  vpc {
    vpc_id = aws_vpc.this.id
  }
  disk_size     = var.site_disk_size
  instance_type = var.aws_instance_type

  ingress_egress_gw {
    aws_certified_hw = var.certified_hardware
    az_nodes {
      aws_az_name = var.aws_az
      inside_subnet {
        existing_subnet_id = aws_subnet.volterra_ce["inside"].id
      }
      workload_subnet {
        existing_subnet_id = aws_subnet.volterra_ce["workload"].id
      }
      outside_subnet {
        existing_subnet_id = aws_subnet.volterra_ce["outside"].id
      }
    }
    active_forward_proxy_policies {
      forward_proxy_policies {
        name      = volterra_forward_proxy_policy.this.name
        namespace = "system"
      }
    }
    active_network_policies {
      network_policies {
        name      = volterra_network_policy_view.this.name
        namespace = "system"
      }
    }
    inside_static_routes {
      dynamic "static_route_list" {
        for_each = var.aws_subnet_eks_cidr
        content {
          simple_static_route = static_route_list.value
        }
      }
    }
    no_global_network        = true
    no_outside_static_routes = true
    no_inside_static_routes  = false
    no_network_policy        = false
    no_forward_proxy         = false
  }
  ssh_key = var.ssh_public_key
  lifecycle {
    ignore_changes = [labels]
  }
}

resource "null_resource" "wait_for_aws_mns" {
  triggers = {
    depends = volterra_aws_vpc_site.this.id
  }
}

resource "volterra_tf_params_action" "apply_aws_vpc" {
  depends_on       = [null_resource.wait_for_aws_mns]
  site_name        = var.skg_name
  site_kind        = "aws_vpc_site"
  action           = "apply"
  wait_for_action  = true
  ignore_on_update = true
}
