defmodule Lunixi.Client do
  @moduledoc """
  Supervised per-merchant client. Token refresh and signing are serialized;
  protected API calls execute concurrently in their caller processes.
  Use a separate named child for each merchant key. State is never persisted.
  """
  use GenServer
  alias Lunixi.{Config, Error, Guards, JSON, Signing, Transport}
  @methods [:get, :post, :put, :patch, :delete]
  @doc "Starts a client with `config: %Lunixi.Config{}` and an optional supervisor name."
  def start_link(opts) do
    with {:ok, config} <- Config.validate(Keyword.get(opts, :config)) do
      GenServer.start_link(__MODULE__, config, Keyword.take(opts, [:name]))
    end
  end

  @doc false
  def child_spec(opts),
    do: %{id: Keyword.get(opts, :name, make_ref()), start: {__MODULE__, :start_link, [opts]}}

  @doc "Clears only the matching cached token; key rotation requires a new supervised client."
  def invalidate_token(client), do: call(client, {:invalidate, :all}, 5_000)
  @doc "Sends a documented merchant API request through shared signing and bounded transport."
  def request(client, method, path, opts \\ []) do
    body = Keyword.get(opts, :body)
    key = Keyword.get(opts, :idempotency_key)
    query = Keyword.get(opts, :query, [])

    with :ok <- validate(method, path, body, key),
         {:ok, encoded} <- encode_body(body),
         {:ok, target} <- target(path, query),
         {:ok, settings} <- call(client, :settings, 125_000) do
      loop(client, settings, method, target, path, encoded, key, 0, false)
    end
  rescue
    _ -> Error.invalid("REQUEST")
  end

  defp validate(method, path, body, key) do
    cond do
      method not in @methods or not Guards.path?(path) ->
        Error.invalid("METHOD_OR_PATH")

      not is_nil(key) and not Guards.key?(key) ->
        Error.invalid("IDEMPOTENCY_KEY")

      method == :get and not is_nil(body) ->
        Error.invalid("GET_BODY")

      method == :post and financial?(path) and not Guards.key?(key) ->
        Error.invalid("IDEMPOTENCY_KEY_REQUIRED")

      true ->
        validate_payment(path, body)
    end
  end

  defp validate_payment(path, body)
       when path in [
              "/api/v1/payments/intents",
              "/api/v1/payments/marketplace/intents",
              "/api/v1/payments/direct/payment"
            ] do
    cond do
      not is_map(body) ->
        Error.invalid("PAYMENT_OBJECT")

      Enum.any?(
        ["price", :price, "paidPrice", :paidPrice, "autoCapture", :autoCapture],
        &Map.has_key?(body, &1)
      ) ->
        Error.invalid("REMOVED_PAYMENT_FIELD")

      not Guards.money?(Map.get(body, "amount", Map.get(body, :amount))) ->
        Error.invalid("INTEGER_MINOR_AMOUNT")

      path == "/api/v1/payments/intents" and
          (Map.has_key?(body, "installment") or Map.has_key?(body, :installment)) ->
        Error.invalid("INTENT_INSTALLMENT")

      true ->
        :ok
    end
  end

  defp validate_payment(_, _), do: :ok

  defp financial?(path),
    do:
      path in [
        "/api/v1/payments/intents",
        "/api/v1/payments/marketplace/intents",
        "/api/v1/payments/direct/payment",
        "/api/v1/payments/split"
      ] or
        (String.starts_with?(path, "/api/v1/payments/") and
           String.ends_with?(path, ["/capture", "/refund", "/void"]))

  defp encode_body(nil), do: {:ok, nil}

  defp encode_body(body) do
    with {:ok, encoded} <- JSON.encode(body) do
      if byte_size(encoded) <= 8_388_608, do: {:ok, encoded}, else: Error.invalid("BODY_SIZE")
    end
  end

  defp target(path, query) do
    encoded = if query in [[], %{}], do: "", else: "?" <> URI.encode_query(query)
    value = path <> encoded
    if byte_size(value) <= 16_384, do: {:ok, value}, else: Error.invalid("QUERY_SIZE")
  end

  defp loop(client, settings, method, target, path, body, key, retries, refreshed) do
    safe = method == :get or not is_nil(key)

    with {:ok, token} <- call(client, :token, settings.timeout + 1_000),
         {:ok, headers} <- call(client, {:sign, method, target, body}, settings.timeout + 1_000) do
      result = Transport.exchange(settings, method, target, body, headers, token, key)

      cond do
        match?({:ok, %{status: status}} when status in 200..299, result) ->
          result

        pending_split?(path, result) ->
          result

        match?({:ok, %{status: 401}}, result) and safe and not refreshed ->
          call(client, {:invalidate, token}, 5_000)
          loop(client, settings, method, target, path, body, key, retries, true)

        safe and retries < settings.max_retries and retry?(result) ->
          Process.sleep(100 * Integer.pow(2, retries))
          loop(client, settings, method, target, path, body, key, retries + 1, refreshed)

        true ->
          as_result(result)
      end
    end
  end

  defp retry?({:error, %Error{kind: kind}}), do: kind in [:transport, :response]
  defp retry?({:ok, %{status: status}}), do: status in [429, 500, 502, 503, 504]

  defp as_result({:ok, response}) do
    code = if is_map(response.envelope), do: Map.get(response.envelope, "code")

    code =
      if is_binary(code) and Regex.match?(~r/^[A-Za-z0-9_.:-]{1,128}$/, code),
        do: code,
        else: "HTTP_ERROR"

    {:error,
     %Error{kind: :api, status: response.status, code: code, request_id: response.request_id}}
  end

  defp as_result(error), do: error

  defp pending_split?("/api/v1/payments/split", {:ok, %{status: 400, data: data}})
       when is_map(data),
       do:
         is_binary(data["splitPaymentId"]) and
           data["status"] in [
             "COMPOSING",
             "AUTHORIZING",
             "AWAITING_3DS",
             "AWAITING_ACTION",
             "AWAITING_CREDIT_APPROVAL",
             "AWAITING_REPLACEMENT_CARD",
             "AUTHORIZED",
             "CAPTURING"
           ]

  defp pending_split?(_, _), do: false

  defp call(client, message, timeout) do
    GenServer.call(client, message, timeout)
  catch
    :exit, _ -> {:error, %Error{kind: :transport, code: "CLIENT_UNAVAILABLE"}}
  end

  @impl true
  def init(config), do: {:ok, %{config: config, token: nil, expiry: 0}}
  @impl true
  def handle_call(:settings, _from, state),
    do: {:reply, {:ok, %{state.config | private_key: nil, key_id: nil}}, state}

  def handle_call({:invalidate, token}, _from, state) do
    state =
      if token == :all or token == state.token, do: %{state | token: nil, expiry: 0}, else: state

    {:reply, :ok, state}
  end

  def handle_call({:sign, method, path, body}, _from, state),
    do: {:reply, {:ok, Signing.headers(state.config, method, path, body)}, state}

  def handle_call(:token, _from, state) do
    if state.token && System.monotonic_time(:millisecond) < state.expiry do
      {:reply, {:ok, state.token}, state}
    else
      case authenticate(state.config) do
        {:ok, token, lifetime} ->
          {:reply, {:ok, token},
           %{state | token: token, expiry: System.monotonic_time(:millisecond) + lifetime}}

        error ->
          {:reply, error, state}
      end
    end
  end

  defp authenticate(config) do
    headers = Signing.headers(config, :post, "/api/v1/auth/token", nil)

    case Transport.exchange(config, :post, "/api/v1/auth/token", nil, headers, nil, nil) do
      {:ok, %{status: status, data: data}} when status in 200..299 and is_map(data) ->
        token = data["access_token"]
        ttl = data["expires_in"]

        if Guards.header?(token, 8192) and is_integer(ttl) and ttl in 1..86_400 do
          {:ok, token, ttl * 1_000 - min(30_000, div(ttl * 1_000, 2))}
        else
          {:error, %Error{kind: :response, code: "AUTH_RESPONSE"}}
        end

      {:ok, _} = response ->
        as_result(response)

      error ->
        error
    end
  end

  @impl true
  def format_status(status),
    do:
      Map.new(status, fn {key, value} ->
        {key,
         if(key in [:state, :message, :reason],
           do: :redacted,
           else: if(key == :log, do: [], else: value)
         )}
      end)
end
