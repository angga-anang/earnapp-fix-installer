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
# Prompt ini dibaca LANGSUNG dari /dev/tty (bukan stdin biasa), supaya tetap
# berfungsi walau script-nya sendiri dijalankan lewat pipe (`curl | bash`).
# Efek sampingnya: trik umum `yes | bash script.sh` TIDAK mempan, karena stdin
# yang di-pipe tidak pernah dibaca oleh prompt-nya.
#
# Solusinya: pakai `expect` untuk membuat pseudo-terminal (PTY) asli, supaya
# /dev/tty di dalam installer terhubung ke situ dan bisa "diisi" otomatis.
if ! command -v expect >/dev/null 2>&1; then
  apt-get install -y expect -qq
fi

expect -c '
  set timeout 120
  spawn bash /tmp/earnapp.sh
  expect {
    -re {[Ww]rite .?yes.? to continue} {
      send "yes\r"
      exp_continue
    }
    eof
  }
  catch wait result
  exit [lindex $result 3]
'

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
