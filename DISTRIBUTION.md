# Glide — Dağıtım ve Kurulum

Bu belge, Glide'ı arkadaşlarına test için nasıl göndereceğini ve onların nasıl
kuracağını anlatır.

---

## Bölüm 1 — Sen (geliştirici) nasıl paket hazırlarsın

Terminal'i aç, repo klasörüne gir ve build script'ini çalıştır:

```bash
cd ~/Desktop/Glide
./build-release.sh
```

Bu komut:
1. Glide'ı **Release** modunda derler
2. `Glide.app`'i paketler
3. Masaüstüne **`Glide.zip`** dosyası koyar

Bu `Glide.zip` dosyasını arkadaşlarına gönder (AirDrop, e-posta, WeTransfer, vb.)
ve birlikte aşağıdaki Bölüm 2'yi de ilet.

---

## Bölüm 2 — Arkadaşların nasıl kurar

> **Gereksinim:** macOS 15.6 veya üzeri.

Glide ücretli bir Apple Developer hesabıyla imzalanmadığı için macOS ilk açılışta
"güvenilmeyen geliştirici" uyarısı verir. Bu normal — aşağıdaki adımlarla aşılır.

### 1. Paketi aç
- `Glide.zip` dosyasına çift tıkla → `Glide.app` çıkar.
- `Glide.app`'i **Applications (Uygulamalar)** klasörüne sürükle.

### 2. Karantina işaretini kaldır
İnternetten indirilen uygulamalara macOS "karantina" etiketi koyar; bu, Glide'ın
"hasarlı" görünmesine yol açabilir. Terminal'i aç (Spotlight → "Terminal") ve şunu
yapıştırıp Enter'a bas:

```bash
xattr -cr /Applications/Glide.app
```

(Hiçbir çıktı vermez — sorun değil, normal.)

### 3. Uygulamayı aç
- `Applications` klasöründe `Glide.app`'e **sağ tıkla → Aç (Open)**.
- Bir uyarı çıkarsa tekrar **Aç (Open)** de.
- Üst menü çubuğunda (saatin solunda) küçük bir simge belirir.

### 4. Erişilebilirlik (Accessibility) iznini ver
Glide pencereleri taşıyabilmek için Erişilebilirlik iznine ihtiyaç duyar.

- Menü çubuğundaki Glide simgesine tıkla → **"Open System Settings"**.
- Açılan **Privacy & Security → Accessibility** listesinde **Glide**'ı bul,
  yanındaki anahtarı **aç**.
  - Glide listede yoksa: `+` butonuna bas, `Applications` → `Glide.app`'i seç.
- **Glide'ı tamamen kapat** (menüden "Quit Glide") ve **yeniden aç**. İzin,
  uygulama başlarken okunur; bu yüzden yeniden başlatmak şart.

### 5. Kullan
Menü çubuğundaki simge artık 3 dikdörtgenli normal hâline döner. Hazır:

- **Trackpad ile:** bir pencerenin başlık çubuğu (title bar) üzerine imleci getir,
  2 parmakla kaydır → pencere o yöne snap olur.
- **Klavye ile:** `Ctrl + Option +` ok tuşları / `U I J K` / `1-5` / `C` / `Return`.
  Tam liste menüdeki **Preferences…** penceresinde.

---

## Sorun giderme

| Belirti | Çözüm |
|---|---|
| "Glide hasarlı, çöpe taşınmalı" | Bölüm 2 Adım 2'deki `xattr -cr` komutunu çalıştır |
| Menü simgesi üçgen-ünlem ⚠️ | Erişilebilirlik izni verilmemiş — Adım 4'ü tekrarla, sonra Glide'ı yeniden başlat |
| Snap çalışmıyor | İzni verdikten sonra Glide'ı kapatıp açtın mı? Şart. |
| Uygulama hiç açılmıyor | macOS sürümü 15.6+ mı kontrol et |

---

## Not — kalıcı/temiz dağıtım

Şu anki yöntem test için yeterli ama her arkadaş "karantina kaldırma" adımını
yapmak zorunda. Bunu tamamen ortadan kaldırmak için **ücretli Apple Developer
Program** ($99/yıl) gerekir: o zaman uygulama "Developer ID" ile imzalanıp
Apple'a notarize ettirilir ve hiçbir uyarı çıkmadan açılır. Geniş dağıtım
düşünüldüğünde bu adıma geçilir.
