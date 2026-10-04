[English](README.md) · **Türkçe**

# Oxide — sürümler

Oxide, Apple Silicon Mac'ler için daemonsuz bir container engine'dir;
Virtualization.framework üstüne kurulu. Her container kendi kısa ömürlü sanal
makinesinde koşar: makine istek anında açılır, container bitince kapanır. Hiçbir
şey çalışmıyorken arkada tek bir süreç bile kalmaz (0 süreç, 0 MB). Komut satırı
Docker ile uyumludur (aynı komutlar, bayraklar ve çıkış kodları); Docker
istemcileri Engine API üzerinden bağlanabilir.

Bu depoda yalnızca imzalı ve notarize edilmiş sürüm paketleri var. Kaynak kod
deposu şimdilik özel.

## İndirme

| Sürüm | Dosya | SHA-256 |
|---|---|---|
| 0.2.0 (2026-10-04) | [Oxide-0.2.0.dmg](https://github.com/emircan-karaca/oxide-releases/releases/download/v0.2.0/Oxide-0.2.0.dmg) | `c558891b7140d697bb9fbecb3a36a07ef5434adb9b38374236d7b293099a9074` |

Gereksinim: Apple Silicon Mac, macOS 26 (26.6.2'de geliştirildi ve doğrulandı).
DMG ve içindeki uygulama Developer ID ile imzalı, Apple tarafından notarize
edilmiş ve bilet yapıştırılmış.

## Kurulum

1. DMG'yi aç, **Oxide.app**'i **Uygulamalar**'a sürükle.
2. Komut satırı aracını PATH'e al (uygulama paketinin içinde geliyor):

```bash
mkdir -p ~/.local/bin
ln -sf "/Applications/Oxide.app/Contents/Helpers/oxide" ~/.local/bin/oxide
export PATH="$HOME/.local/bin:$PATH"   # kabuk profiline ekle
oxide version
```

Guest Linux çekirdeği ve initramfs paketin içinde (`Contents/Resources/guest`);
başka bir şey indirmek gerekmiyor. İmajlar ilk kullanımda Docker Hub'dan (ya da
herhangi bir OCI registry'den) `~/.oxide` altına çekilir.

## Docker gibi kullan

```bash
oxide run --rm alpine echo merhaba          # çek + çalıştır, VM ~0,5 sn'de açılır
oxide run -d --name web -p 8080:80 nginx    # arka planda, port host'ta yayınlı
oxide ps
oxide logs web
oxide exec -it web sh
oxide stop web && oxide rm web

oxide build -t uygulamam .                  # çok aşamalı Dockerfile, build önbelleği
oxide compose up -d                         # compose.yaml yığınları

oxide network create arka
oxide run -d --name db  --network arka postgres:16
oxide run -d --name api --network arka --network on uygulamam
oxide network connect arka api              # container koşarken de çalışır
```

Günlük kullanımda `alias docker=oxide` yeterli. Son container durunca:

```bash
ps aux | grep oxide   # hiçbir şey — daemon yok, paylaşımlı VM yok
```

## Docker istemcileri

Engine API dinleyicisini başlat, herhangi bir Docker istemcisini ona yönlendir:

```bash
oxide api                                   # unix soketi ~/.oxide/oxide.sock
export DOCKER_HOST=unix://$HOME/.oxide/oxide.sock
docker ps                                   # gerçek docker CLI, dockerode, testcontainers, IDE eklentileri
```

## Ağ notları

- Aynı kullanıcı ağındaki container'lar birbirine doğrudan ve isimle ulaşır;
  bunu `VZFileHandleNetworkDeviceAttachment` üstüne yazılmış, kullanıcı
  alanında çalışan bir katman-2 anahtarı sağlar (entitlement gerekmez). Bir
  container 32 ağa kadar üye olabilir; `network connect`/`disconnect` koşan
  container'da çalışır.
- Dışarıya çıkış ve `-p` port yayınları `VZNATNetworkDeviceAttachment` üzerinden.
- Bugün **yapılamayan** tek şey: container'ın LAN'da kendi adresiyle görünmesi
  (Docker'ın bridged/macvlan kullanımı). Bunun için
  `VZBridgedNetworkDeviceAttachment` gerekiyor; o da Apple'ın kısıtlı
  `com.apple.vm.networking` iznini istiyor (başvuru yapıldı).

## İndirmeyi doğrula

```bash
shasum -a 256 Oxide-0.2.0.dmg
spctl -a -vv -t open --context context:primary-signature Oxide-0.2.0.dmg   # "Notarized Developer ID"
```
