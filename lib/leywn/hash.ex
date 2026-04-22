defmodule Leywn.Hash do
  @moduledoc "POST body hashing via :crypto."

  def sha256(body) do
    hex = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
    result = Jason.encode!(%{hash: hex, algorithm: "sha256", input_bytes: byte_size(body)})
    {:ok, "application/json", result}
  end

  def md5(body) do
    hex = :crypto.hash(:md5, body) |> Base.encode16(case: :lower)
    result = Jason.encode!(%{hash: hex, algorithm: "md5", input_bytes: byte_size(body)})
    {:ok, "application/json", result}
  end
end
