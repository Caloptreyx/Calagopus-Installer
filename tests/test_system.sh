# shellcheck shell=bash
# OS detection, requirements, network and DNS verdicts, firewall ports.

os_case() {
  local file="$1" arch="$2" expected="$3" id version
  id="$(cala_os_release_value "$FIXTURES/os-release/$file" ID)"
  version="$(cala_os_release_value "$FIXTURES/os-release/$file" VERSION_ID)"
  if cala_os_supported "$id" "$version" "$arch"; then
    assert_eq supported "$expected" "$file $arch"
  else
    assert_eq unsupported "$expected" "$file $arch"
  fi
}

test_os_support_matrix() {
  os_case ubuntu-22.04 x86_64 supported
  os_case ubuntu-24.04 aarch64 supported
  os_case ubuntu-26.04 x86_64 supported
  os_case debian-12 x86_64 supported
  os_case debian-13 aarch64 supported
  os_case rocky-9.6 x86_64 supported
  os_case almalinux-10.0 x86_64 supported
  os_case ubuntu-20.04 x86_64 unsupported
  os_case fedora-41 x86_64 unsupported
  os_case linuxmint-22 x86_64 unsupported
  os_case debian-12 armv7l unsupported
  os_case ubuntu-24.04 riscv64 unsupported
}

test_os_release_parsing() {
  assert_eq "$(cala_os_release_value "$FIXTURES/os-release/rocky-9.6" ID)" rocky
  assert_eq "$(cala_os_release_value "$FIXTURES/os-release/almalinux-10.0" ID)" almalinux
  assert_eq "$(cala_os_release_value "$FIXTURES/os-release/debian-13" PRETTY_NAME)" "Debian GNU/Linux 13 (trixie)"
  assert_eq "$(cala_os_release_value "$FIXTURES/os-release/debian-13" MISSING)" ""
}

test_detect_os_family_from_id_like() {
  local OS_ID OS_VERSION OS_NAME OS_ARCH OS_FAMILY
  CALA_OS_RELEASE="$FIXTURES/os-release/linuxmint-22" cala_detect_os
  assert_eq "$OS_FAMILY" debian
  CALA_OS_RELEASE="$FIXTURES/os-release/rocky-9.6" cala_detect_os
  assert_eq "$OS_FAMILY" rhel
  CALA_OS_RELEASE="$FIXTURES/os-release/fedora-41" cala_detect_os
  assert_eq "$OS_FAMILY" ""
}

test_unsupported_os_refused_unless_overridden() {
  local out
  out="$(CALA_OS_RELEASE="$FIXTURES/os-release/ubuntu-20.04" CALA_SKIP_OS_CHECK=no cala_check_os 2>&1)" &&
    fail "ubuntu 20.04 was accepted"
  assert_contains "$out" "CALA_SKIP_OS_CHECK"
  out="$(CALA_OS_RELEASE="$FIXTURES/os-release/ubuntu-20.04" CALA_SKIP_OS_CHECK=yes cala_check_os 2>&1)" ||
    fail "override did not work: $out"
}

test_package_names() {
  assert_eq "$(cala_package_for dig debian)" bind9-dnsutils
  assert_eq "$(cala_package_for dig rhel)" bind-utils
  assert_eq "$(cala_package_for ss rhel)" iproute
  assert_eq "$(cala_package_for jq debian)" jq
}

test_requirements_verdict() {
  local out
  out="$(cala_requirements_verdict 4000 40000 no)"
  assert_eq "$out" ok
  out="$(cala_requirements_verdict 512 40000 no)"
  assert_contains "$out" "fail 512 MB RAM"
  out="$(cala_requirements_verdict 1024 40000 no)"
  assert_contains "$out" "warn 1024 MB RAM"
  out="$(cala_requirements_verdict 4000 8000 yes)"
  assert_contains "$out" "fail 8000 MB free disk"
  out="$(cala_requirements_verdict 4000 8000 no)"
  assert_contains "$out" "warn 8000 MB free disk"
}

test_extension_memory() {
  assert_ok cala_extension_memory_ok 4000 0
  assert_ok cala_extension_memory_ok 2000 2048
  assert_fails cala_extension_memory_ok 2000 1000
}

test_cidr_and_cloudflare() {
  assert_ok cala_ipv4_in_cidr 172.18.0.1 172.16.0.0/12
  assert_fails cala_ipv4_in_cidr 172.32.0.1 172.16.0.0/12
  assert_ok cala_ipv4_in_cidr 8.8.8.8 0.0.0.0/0
  assert_ok cala_is_cloudflare_ipv4 104.21.12.34
  assert_ok cala_is_cloudflare_ipv4 172.67.1.1
  assert_fails cala_is_cloudflare_ipv4 203.0.113.10
  assert_ok cala_is_private_ipv4 192.168.1.5
  assert_fails cala_is_private_ipv4 203.0.113.10
}

test_dns_verdict() {
  assert_eq "$(cala_dns_verdict "203.0.113.10 " "" 203.0.113.10 "")" ok
  assert_eq "$(cala_dns_verdict "" "" 203.0.113.10 "")" no_a
  assert_eq "$(cala_dns_verdict "198.51.100.7 " "" 203.0.113.10 "")" "a_mismatch 198.51.100.7"
  assert_eq "$(cala_dns_verdict "104.21.12.34 172.67.1.1 " "" 203.0.113.10 "")" "$(printf 'cloudflare 104.21.12.34\ncloudflare 172.67.1.1')"
  assert_eq "$(cala_dns_verdict "203.0.113.10 " "2001:db8::1 " 203.0.113.10 "")" "stray_aaaa 2001:db8::1"
  assert_eq "$(cala_dns_verdict "203.0.113.10 " "2001:DB8::1 " 203.0.113.10 "2001:db8::1")" ok
  assert_eq "$(cala_dns_verdict "203.0.113.10 " "2001:db8::2 " 203.0.113.10 "2001:db8::1")" "aaaa_mismatch 2001:db8::2"
}

test_ssh_ports() {
  assert_eq "$(cala_ssh_ports_from "" "")" 22
  assert_eq "$(cala_ssh_ports_from $'port 2222\nlistenaddress 0.0.0.0' "")" 2222
  assert_eq "$(cala_ssh_ports_from $'port 22\nport 2222' "198.51.100.2 51000 203.0.113.10 2222")" "22 2222"
  assert_eq "$(cala_ssh_ports_from "" "198.51.100.2 51000 203.0.113.10 4422")" 4422
}

test_firewall_ports() {
  assert_eq "$(cala_firewall_tcp_ports aio "" 22)" "22 8000 2022"
  assert_eq "$(cala_firewall_tcp_ports aio panel.example.com "22 2222")" "22 2222 80 443 2022"
  assert_eq "$(cala_firewall_tcp_ports panel "" 22)" "22 8000"
  assert_eq "$(cala_firewall_tcp_ports wings "" 22)" "22 8080 2022"
  assert_eq "$(cala_firewall_port_spec 25570-25580 ufw)" 25570:25580
  assert_eq "$(cala_firewall_port_spec 25570-25580 firewalld)" 25570-25580
}
