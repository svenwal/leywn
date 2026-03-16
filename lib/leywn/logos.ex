defmodule Leywn.Logos do
  def ensure, do: :ok

  def path_for(type) when is_binary(type) do
    case String.downcase(type) do
      ext when ext in ["png", "jpeg", "gif"] ->
        path = Application.app_dir(:leywn, "priv/images/leywn.#{ext}")
        {:ok, path, mime(ext)}

      _ ->
        {:error, "unsupported_image_type"}
    end
  end

  defp mime("png"), do: "image/png"
  defp mime("jpeg"), do: "image/jpeg"
  defp mime("gif"), do: "image/gif"
end
