# Consume an authentic raw delivery on stdin. This receipt consumer does not
# mark orders paid; the financial adapter belongs inside the transaction below.
secret = System.fetch_env!("LUNIXI_WEBHOOK_SECRET")

headers = [
  {"x-lunixi-event-id", System.fetch_env!("LUNIXI_EVENT_ID")},
  {"x-lunixi-signature-timestamp", System.fetch_env!("LUNIXI_SIGNATURE_TIMESTAMP")},
  {"x-lunixi-signature", System.fetch_env!("LUNIXI_SIGNATURE")}
]

raw = IO.binread(:stdio, 8_388_609)

with {:ok, event} <- Lunixi.Webhook.verify(raw, headers, secrets: [secret]),
     {:ok, db} <- Exqlite.Sqlite3.open("lunixi-webhooks.db"),
     :ok <- Exqlite.Sqlite3.set_busy_timeout(db, 100),
     :ok <- Lunixi.SqliteInbox.ensure_schema(db),
     :ok <-
       Exqlite.Sqlite3.execute(
         db,
         "CREATE TABLE IF NOT EXISTS payment_notifications (event_id TEXT PRIMARY KEY,event_type TEXT NOT NULL)"
       ) do
  result =
    Lunixi.SqliteInbox.process(db, "merchant-payments", event, fn transaction ->
      # Match merchant/order/payment/expected amount/currency/final state before
      # changing an order. Use this connection for state and outbox writes.
      Lunixi.SqliteInbox.execute(
        transaction,
        "INSERT INTO payment_notifications (event_id,event_type) VALUES (?1,?2)",
        [event.id, event.type]
      )
    end)

  Exqlite.Sqlite3.close(db)

  case result do
    {:ok, applied} ->
      IO.puts("Verified receipt committed: #{applied}")

    {:error, _} ->
      IO.puts(:stderr, "Receipt not acknowledged; retry after checking storage")
      System.halt(1)
  end
else
  _ ->
    IO.puts(:stderr, "Delivery verification or storage failed")
    System.halt(1)
end
