# TODO

- [ ] Kurulumunun tamamlanması için kullanıcı etkileşimi gereken modüllerde bunu belirtmeli ve tüm provizyonlama sonunda bunu listelemeliyiz.
- [x] debian'da şu paketlerin kurulu olması gerekiyor: qemu-utils qemu-system-x86 ovmf
- [x] `home/javascript` içindeki geçersiz `brew:oven-sh/bun/bun` bildirimini `brew:bun` olarak düzeltmeliyiz.
- [x] Neovim için gereken komut satırı aracını `brew:tree-sitter-cli` olarak bildirmeliyiz; `brew:tree-sitter` yeterli değil.
- [x] `github:Lampese/codex-switcher` paketinin macOS arm64 v0.2.2 varlıkları katı kod imzası doğrulamasından geçmiyor; kurulum politikasını veya üst sürüm düzeltmesini beklemeyi kararlaştırmalıyız.
- [x] `home/macos` modülü için `~/.bun/bin`, keg-only Ruby/curl/zip yolları, Tailscale uygulaması ve rclone FUSE/nfsmount tercihlerini kararlaştırmalıyız.
- [x] Linux'a özgü systemd, Remmina ve masaüstü bağlantılarını platforma göre sınırlamalıyız.
- [ ] `references/specification/apply.md` uyarınca deterministik `bin/apply` yürütücüsünü aşamalı olarak uygulamalıyız.
- [ ] `bin/plan` çıktısına sürümlü şema, plan kimliği, depo rolü, `role/name` modül kimliği ve tek sıralı `actions` akışı eklemeliyiz.
- [ ] Planner, kaynak ve hedef aynı Dropbox ağacındaysa tam sembolik bağ değerini eşdeğer göreli yol olarak üretmeli.
- [ ] Birleşik public/private `last-plan.json`, `last-apply.json` ve host state üretip iki planın aynı durum dosyalarını ezmesini önlemeliyiz.
- [ ] Apply testlerinde doğrulama-öncesi-yazmama, backup, göreli Dropbox bağları, paket hatası, Bash-only bölüm, manual/deferred, kesinti ve resume durumlarını kapsamalıyız.
- [ ] `doctor`, Dropbox aktif alanındaki kırık ve host-mutlak sembolik bağları cache/arşiv/tmp politikasına göre raporlamalı.
- [ ] `kant` Dropbox eşzamanlaması tamamlandıktan sonra göreli Codex/Gemini/OpenCode bağlarını, Codex hook'larını ve Fish giriş kabuğunu doğrulamalıyız.
- [x] Bayat provision smoke beklentilerini güncel shared-agent düzeniyle uyumlu hale getirmeli ve mevcut `bin/plan` RuboCop borcunu temizlemeliyiz.
