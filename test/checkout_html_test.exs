defmodule Lunixi.CheckoutHTMLTest do
  use ExUnit.Case, async: true

  test "fixed official origin and escaped data prevent script injection" do
    token = ~S|</script><script>alert("x")</script>|
    nonce = "synthetic_nonce_1234567890"
    assert {:ok, html} = Lunixi.CheckoutHTML.render(token, nonce: nonce)
    refute html =~ token
    assert html =~ "https://cdn.lunixi.com/lunixi-checkout.min.js"
    assert html =~ "checkout.mount('#lunixi-checkout-form')"
    assert html =~ ~s(nonce="#{nonce}")
    assert {:error, _} = Lunixi.CheckoutHTML.render("token", nonce: ~S|" onload="alert(1)|)
    assert {:error, _} = Lunixi.CheckoutHTML.render("")
  end
end
