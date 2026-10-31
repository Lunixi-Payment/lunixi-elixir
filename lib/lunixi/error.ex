defmodule Lunixi.Error do
  @moduledoc "Safe SDK diagnostics. Upstream messages, bodies, URLs and secrets are omitted."
  defexception [:kind, :code, :status, :request_id]

  @type t :: %__MODULE__{
          kind: atom(),
          code: String.t() | nil,
          status: integer() | nil,
          request_id: String.t() | nil
        }
  @impl true
  def message(%__MODULE__{kind: kind, code: code, status: status}),
    do: "lunixi: #{kind} (#{code || "UNKNOWN"}, HTTP #{status || 0})"

  @doc false
  def invalid(code), do: {:error, %__MODULE__{kind: :invalid, code: code}}
end
