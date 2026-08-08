# EarnApp Installer (Fixed for SSL Cert Chain Error)

Script instalasi [EarnApp](https://earnapp.com) untuk Linux server yang sudah memperbaiki
error umum berikut yang muncul saat registrasi device:

```
AxiosError: self-signed certificate in certificate chain
code: 'SELF_SIGNED_CERT_IN_CHAIN'
Failed registration: check internet connection and try again
```

Yang berlanjut jadi error di dashboard EarnApp:

```
Error while linking device: The device is not found
```

## Penyebab

Binary CLI EarnApp adalah Node.js snapshot yang membawa CA root store versi lama
(di-bundle saat build). Kalau sertifikat `*.earnapp.com` diterbitkan ulang dari
intermediate CA yang lebih baru (mis. SSL.com), binary lama ini gagal memverifikasinya
dan salah mengiranya sebagai sertifikat self-signed — padahal sertifikatnya valid
(bisa dibuktikan dengan `curl` yang berhasil verifikasi normal karena `curl` pakai
CA store sistem yang selalu ter-update via `apt`).

Karena registrasi device gagal di tahap ini, device tidak pernah benar-benar
tersimpan di server EarnApp, sehingga link dashboard registrasi menampilkan
"device not found" meskipun instalasi lokal sukses.

## Solusi

Paksa proses Node.js di dalam EarnApp CLI memakai CA store sistem (bukan bundle-nya
sendiri) dengan environment variable:

```bash
NODE_OPTIONS="--use-openssl-ca"
NODE_EXTRA_CA_CERTS="/etc/ssl/certs/ca-certificates.crt"
```

Env var ini di-export **sebelum** installer resmi dijalankan, supaya diwariskan ke
proses auto-registrasi di dalamnya.

## Cara Pakai

```bash
git clone <url-repo-kamu>.git
cd earnapp-fix-installer
sudo bash install_earnapp.sh
```

Atau langsung tanpa clone:

```bash
curl -fsSL https://raw.githubusercontent.com/<username>/<repo>/main/install_earnapp.sh -o install_earnapp.sh
sudo bash install_earnapp.sh
```

## Apa yang dilakukan script ini

1. Update paket `ca-certificates` ke versi terbaru.
2. Sinkronkan waktu server (jaga-jaga dari false-positive validasi sertifikat akibat jam ngaco).
3. Set `NODE_OPTIONS` dan `NODE_EXTRA_CA_CERTS` sebelum menjalankan installer resmi BrightData.
4. Jalankan installer EarnApp resmi.
5. Kalau auto-register masih gagal, coba `earnapp register` ulang secara eksplisit dengan env var yang sama.
6. Tampilkan Device ID dan link registrasi di akhir untuk verifikasi manual di dashboard.

## Troubleshooting Manual

Kalau script tetap gagal, cek chain sertifikat server secara manual:

```bash
curl -vI https://client.earnapp.com/install_device
```

Perhatikan bagian `issuer:` — kalau `curl` berhasil verifikasi (`SSL certificate verify ok.`)
tapi binary `earnapp` tetap gagal, berarti memang masalah CA bundle bawaan binary, bukan
masalah jaringan/firewall.

Cek status device setelah instalasi:

```bash
sudo earnapp status
sudo earnapp showid
```

Lalu buka `https://earnapp.com/r/<device-id>` dan **hard refresh** (Ctrl+Shift+R) browser
kalau dashboard masih menampilkan "device not found" — kadang halamannya ter-cache
meski registrasi backend sebenarnya sudah sukses.

## Disclaimer

Script ini tidak berafiliasi resmi dengan EarnApp/BrightData. Gunakan dengan risiko
sendiri dan pastikan kamu memahami [Terms of Service EarnApp](https://earnapp.com/dashboard)
sebelum menjalankannya di server produksi.
