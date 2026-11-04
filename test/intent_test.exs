defmodule Lunixi.Payment.IntentTest do
  use ExUnit.Case, async: true
  alias Lunixi.Payment.Intent

  defp intent(counts) do
    %Intent{
      amount: "10050",
      currency: "TRY",
      order_id: "order-123",
      callback_url: "https://merchant.example/payments/return",
      enabled_installments: counts
    }
  end

  test "enabled installments are sent in ascending order" do
    request = intent([3, 1, 2])
    assert Intent.validate(request) == :ok
    assert Intent.to_map(request)["enabledInstallments"] == [1, 2, 3]
    assert request.enabled_installments == [3, 1, 2]
  end

  test "single payment only and the bounds are accepted" do
    assert Intent.validate(intent([1])) == :ok
    assert Intent.validate(intent([36, 1])) == :ok
  end

  test "nil sends no field" do
    assert Intent.validate(intent(nil)) == :ok
    refute Map.has_key?(Intent.to_map(intent(nil)), "enabledInstallments")
  end

  test "broken lists are refused" do
    for counts <- [[], [2, 3], [1, 2, 2], [0, 1], [1, -3], [1, 37], [1, 2.0], [1, "3"], "1,2,3"] do
      assert {:error, %Lunixi.Error{kind: :invalid, code: "ENABLED_INSTALLMENTS"}} =
               Intent.validate(intent(counts))
    end
  end

  test "other intent rules still apply with a valid list" do
    assert {:error, %Lunixi.Error{code: "INTENT"}} =
             Intent.validate(%{intent([1, 2]) | callback_url: "http://merchant.example/return"})
  end
end
