defmodule ColdStorage.MixProject do
  use Mix.Project

  @source_url "https://github.com/lud/cold_storage"
  @version "0.15.0"

  def project do
    [
      app: :cold_storage,
      description: "A simple hard drive persistent cache for scripting purposes.",
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      source_url: @source_url,
      deps: deps(),
      dialyzer: dialyzer(),
      package: package(),
      docs: docs(),
      versioning: versioning()
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
      {:libdev, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:readmix, ">= 0.0.0", only: [:dev, :test], runtime: false}
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
      plt_add_apps: [:ex_unit, :mix],
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

  defp versioning do
    [
      before_commit: [
        &readmix/1,
        {:add, "README.md"},
        &gen_changelog/2,
        {:add, "CHANGELOG.md"}
      ]
    ]
  end

  def readmix(vsn) do
    rdmx = Readmix.new(vars: %{app_vsn: vsn})
    :ok = Readmix.update_file(rdmx, "README.md")
  end

  defp gen_changelog(vsn, info) do
    args = ["cliff", "--tag", vsn, "--with-tag-message", info.annotation, "-o", "CHANGELOG.md"]

    case System.cmd("git", args, stderr_to_stdout: true) do
      {_, 0} -> IO.puts("Updated CHANGELOG.md with #{vsn}")
      {out, _} -> {:error, "Could not update CHANGELOG.md:\n\n #{out}"}
    end
  end
end
