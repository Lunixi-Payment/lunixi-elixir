defmodule Lunixi.Fraud do
  @moduledoc "Typed fraud evaluation/event operations. Tenant identity always comes from credentials."
  @fields ~w(integrationMode productContext transactionRef channel surface stage operationKind authModeRequested authModeApplied subMerchantRef subjectType subjectId paymentRail transferDirection merchantGroupIds paymentId payment bankTransfer cryptoTransfer walletOperation billPayment loanApplication payout customer device session merchant mobileApp telemetry metadata identitySnapshot identityAssertion)
  @doc "Evaluates a transaction; rejects unknown top-level fields including tenantId."
  def evaluate(client, body) when is_map(body) do
    if Enum.all?(Map.keys(body), &(&1 in @fields)),
      do: Lunixi.Client.request(client, :post, "/api/v1/fraud/decisions/evaluate", body: body),
      else: Lunixi.Error.invalid("FRAUD_FIELD")
  end

  def evaluate(_, _), do: Lunixi.Error.invalid("FRAUD_OBJECT")
  @doc "Ingests a stable transaction event with a persisted key."
  def record_event(client, body, key) when is_map(body) do
    if Enum.all?(
         ~w(eventId subjectType eventType occurredAt),
         &(is_binary(body[&1]) and body[&1] != "")
       ) and Lunixi.Guards.key?(key) do
      Lunixi.Client.request(client, :post, "/api/v1/fraud/events/transactions",
        body: body,
        idempotency_key: key
      )
    else
      Lunixi.Error.invalid("FRAUD_EVENT_OR_KEY")
    end
  end

  def record_event(_, _, _), do: Lunixi.Error.invalid("FRAUD_EVENT")
  @doc "Lists decision logs and preserves pageInfo."
  def decisions(client, query \\ []),
    do: Lunixi.Client.request(client, :get, "/api/v1/fraud/decision-logs", query: query)

  @doc "Reads one decision by trace ID."
  def decision(client, id),
    do:
      if(Lunixi.Guards.id?(id),
        do: Lunixi.Client.request(client, :get, "/api/v1/fraud/decision-logs/" <> id),
        else: Lunixi.Error.invalid("TRACE_ID")
      )
end
