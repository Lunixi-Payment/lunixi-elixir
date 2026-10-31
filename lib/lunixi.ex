defmodule Lunixi do
  @moduledoc "Server-side Lunixi SDK. Use supervised clients, integer money and verified durable webhook processing."
  @doc "Current SDK semantic version."
  def version, do: "0.1.1"

  @doc "Generic signed access to a documented merchant endpoint; schemas remain the caller's responsibility."
  defdelegate request(client, method, path, opts \\ []), to: Lunixi.Client
end
