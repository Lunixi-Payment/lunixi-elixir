defmodule Lunixi.Payment.BasketItem do
  @moduledoc "A trusted checkout line; price is the integer minor-unit line total."
  @derive {Inspect, only: [:item_type, :price]}
  @enforce_keys [:id, :name, :item_type, :price]
  defstruct [
    :id,
    :name,
    :item_type,
    :price,
    :category1,
    :category2,
    :insurance_category,
    :insurance_data,
    insurance_types: []
  ]

  @type t :: %__MODULE__{}
  @doc false
  def to_map(item),
    do:
      item
      |> Map.from_struct()
      |> Enum.reject(fn {_, value} -> value in [nil, []] end)
      |> Map.new(fn {k, v} -> {Lunixi.Payment.Intent.camel(k), v} end)
end

defmodule Lunixi.Payment.Intent do
  @moduledoc "Hosted checkout request. No raw card, installment or removed amount fields."
  @derive {Inspect, only: [:amount, :currency, :preauth]}
  @enforce_keys [:amount, :currency, :order_id, :callback_url]
  defstruct [
    :amount,
    :currency,
    :order_id,
    :callback_url,
    :buyer,
    :billing_address,
    :shipping_address,
    :description,
    :customer_id,
    :card_user_key,
    :payment_method,
    :wallet_provider,
    :payment_channel,
    :payment_group,
    :locale,
    :preauth,
    :force_3d,
    :metadata,
    :settings,
    basket_items: []
  ]

  @type t :: %__MODULE__{}
  @doc false
  def validate(%__MODULE__{} = intent) do
    uri = URI.parse(intent.callback_url)

    valid_url =
      uri.scheme == "https" and is_binary(uri.host) and is_nil(uri.userinfo) and
        is_nil(uri.fragment)

    valid_order =
      is_binary(intent.order_id) and String.trim(intent.order_id) != "" and
        byte_size(intent.order_id) <= 200

    booleans = intent.preauth in [nil, true, false] and intent.force_3d in [nil, true, false]

    if Lunixi.Guards.money?(intent.amount) and Lunixi.Guards.currency?(intent.currency) and
         valid_url and valid_order and booleans and basket?(intent) do
      :ok
    else
      Lunixi.Error.invalid("INTENT")
    end
  rescue
    _ -> Lunixi.Error.invalid("INTENT")
  end

  def validate(_), do: Lunixi.Error.invalid("INTENT")
  defp basket?(%{basket_items: []}), do: true

  defp basket?(intent) do
    is_list(intent.basket_items) and
      Enum.all?(intent.basket_items, fn
        %Lunixi.Payment.BasketItem{} = item ->
          Lunixi.Guards.money?(item.price) and is_binary(item.id) and item.id != "" and
            is_binary(item.name) and item.name != "" and item.item_type in ["PHYSICAL", "VIRTUAL"]

        _ ->
          false
      end) and Enum.sum(Enum.map(intent.basket_items, & &1.price)) == intent.amount
  end

  @doc "Converts the documented request to string-keyed JSON fields without dropping false."
  def to_map(intent),
    do:
      intent
      |> Map.from_struct()
      |> Enum.reject(fn {_, value} -> value in [nil, []] end)
      |> Map.new(fn {k, v} ->
        {camel(k),
         if(k == :basket_items, do: Enum.map(v, &Lunixi.Payment.BasketItem.to_map/1), else: v)}
      end)

  @doc false
  def camel(:force_3d), do: "force3D"

  def camel(key) do
    [first | rest] = key |> Atom.to_string() |> String.split("_")
    first <> Enum.map_join(rest, &String.capitalize/1)
  end
end
