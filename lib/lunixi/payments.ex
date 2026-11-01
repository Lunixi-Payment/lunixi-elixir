defmodule Lunixi.Payments do
  @moduledoc "Typed checkout form and payment lifecycle methods sharing one supervised client."
  alias Lunixi.{Client, Error, Guards}
  alias Lunixi.Payment.Intent
  @doc "Creates a checkout form intent with a persisted per-attempt idempotency key."
  def create_intent(client, %Intent{} = intent, key) do
    with :ok <- Intent.validate(intent),
         do:
           Client.request(client, :post, "/api/v1/payments/intents",
             body: Intent.to_map(intent),
             idempotency_key: key
           )
  end

  @doc "Reads authoritative gateway state for reconciliation."
  def get(client, id),
    do: with_id(id, fn -> Client.request(client, :get, "/api/v1/payments/" <> id) end)

  @doc "Lists payments without discarding envelope pagination metadata."
  def list(client, query \\ []),
    do: Client.request(client, :get, "/api/v1/payments", query: query)

  @doc "Lists enabled payment method/provider capabilities, optionally filtered by method."
  def methods(client, method \\ nil),
    do:
      Client.request(client, :get, "/api/v1/payments/methods",
        query: if(method, do: [{"paymentMethod", method}], else: [])
      )

  @doc "Captures the remaining authorization without an amount field."
  def capture_remaining(client, id, key), do: send_mutation(client, "capture", id, %{}, nil, key)
  @doc "Refunds the remaining balance without an amount field."
  def refund_remaining(client, id, reason, key), do: send_mutation(client, "refund", id, %{}, reason, key)
  @doc "Captures a positive minor-unit string amount; nil is invalid."
  def capture(client, id, amount, key), do: mutation(client, "capture", id, amount, nil, key)
  @doc "Refunds a positive minor-unit string amount; nil is invalid."
  def refund(client, id, amount, reason, key),
    do: mutation(client, "refund", id, amount, reason, key)

  @doc "Releases an authorization; this is not a captured payment refund."
  def void(client, id, key),
    do:
      with_id(id, fn ->
        Client.request(client, :post, "/api/v1/payments/#{id}/void", idempotency_key: key)
      end)

  defp mutation(client, action, id, amount, reason, key) do
    if Guards.money?(amount) do
      send_mutation(client, action, id, %{"amount" => amount}, reason, key)
    else
      Error.invalid("MUTATION_AMOUNT_OR_REASON")
    end
  end

  defp send_mutation(client, action, id, amounts, reason, key) do
    if is_nil(reason) or (is_binary(reason) and byte_size(reason) <= 500) do
      body = Map.merge(%{"paymentIntentId" => id}, amounts) |> optional("reason", reason)
      with_id(id, fn ->
        Client.request(client, :post, "/api/v1/payments/#{id}/#{action}",
          body: body,
          idempotency_key: key
        )
      end)
    else
      Error.invalid("MUTATION_AMOUNT_OR_REASON")
    end
  end

  @doc "Starts/continues split payment; pending HTTP 400 remains an explicitly unpaid response."
  def split(client, body, key) when is_map(body) do
    legs = Map.get(body, "legs")

    valid =
      Guards.money?(body["totalAmount"]) and Guards.currency?(body["currency"]) and
        is_binary(body["ownerRef"]) and body["ownerRef"] != "" and is_list(legs) and
        length(legs) in 1..5

    if valid and Enum.all?(legs, &(is_map(&1) and Guards.money?(&1["amount"]))) and
         Enum.sum(Enum.map(legs, &String.to_integer(&1["amount"]))) == String.to_integer(body["totalAmount"]) do
      Client.request(client, :post, "/api/v1/payments/split", body: body, idempotency_key: key)
    else
      Error.invalid("SPLIT_AMOUNT_OR_LEGS")
    end
  end

  def split(_, _, _), do: Error.invalid("SPLIT_OBJECT")
  @doc "Reads aggregate split/leg state; check final capture and balance before fulfillment."
  def get_split(client, id),
    do: with_id(id, fn -> Client.request(client, :get, "/api/v1/payments/split/" <> id) end)

  @doc "Requests allocation of a split refund; partial/uncertain outcomes require reconciliation."
  def refund_split(client, id, amount, reason, key) do
    if Guards.money?(amount) and
         (is_nil(reason) or (is_binary(reason) and byte_size(reason) <= 500)) do
      with_id(id, fn ->
        Client.request(client, :post, "/api/v1/payments/split/#{id}/refund",
          body: optional(%{"amount" => amount}, "reason", reason),
          idempotency_key: key
        )
      end)
    else
      Error.invalid("SPLIT_REFUND_AMOUNT")
    end
  end

  defp optional(map, _key, nil), do: map
  defp optional(map, key, value), do: Map.put(map, key, value)
  defp with_id(id, fun), do: if(Guards.id?(id), do: fun.(), else: Error.invalid("RESOURCE_ID"))
end
