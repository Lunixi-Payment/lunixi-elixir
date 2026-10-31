defmodule Lunixi.CheckoutHTML do
  @moduledoc "Mounts the existing Lunixi form with a fixed official script origin. Serve only to the authenticated order customer with Cache-Control: no-store."
  @doc "Renders an HTML fragment with escaped token JSON and an optional server-generated CSP nonce. Browser completion is never financial authority."
  def render(token, opts \\ []) do
    nonce = Keyword.get(opts, :nonce)

    valid_nonce =
      is_nil(nonce) or (is_binary(nonce) and Regex.match?(~r/^[A-Za-z0-9+\/_=-]{16,128}$/, nonce))

    if is_binary(token) and byte_size(token) in 1..8192 and String.valid?(token) and valid_nonce do
      config = Jason.encode!(%{token: token}, escape: :html_safe)
      attribute = if nonce, do: ~s( nonce="#{nonce}"), else: ""

      {:ok,
       """
       <div id="lunixi-checkout-form"></div>
       <script src="https://cdn.lunixi.com/lunixi-checkout.min.js"#{attribute}></script>
       <script type="application/json" id="lunixi-checkout-config"#{attribute}>#{config}</script>
       <script#{attribute}>
       (() => {
         const settings = JSON.parse(document.getElementById('lunixi-checkout-config').textContent);
         const checkout = Lunixi.checkout.create({type: 'payment', target: 'lunixi-checkout-form', options: {token: settings.token}});
         checkout.mount('#lunixi-checkout-form');
       })();
       </script>
       """}
    else
      Lunixi.Error.invalid("CHECKOUT_TOKEN_OR_NONCE")
    end
  rescue
    _ -> Lunixi.Error.invalid("CHECKOUT_HTML")
  end
end
