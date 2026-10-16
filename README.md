# 🃏 Yunan Yanık VIP — Çok Oyunculu Mobil Oyun & Linux Sunucu

Özel kurallı **Yunan Yanık** çok oyunculu kart oyunu.
* **Linux Oyun Sunucusu (`server/`):** Node.js (TypeScript) + Socket.IO + PostgreSQL (Docker Compose ile izole, mevcut Docker konteynerleriyle çakışmayan `4545` portu).
* **Android Uygulaması (`mobile/`):** Flutter (Yatay Ekran / Landscape VIP Casino teması, Klasik Yelpaze kağıt dizilimi, Uygulama İçi Admin Paneli).

---

## 🐧 Linux Sunucu Kurulumu (Tek Komutla)

Mevcut Docker çalışan Linux sunucunuzda hiçbir port çakışması yaşamadan çalıştırmak için:

```bash
git clone https://github.com/karmenali/yunan-yanik-vip.git
cd yunan-yanik-vip
docker compose up -d --build
```

* Sunucu **`4545`** portundan yayın yapar (`http://SUNUCU_IP_ADRESINIZ:4545`).
* PostgreSQL veritabanı sadece iç Docker ağında (`yunan_yanik_net`) çalışır, sunucunuzdaki mevcut `5432` portlarıyla **asla çakışmaz**.
* **Varsayılan Admin Hesabı:**
  * **Kullanıcı Adı:** `admin`
  * **Şifre:** `admin123456`
* **Hazır Test Oyuncuları:**
  * `oyuncu1` / `123456` (5.000 Kredi)
  * `oyuncu2` / `123456` (5.000 Kredi)
  * `oyuncu3` / `123456` (5.000 Kredi)
  * `oyuncu4` / `123456` (5.000 Kredi)

---

## 📱 Android APK Derleme (`mobile/`)

```bash
cd mobile
flutter pub get
flutter build apk --release
```
Üretilen APK dosyası: `mobile/build/app/outputs/flutter-apk/app-release.apk`
