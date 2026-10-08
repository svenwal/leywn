defmodule Leywn.MixProject do
  use Mix.Project

  def project do
    [
      app: :leywn,
      version: "1.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Leywn.Application, []}
    ]
  end

  defp releases do
    [
      leywn: [
        strip_beams: true
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # 2.9.0 is the first plug_cowboy without CVE-2026-32688 (atom table
      # exhaustion via the HTTP/2 :scheme pseudo-header) and it pulls plug 1.18+.
      {:plug_cowboy, "~> 2.9"},
      # Pinned above the transitive floor plug_cowboy would accept: 1.20.3 is the
      # first release carrying all four 2026 plug fixes (multipart accumulation,
      # cookie attribute injection, unbounded temp files, quadratic query decoding).
      {:plug, "~> 1.20.3"},
      # Likewise above cowboy's own floor: 2.18.0/2.19.0 close the max_headers
      # bypass, the chunk-size and HPACK/QPACK decoding DoS and the SPDY zip bomb.
      {:cowboy, "~> 2.20"},
      {:cowlib, "~> 2.21"},
      {:jason, "~> 1.4"},
      {:xml_builder_ex, "~> 3.1"},
      # tz replaces tzdata: same IANA data, but pure Elixir with no runtime
      # dependencies, where tzdata drags in hackney (10 open CVEs, all fixed only
      # in 4.x, which tzdata's "~> 1.17" requirement will not accept) purely for an
      # auto-update path Leywn had already disabled.
      {:tz, "~> 0.28.4"},
      {:yaml_elixir, "~> 2.11"},
      {:yamerl, "~> 0.10"}
    ]
  end
end
