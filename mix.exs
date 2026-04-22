defmodule Leywn.MixProject do
  use Mix.Project

  def project do
    [
      app: :leywn,
      version: "1.0.0-beta2",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Leywn.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug_cowboy, "~> 2.8"},
      {:jason, "~> 1.4"},
      {:xml_builder_ex, "~> 3.1"},
      {:tzdata, "~> 1.1"},
      {:yaml_elixir, "~> 2.11"},
      {:yamerl, "~> 0.10"}
    ]
  end
end
