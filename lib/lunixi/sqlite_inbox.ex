defmodule Lunixi.SqliteInbox do
  @moduledoc """
  Durable transactional event deduplication using optional Exqlite. Pass a
  connection owned exclusively by the current transaction. Separate processes
  must use separate connections with a busy timeout; never interleave two
  transactions on the same connection. No raw webhook is persisted here.
  """
  @compile {:no_warn_undefined, Exqlite.Sqlite3}
  alias Exqlite.Sqlite3, as: SQL
  alias Lunixi.{Error, Webhook.Event}
  @doc "Explicit inbox schema migration; run during startup or normal migrations."
  def ensure_schema(connection) do
    normalize(
      SQL.execute(
        connection,
        "CREATE TABLE IF NOT EXISTS lunixi_webhook_inbox (scope TEXT NOT NULL,event_id TEXT NOT NULL,payload_sha256 TEXT NOT NULL,received_at TEXT NOT NULL,PRIMARY KEY(scope,event_id))"
      )
    )
  rescue
    _ -> storage_error()
  end

  @doc """
  Applies a verified event once. Marker, order changes and outbox rows MUST use
  this same connection/transaction. Callback returns :ok or {:error, reason}.
  Returns {:ok, true} on commit, {:ok, false} on duplicate; collisions fail closed.
  Callback/storage failure rolls back the marker so provider delivery can retry.
  """
  def process(connection, scope, %Event{} = event, apply) when is_function(apply, 1) do
    with true <-
           Lunixi.Guards.header?(scope, 200) and Lunixi.Guards.header?(event.id, 200) and
             is_binary(event.raw) and byte_size(event.raw) > 0,
         :ok <- SQL.execute(connection, "BEGIN IMMEDIATE") do
      transaction(connection, scope, event, apply)
    else
      _ -> storage_error()
    end
  rescue
    _ -> storage_error()
  end

  defp transaction(connection, scope, event, apply) do
    hash = :crypto.hash(:sha256, event.raw) |> Base.encode16(case: :lower)

    result =
      with :ok <-
             execute(
               connection,
               "INSERT INTO lunixi_webhook_inbox (scope,event_id,payload_sha256,received_at) VALUES (?1,?2,?3,?4) ON CONFLICT(scope,event_id) DO NOTHING",
               [scope, event.id, hash, DateTime.to_iso8601(DateTime.utc_now())]
             ),
           {:ok, changed} <- SQL.changes(connection) do
        if changed == 0 do
          with {:ok, [[^hash]]} <-
                 query(
                   connection,
                   "SELECT payload_sha256 FROM lunixi_webhook_inbox WHERE scope=?1 AND event_id=?2",
                   [scope, event.id]
                 ),
               do: {:ok, false},
               else: (_ -> {:error, %Error{kind: :webhook, code: "EVENT_COLLISION"}})
        else
          case apply.(connection) do
            :ok -> {:ok, true}
            _ -> storage_error()
          end
        end
      else
        _ -> storage_error()
      end

    case result do
      {:ok, true} ->
        case SQL.execute(connection, "COMMIT") do
          :ok ->
            result

          _ ->
            SQL.execute(connection, "ROLLBACK")
            storage_error()
        end

      other ->
        SQL.execute(connection, "ROLLBACK")
        other
    end
  rescue
    _ ->
      SQL.execute(connection, "ROLLBACK")
      storage_error()
  catch
    _, _ ->
      SQL.execute(connection, "ROLLBACK")
      storage_error()
  end

  @doc "Executes a parameterized statement on the caller's connection/transaction."
  def execute(connection, sql, arguments \\ []) do
    with {:ok, statement} <- SQL.prepare(connection, sql) do
      try do
        with :ok <- SQL.bind(statement, arguments),
             :done <- SQL.step(connection, statement),
             do: :ok,
             else: (_ -> storage_error())
      after
        SQL.release(connection, statement)
      end
    else
      _ -> storage_error()
    end
  rescue
    _ -> storage_error()
  end

  @doc "Queries using bound parameters; no string interpolation of event/customer values."
  def query(connection, sql, arguments \\ []) do
    with {:ok, statement} <- SQL.prepare(connection, sql) do
      try do
        with :ok <- SQL.bind(statement, arguments),
             {:ok, rows} <- SQL.fetch_all(connection, statement),
             do: {:ok, rows},
             else: (_ -> storage_error())
      after
        SQL.release(connection, statement)
      end
    else
      _ -> storage_error()
    end
  rescue
    _ -> storage_error()
  end

  defp normalize(:ok), do: :ok
  defp normalize(_), do: storage_error()
  defp storage_error, do: {:error, %Error{kind: :storage, code: "INBOX_FAILED"}}
end
