defmodule Lunixi.JSON do
  @moduledoc "Strict JSON and JavaScript-compatible canonical bodies. Never re-encode webhook bytes for HMAC."
  @max 9_007_199_254_740_991
  @doc "Decodes without duplicate keys, preserving object insertion order."
  def decode_ordered(bytes) when is_binary(bytes) do
    with {:ok, value} <- Jason.decode(bytes, objects: :ordered_objects),
         :ok <- validate(value, 0),
         do: {:ok, value}
  rescue
    _ -> Lunixi.Error.invalid("JSON_BODY")
  end

  def decode_ordered(_), do: Lunixi.Error.invalid("JSON_BODY")
  @doc "Decodes strict JSON to string-keyed maps without creating atoms."
  def decode(bytes), do: with({:ok, value} <- decode_ordered(bytes), do: {:ok, maps(value)})
  @doc "Encodes compact JSON with JS integer-index ordering and number formatting."
  def encode(value) do
    with :ok <- validate(value, 0), do: {:ok, IO.iodata_to_binary(write(value))}
  rescue
    _ -> Lunixi.Error.invalid("JSON_BODY")
  end

  defp validate(_, depth) when depth > 64, do: Lunixi.Error.invalid("JSON_DEPTH")

  defp validate(%Jason.OrderedObject{values: values}, depth) do
    keys = Enum.map(values, fn {key, _} -> to_string(key) end)

    if length(Enum.uniq(keys)) != length(keys),
      do: Lunixi.Error.invalid("DUPLICATE_JSON_KEY"),
      else: validate_values(values, depth)
  end

  defp validate(%_module{}, _depth), do: Lunixi.Error.invalid("JSON_STRUCT")

  defp validate(value, depth) when is_map(value),
    do: validate(%Jason.OrderedObject{values: Map.to_list(value)}, depth)

  defp validate(value, depth) when is_list(value), do: all_valid(value, &validate(&1, depth + 1))

  defp validate(value, _) when is_integer(value) and abs(value) > @max,
    do: Lunixi.Error.invalid("UNSAFE_JSON_INTEGER")

  defp validate(value, _) when is_float(value) and abs(value) > @max and trunc(value) == value,
    do: Lunixi.Error.invalid("UNSAFE_JSON_INTEGER")

  defp validate(value, _) when is_binary(value),
    do: if(String.valid?(value), do: :ok, else: Lunixi.Error.invalid("JSON_UTF8"))

  defp validate(value, _) when is_number(value) or is_boolean(value) or is_nil(value), do: :ok
  defp validate(_, _), do: Lunixi.Error.invalid("JSON_VALUE")

  defp validate_values(values, depth) do
    all_valid(values, fn {key, value} ->
      if is_atom(key) or is_binary(key),
        do: validate(value, depth + 1),
        else: Lunixi.Error.invalid("JSON_KEY")
    end)
  end

  defp all_valid(values, fun),
    do:
      Enum.reduce_while(values, :ok, fn value, :ok ->
        case fun.(value) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)

  defp maps(%Jason.OrderedObject{values: values}),
    do: Map.new(values, fn {k, v} -> {k, maps(v)} end)

  defp maps(values) when is_list(values), do: Enum.map(values, &maps/1)
  defp maps(value), do: value
  defp write(%Jason.OrderedObject{values: values}), do: object(values)

  defp write(value) when is_map(value),
    do: value |> Enum.sort_by(fn {k, _} -> to_string(k) end) |> object()

  defp write(values) when is_list(values),
    do: ["[", Enum.intersperse(Enum.map(values, &write/1), ","), "]"]

  defp write(value) when is_float(value), do: float(value)
  defp write(value), do: Jason.encode!(value, escape: :json)

  defp object(values) do
    sorted =
      values
      |> Enum.with_index()
      |> Enum.sort_by(fn {{k, _}, index} ->
        case index_key(to_string(k)) do
          nil -> {1, index}
          n -> {0, n}
        end
      end)

    [
      "{",
      Enum.intersperse(
        Enum.map(sorted, fn {{k, v}, _} -> [Jason.encode!(to_string(k)), ":", write(v)] end),
        ","
      ),
      "}"
    ]
  end

  defp index_key(key) do
    case Integer.parse(key) do
      {n, ""} when n >= 0 and n < 4_294_967_295 -> if Integer.to_string(n) == key, do: n
      _ -> nil
    end
  end

  defp float(value) when value == 0.0, do: "0"

  defp float(value) do
    text = :erlang.float_to_binary(value, [:short])
    [mantissa | exponent] = String.split(text, "e")

    exp =
      case exponent do
        [] -> 0
        [e] -> String.to_integer(e)
      end

    sign = if String.starts_with?(mantissa, "-"), do: "-", else: ""
    mantissa = String.trim_leading(mantissa, "-")
    [whole | fraction] = String.split(mantissa, ".")
    decimals = Enum.join(fraction)
    digits = String.trim_trailing(whole <> decimals, "0")
    digits = if digits == "", do: "0", else: digits
    position = byte_size(whole) + exp

    if abs(value) >= 1.0e-6 and abs(value) < 1.0e21 do
      sign <>
        cond do
          position <= 0 ->
            "0." <> String.duplicate("0", -position) <> digits

          position >= byte_size(digits) ->
            digits <> String.duplicate("0", position - byte_size(digits))

          true ->
            binary_part(digits, 0, position) <>
              "." <> binary_part(digits, position, byte_size(digits) - position)
        end
    else
      power = position - 1
      tail = binary_part(digits, 1, byte_size(digits) - 1)

      sign <>
        binary_part(digits, 0, 1) <>
        if(tail == "", do: "", else: "." <> tail) <>
        "e" <> if(power >= 0, do: "+", else: "") <> Integer.to_string(power)
    end
  end
end
