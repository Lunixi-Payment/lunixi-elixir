defmodule Lunixi.Config do
  @moduledoc "Trusted merchant configuration; Inspect and JSON output redact all credentials."
  @derive {Inspect, only: [:timeout, :max_retries, :max_response_bytes]}
  @enforce_keys [:base_url, :key_id, :private_key]
  defstruct [
    :base_url,
    :key_id,
    :private_key,
    timeout: 30_000,
    max_retries: 0,
    max_response_bytes: 8_388_608,
    allow_insecure_localhost: false,
    additional_ca_certificates: []
  ]

  @type t :: %__MODULE__{}

  @doc "Validates an HTTPS origin, request limits and the Ed25519 private key before starting a client."
  def validate(%__MODULE__{} = config) do
    uri = URI.parse(config.base_url)

    valid_origin =
      is_binary(uri.host) and uri.host != "" and uri.path in [nil, "", "/"] and is_nil(uri.query) and
        is_nil(uri.fragment) and is_nil(uri.userinfo)

    secure =
      uri.scheme == "https" or
        (uri.scheme == "http" and config.allow_insecure_localhost and loopback?(uri.host))

    limits =
      is_integer(config.timeout) and config.timeout in 1..120_000 and config.max_retries in 0..5 and
        is_integer(config.max_response_bytes) and config.max_response_bytes in 1..33_554_432

    if valid_origin and secure and limits and Lunixi.Guards.header?(config.key_id, 200) and
         is_list(config.additional_ca_certificates) and
         length(config.additional_ca_certificates) <= 8 and
         Enum.all?(
           config.additional_ca_certificates,
           &(is_binary(&1) and byte_size(&1) <= 65_536)
         ) do
      with {:ok, seed} <- Lunixi.Signing.decode_key(config.private_key),
           do:
             {:ok,
              %{
                config
                | base_url: String.trim_trailing(URI.to_string(uri), "/"),
                  private_key: seed
              }}
    else
      Lunixi.Error.invalid("CONFIGURATION")
    end
  rescue
    _ -> Lunixi.Error.invalid("CONFIGURATION")
  end

  def validate(_), do: Lunixi.Error.invalid("CONFIGURATION")
  defp loopback?("localhost"), do: true

  defp loopback?(host) when is_binary(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, {127, _, _, _}} -> true
      {:ok, {0, 0, 0, 0, 0, 0, 0, 1}} -> true
      _ -> false
    end
  end

  defp loopback?(_), do: false
end

defimpl Jason.Encoder, for: Lunixi.Config do
  def encode(_, opts), do: Jason.Encode.map(%{credentials: "[REDACTED]"}, opts)
end
