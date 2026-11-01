defmodule Lunixi.MoneyTest do
  use ExUnit.Case, async: true
  alias Lunixi.Money

  test "canonical money strings and exact currency exponents" do
    large = "9007199254740993"
    assert Money.valid?(large, true)
    assert Money.valid?("-9007199254740993", false, true)

    for value <- [1, 1.5, "0", "-0", "01", "+1", " 1", "1.0", "1e3", "9223372036854775808"],
        do: refute(Money.valid?(value, true))

    for {decimal, currency} <- [
          {large, "JPY"},
          {"90071992547409.93", "TRY"},
          {"9007199254740.993", "KWD"}
        ],
        do: assert(Money.decimal_to_minor(decimal, currency) == large)

    assert_raise ArgumentError, fn -> Money.decimal_to_minor("1.1", "JPY") end
    assert_raise ArgumentError, fn -> Money.decimal_to_minor("1", "ZZZ") end
    refute Money.fields?(%{"data" => %{"amount" => 1}}, true)

    assert Money.fields?(%{
             "metadata" => %{"amount" => 1},
             "providerPayload" => %{"amount" => 1},
             "rate" => 1.5
           })
  end
end
