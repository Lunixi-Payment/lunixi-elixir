defmodule Lunixi.TransportTest do
  use ExUnit.Case, async: false
  @moduletag capture_log: true
  alias Lunixi.{Client, Payments, TestTLS}
  defp token, do: ~s({"access_token":"at_TEST_fixture","expires_in":1800})

  defp validate(request) do
    assert request.headers["x-key-id"] == "mk_test_fixture"

    canonical =
      request.method <>
        "\n" <>
        request.path <>
        "\nX-Date:" <> request.headers["x-date"] <> "\nX-Nonce:" <> request.headers["x-nonce"]

    canonical =
      if request.body == "" do
        refute Map.has_key?(request.headers, "digest")
        canonical
      else
        expected = "SHA-256=" <> Base.encode64(:crypto.hash(:sha256, request.body))
        assert request.headers["digest"] == expected
        canonical <> "\nDigest:" <> expected
      end

    seed = Base.decode64!("AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=")
    {public, _} = :crypto.generate_key(:eddsa, :ed25519, seed)

    assert :crypto.verify(
             :eddsa,
             :none,
             canonical,
             Base.decode64!(request.headers["x-signature"]),
             [public, :ed25519]
           )

    if request.path == "/api/v1/auth/token",
      do: refute(Map.has_key?(request.headers, "authorization"))
  end

  test "real TLS signatures query envelope and concurrent token single flight" do
    {:ok, counts} = Agent.start_link(fn -> %{auth: 0, calls: 0} end)

    server =
      TestTLS.start(fn request ->
        validate(request)

        if request.path == "/api/v1/auth/token" do
          Agent.update(counts, &Map.update!(&1, :auth, fn n -> n + 1 end))
          {200, token()}
        else
          Agent.update(counts, &Map.update!(&1, :calls, fn n -> n + 1 end))
          assert request.headers["authorization"] == "Bearer at_TEST_fixture"
          assert request.path =~ "%C5%9E"
          {200, ~s({"data":{"items":[]},"pageInfo":{"hasNextPage":false}})}
        end
      end)

    client = start_supervised!({Client, config: TestTLS.config(server)})

    results =
      1..24
      |> Task.async_stream(
        fn _ ->
          Client.request(client, :get, "/api/v1/payments", query: [{"search", "Şükrü & Co"}])
        end,
        max_concurrency: 24,
        timeout: 10_000
      )
      |> Enum.to_list()

    assert Enum.all?(results, fn {:ok, {:ok, response}} ->
             response.status == 200 and response.page_info == %{"hasNextPage" => false}
           end)

    assert Agent.get(counts, & &1) == %{auth: 1, calls: 24}
    refute inspect(:sys.get_status(client)) =~ "at_TEST_fixture"
    refute inspect(:sys.get_status(client)) =~ "AAECAwQFBgc"
  end

  test "keyed retry preserves body and key with fresh nonce; unkeyed mutation never retries" do
    {:ok, calls} = Agent.start_link(fn -> [] end)

    server =
      TestTLS.start(fn request ->
        validate(request)

        if request.path == "/api/v1/auth/token" do
          {200, token()}
        else
          previous = Agent.get_and_update(calls, fn seen -> {seen, seen ++ [request]} end)

          case previous do
            [] ->
              {503, ~s({"code":"unavailable"})}

            [first] ->
              assert first.body == request.body
              assert request.headers["idempotency-key"] == "attempt-0000000001"
              refute first.headers["x-nonce"] == request.headers["x-nonce"]
              {200, ~s({"data":{"status":"CAPTURED"}})}
          end
        end
      end)

    client = start_supervised!({Client, config: TestTLS.config(server, max_retries: 2)})
    assert {:ok, _} = Payments.capture(client, "p", 100, "attempt-0000000001")
    assert length(Agent.get(calls, & &1)) == 2
    Agent.update(calls, fn _ -> [] end)
    assert {:error, error} = Lunixi.Fraud.evaluate(client, %{"transactionRef" => "order-1"})
    refute Exception.message(error) =~ "private"
    assert length(Agent.get(calls, & &1)) == 1
  end

  test "401 refresh once and token expiry margin" do
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    server =
      TestTLS.start(fn request ->
        if request.path == "/api/v1/auth/token" do
          n = Agent.get_and_update(calls, fn n -> {n, n + 1} end)
          {200, Jason.encode!(%{access_token: "at_TEST_#{n}", expires_in: 1})}
        else
          if request.headers["authorization"] == "Bearer at_TEST_0",
            do: {401, ~s({"code":"expired"})},
            else: {200, ~s({"data":{}})}
        end
      end)

    client = start_supervised!({Client, config: TestTLS.config(server)})
    assert {:ok, _} = Payments.get(client, "p")
    assert Agent.get(calls, & &1) == 2
    Process.sleep(650)
    assert {:ok, _} = Payments.get(client, "p")
    assert Agent.get(calls, & &1) == 3
  end

  test "redirect does not leak credentials and default TLS rejects untrusted certificate" do
    parent = self()

    attacker =
      TestTLS.start(fn _ ->
        send(parent, :leaked)
        {200, "{}"}
      end)

    server =
      TestTLS.start(fn request ->
        if request.path == "/api/v1/auth/token",
          do: {200, token()},
          else: {307, "{}", [{"location", attacker.url <> "/api/v1/payments"}]}
      end)

    client = start_supervised!({Client, config: TestTLS.config(server)})
    assert {:error, %{kind: :api, status: 307}} = Payments.get(client, "p")
    refute_received :leaked
    config = %{TestTLS.config(server) | additional_ca_certificates: []}
    {:ok, other} = Client.start_link(config: config)
    assert {:error, %{kind: :transport}} = Payments.get(other, "p")
    GenServer.stop(other)
  end

  test "configuration and input guards prevent any request" do
    source = Jason.decode!(File.read!(Path.join(__DIR__, "fixtures/canonical-vectors.json")))

    for base <- [
          "http://example.com",
          "http://localhost.evil.test",
          "https://user:secret@example.com",
          "https://example.com/path",
          "https://example.com?",
          "https://example.com#x"
        ] do
      assert {:error, _} =
               Client.start_link(
                 config: %Lunixi.Config{
                   base_url: base,
                   key_id: "key",
                   private_key: source["privateSeed"],
                   allow_insecure_localhost: true
                 }
               )
    end

    parent = self()

    server =
      TestTLS.start(fn _ ->
        send(parent, :network)
        {500, "{}"}
      end)

    client = start_supervised!({Client, config: TestTLS.config(server)})

    for path <- [
          "https://evil.example/api/v1/payments",
          "/api/v1/../auth",
          "/api/v1/%2e%2e/auth",
          "/api/v1/payments?secret=x",
          "/api/v1/auth/token",
          "/api/v1/auth/token/"
        ] do
      assert {:error, _} = Client.request(client, :get, path)
    end

    for body <- [
          %{"amount" => 100, "price" => 100},
          %{"amount" => 100, :price => 100},
          %{"amount" => 100, "paidPrice" => nil},
          %{"amount" => 100.5},
          %{"amount" => 0},
          %{"amount" => 9_007_199_254_740_992}
        ] do
      assert {:error, _} =
               Client.request(client, :post, "/api/v1/payments/intents",
                 body: body,
                 idempotency_key: "attempt-0000000001"
               )
    end

    assert {:error, _} = Lunixi.Fraud.evaluate(client, %{"tenantId" => "other"})
    assert {:error, _} = Payments.refund(client, "p", -1, nil, "attempt-0000000001")
    assert {:error, _} = Payments.capture(client, "p", 100, "short")
    refute_received :network
  end

  test "response bounds malformed JSON timeout and pending split remain explicit" do
    server = TestTLS.start(fn _ -> {200, Jason.encode!(%{blob: String.duplicate("x", 1000)})} end)
    client = start_supervised!({Client, config: TestTLS.config(server, max_response_bytes: 100)})
    assert {:error, %{kind: :response, code: "SIZE_LIMIT"}} = Payments.get(client, "p")
    server2 = TestTLS.start(fn _ -> {200, "{invalid"} end)
    {:ok, second} = Client.start_link(config: TestTLS.config(server2))
    assert {:error, %{kind: :response}} = Payments.get(second, "p")
    GenServer.stop(second)

    server3 =
      TestTLS.start(fn request ->
        if request.path == "/api/v1/auth/token",
          do: {200, token()},
          else:
            {400,
             ~s({"data":{"splitPaymentId":"s","status":"AWAITING_3DS","secret":"private-customer-value"}})}
      end)

    {:ok, third} = Client.start_link(config: TestTLS.config(server3))

    assert {:ok, response} =
             Payments.split(
               third,
               %{
                 "totalAmount" => 100,
                 "currency" => "TRY",
                 "ownerRef" => "owner",
                 "legs" => [%{"amount" => 100}]
               },
               "attempt-0000000001"
             )

    assert response.status == 400
    refute inspect(response) =~ "private-customer-value"
    refute Jason.encode!(response) =~ "private-customer-value"
    GenServer.stop(third)

    slow =
      TestTLS.start(fn _ ->
        Process.sleep(100)
        {200, "{}"}
      end)

    {:ok, fourth} = Client.start_link(config: TestTLS.config(slow, timeout: 10))
    assert {:error, %{kind: :transport}} = Payments.get(fourth, "p")
    GenServer.stop(fourth)
  end
end
