defmodule DrawMusicWeb.ScoreExport do
  @moduledoc """
  A version as a standalone SVG document for printing or sharing: page
  layout, black on white, with the title and credits above the music and
  Bravura embedded, so it renders the same without the font installed.

  Units are staff spaces; the document is sized in millimetres at 1.75 mm
  per staff space.
  """

  use Phoenix.Component

  import DrawMusicWeb.ScoreComponents, only: [systems: 1, page_width: 0]

  alias DrawMusic.Engraving.Layout
  alias DrawMusic.Library.{Composition, Key, Version}
  alias DrawMusic.Music.Context
  alias Phoenix.HTML.Safe

  @font_path Path.expand("../../priv/static/fonts/Bravura.woff2", __DIR__)
  @external_resource @font_path
  # HEEx does not interpolate inside <style>, so the whole element is
  # injected as markup. Its only content is our own font.
  @font_style "<style>@font-face{font-family:Bravura;src:url(data:font/woff2;base64,#{@font_path |> File.read!() |> Base.encode64()}) format(\"woff2\")}</style>"

  @mm_per_space 1.75
  @margin 6
  @title_size 3.2
  @subtitle_size 2
  @credit_size 1.6

  @doc "The SVG document for a version with its key and composition loaded."
  def svg(%Version{key: %Key{composition: %Composition{} = composition}} = version) do
    layout = Layout.layout(version.score, Context.from_version(version), width: page_width())
    lines = credit_lines(composition)

    top =
      @margin + @title_size + if(composition.subtitle, do: @subtitle_size + 1, else: 0) +
        length(lines) * (@credit_size + 0.6) + 3

    width = page_width() + 2 * @margin

    assigns = %{
      layout: layout,
      composition: composition,
      lines: lines,
      width: width,
      height: top + layout.height + @margin,
      top: top,
      font_style: Phoenix.HTML.raw(@font_style)
    }

    document =
      ~H"""
      <svg
        xmlns="http://www.w3.org/2000/svg"
        viewBox={"0 0 #{n(@width)} #{n(@height)}"}
        width={"#{n(@width * mm_per_space())}mm"}
        height={"#{n(@height * mm_per_space())}mm"}
      >
        <defs>{@font_style}</defs>
        <rect width="100%" height="100%" fill="#fff" />
        <g fill="#000" font-family="serif" text-anchor="middle">
          <text
            x={n(@width / 2)}
            y={n(margin() + title_size())}
            font-size={title_size()}
            font-weight="bold"
          >
            {@composition.name}
          </text>
          <text
            :if={@composition.subtitle}
            x={n(@width / 2)}
            y={n(margin() + title_size() + subtitle_size() + 0.5)}
            font-size={subtitle_size()}
          >
            {@composition.subtitle}
          </text>
          <text
            :for={{line, i} <- Enum.with_index(@lines)}
            x={n(@width - margin())}
            y={n(@top - 2 - (length(@lines) - 1 - i) * (credit_size() + 0.6))}
            font-size={credit_size()}
            text-anchor="end"
          >
            {line}
          </text>
        </g>
        <g transform={"translate(#{margin()} #{n(@top)})"} color="#000">
          <.systems layout={@layout} />
        </g>
      </svg>
      """

    [~s(<?xml version="1.0" encoding="UTF-8"?>\n) | Safe.to_iodata(document)]
    |> IO.iodata_to_binary()
    |> strip_root_markers()
  end

  # LiveView marks template root tags with a valueless `phx-r` attribute.
  # That is fine in HTML but not in XML, which a standalone SVG must be.
  defp strip_root_markers(svg), do: String.replace(svg, ~r/ phx-r(?=[\s>\/])/, "")

  @doc "Download filename, e.g. `Waltz - G major - v2.svg` (or `.mid`)."
  def filename(
        %Version{key: %Key{composition: composition} = key, number: number},
        extension \\ "svg"
      ),
      do: "#{composition.name} - #{Key.name(key)} - v#{number}.#{extension}"

  defp credit_lines(composition) do
    [
      composition.composer && "Music: #{composition.composer}",
      composition.lyricist && "Words: #{composition.lyricist}",
      composition.arranger && "Arranged by #{composition.arranger}",
      composition.copyright && "© #{composition.copyright}"
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp mm_per_space, do: @mm_per_space
  defp margin, do: @margin
  defp title_size, do: @title_size
  defp subtitle_size, do: @subtitle_size
  defp credit_size, do: @credit_size

  defp n(x) when is_integer(x), do: x
  defp n(x), do: Float.round(x, 3)
end
