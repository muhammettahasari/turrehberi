# TurSes

Rehber konuşur, gruptakiler kendi telefonlarına taktıkları kulaklıktan canlı dinler.

Bu deneme sürümü yerel Wi-Fi üzerinden çalışır: internet ya da sunucu gerekmez, ses doğrudan rehberin telefonundan gruptaki telefonlara gider. Rehber başına en fazla 10 dinleyici kabul edilir (ücretsiz sürüm sınırı).

- **TurSes ağı (önerilen):** Rehberin uygulaması kendi Wi-Fi ağını açar; karekod ağ adı ve şifresini taşır, turist telefonu karekodu okutunca bu ağa kendiliğinden bağlanır (Android bir kez "Bağlan" onayı ister).
- **Kendi erişim noktası:** Rehber telefonunun normal hotspot'u. Ağ adı ve şifresi bir kez uygulamaya yazılır, karekoda eklenir.
- **Kendini güncelleme:** Uygulama açılışta yeni deneme sürümü olup olmadığına bakar; "Güncelle" ile indirip kurar. Bunun için her sürümün aynı anahtarla imzalanması gerekir (GitHub gizli değişkenleri `TURSES_KS`, `TURSES_KS_PASS`).

## Uygulamayı telefona kurma

1. Bu depoya her kod gönderildiğinde GitHub, Android uygulama dosyasını (APK) kendisi derler.
2. Telefondan **Releases** sayfasını açın (depo ana sayfasında sağ tarafta) ve en üstteki `TurSes-…apk` dosyasını indirin.
3. Telefon "bilinmeyen kaynak" uyarısı verirse bu kurulum için izin verin.

## İlk ses denemesi (2 telefon)

**Rehber telefonu**
1. TurSes → **Rehber**. Mikrofon iznini verin.
2. **TurSes ağını başlat**'a dokunun (telefonun normal erişim noktası kapalı olmalı). İstenen izinleri verin.
3. Ekranda karekod çıkar.

**Turist telefonu**
1. Kulaklığı takın.
2. TurSes → **Turist** → adınızı yazın → **Karekodu okut**.
3. Android "ağa bağlan" diye sorarsa onaylayın.
4. "Rehberi dinliyorsunuz" yazısı çıkınca rehber konuşsun.

## Ölçülecekler

- Kaç metreye kadar kesintisiz duyuluyor? (açık alanda, telefon cepteyken)
- Kaç telefon aynı anda sorunsuz dinliyor?
- Rehberin mobil verisi kapalıyken de çalışıyor mu?
- Ses gecikmesi rahatsız edici mi?

## Bilinen sınırlar (bu sürüm)

- Ekran açık kalmalı; uygulama arka plana alınınca ses kesilebilir.
- TurSes ağı internet paylaşmaz; turist telefonu internet için mobil veriyi kullanmaya devam eder.
- Cep Wi-Fi cihazı ve internet modu sonraki adımlar.

## Teknik

- Flutter (Android). Ses: WebRTC (Opus), yerel ağda doğrudan bağlantı.
- Rehber telefonu 8765 numaralı portta küçük bir eşleşme sunucusu açar; karekod bu adresi taşır.
- Depoda yalnızca elle yazılan dosyalar tutulur; eksik Android dosyalarını derleme sırasında `flutter create` üretir (`.github/workflows/android.yml`).
