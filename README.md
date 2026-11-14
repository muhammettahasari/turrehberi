# TurSes

Rehber konuşur, gruptakiler kendi telefonlarına taktıkları kulaklıktan canlı dinler.

Bu ilk deneme sürümü yalnızca **mobil erişim noktası (hotspot)** üzerinden çalışır: internet ya da sunucu gerekmez, ses doğrudan rehberin telefonundan gruptaki telefonlara gider. Rehber başına en fazla 10 dinleyici kabul edilir (ücretsiz sürüm sınırı).

## Uygulamayı telefona kurma

1. Bu depoya her kod gönderildiğinde GitHub, Android uygulama dosyasını (APK) kendisi derler.
2. Telefondan **Releases** sayfasını açın (depo ana sayfasında sağ tarafta) ve en üstteki `TurSes-…apk` dosyasını indirin.
3. Telefon "bilinmeyen kaynak" uyarısı verirse bu kurulum için izin verin.

## İlk ses denemesi (2 telefon)

**Rehber telefonu**
1. TurSes → **Rehber**. Mikrofon iznini verin.
2. "Erişim noktası ayarlarını aç" ile mobil erişim noktasını açın, uygulamaya geri dönün.
3. Ekranda TurSes karekodu çıkar.

**Turist telefonu**
1. Wi-Fi ayarlarından rehberin erişim noktasına bağlanın.
2. Kulaklığı takın.
3. TurSes → **Turist** → adınızı yazın → **Karekodu okut** → rehberin ekranındaki karekodu okutun.
4. "Rehberi dinliyorsunuz" yazısı çıkınca rehber konuşsun.

## Ölçülecekler

- Kaç metreye kadar kesintisiz duyuluyor? (açık alanda, telefon cepteyken)
- Kaç telefon aynı anda sorunsuz dinliyor?
- Rehberin mobil verisi kapalıyken de çalışıyor mu?
- Ses gecikmesi rahatsız edici mi?

## Bilinen sınırlar (bu sürüm)

- Ekran açık kalmalı; uygulama arka plana alınınca ses kesilebilir.
- Turist Wi-Fi'a elle bağlanıyor; tek karekodla otomatik bağlanma sonraki adım.
- Cep Wi-Fi cihazı ve internet modu sonraki adımlar.

## Teknik

- Flutter (Android). Ses: WebRTC (Opus), yerel ağda doğrudan bağlantı.
- Rehber telefonu 8765 numaralı portta küçük bir eşleşme sunucusu açar; karekod bu adresi taşır.
- Depoda yalnızca elle yazılan dosyalar tutulur; eksik Android dosyalarını derleme sırasında `flutter create` üretir (`.github/workflows/android.yml`).
