#!/usr/bin/env bash
# shellcheck shell=bash
# Bootstrap JENKINS SERVER: Docker + Go + Java 21 + Jenkins (systemd).
# Prasyarat: source common.sh dulu.
# Env opsional: GO_VERSION (default 1.22.10), APP_SERVER_HOST (IP private app server)

set -euo pipefail

log "== Bootstrap Jenkins server =="
GO_VERSION="${GO_VERSION:-1.22.10}"
APP_SERVER_HOST="${APP_SERVER_HOST:-}"

install_base_packages
install_docker

log "Install Java 21 (Runtime Jenkins terbaru)"
apt_get install fontconfig openjdk-21-jre

log "Install Go ${GO_VERSION}"
curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -o /tmp/go.tgz
rm -rf /usr/local/go
tar -C /usr/local -xzf /tmp/go.tgz
rm -f /tmp/go.tgz
ln -sf /usr/local/go/bin/go /usr/local/bin/go
ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
echo 'export PATH=$PATH:/usr/local/go/bin' > /etc/profile.d/go.sh
/usr/local/go/bin/go version

log "Siapkan init script Jenkins (set env global APP_SERVER_HOST=${APP_SERVER_HOST})"
install -d -m 0755 /var/lib/jenkins/init.groovy.d
cat > /var/lib/jenkins/init.groovy.d/10-global-env.groovy <<GROOVY
import jenkins.model.Jenkins
import hudson.slaves.EnvironmentVariablesNodeProperty

def j = Jenkins.get()
def props = j.getGlobalNodeProperties()
def envProp = props.get(EnvironmentVariablesNodeProperty)
if (envProp == null) {
  envProp = new EnvironmentVariablesNodeProperty()
  props.add(envProp)
}
envProp.getEnvVars().put('APP_SERVER_HOST', '${APP_SERVER_HOST}')
j.save()
GROOVY

log "Install Jenkins LTS (repo resmi dengan GPG Keyring 2026)"
install -d -m 0755 /usr/share/keyrings
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key | gpg --dearmor --yes -o /usr/share/keyrings/jenkins-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.gpg] https://pkg.jenkins.io/debian-stable binary/" \
  > /etc/apt/sources.list.d/jenkins.list

apt_get update
apt_get install -y jenkins

chown -R jenkins:jenkins /var/lib/jenkins/init.groovy.d

# Izinkan Jenkins memakai Docker (docker build di pipeline)
usermod -aG docker jenkins

systemctl enable jenkins
systemctl restart jenkins   # restart agar group docker + init.groovy.d aktif

log "Menunggu Jenkins siap & initial admin password"
for _ in $(seq 1 90); do
  if [ -s /var/lib/jenkins/secrets/initialAdminPassword ]; then break; fi
  sleep 5
done

if [ -s /var/lib/jenkins/secrets/initialAdminPassword ]; then
  install -m 0600 /var/lib/jenkins/secrets/initialAdminPassword /root/jenkins-initial-admin-password.txt
  log "Initial admin password tersimpan di /root/jenkins-initial-admin-password.txt"
else
  log "PERINGATAN: initialAdminPassword belum muncul, cek: journalctl -u jenkins"
fi

systemctl is-active jenkins
mark_done