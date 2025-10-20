defmodule ColdStorage.MixProject do
  use Mix.Project

  @source_url "https://github.com/lud/cold_storage"
  @version "0.11.3"

  def project do
    [
      app: :cold_storage,
      description: "A simple hard drive persistent cache for scripting purposes.",
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      source_url: @source_url,
      deps: deps(),
      dialyzer: dialyzer(),
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # Dev / Test
      {:briefly, "~> 0.5.1", only: [:test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.38", only: [:dev, :test, :doc], runtime: false}
    ]
  end

  def cli do
    [
      preferred_envs: [
        dialyzer: :test
      ]
    ]
  end

  defp dialyzer do
    [
      flags: [:unmatched_returns, :error_handling, :unknown, :extra_return],
      list_unused_filters: true,
      plt_add_deps: :app_tree,
      plt_add_apps: [:ex_unit, :mix, :jsv],
      plt_local_path: "_build/plts"
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "Github" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: doc_extras()
    ]
  end

  def doc_extras do
    ["README.md", "CHANGELOG.md"]
  end
end
