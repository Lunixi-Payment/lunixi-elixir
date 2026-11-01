Code.require_file("checkout_presentation.exs", __DIR__)

alias Lunixi.{Client, Config, Payments}
alias Lunixi.Payment.{Intent, BasketItem}

key_id = System.fetch_env!("LUNIXI_KEY_ID")
unless String.starts_with?(key_id, "mk_test_"), do: raise("Example requires a TEST key")

config = %Config{
  base_url: System.fetch_env!("LUNIXI_BASE_URL"),
  key_id: key_id,
  private_key: System.fetch_env!("LUNIXI_PRIVATE_KEY_PEM")
}

{:ok, client} = Client.start_link(config: config)

intent = %Intent{
  amount: "10050",
  currency: "TRY",
  order_id: System.fetch_env!("LUNIXI_ORDER_ID"),
  callback_url: "https://merchant.example/payment/return",
  basket_items: [
    %BasketItem{id: "line-1", name: "Example product", item_type: "PHYSICAL", price: "10050"}
  ]
}

case Payments.create_intent(client, intent, System.fetch_env!("LUNIXI_ATTEMPT_KEY")) do
  {:ok, %{data: %{"token" => token, "paymentId" => id} = data}}
  when is_binary(token) and token != "" and is_binary(id) and id != "" ->
    mode =
      case System.get_env("LUNIXI_CHECKOUT_MODE", "embedded") do
        "embedded" -> :embedded
        "hosted" -> :hosted
        _ -> :invalid
      end

    case Lunixi.Examples.CheckoutPresentation.present(data, mode: mode) do
      {:ok, _presentation} ->
        :ok

      {:error, _} ->
        raise("Checkout presentation unavailable; retain and reconcile the existing attempt")
    end

    # In a web controller, authenticate this order's customer first, then use
    # CheckoutHTML.render(token, nonce: server_generated_csp_nonce) and no-store.
    # This CLI intentionally omits token and HTML from logs/stdout.
    IO.puts("TEST checkout ready; token omitted from output")

  {:error, error} ->
    IO.puts(:stderr, Exception.message(error))
    System.halt(1)

  _ ->
    IO.puts(:stderr, "Missing checkout token")
    System.halt(1)
end
