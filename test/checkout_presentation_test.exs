Code.require_file("../examples/checkout_presentation.exs", __DIR__)

defmodule Lunixi.CheckoutPresentationTest do
  use ExUnit.Case, async: true
  alias Lunixi.Examples.CheckoutPresentation

  test "embedded is default and mounts the original form without requiring a hosted URL" do
    token = "</script><svg/onload=unexpected()>"
    assert {:ok, {:html, html}} = CheckoutPresentation.present(%{"token" => token})
    refute String.contains?(html, token)
    assert String.contains?(html, "https://cdn.lunixi.com/lunixi-checkout.min.js")
    assert String.contains?(html, "checkout.mount('#lunixi-checkout-form')")

    assert {:error, _} =
             CheckoutPresentation.present(%{"token" => token}, nonce: "bad_nonce_123456789\n")
  end

  test "optional redirect uses an independent backend token and fails closed on missing URL" do
    url = "https://pay.lunixi.com/payment/independent-hosted-token-12345"

    assert {:ok, {:redirect, ^url}} =
             CheckoutPresentation.present(
               %{"token" => "different-browser-token", "paymentPageUrl" => url},
               mode: :hosted
             )

    assert {:error, _} =
             CheckoutPresentation.present(%{"token" => "browser-token"}, mode: :hosted)

    for bad <- [
          nil,
          "http://pay.lunixi.com/payment/opaque-hosted-token-1234",
          "https://evil.example/payment/opaque-hosted-token-1234",
          "https://pay.lunixi.com:443/payment/opaque-hosted-token-1234",
          "https://user@pay.lunixi.com/payment/opaque-hosted-token-1234",
          url <> "?x=1",
          url <> "#x",
          url <> "\n",
          "https://pay.lunixi.com/payment/short",
          "https://pay.lunixi.com/payment/escaped%2Ftoken-12345"
        ] do
      assert {:error, _} = CheckoutPresentation.hosted_url(bad)
    end
  end
end
