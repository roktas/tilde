# TODO

- [ ] Kurulumunun tamamlanması için kullanıcı etkileşimi gereken modüllerde bunu belirtmeli ve tüm provizyonlama sonunda bunu listelemeliyiz.
- [x] debian'da şu paketlerin kurulu olması gerekiyor: qemu-utils qemu-system-x86 ovmf
- [ ] `home/javascript` içindeki geçersiz `brew:oven-sh/bun/bun` bildirimini `brew:bun` olarak düzeltmeliyiz.
- [ ] Neovim için gereken komut satırı aracını `brew:tree-sitter-cli` olarak bildirmeliyiz; `brew:tree-sitter` yeterli değil.
- [ ] `github:Lampese/codex-switcher` paketinin macOS arm64 v0.2.2 varlıkları katı kod imzası doğrulamasından geçmiyor; kurulum politikasını veya üst sürüm düzeltmesini beklemeyi kararlaştırmalıyız.
- [ ] `home/macos` modülü için `~/.bun/bin`, keg-only Ruby/curl/zip yolları, Tailscale uygulaması ve rclone FUSE/nfsmount tercihlerini kararlaştırmalıyız.
- [ ] Linux'a özgü systemd, Remmina ve masaüstü bağlantılarını platforma göre sınırlamalıyız.
- [ ] Planı uygulayan ortak bir yürütücü tanımlamalı ve public/private plan durumlarının aynı dosya adlarını ezmesini önlemeliyiz.
