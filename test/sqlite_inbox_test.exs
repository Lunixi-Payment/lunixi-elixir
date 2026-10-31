defmodule Lunixi.SqliteInboxTest do
  use ExUnit.Case, async: true
  alias Exqlite.Sqlite3, as: SQL
  alias Lunixi.SqliteInbox, as: Inbox

  defp event(id, type \\ "payment.captured") do
    secret = "synthetic_webhook_secret_0123456789"
    timestamp = DateTime.to_iso8601(DateTime.utc_now())

    raw =
      Jason.encode!(%{
        type: type,
        data: %{orderId: "order-1", capturedAmountMinor: "10050", currency: "TRY"}
      })

    signature =
      "v2=" <>
        Base.encode16(:crypto.mac(:hmac, :sha256, secret, id <> "." <> timestamp <> "." <> raw),
          case: :lower
        )

    headers = [
      {"x-lunixi-event-id", id},
      {"x-lunixi-signature-timestamp", timestamp},
      {"x-lunixi-signature", signature}
    ]

    {:ok, event} = Lunixi.Webhook.verify(raw, headers, secrets: [secret])
    event
  end

  defp file do
    path = Path.join(System.tmp_dir!(), "lunixi-inbox-#{System.unique_integer([:positive])}.db")
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp open(path) do
    {:ok, db} = SQL.open(path)
    :ok = SQL.set_busy_timeout(db, 100)
    db
  end

  test "rollback retry duplicate collision and durable restart share one transaction" do
    path = file()
    db = open(path)
    assert :ok = Inbox.ensure_schema(db)

    :ok =
      SQL.execute(
        db,
        "CREATE TABLE orders (id TEXT PRIMARY KEY, applications INTEGER NOT NULL); INSERT INTO orders VALUES ('order-1',0)"
      )

    event = event("event-1")

    apply = fn tx ->
      Inbox.execute(tx, "UPDATE orders SET applications=applications+1 WHERE id=?1", ["order-1"])
    end

    assert {:error, _} =
             Inbox.process(db, "merchant-a", event, fn tx ->
               :ok = apply.(tx)
               {:error, :synthetic_crash}
             end)

    assert {:ok, true} = Inbox.process(db, "merchant-a", event, apply)
    assert {:ok, false} = Inbox.process(db, "merchant-a", event, apply)
    assert {:ok, [[1]]} = Inbox.query(db, "SELECT applications FROM orders")
    :ok = SQL.close(db)
    db = open(path)
    assert {:ok, false} = Inbox.process(db, "merchant-a", event, apply)

    assert {:error, %{kind: :webhook}} =
             Inbox.process(db, "merchant-a", event("event-1", "payment.failed"), apply)

    assert {:ok, true} = Inbox.process(db, "merchant-b", event, fn _ -> :ok end)
    SQL.close(db)
  end

  test "independent concurrent connections consume the unique marker once" do
    path = file()
    db = open(path)
    :ok = Inbox.ensure_schema(db)
    SQL.close(db)
    event = event("event-concurrent")

    results =
      1..12
      |> Task.async_stream(
        fn _ ->
          db = open(path)
          result = retry_busy(db, event, 20)
          SQL.close(db)
          result
        end,
        max_concurrency: 12,
        timeout: 10_000
      )
      |> Enum.to_list()

    assert Enum.count(results, &(&1 == {:ok, {:ok, true}})) == 1
    assert Enum.count(results, &(&1 == {:ok, {:ok, false}})) == 11
  end

  test "database or callback exception never leaves a consumed event" do
    db = open(file())
    event = event("event-failure")
    assert {:error, %{kind: :storage}} = Inbox.process(db, "merchant-a", event, fn _ -> :ok end)
    :ok = Inbox.ensure_schema(db)

    assert {:error, %{kind: :storage}} =
             Inbox.process(db, "merchant-a", event, fn _ -> raise "synthetic callback failure" end)

    assert {:ok, true} = Inbox.process(db, "merchant-a", event, fn _ -> :ok end)
    SQL.close(db)
  end

  defp retry_busy(db, event, remaining) do
    case Inbox.process(db, "merchant-a", event, fn _ -> :ok end) do
      {:error, %{kind: :storage}} when remaining > 0 ->
        Process.sleep(20)
        retry_busy(db, event, remaining - 1)

      result ->
        result
    end
  end
end
