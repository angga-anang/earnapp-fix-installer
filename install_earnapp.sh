#!/usr/bin/env bash
#
# install_earnapp.sh
# Instalasi EarnApp untuk Linux server dengan fix untuk dua masalah umum:
#
#  1. Prompt "Do you agree to EarnApp's terms?" tidak bisa dijawab otomatis
#     lewat `curl | bash` karena installer membaca jawabannya LANGSUNG dari
#     /dev/tty, bukan dari stdin biasa.
#     -> Fix: jalankan installer di dalam `expect` (PTY asli) dan auto-jawab "yes".
#
#  2. Registrasi device gagal dengan:
#       AxiosError: self-signed certificate in certificate chain
#       code: 'SELF_SIGNED_CERT_IN_CHAIN'
#     Ini BUKAN masalah jaringan/firewall (curl biasa berhasil verifikasi SSL
#     situs earnapp.com dengan normal). Penyebabnya: binary installer EarnApp
#     (Node.js snapshot) membawa CA root store versi lama yang belum mengenali
#     intermediate CA baru dari SSL.com yang dipakai *.earnapp.com. Env var
#     NODE_EXTRA_CA_CERTS tidak selalu terbawa ke proses registrasi internalnya.
#     -> Fix: setelah installer gagal registrasi, script ini mengambil `uuid`
#        dan `serial` dari output error yang ditampilkan installer, lalu
#        mengirim ulang request registrasi secara manual via `curl` (yang
#        selalu berhasil karena pakai CA store sistem yang up-to-date).
#
# Jalankan sebagai root / dengan sudo:
#   sudo bash install_earnapp.sh
#

set -uo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Script ini harus dijalankan sebagai root (pakai sudo)." >&2
  exit 1
fi

echo "==> [1/5] Update & pastikan ca-certificates paling baru..."
apt-get update -qq
apt-get install -y --reinstall ca-certificates -qq
update-ca-certificates --fresh >/dev/null 2>&1 || update-ca-certificates >/dev/null 2>&1

echo "==> [2/5] Sinkronkan waktu server (hindari false-positive validasi sertifikat)..."
if command -v timedatectl >/dev/null 2>&1; then
  timedatectl set-ntp true || true
fi

# Tetap di-export untuk jaga-jaga (defense in depth), walau di beberapa versi
# installer env var ini tidak terbawa ke proses registrasi internalnya --
# makanya ada fallback manual di step 4.
export NODE_OPTIONS="--use-openssl-ca"
export NODE_EXTRA_CA_CERTS="/etc/ssl/certs/ca-certificates.crt"

echo "==> [3/5] Download & jalankan installer EarnApp..."
wget -qO /tmp/earnapp.sh https://brightdata.com/static/earnapp/install.sh

INSTALL_LOG="/tmp/earnapp_install_output.log"

# Installer resmi minta konfirmasi interaktif ("yes") untuk menyetujui terms,
# dibaca langsung dari /dev/tty. Pakai `expect` untuk bikin PTY asli supaya
# bisa dijawab otomatis walau script ini sendiri dijalankan lewat pipe.
if ! command -v expect >/dev/null 2>&1; then
  apt-get install -y expect -qq
fi

expect -c '
  set timeout 120
  log_user 1
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
' 2>&1 | tee "$INSTALL_LOG"

echo ""
echo "==> [4/5] Verifikasi status registrasi..."

DEVICE_UUID="$(earnapp showid 2>/dev/null || true)"

# Cek apakah registrasi gagal dengan error SSL yang dikenal.
if grep -q "SELF_SIGNED_CERT_IN_CHAIN\|Failed registration" "$INSTALL_LOG"; then
  echo "    Registrasi internal installer gagal (SSL cert chain issue di binary lama)."
  echo "    Mencoba registrasi ulang secara manual via curl..."

  # Ambil serial dari payload yang dicoba dikirim installer (tercetak di error log-nya).
  SERIAL="$(grep -oP '"serial":"\K[a-f0-9]+' "$INSTALL_LOG" | head -n1 || true)"

  # Ambil versi & arch dari baris "Fetching earnapp-ssl3-<arch>-<version>"
  FETCH_LINE="$(grep -oP 'Fetching earnapp-ssl3-\K[a-z0-9]+-[0-9.]+' "$INSTALL_LOG" | head -n1 || true)"
  ARCH="$(echo "$FETCH_LINE" | cut -d'-' -f1)"
  VERSION="$(echo "$FETCH_LINE" | cut -d'-' -f2)"

  OS_STR="Linux"
  if [[ -f /etc/os-release ]]; then
    OS_STR="$(. /etc/os-release && echo "$PRETTY_NAME")"
  fi
  OS_ENC="$(echo "$OS_STR" | sed 's/\//%2F/g; s/ /+/g')"

  if [[ -n "$DEVICE_UUID" && -n "$SERIAL" ]]; then
    RESP="$(curl -s -X POST \
      "https://client.earnapp.com/install_device?uuid=${DEVICE_UUID}&version=${VERSION:-unknown}&arch=${ARCH:-x64}&appid=node_earnapp.com&os=${OS_ENC}" \
      -H "Content-Type: application/json" \
      -d "{\"serial\":\"${SERIAL}\"}")"

    if echo "$RESP" | grep -q '"ok":1'; then
      echo "    OK - Registrasi manual berhasil: $RESP"
    else
      echo "    GAGAL - Registrasi manual gagal, respons server: $RESP"
      echo "    Silakan coba jalankan ulang: sudo earnapp register"
    fi
  else
    echo "    GAGAL - Tidak berhasil mengekstrak uuid/serial dari log installer."
    echo "    uuid: ${DEVICE_UUID:-<kosong>} | serial: ${SERIAL:-<kosong>}"
    echo "    Coba jalankan manual: sudo earnapp register --verbose"
  fi
else
  echo "    OK - Tidak terdeteksi error SSL saat registrasi. Kemungkinan sudah berhasil."
fi

if ! earnapp status 2>/dev/null | grep -qi "enabled"; then
  earnapp start || true
fi

echo ""
echo "==> [5/5] Selesai."
echo "Device ID : ${DEVICE_UUID:-$(earnapp showid 2>/dev/null)}"
echo ""
echo "Buka link berikut di browser untuk verifikasi (hard refresh Ctrl+Shift+R kalau perlu):"
echo "  https://earnapp.com/r/${DEVICE_UUID:-$(earnapp showid 2>/dev/null)}"
