defmodule Lunixi.Money do
  @moduledoc "Exact canonical fiat minor strings and decimal text conversion."
  @max 9_223_372_036_854_775_807
  @doc false
  def fiat_route?(path),
    do:
      Regex.match?(
        ~r{\A/api/v1/(?:payments|wallet|insurance|bank-connect|fraud)(?:[/?]|\z)},
        path
      )

  @doc "Validate canonical minor text; numeric inputs fail closed."
  def valid?(value, positive \\ false, signed \\ false) do
    pattern =
      cond do
        signed -> ~r/\A(?:0|-?[1-9][0-9]*)\z/
        positive -> ~r/\A[1-9][0-9]*\z/
        true -> ~r/\A(?:0|[1-9][0-9]*)\z/
      end

    is_binary(value) and Regex.match?(pattern, value) and
      String.to_integer(value) in (-@max - 1)..@max
  end

  @doc "Convert decimal text with the actual supported currency exponent."
  def decimal_to_minor(value, currency) do
    exponent =
      cond do
        currency == "JPY" -> 0
        currency == "KWD" -> 3
        currency in ~w(TRY USD EUR GBP RUB AED SAR QAR CHF CAD AUD CNY AZN) -> 2
        true -> raise ArgumentError, "Unsupported currency"
      end

    if not is_binary(value) or not Regex.match?(~r/\A(?:0|[1-9][0-9]*)(?:\.[0-9]+)?\z/, value),
      do: raise(ArgumentError, "Decimal text required")

    [whole | rest] = String.split(value, ".")
    fraction = List.first(rest) || ""

    if Regex.match?(~r/[1-9]/, String.slice(fraction, exponent..-1//1)),
      do: raise(ArgumentError, "Currency precision exceeded")

    text =
      (whole <> String.pad_trailing(String.slice(fraction, 0, exponent), exponent, "0"))
      |> String.to_integer()
      |> Integer.to_string()

    if valid?(text), do: text, else: raise(ArgumentError, "Fiat range exceeded")
  end

  @doc false
  def fields?(value, response \\ false)
  def fields?(value, response) when is_list(value), do: Enum.all?(value, &fields?(&1, response))

  def fields?(value, response) when is_map(value) do
    Enum.all?(value, fn {name, entry} ->
      key = to_string(name)

      cond do
        is_nil(entry) or key in ~w(metadata fields inputFields insuranceData) ->
          true

        key in ~w(amount amountMinor authorizedAmount availableBalance balanceMinor buyerTotalCharge cancelledPremiumAmount capturedAmount capturedAmountMinor chargeAmount collectedAmountMinor collectedPremiumAmount compensatedAmount disputedAmount feeTotal fixedFee inForcePremiumAmount insuranceValueAmount legAmount legsAmount lineTotalMinor maxAmount maxAmountMinor minAmount minAmountMinor nonRefundableAmount paidAmount paidPrice pendingBalance premiumAmount price refundAmount refundOpenPremiumAmount refundableAmount refundedAmount refundedAmountMinor refundedPremiumAmount requestedAmount reservedBalance sourceAmountMinor targetAmountMinor taxAmountMinor taxTotal totalAmount unitPriceMinor) ->
          valid?(
            entry,
            not response and key in ~w(amount price totalAmount),
            String.contains?(String.downcase(key), "balance")
          )

        key in ~w(data details items rows results payments operations balances wallets legs aggregate refund refunds totals charge fees fee balance splits sellers basketItems promissoryNote schedule notes lines offers policies reconciliation quotes payment transactions accounts settlements payouts limits) ->
          fields?(entry, response)

        true ->
          true
      end
    end)
  end

  def fields?(_, _), do: true
end
