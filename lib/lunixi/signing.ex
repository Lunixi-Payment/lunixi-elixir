defmodule Lunixi.Signing do
  @moduledoc "OTP-backed Ed25519 signing and the gateway's exact canonical request format."
  @doc "Decodes PKCS8 PEM/DER or a base64 32-byte Ed25519 seed/validated 64-byte keypair."
  def decode_key(value) when is_binary(value) do
    if String.contains?(value, "-----BEGIN") do
      case :public_key.pem_decode(value) do
        [{:PrivateKeyInfo, der, :not_encrypted}] -> decode_der(der)
        _ -> Lunixi.Error.invalid("ED25519_PRIVATE_KEY")
      end
    else
      with {:ok, raw} <- Base.decode64(String.trim(value)) do
        case raw do
          <<seed::binary-size(32)>> ->
            {:ok, seed}

          <<seed::binary-size(32), public::binary-size(32)>> ->
            {expected, _} = :crypto.generate_key(:eddsa, :ed25519, seed)

            if :crypto.hash_equals(expected, public),
              do: {:ok, seed},
              else: Lunixi.Error.invalid("ED25519_KEYPAIR")

          _ ->
            decode_der(raw)
        end
      else
        _ -> Lunixi.Error.invalid("ED25519_PRIVATE_KEY")
      end
    end
  rescue
    _ -> Lunixi.Error.invalid("ED25519_PRIVATE_KEY")
  end

  def decode_key(_), do: Lunixi.Error.invalid("ED25519_PRIVATE_KEY")

  defp decode_der(der) do
    case :public_key.der_decode(:PrivateKeyInfo, der) do
      {:ECPrivateKey, 1, <<seed::binary-size(32)>>, {:namedCurve, {1, 3, 101, 112}}, _, _} ->
        {:ok, seed}

      _ ->
        Lunixi.Error.invalid("ED25519_PKCS8")
    end
  rescue
    _ -> Lunixi.Error.invalid("ED25519_PKCS8")
  end

  @doc "Returns the SHA-256 body Digest header."
  def digest(bytes), do: "SHA-256=" <> Base.encode64(:crypto.hash(:sha256, bytes))
  @doc "Builds the exact canonical method/path/date/nonce/optional-digest string."
  def canonical(method, path, date, nonce, digest \\ nil) do
    fields = [String.upcase(to_string(method)), path, "X-Date:" <> date, "X-Nonce:" <> nonce]
    Enum.join(if(digest, do: fields ++ ["Digest:" <> digest], else: fields), "\n")
  end

  @doc false
  def headers(config, method, path, body) do
    date = DateTime.utc_now(:millisecond) |> DateTime.to_iso8601()
    nonce = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    digest = if is_binary(body), do: digest(body)

    signature =
      :crypto.sign(:eddsa, :none, canonical(method, path, date, nonce, digest), [
        config.private_key,
        :ed25519
      ])
      |> Base.encode64()

    headers = [
      {"x-key-id", config.key_id},
      {"x-date", date},
      {"x-nonce", nonce},
      {"x-signature", signature}
    ]

    if digest,
      do: headers ++ [{"digest", digest}, {"content-type", "application/json"}],
      else: headers
  end
end
