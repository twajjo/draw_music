defmodule DrawMusicWeb.CreditsLive do
  @moduledoc """
  The Credits page: the fonts, libraries and instrument samples DrawMusic
  is built on, with their licenses. Open to everyone, signed in or not.
  """

  use DrawMusicWeb, :live_view

  alias DrawMusicWeb.Credit

  @mit "https://opensource.org/license/mit"

  @credits [
    %Credit{
      work: "Bravura music font",
      holder: "© 2015 Steinberg Media Technologies GmbH",
      license: "SIL Open Font License 1.1",
      license_url: "https://openfontlicense.org",
      source_url: "https://github.com/steinbergmedia/bravura",
      use: "Every note, rest, clef and sign on the score, and in exported SVG files."
    },
    %Credit{
      work: "SMuFL glyph names",
      holder: "W3C Music Notation Community Group",
      license: "W3C Software and Document License",
      license_url: "https://www.w3.org/copyright/software-license-2023/",
      source_url: "https://github.com/w3c/smufl",
      use: "Finding each symbol in the music font."
    },
    %Credit{
      work: "Tone.js",
      holder: "© Yotam Mann",
      license: "MIT",
      license_url: @mit,
      source_url: "https://github.com/Tonejs/Tone.js",
      use: "The tone you hear while placing notes, and the built-in synth."
    },
    %Credit{
      work: "smplr",
      holder: "© danigb",
      license: "MIT",
      license_url: @mit,
      source_url: "https://github.com/danigb/smplr",
      use: "Playing the sampled instruments."
    },
    %Credit{
      work: "Musyng Kite soundfont",
      holder: "Converted for the web by Benjamin Gleitzman (midi-js-soundfonts)",
      license: "CC BY-SA 3.0",
      license_url: "https://creativecommons.org/licenses/by-sa/3.0/",
      source_url: "https://github.com/gleitz/midi-js-soundfonts",
      use: "The instrument sounds, apart from the grand piano."
    },
    %Credit{
      work: "Splendid Grand Piano",
      holder: "Samples by Akai, prepared by smpldsnds",
      license: "Public domain",
      license_url: nil,
      source_url: "https://github.com/smpldsnds/sfzinstruments-splendid-grand-piano",
      use: "The grand piano sound."
    },
    %Credit{
      work: "ex_midi",
      holder: "© manhvu",
      license: "Apache License 2.0",
      license_url: "https://www.apache.org/licenses/LICENSE-2.0",
      source_url: "https://github.com/manhvu/ex_midi",
      use: "Reading and writing MIDI files."
    }
  ]

  @doc "Every credit, in the order the page lists them."
  @spec credits() :: [Credit.t()]
  def credits, do: @credits

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <h1 class="text-2xl font-semibold">Credits</h1>
      <p class="opacity-80">
        DrawMusic is built on the work of these people and projects. Thank you.
      </p>

      <ul class="divide-y divide-base-300">
        <li
          :for={{credit, n} <- Enum.with_index(@credits, 1)}
          id={"credit-#{n}"}
          class="space-y-1 py-4"
        >
          <h2 class="font-semibold">
            <a href={credit.source_url} class="link link-hover" rel="noopener">{credit.work}</a>
          </h2>
          <p class="text-sm opacity-80">{credit.use}</p>
          <p class="flex flex-wrap gap-x-4 text-sm">
            <span>{credit.holder}</span>
            <%= if credit.license_url do %>
              <a href={credit.license_url} class="link" rel="noopener">{credit.license}</a>
            <% else %>
              {credit.license}
            <% end %>
          </p>
        </li>
      </ul>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Credits", credits: @credits)}
  end
end
