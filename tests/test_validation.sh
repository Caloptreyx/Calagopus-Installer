# shellcheck shell=bash
# Input validators.

test_email() {
  assert_ok cala_valid_email admin@example.com
  assert_ok cala_valid_email first.last+tag@mail.example.co.uk
  assert_fails cala_valid_email ""
  assert_fails cala_valid_email admin
  assert_fails cala_valid_email "admin@localhost"
  assert_fails cala_valid_email "ad min@example.com"
  assert_fails cala_valid_email 'a"b@example.com'
}

test_username_follows_panel_rule() {
  assert_ok cala_valid_username admin
  assert_ok cala_valid_username Admin_01
  assert_fails cala_valid_username ab
  assert_fails cala_valid_username "with space"
  assert_fails cala_valid_username "dash-name"
  assert_fails cala_valid_username "$(printf 'a%.0s' {1..49})"
}

test_password_length() {
  assert_ok cala_valid_password 12345678
  assert_ok cala_valid_password 'p4ss w0rd "quoted" and \backslash'
  assert_fails cala_valid_password 1234567
  assert_fails cala_valid_password "$(printf 'a%.0s' {1..513})"
  assert_fails cala_valid_password $'line\nbreak1'
}

test_domain() {
  assert_ok cala_valid_domain panel.example.com
  assert_ok cala_valid_domain Panel.Example.COM
  assert_ok cala_valid_domain a-b.example.io
  assert_fails cala_valid_domain example
  assert_fails cala_valid_domain "-bad.example.com"
  assert_fails cala_valid_domain "bad-.example.com"
  assert_fails cala_valid_domain "http://example.com"
  assert_fails cala_valid_domain "203.0.113.10"
  assert_ok cala_valid_domain_or_empty ""
  assert_fails cala_valid_domain_or_empty "not a domain"
}

test_ipv4() {
  assert_ok cala_valid_ipv4 203.0.113.10
  assert_ok cala_valid_ipv4 0.0.0.0
  assert_ok cala_valid_ipv4 255.255.255.255
  assert_fails cala_valid_ipv4 256.1.1.1
  assert_fails cala_valid_ipv4 1.2.3
  assert_fails cala_valid_ipv4 01.2.3.4
  assert_fails cala_valid_ipv4 "1.2.3.4 "
  assert_ok cala_valid_ipv6 2001:db8::1
  assert_fails cala_valid_ipv6 203.0.113.10
}

test_ports() {
  assert_ok cala_valid_port 22
  assert_ok cala_valid_port 65535
  assert_fails cala_valid_port 0
  assert_fails cala_valid_port 65536
  assert_fails cala_valid_port 022
  assert_ok cala_valid_port_list 25565
  assert_ok cala_valid_port_list "25565,25570-25580"
  assert_ok cala_valid_port_list "25565, 19132"
  assert_fails cala_valid_port_list "25580-25570"
  assert_fails cala_valid_port_list "25565,"
  assert_fails cala_valid_port_list "25565,,1"
  assert_fails cala_valid_port_list "abc"
  assert_fails cala_valid_port_list ""
  assert_ok cala_valid_port_list_or_empty ""
  assert_ok cala_valid_port_list_spaces "22 2222"
  assert_fails cala_valid_port_list_spaces "22 x"
}

test_timezone() {
  assert_ok cala_valid_timezone UTC
  assert_ok cala_valid_timezone Europe/Berlin
  assert_fails cala_valid_timezone "Europe/Berlin; rm -rf /"
  assert_fails cala_valid_timezone "../etc/passwd"
  assert_fails cala_valid_timezone ""
}

test_install_dir() {
  assert_ok cala_valid_install_dir /opt/calagopus-panel
  assert_ok cala_valid_install_dir /srv/cala
  assert_fails cala_valid_install_dir opt/calagopus
  assert_fails cala_valid_install_dir /opt/calagopus/
  assert_fails cala_valid_install_dir "/opt/with space"
  assert_fails cala_valid_install_dir /opt/../etc
  assert_fails cala_valid_install_dir /
  assert_fails cala_valid_install_dir /etc
  assert_fails cala_valid_install_dir /opt
}

test_urls_and_codes() {
  assert_ok cala_valid_url https://panel.example.com
  assert_ok cala_valid_url http://203.0.113.10:8000
  assert_fails cala_valid_url https://panel.example.com/
  assert_fails cala_valid_url ftp://panel.example.com
  assert_fails cala_valid_url "https://panel.example.com/a b"
  assert_ok cala_valid_url_or_empty ""
  assert_ok cala_valid_enroll_code AbC123-_x
  assert_fails cala_valid_enroll_code "bad code"
  assert_fails cala_valid_enroll_code "a'b"
}
