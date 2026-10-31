defmodule Lunixi.Examples.CheckoutPresentation do
  @moduledoc "Merchant-controller adapter: authorize ownership/CSRF first, then send no-store HTML or an optional backend redirect. Never log either result."

  def present(data, opts \\ []) when is_map(data) do
    case Keyword.get(opts, :mode, :embedded) do
      :embedded ->
        nonce = Keyword.get(opts, :nonce)

        if is_nil(nonce) or
             (is_binary(nonce) and Regex.match?(~r/\A[A-Za-z0-9+\/_=-]{16,128}\z/, nonce)) do
          with {:ok, html} <- Lunixi.CheckoutHTML.render(data["token"], nonce: nonce) do
            {:ok, {:html, html}}
          end
        else
          Lunixi.Error.invalid("CHECKOUT_NONCE")
        end

      :hosted ->
        with {:ok, url} <- hosted_url(data["paymentPageUrl"]) do
          {:ok, {:redirect, url}}
        end

      _ ->
        Lunixi.Error.invalid("CHECKOUT_MODE")
    end
  end

  def hosted_url(value) when is_binary(value) do
    if Regex.match?(~r/\Ahttps:\/\/pay\.lunixi\.com\/payment\/[A-Za-z0-9_.~-]{16,4096}\z/, value) do
      {:ok, value}
    else
      Lunixi.Error.invalid("PAYMENT_PAGE_URL")
    end
  end

  def hosted_url(_), do: Lunixi.Error.invalid("PAYMENT_PAGE_URL")
end
