defmodule Lunixi.Response do
  @moduledoc "Preserved response envelope, pagination and binary data; Inspect excludes bodies."
  @derive {Inspect, only: [:status, :request_id]}
  defstruct [:status, :request_id, :envelope, :data, :page_info, :content_type, bytes: ""]
  @type t :: %__MODULE__{}
end

defimpl Jason.Encoder, for: Lunixi.Response do
  def encode(response, opts),
    do:
      Jason.Encode.map(
        %{status: response.status, request_id: response.request_id, data: "[REDACTED]"},
        opts
      )
end
