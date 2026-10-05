[English](README.md) · **Türkçe**

# Oxide — sürümler

Oxide, Apple Silicon Mac'ler için daemonsuz bir container engine'dir;
Virtualization.framework üstüne kurulu. Her container kendi kısa ömürlü sanal
makinesinde koşar: makine istek anında açılır, container bitince kapanır. Hiçbir
şey çalışmıyorken arkada tek bir süreç bile kalmaz (0 süreç, 0 MB). Komut satırı
Docker ile uyumludur (aynı komutlar, bayraklar ve çıkış kodları); Docker
istemcileri Engine API üzerinden bağlanabilir.

Bu depoda imzalı ve notarize edilmiş sürüm paketleri, kurulum betiği ve sürüm
imza anahtarı var. Kaynak kod deposu şimdilik özel.

**Son sürüm: 0.3.0** · Gereksinim: Apple Silicon Mac, macOS 13 ya da üstü
(macOS 26'da geliştirildi ve doğrulandı).

## Kurulum

Üç yoldan birini seç.

**Homebrew**

```bash
brew install --cask emircan-karaca/oxide/oxide
```

**Tek satır**

```bash
curl -fsSL https://raw.githubusercontent.com/emircan-karaca/oxide-releases/main/install.sh | sh
```

Betik makineyi kontrol eder, son sürümün manifest'ini ve DMG'sini indirir;
sha256'yı, Apple notarization'ını ve yayıncı Team ID'sini doğrular; `Oxide.app`i
`/Applications`'a (yazılamıyorsa `~/Applications`'a) kurar, `oxide` komutunu
`~/.local/bin`e bağlar ve kabuk tamamlamalarını kurar. Önce okumak istersen:
[install.sh](install.sh).

**DMG ile elle**

1. Aşağıdaki tablodan DMG'yi indir, **Oxide.app**'i **Uygulamalar**'a sürükle.
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

## Güncelleme

```bash
oxide self-update            # DMG / install.sh kurulumları
oxide self-update --check    # yalnızca sor (çıkış 0 = güncel, 2 = yeni sürüm var)
brew upgrade --cask oxide    # Homebrew kurulumları
```

`oxide version --check` de yeni sürüm olup olmadığını söyler. Arka planda hiçbir
şey sürüm yoklamaz: komut satırı yalnızca sen istediğinde ağa çıkar, masaüstü
uygulaması pencere açılırken bir kez sorar.

## İndirmeler

| Sürüm | Dosya | SHA-256 |
|---|---|---|
| 0.3.0 (2026-10-05) | [Oxide-0.3.0.dmg](https://github.com/emircan-karaca/oxide-releases/releases/download/v0.3.0/Oxide-0.3.0.dmg) | `222726cc65aa3800964e8f92310663779670dcf19b5f8efb9535565d0985e60e` |
| 0.2.0 (2026-10-04) | [Oxide-0.2.0.dmg](https://github.com/emircan-karaca/oxide-releases/releases/download/v0.2.0/Oxide-0.2.0.dmg) | `c558891b7140d697bb9fbecb3a36a07ef5434adb9b38374236d7b293099a9074` |

Her sürümle birlikte `SHA256SUMS`, `manifest.json` ve `manifest.json.sig` de yayınlanır.

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

## Bir sürüme neden güvenilir

| Yol | Doğrulanan |
|---|---|
| `install.sh` | HTTPS; manifest'teki DMG sha256'sı; Gatekeeper'ın DMG'yi ve uygulamayı kabul etmesi (Apple notarization); uygulamanın Team ID `3FMDTGB65C` ve bundle id `com.emircankaraca.oxide` ile imzalı olması; yerel `openssl` Ed25519 biliyorsa manifest imzası |
| `oxide self-update` | ikiliye gömülü Ed25519 anahtarıyla manifest imzası (aşağıda); DMG sha256 + boyut; `codesign --verify --strict --deep`, Team ID, bundle id, Gatekeeper; yeni paketin kendi `--version`ı |
| Homebrew | Cask'in `sha256`sı ve Apple notarization (Homebrew yeniden imzalamaz) |

Sürüm imza anahtarı ([keys/oxide-release.pub](keys/oxide-release.pub)):

```text
oxide-relpub1 b8432d0e682435cc DmlyTWkSIuEHkNbKKRkwhf2g0+TIdoLHX95IBTrkzrU=
```

Biçim: `oxide-relpub1 <keyid> <base64 ham Ed25519 açık anahtar>`;
`manifest.json.sig` içindeki imzalar `oxide-sig1 <keyid> <base64 imza>` ve
`manifest.json`un ham baytları üzerinden alınır. `keyid`, `sha256(açık anahtar)`ın
ilk 8 baytı. Bir GitHub Actions koşumu
([verify-release.yml](.github/workflows/verify-release.yml)) her yayınlanan sürümü
yeniden doğrular ve kurulum betiğini temiz bir macOS runner'da çalıştırır.

## İndirmeyi elle doğrula

```bash
shasum -a 256 -c SHA256SUMS
spctl -a -vv -t open --context context:primary-signature Oxide-0.3.0.dmg   # "Notarized Developer ID"
python3 verify-sig.py keys/oxide-release.pub manifest.json manifest.json.sig   # `pip install cryptography` gerekir
```
