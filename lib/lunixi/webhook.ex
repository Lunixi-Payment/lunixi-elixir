defmodule Lunixi.Webhook.Event do
  @moduledoc "Authenticated event returned by the verifier. Use only values returned by verify/3."
  @derive {Inspect, only: [:id, :type, :timestamp]}
  @enforce_keys [:id, :type, :timestamp, :data, :raw]
  defstruct [:id, :type, :timestamp, :data, :raw]
  @type t :: %__MODULE__{}
end

defimpl Jason.Encoder, for: Lunixi.Webhook.Event do
  def encode(event, opts),
    do: Jason.Encode.map(%{id: event.id, type: event.type, data: "[REDACTED]"}, opts)
end

defmodule Lunixi.Webhook do
  @moduledoc "Strict raw-body v2 HMAC verification with timestamp freshness, identity/type binding and secret rotation."
  @doc "Verifies raw bytes with a list of header pairs; duplicates must not be combined by middleware."
  def verify(raw, headers, opts) do
    secrets = Keyword.fetch!(opts, :secrets)
    tolerance = Keyword.get(opts, :tolerance_seconds, 300)
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

    with true <- is_binary(raw) and byte_size(raw) in 1..8_388_608,
         true <-
           is_list(secrets) and length(secrets) in 1..3 and
             Enum.all?(secrets, &(is_binary(&1) and byte_size(&1) in 16..1024)),
         true <- is_integer(tolerance) and tolerance in 1..900,
         {:ok, id} <- header(headers, "x-lunixi-event-id"),
         true <- Lunixi.Guards.header?(id, 200),
         {:ok, timestamp} <- header(headers, "x-lunixi-signature-timestamp"),
         true <- is_binary(timestamp) and byte_size(timestamp) <= 100,
         {:ok, signature} <- header(headers, "x-lunixi-signature"),
         true <- is_binary(signature) and byte_size(signature) <= 1024,
         {:ok, time, _} <- DateTime.from_iso8601(timestamp),
         true <- abs(DateTime.diff(now, time, :millisecond)) <= tolerance * 1000,
         true <- valid_mac?(secrets, signature, id <> "." <> timestamp <> "." <> raw),
         {:ok, body} <- Lunixi.JSON.decode(raw),
         true <- is_map(body),
         true <- Lunixi.Guards.header?(body["type"], 200),
         true <- not Map.has_key?(body, "id") or body["id"] == id,
         {:ok, kind} <- header(headers, "x-lunixi-event-type"),
         true <- is_nil(kind) or kind == body["type"] do
      {:ok,
       %Lunixi.Webhook.Event{
         id: id,
         type: body["type"],
         timestamp: time,
         data: body["data"],
         raw: raw
       }}
    else
      _ -> {:error, %Lunixi.Error{kind: :webhook, code: "VERIFICATION_FAILED"}}
    end
  rescue
    _ -> {:error, %Lunixi.Error{kind: :webhook, code: "VERIFICATION_FAILED"}}
  end

  defp header(headers, name) when is_list(headers) do
    case for {key, value} <- headers, is_binary(key), String.downcase(key) == name, do: value do
      [] -> {:ok, nil}
      [value] when is_binary(value) -> {:ok, value}
      _ -> :error
    end
  end

  defp header(_, _), do: :error

  defp valid_mac?(secrets, signature, input) do
    parts = String.split(signature, ",")

    if length(parts) > 8 do
      false
    else
      for secret <- secrets, part <- parts do
        expected = :crypto.mac(:hmac, :sha256, secret, input)

        case String.split(String.trim(part), "=", parts: 2) do
          ["v2", hex] ->
            case Base.decode16(String.trim(hex), case: :mixed) do
              {:ok, actual} when byte_size(actual) == 32 -> :crypto.hash_equals(expected, actual)
              _ -> false
            end

          _ ->
            false
        end
      end
      |> Enum.reduce(false, fn value, acc -> value or acc end)
    end
  end
end
