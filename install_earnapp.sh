#!/usr/bin/env bash
#
# install_earnapp.sh
# Instalasi EarnApp dengan fix untuk error:
#   AxiosError: self-signed certificate in certificate chain (SELF_SIGNED_CERT_IN_CHAIN)
#
# Penyebab: binary EarnApp CLI (Node.js snapshot) membawa CA root store versi lama
# yang belum mengenali intermediate CA baru dari SSL.com yang dipakai *.earnapp.com.
# Fix: paksa Node pakai CA store sistem (yang selalu up-to-date via apt) dengan
# NODE_OPTIONS="--use-openssl-ca" dan NODE_EXTRA_CA_CERTS.
#
# Jalankan sebagai root / dengan sudo:
#   sudo bash install_earnapp.sh
#

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Script ini harus dijalankan sebagai root (pakai sudo)." >&2
  exit 1
fi

echo "==> [1/4] Update & pastikan ca-certificates paling baru..."
apt-get update -qq
apt-get install -y --reinstall ca-certificates -qq
update-ca-certificates --fresh >/dev/null 2>&1 || update-ca-certificates >/dev/null 2>&1

echo "==> [2/4] Sinkronkan waktu server (hindari false-positive validasi sertifikat)..."
if command -v timedatectl >/dev/null 2>&1; then
  timedatectl set-ntp true || true
fi

# Export env var ini SEBELUM download & run installer, supaya diwariskan
# ke semua proses child (termasuk saat installer otomatis memanggil `earnapp register`).
export NODE_OPTIONS="--use-openssl-ca"
export NODE_EXTRA_CA_CERTS="/etc/ssl/certs/ca-certificates.crt"

echo "==> [3/4] Download & jalankan installer EarnApp..."
wget -qO /tmp/earnapp.sh https://brightdata.com/static/earnapp/install.sh

# Installer resmi minta konfirmasi interaktif ("yes") untuk menyetujui terms.
# Saat script ini dijalankan lewat `curl | sudo bash`, stdin sudah dipakai oleh
# pipe curl sehingga installer tidak bisa membaca input dari terminal.
# Solusinya: sediakan jawaban "yes" otomatis lewat `yes "yes"`.
yes "yes" | bash /tmp/earnapp.sh

echo "==> [4/4] Pastikan device ter-register (kalau installer belum otomatis sukses)..."
if ! earnapp status 2>/dev/null | grep -qi "enabled"; then
  earnapp start
fi

# Coba register ulang secara eksplisit dengan env var fix, in case auto-register
# di dalam installer gagal duluan sebelum env var ini terbaca.
earnapp register --verbose || true

echo ""
echo "==> Selesai. Device ID:"
earnapp showid

echo ""
echo "==> Kalau dashboard EarnApp masih bilang 'device not found', buka URL registrasi berikut"
echo "    dan lakukan HARD REFRESH (Ctrl+Shift+R) di browser:"
echo "    https://earnapp.com/r/$(earnapp showid)"
