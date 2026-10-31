# Lunixi Elixir SDK

[English README](../README.md) · [Elixir dokümantasyonu](https://docs.lunixi.com/tr/sdks/elixir)

Elixir 1.20+ ve Erlang/OTP 29+ sunucu SDK'sıdır. Phoenix, Plug, LiveView sunucu süreçleri ve OTP uygulamalarında kullanılabilir.

## Hex üzerinden kurulum

[Lunixi 0.1.0 Hex.pm'de yayımlandı](https://hex.pm/packages/lunixi/0.1.0). Uygulamanızın `mix.exs` dosyasındaki `deps/0` listesine ekleyin:

```elixir
{:lunixi, "~> 0.1.0"}
```

Ardından `mix deps.get` çalıştırın.

Kaynaktan kurulum için Hex bağımlılığı yerine GitHub sürüm etiketi kullanılabilir:

```elixir
{:lunixi, github: "Lunixi-Payment/lunixi-elixir", tag: "v0.1.0"}
```

```elixir
config = %Lunixi.Config{
  base_url: "https://api-gateway.lunixi.com",
  key_id: System.fetch_env!("LUNIXI_KEY_ID"),
  private_key: System.fetch_env!("LUNIXI_PRIVATE_KEY_PEM")
}
children = [{Lunixi.Client, name: MyApp.Lunixi, config: config}]
Supervisor.start_link(children, strategy: :one_for_one)
```

Merchant anahtarı başına ayrı isimli supervised istemci kurun. Token önbelleği/sıralı yenileme istemcidedir; ödeme HTTP çağrıları çağıran süreçlerde eşzamanlı yürür. Yeniden başlatmada token güvenle tekrar alınır, diske yazılmaz. Açık Ed25519 anahtarını panelde kaydedin; PKCS8 PEM/base64 DER/32 bayt seed/doğrulanmış 64 bayt keypair özel anahtarı sunucuda tutun. TEST/LIVE ortamını anahtar belirler.

HTTPS ve sertifika/host doğrulaması zorunludur. Yönlendirmeler ve Req tekrarları kapalıdır. Varsayılan HTTP timeout 30 saniye, en çok 120 saniye; yanıt limiti 8 MiB, en çok 32 MiB'dir. `max_retries` varsayılan sıfır, en çok beştir. BaseURL güvenilir kökendir; kullanıcı bilgisi, yol veya sorgu içermez. `allow_insecure_localhost` yalnız açıkça seçilen yerel HTTP testleri içindir. `additional_ca_certificates` güvenilir DER sertifikaları ekler, doğrulamayı kapatmaz.

```elixir
intent = %Lunixi.Payment.Intent{
  amount: 10050, currency: "TRY", order_id: "ORD-1001",
  callback_url: "https://merchant.example/payment/return"
}
{:ok, response} = Lunixi.Payments.create_intent(MyApp.Lunixi,intent,kayitli_deneme_anahtari)
{:ok, html} = Lunixi.CheckoutHTML.render(response.data["token"], nonce: sunucu_csp_nonce)
```

Sipariş toplamını sunucudan okuyun; anahtarı çağrıdan önce kaydedin. Token/HTML yalnız ilgili siparişin yetkili müşterisine `Cache-Control: no-store` ile döner. Yardımcı yalnız `https://cdn.lunixi.com/lunixi-checkout.min.js` dosyasını yükler; mevcut formu açar ve token JSON'unu HTML bağlamı için kaçırır. Ham kart toplamaz. Tutarlar tam sayı kuruştur; `10050` = 100,50 TRY. Sepet `price` kalem toplamıdır, toplam intent `amount` ile eşleşir. Kaldırılmış kök tutar alanları reddedilir; taksit/vade farkını form yönetir. `preauth`/`force_3d` açık false değerini korur.

`Lunixi.Payments` intent/liste/yöntem/get/capture/refund/void/split akışlarını, `Lunixi.Fraud` değerlendirme/olay/karar sorgularını kapsar. Diğer belgelenmiş `/api/v1/` ürünleri `Lunixi.request` ile aynı imzalı taşıma üzerinden kullanılır; 0.1.0 sürümü bu ürünlerde tipli yardımcı eşitliği iddia etmez. Zarf, `data`, `page_info` ve ikili `bytes` korunur. Split bekleyen durumda HTTP 400 içeren yanıt dönebilir; ödeme tamamlanmış sayılmaz.

Finansal mutasyonlar 16–128 boşluksuz yazdırılabilir ASCII anahtar ister. Tekrarda anahtar/gövde değişmez, nonce yenilenir. Anahtarsız mutasyon kör tekrarlanmaz. Token, tarayıcı dönüşü, HTTP 200 veya `AUTHORIZED` tahsilat değildir. Merchant/sipariş/ödeme kimliği, beklenen tutar/para birimi ve nihai tahsilat/uzlaştırma durumu eşleşmeden teslimat yapmayın. Belirsiz sonucu yeni denemeden önce uzlaştırın.

## Webhook ve kalıcı tekrar koruması

```elixir
{:ok, event} = Lunixi.Webhook.verify(ham_govde, baslik_ciftleri,
  secrets: [System.fetch_env!("LUNIXI_WEBHOOK_SECRET")])
```

Ham baytları JSON middleware'den önce doğrulayın; yinelenen başlıkları gizlemeden çift listesi olarak aktarın. OTP HMAC ve sabit zamanlı karşılaştırma kullanılır. İmza event ID, zaman damgasının birebir metni ve ham gövdeyi kapsar. Varsayılan tolerans 5 dakika, aralık 1–900 saniyedir; kapatılamaz. `now` yalnız güvenilir test saatidir. İmzalı gövdede `type` gerekir; başlık/JSON tekrarları ve ID/tür uyuşmazlığı reddedilir. En fazla üç secret rotasyon sağlar.

İmza doğrulama olay kaydı oluşturmaz. SQLite için uygulamanıza ayrıca `{:exqlite,"~> 0.43.0"}` ekleyin:

```elixir
:ok = Lunixi.SqliteInbox.ensure_schema(connection)
{:ok, uygulandi} = Lunixi.SqliteInbox.process(connection,merchant_scope,event,fn transaction ->
  dogrulanmis_siparisi_isle(transaction,event)
end)
```

Sipariş/outbox güncellemesi ve tekrar kaydı aynı transaction içinde commit edilir. Callback hata verirse marker da geri alınır. Tekrar callback'i çalıştırmaz; aynı ID farklı gövdeyle gelirse reddedilir. Bağlantı transaction boyunca tek sürecin olmalıdır; süreçler ayrı bağlantı kullanır. Native busy timeout'u kısa tutun (örnek 100 ms); kilit/depolama hatasında sağlayıcı tekrarına izin veren HTTP hatası dönün. Merchant scope ayırın, marker'ları replay politikanız boyunca saklayın. Harici yan etkiler outbox worker'da yürür. Depolama hatasına 2xx dönmeyin. Örnek yalnız doğrulanmış bildirim kaydeder, siparişi tamamlamaz.

Inspect/JSON ve OTP süreç durumunda secret/gövde gizlenir; açık veri/ham gövde erişimcileri ve ham map'ler yine müşteri bilgisi içerebilir, loglanmaz. BEAM belleği için sıfırlama garantisi verilmez.

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix credo --strict --only warning
mix deps.audit
mix hex.audit
mix hex.build
```

Testler gerçek TLS, sentetik çapraz dil vektörleri, eşzamanlı token, form enjeksiyonu, SQLite geri alma/yeniden başlatma/tekrar senaryolarını kapsar. OpenSSL yalnız test sertifikası üretmek için kullanılır. Credo uyarı/güvenlik kontrolleri çalışır; Dialyzer analizi iddia edilmez. [Güvenlik](../SECURITY.md) · [Katkı](../CONTRIBUTING.md) · [MIT](../LICENSE)
