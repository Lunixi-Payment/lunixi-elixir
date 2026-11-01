defmodule Lunixi.Transport do
  @moduledoc false
  alias Lunixi.{Error, JSON, Response}

  def exchange(settings, method, path, body, signed_headers, token, key) do
    headers =
      signed_headers ++ [{"accept", "application/json"}, {"user-agent", "lunixi-elixir/1.0.0"}]

    headers = if token, do: headers ++ [{"authorization", "Bearer " <> token}], else: headers
    headers = if key, do: headers ++ [{"idempotency-key", key}], else: headers

    roots =
      if settings.additional_ca_certificates == [],
        do: :public_key.cacerts_get(),
        else: :public_key.cacerts_get() ++ settings.additional_ca_certificates

    into = fn {:data, chunk}, {request, response} ->
      case response.body do
        :lunixi_too_large ->
          {:halt, {request, response}}

        acc when byte_size(acc) + byte_size(chunk) > settings.max_response_bytes ->
          {:halt, {request, %{response | body: :lunixi_too_large}}}

        acc ->
          {:cont, {request, %{response | body: acc <> chunk}}}
      end
    end

    options = [
      url: settings.base_url <> path,
      method: method,
      headers: headers,
      body: body,
      retry: false,
      retry_log_level: false,
      redirect: false,
      raw: true,
      compressed: false,
      receive_timeout: settings.timeout,
      request_timeout: settings.timeout,
      connect_options: [
        timeout: min(settings.timeout, 10_000),
        protocols: [:http1],
        transport_opts: [verify: :verify_peer, cacerts: roots]
      ],
      into: into
    ]

    case Req.request(options) do
      {:ok, %{body: :lunixi_too_large}} -> {:error, %Error{kind: :response, code: "SIZE_LIMIT"}}
      {:ok, response} -> parse(response)
      {:error, _} -> {:error, %Error{kind: :transport, code: "REQUEST_FAILED"}}
    end
  rescue
    _ -> {:error, %Error{kind: :transport, code: "REQUEST_FAILED"}}
  catch
    _, _ -> {:error, %Error{kind: :transport, code: "REQUEST_FAILED"}}
  end

  defp parse(response) do
    content_type = List.first(Req.Response.get_header(response, "content-type"))
    request_id = List.first(Req.Response.get_header(response, "x-request-id"))
    request_id = if Lunixi.Guards.header?(request_id, 200), do: request_id

    result = %Response{
      status: response.status,
      request_id: request_id,
      content_type: content_type
    }

    if (is_binary(content_type) and String.contains?(String.downcase(content_type), "json")) or
         String.starts_with?(String.trim_leading(response.body), ["{", "["]) do
      case JSON.decode(response.body) do
        {:ok, envelope} ->
          {:ok,
           %{
             result
             | envelope: envelope,
               data:
                 if(is_map(envelope), do: Map.get(envelope, "data", envelope), else: envelope),
               page_info: if(is_map(envelope), do: Map.get(envelope, "pageInfo"))
           }}

        _ ->
          {:error, %Error{kind: :response, code: "INVALID_JSON"}}
      end
    else
      {:ok, %{result | bytes: response.body}}
    end
  end
end
