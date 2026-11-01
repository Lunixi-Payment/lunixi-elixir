defmodule Lunixi.MixProject do
  use Mix.Project

  def project do
    [
      app: :lunixi,
      version: "1.0.1",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      description: "Lunixi signed merchant APIs, payments and verified webhooks",
      package: [
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/Lunixi-Payment/lunixi-elixir"},
        files: [
          "lib",
          "mix.exs",
          "mix.lock",
          "README.md",
          "LICENSE",
          "CHANGELOG.md",
          "MIGRATION-1.0.md",
          "SECURITY.md",
          "CONTRIBUTING.md",
          "docs",
          "examples",
          "test",
          ".github/assets",
          ".formatter.exs",
          ".credo.exs"
        ]
      ],
      source_url: "https://github.com/Lunixi-Payment/lunixi-elixir"
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto, :public_key, :ssl]]
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:req, "~> 0.7.5"},
      {:jason, "~> 1.4.5"},
      {:exqlite, "~> 0.43.0", optional: true},
      {:credo, "~> 1.7.19", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1.5", only: [:dev, :test], runtime: false}
    ]
  end
end
