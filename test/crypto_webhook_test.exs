defmodule Lunixi.CryptoWebhookTest do
  use ExUnit.Case, async: true
  alias Lunixi.{JSON, Signing, Webhook}

  defp fixture,
    do: Jason.decode!(File.read!(Path.join(__DIR__, "fixtures/canonical-vectors.json")))

  test "Node JSON digest Ed25519 golden vectors with PKCS8 and seed" do
    source = fixture()

    for key <- [source["privateSeed"], source["privateKeyPem"]] do
      assert {:ok, seed} = Signing.decode_key(key)

      for vector <- source["vectors"] do
        assert {:ok, ordered} = JSON.decode_ordered(vector["input"])
        assert {:ok, body} = JSON.encode(ordered)
        assert body == vector["body"]
        assert Signing.digest(body) == vector["digest"]

        canonical =
          Signing.canonical(
            :post,
            "/api/v1/payments/intents?locale=tr",
            "2026-10-31T00:00:00Z",
            "0123456789abcdef0123456789abcdef",
            Signing.digest(body)
          )

        assert canonical == vector["canonical"]

        assert Base.encode64(:crypto.sign(:eddsa, :none, canonical, [seed, :ed25519])) ==
                 vector["signature"]
      end
    end
  end

  test "strict duplicate keys, safe integers and explicit false" do
    assert {:error, _} = JSON.decode(~s({"a":1,"a":2}))
    assert {:error, _} = JSON.encode(%{:a => 1, "a" => 2})
    assert {:error, _} = JSON.encode(%{"amount" => 9_007_199_254_740_992})
    assert {:error, _} = JSON.encode(%{"amount" => -9_007_199_254_740_992})
    assert {:ok, _} = JSON.encode(%{"amount" => 9_007_199_254_740_991})
    deep = Enum.reduce(1..66, nil, fn _, acc -> [acc] end)
    assert {:error, _} = JSON.encode(deep)

    intent = %Lunixi.Payment.Intent{
      amount: 100,
      currency: "TRY",
      order_id: "order",
      callback_url: "https://merchant.example/return",
      preauth: false,
      force_3d: false
    }

    assert Lunixi.Payment.Intent.to_map(intent)["force3D"] == false
    assert Lunixi.Payment.Intent.to_map(intent)["preauth"] == false
  end

  test "keypair validation and config JSON Inspect redaction" do
    {:ok, seed} = Signing.decode_key(fixture()["privateSeed"])
    {public, _} = :crypto.generate_key(:eddsa, :ed25519, seed)
    assert {:ok, ^seed} = Signing.decode_key(Base.encode64(seed <> public))
    assert {:error, _} = Signing.decode_key(Base.encode64(seed <> :binary.copy(<<0>>, 32)))
    assert {:error, _} = Signing.decode_key("bad-key-secret")

    config = %Lunixi.Config{
      base_url: "https://example.com",
      key_id: "private-key-id",
      private_key: "private-key-secret"
    }

    refute inspect(config) =~ "private-key-secret"
    refute Jason.encode!(config) =~ "private-key-secret"
    refute Jason.encode!(config) =~ "private-key-id"
  end

  test "shared raw v2 HMAC fixtures" do
    for vector <-
          Jason.decode!(File.read!(Path.join(__DIR__, "fixtures/webhook-v2-vectors.json"))) do
      {:ok, now, _} = DateTime.from_iso8601(vector["timestamp"])
      headers = headers(vector["eventId"], vector["timestamp"], "v2=" <> vector["expectedV2"])

      assert {:ok, event} =
               Webhook.verify(vector["rawBody"], headers, secrets: [vector["secret"]], now: now)

      assert event.id == vector["eventId"]
      assert event.raw == vector["rawBody"]
      refute inspect(event) =~ "capturedAmountMinor"
      refute Jason.encode!(event) =~ "capturedAmountMinor"
    end
  end

  test "tamper timestamp identity type duplicate and rotation guards" do
    secret = "synthetic_webhook_secret_0123456789"
    previous = "synthetic_previous_secret_0123456789"
    raw = ~s({"id":"event-1","type":"payment.captured","data":{"amountMinor":"10050"}})
    timestamp = "2026-10-31T00:00:00.000Z"
    now = DateTime.from_iso8601(timestamp) |> elem(1)
    sig = signature(previous, "event-1", timestamp, raw)
    headers = headers("event-1", timestamp, "v2=" <> String.duplicate("0", 64) <> "," <> sig)
    options = [secrets: [secret, previous], now: now]
    assert {:ok, _} = Webhook.verify(raw, headers, options)
    assert {:error, _} = Webhook.verify(raw <> " ", headers, options)

    assert {:error, _} =
             Webhook.verify(raw, headers, Keyword.put(options, :now, DateTime.add(now, 301)))

    assert {:error, _} =
             Webhook.verify(raw, headers, Keyword.put(options, :now, DateTime.add(now, -301)))

    assert {:error, _} =
             Webhook.verify(raw, headers ++ [{"X-Lunixi-Event-Id", "event-1"}], options)

    assert {:error, _} =
             Webhook.verify(raw, headers ++ [{"x-lunixi-event-type", "payment.failed"}], options)

    assert {:error, _} = Webhook.verify(raw, headers("changed", timestamp, sig), options)

    for body <- [
          ~s({"id":"changed","type":"payment.captured"}),
          ~s({"type":"a","type":"b"}),
          ~s({"data":{}})
        ] do
      assert {:error, _} =
               Webhook.verify(
                 body,
                 headers("event-1", timestamp, signature(secret, "event-1", timestamp, body)),
                 options
               )
    end

    for sig <- [
          "v1=unknown",
          "v2=" <> String.duplicate("ö", 32),
          "v2=" <> String.duplicate("a", 63),
          ""
        ] do
      assert {:error, _} = Webhook.verify(raw, headers("event-1", timestamp, sig), options)
    end
  end

  defp headers(id, timestamp, sig),
    do: [
      {"x-lunixi-event-id", id},
      {"x-lunixi-signature-timestamp", timestamp},
      {"x-lunixi-signature", sig}
    ]

  defp signature(secret, id, timestamp, body),
    do:
      "v2=" <>
        Base.encode16(:crypto.mac(:hmac, :sha256, secret, id <> "." <> timestamp <> "." <> body),
          case: :lower
        )
end
